import AppKit
import Darwin
import Foundation
import Observation
import SwiftTerm

private let terminalName = "xterm-256color"
/// `LocalProcess.terminate()` cancels its own exit-watching DispatchSource before sending
/// SIGTERM, so `processTerminated` never fires for a graceful stop (see `PTYSession.terminate`).
/// We send the signal ourselves and keep the child monitor alive to observe the exit.
private let defaultGracefulStopTimeout: TimeInterval = 5.0

/// Thread-safe cache of the pty window size, read synchronously by `LocalProcessDelegate.getWindowSize`
/// which can be invoked off the main thread while `TerminalView` state is main-actor isolated.
private final class WindowSizeBox: @unchecked Sendable {
    private let lock = NSLock()
    private var size: winsize

    init(size: winsize) {
        self.size = size
    }

    func get() -> winsize {
        lock.lock()
        defer { lock.unlock() }
        return size
    }

    func set(_ newSize: winsize) {
        lock.lock()
        defer { lock.unlock() }
        size = newSize
    }
}

/// Non-isolated bridge between SwiftTerm's synchronous, non-actor-isolated delegate protocols
/// and the main-actor-isolated `PTYSession`. Lets `PTYSession` stay @MainActor while still
/// satisfying `LocalProcessDelegate`/`TerminalViewDelegate`, whose requirements are plain
/// synchronous methods that cannot themselves be actor-isolated.
private final class PTYBridge: LocalProcessDelegate, TerminalViewDelegate {
    weak var session: PTYSession?
    var process: LocalProcess?
    let windowSize: WindowSizeBox

    init(windowSize: WindowSizeBox) {
        self.windowSize = windowSize
    }

    // MARK: LocalProcessDelegate

    func processTerminated(_ source: LocalProcess, exitCode: Int32?) {
        Task { @MainActor [weak session] in
            session?.handleProcessTerminated(exitCode: exitCode)
        }
    }

    func dataReceived(slice: ArraySlice<UInt8>) {
        let bytes = Array(slice)
        Task { @MainActor [weak session] in
            session?.handleDataReceived(bytes)
        }
    }

    func getWindowSize() -> winsize {
        windowSize.get()
    }

    // MARK: TerminalViewDelegate

    func send(source: TerminalView, data: ArraySlice<UInt8>) {
        process?.send(data: data)
    }

    func sizeChanged(source: TerminalView, newCols: Int, newRows: Int) {
        var size = winsize(ws_row: UInt16(newRows), ws_col: UInt16(newCols), ws_xpixel: 0, ws_ypixel: 0)
        windowSize.set(size)
        if let childfd = process?.childfd, childfd >= 0 {
            _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: childfd, windowSize: &size)
        }
    }

    func clipboardCopy(source: TerminalView, content: Data) {
        guard let string = String(data: content, encoding: .utf8) else { return }
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        pasteboard.writeObjects([string as NSString])
    }

    func clipboardRead(source: TerminalView) -> Data? {
        nil
    }

    func setTerminalTitle(source: TerminalView, title: String) {}
    func hostCurrentDirectoryUpdate(source: TerminalView, directory: String?) {}
    func scrolled(source: TerminalView, position: Double) {}
    func requestOpenLink(source: TerminalView, link: String, params: [String: String]) {}
    func bell(source: TerminalView) {}
    func iTermContent(source: TerminalView, content: ArraySlice<UInt8>) {}
    func rangeChanged(source: TerminalView, startY: Int, endY: Int) {}
}

@MainActor
@Observable
final class PTYSession {
    let id = UUID()
    private(set) var state: PTYRuntimeState = .notStarted
    let terminalView: PiBoardTerminalView
    private let process: LocalProcess
    private let bridge: PTYBridge
    private let gracefulStopTimeout: TimeInterval
    private var fallbackStopTask: Task<Void, Never>?

    /// Exposed for tests: counts bytes delivered from the pty, since reading the
    /// terminal's internal buffer lines is also used but this is a simpler liveness check.
    private(set) var receivedBytes: Int = 0

    /// Pid of the spawned child, nil before start or when the spawn failed.
    var processID: pid_t? {
        process.shellPid > 0 ? process.shellPid : nil
    }

    init(
        gracefulStopTimeout: TimeInterval = defaultGracefulStopTimeout,
        appearance: TerminalAppearance = .default,
        scrollbackLines: Int = TerminalScrollback.defaultLines
    ) {
        self.gracefulStopTimeout = gracefulStopTimeout
        var options = TerminalOptions.default
        options.scrollback = scrollbackLines
        options.termName = terminalName

        let windowSize = WindowSizeBox(
            size: winsize(ws_row: UInt16(options.rows), ws_col: UInt16(options.cols), ws_xpixel: 0, ws_ypixel: 0)
        )
        let bridge = PTYBridge(windowSize: windowSize)

        self.terminalView = PiBoardTerminalView(frame: .zero, options: options)
        self.terminalView.nativeForegroundColor = appearance.foreground
        self.terminalView.nativeBackgroundColor = appearance.background
        self.terminalView.caretColor = appearance.cursor
        self.terminalView.font = appearance.font
        self.terminalView.lineSpacing = appearance.lineSpacing
        self.process = LocalProcess(delegate: bridge)
        self.bridge = bridge

        bridge.process = process
        bridge.session = self
        terminalView.terminalDelegate = bridge
    }

