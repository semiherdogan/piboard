import AppKit
import Foundation
import Observation
import SwiftTerm

private let scrollbackLineCount = 100_000
private let terminalName = "xterm-256color"

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
    let terminalView: TerminalView
    private let process: LocalProcess
    private let bridge: PTYBridge

    /// Exposed for tests: counts bytes delivered from the pty, since reading the
    /// terminal's internal buffer lines is also used but this is a simpler liveness check.
    private(set) var receivedBytes: Int = 0

    init() {
        var options = TerminalOptions.default
        options.scrollback = scrollbackLineCount
        options.termName = terminalName

        let windowSize = WindowSizeBox(
            size: winsize(ws_row: UInt16(options.rows), ws_col: UInt16(options.cols), ws_xpixel: 0, ws_ypixel: 0)
        )
        let bridge = PTYBridge(windowSize: windowSize)

        self.terminalView = TerminalView(frame: .zero, options: options)
        self.process = LocalProcess(delegate: bridge)
        self.bridge = bridge

        bridge.process = process
        bridge.session = self
        terminalView.terminalDelegate = bridge
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

    func terminate() {
        process.terminate()
    }

    fileprivate func handleDataReceived(_ bytes: [UInt8]) {
        receivedBytes += bytes.count
        terminalView.feed(byteArray: bytes[...])
    }

    fileprivate func handleProcessTerminated(exitCode: Int32?) {
        // LocalProcess hands back the raw waitpid(2) status, not the decoded exit code.
        state = .exited(exitCode.map(Self.decodeExitStatus))
    }

    private static func decodeExitStatus(_ waitStatus: Int32) -> Int32 {
        let isNormalExit = (waitStatus & 0x7F) == 0
        return isNormalExit ? (waitStatus >> 8) & 0xFF : waitStatus
    }
}