    /// Restyles the live view. Font and line spacing change the cell size, so the pty is re-synced
    /// to the new cols/rows.
    func apply(_ appearance: TerminalAppearance, cursorStyle: TerminalCursorStyleChoice, optionAsMeta: Bool) {
        terminalView.nativeForegroundColor = appearance.foreground
        terminalView.nativeBackgroundColor = appearance.background
        terminalView.caretColor = appearance.cursor
        // The font setter clears the selection, so only reassign on an actual change.
        if terminalView.font != appearance.font {
            terminalView.font = appearance.font
        }
        if terminalView.lineSpacing != appearance.lineSpacing {
            terminalView.lineSpacing = appearance.lineSpacing
        }
        terminalView.optionAsMetaKey = optionAsMeta
        terminalView.getTerminal().setCursorStyle(cursorStyle.swiftTermStyle)
        syncWindowSize()
    }

    func startLoginShell(currentDirectory: String? = nil) {
        let shellPath = ShellResolver.loginShell()
        let execName = ShellResolver.loginExecName(for: shellPath)

        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = terminalName
        environment["COLORTERM"] = "truecolor"
        let environmentList = environment.map { "\($0.key)=\($0.value)" }

        start(
            executable: shellPath,
            args: [],
            environment: environmentList,
            execName: execName,
            currentDirectory: currentDirectory
        )
    }

    func start(command: PiLaunchCommand) {
        var environment = ProcessInfo.processInfo.environment
        environment["TERM"] = terminalName
        environment["COLORTERM"] = "truecolor"
        let environmentList = environment.map { "\($0.key)=\($0.value)" }

        start(
            executable: command.executable.path,
            args: command.arguments,
            environment: environmentList,
            currentDirectory: command.currentDirectory.path
        )
    }

    func start(
        executable: String,
        args: [String],
        environment: [String]? = nil,
        execName: String? = nil,
        currentDirectory: String? = nil
    ) {
        process.startProcess(
            executable: executable,
            args: args,
            environment: environment,
            execName: execName,
            currentDirectory: currentDirectory
        )
        state = .running
    }

    /// Sends SIGTERM directly instead of calling `LocalProcess.terminate()`, which cancels its
    /// own child-exit monitor before the process actually dies, so `processTerminated` never fires.
    /// The existing monitor stays armed here, so the exit still flows through `handleProcessTerminated`.
    func terminate() {
        guard state.isRunning, process.shellPid > 0 else { return }
        let pid = process.shellPid
        Darwin.kill(pid, SIGTERM)
        fallbackStopTask?.cancel()
        let timeout = gracefulStopTimeout
        fallbackStopTask = Task { [weak self] in
            try? await Task.sleep(nanoseconds: UInt64(timeout * 1_000_000_000))
            guard let self, !Task.isCancelled, self.state.isRunning else { return }
            Darwin.kill(pid, SIGKILL)
        }
    }

    /// Immediately kills the process, bypassing the graceful-stop grace period. Used by the
    /// app-quit path once it has already waited its own grace period for a clean exit.
    func forceKill() {
        guard state.isRunning, process.shellPid > 0 else { return }
        fallbackStopTask?.cancel()
        fallbackStopTask = nil
        Darwin.kill(process.shellPid, SIGKILL)
    }

    /// Sends SIGINT to the foreground process group, for a later interrupt toolbar action.
    func interrupt() {
        guard state.isRunning, process.shellPid > 0 else { return }
        let childfd = process.childfd
        let foregroundGroup = childfd >= 0 ? tcgetpgrp(childfd) : -1
        if foregroundGroup > 0 {
            Darwin.kill(-foregroundGroup, SIGINT)
        } else {
            Darwin.kill(process.shellPid, SIGINT)
        }
    }

    /// Pushes the terminal's current cols/rows to the pty. Needed after the first real layout:
    /// if the computed size happens to match the pty's startup size, SwiftTerm's `sizeChanged`
    /// delegate callback never fires, so the pty would otherwise never learn the view is live.
    func syncWindowSize() {
        let terminal = terminalView.getTerminal()
        var size = winsize(
            ws_row: UInt16(terminal.rows),
            ws_col: UInt16(terminal.cols),
            ws_xpixel: 0,
            ws_ypixel: 0
        )
        bridge.windowSize.set(size)
        if process.childfd >= 0 {
            _ = PseudoTerminalHelpers.setWinSize(masterPtyDescriptor: process.childfd, windowSize: &size)
        }
    }

    fileprivate func handleDataReceived(_ bytes: [UInt8]) {
        receivedBytes += bytes.count
        terminalView.feed(byteArray: bytes[...])
    }

    fileprivate func handleProcessTerminated(exitCode: Int32?) {
        fallbackStopTask?.cancel()
        fallbackStopTask = nil
        // LocalProcess hands back the raw waitpid(2) status, not the decoded exit code.
        state = .exited(exitCode.map(Self.decodeExitStatus))
    }

    private static func decodeExitStatus(_ waitStatus: Int32) -> Int32 {
        let isNormalExit = (waitStatus & 0x7F) == 0
        return isNormalExit ? (waitStatus >> 8) & 0xFF : waitStatus
    }
}
