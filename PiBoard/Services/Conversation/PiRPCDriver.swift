import Darwin
import Foundation
import OSLog

/// What the background readers hand to the main actor. One ordered stream keeps events and
/// responses in the order Pi wrote them, which a task per record would not.
private enum PiRPCInbound: Sendable {
    case record(PiRPCRecord)
    case stderrLine(String)
    case stdoutClosed
    case stderrClosed
}

private let signalExitCodeBase: Int32 = 128

/// Frames one pipe's bytes into lines off the main thread.
private final class PiRPCLinePump: @unchecked Sendable {
    private static let readChunkSize = 64 * 1024

    private let queue = DispatchQueue(label: "dev.piboard.pirpc.read")
    private var framer = JSONLineFramer()
    // Reused across reads: the handler runs serially on `queue`, so no read overlaps another.
    private var readBuffer = [UInt8](repeating: 0, count: PiRPCLinePump.readChunkSize)
    private var source: (any DispatchSourceRead)?
    private let continuation: AsyncStream<PiRPCInbound>.Continuation
    private let transform: @Sendable (Data) -> PiRPCInbound?
    private let closedMarker: PiRPCInbound?

    init(
        continuation: AsyncStream<PiRPCInbound>.Continuation,
        closedMarker: PiRPCInbound?,
        transform: @escaping @Sendable (Data) -> PiRPCInbound?
    ) {
        self.continuation = continuation
        self.closedMarker = closedMarker
        self.transform = transform
    }

    /// The handle is closed by the source's cancel handler on `queue`, never from another thread:
    /// closing a descriptor while a read on it may be running is a race.
    func attach(to handle: FileHandle) {
        let descriptor = handle.fileDescriptor
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: queue)
        source.setEventHandler { [self] in
            let count = read(descriptor, &readBuffer, Self.readChunkSize)
            if count > 0 {
                consume(Data(readBuffer[0..<count]))
            } else if count == 0 || (errno != EINTR && errno != EAGAIN) {
                source.cancel()
                if let closedMarker { continuation.yield(closedMarker) }
            }
        }
        source.setCancelHandler { try? handle.close() }
        self.source = source
        source.resume()
    }

    /// Safe from any thread; the handle closes on the read queue once a running read finishes.
    func stop() {
        source?.cancel()
    }

    private func consume(_ data: Data) {
        let lines = framer.append(data)
        for line in lines {
            if let item = transform(line) { continuation.yield(item) }
        }
    }
}

/// Drives Pi's `--mode rpc` over stdin and stdout. Everything but the pipe readers and the
/// write queue runs on the main actor, so pending requests need no lock.
@MainActor
final class PiRPCDriver: ConversationDriver {
    static let defaultCommandTimeout: Duration = .seconds(30)
    /// Mirrors `PTYSession`'s graceful stop timeout, which is private to that file.
    static let defaultStopTimeout: Duration = .seconds(5)
    private static let stderrLineLimit = 20
    /// How long to wait for stdout and stderr to close after the process ended, in case a grandchild holds a pipe open.
    private static let stdoutDrainTimeout: Duration = .seconds(1)

    private struct Pending {
        let command: String
        let continuation: CheckedContinuation<PiRPCResponse, Error>
        let timeout: Task<Void, Never>?
    }

    var onEvent: (@MainActor (ConversationEvent) -> Void)?
    var onExit: (@MainActor (Int32?) -> Void)?
    private(set) var lastStderrLines: [String] = []

    private let launch: AgentLaunchCommand
    private let launchEnvironment: [String: String]
    private let commandTimeout: Duration
    private let gracePeriod: Duration
    private let stopTimeout: Duration
    private let writeQueue = DispatchQueue(label: "dev.piboard.pirpc.write")

    private var process: Process?
    private var stdinHandle: FileHandle?
    private var pumps: [PiRPCLinePump] = []
    private var inboundContinuation: AsyncStream<PiRPCInbound>.Continuation?
    private var consumer: Task<Void, Never>?
    private var escalation: Task<Void, Never>?
    private var drainTask: Task<Void, Never>?
    private var pending: [String: Pending] = [:]
    private var didTerminate = false
    private var stdoutClosed = false
    private var stderrClosed = false
    private var terminationCode: Int32?
    private var didExit = false

    var processID: pid_t? { liveProcess?.processIdentifier }
    var executablePath: String? { launch.executable.path }

    private var liveProcess: Process? {
        didTerminate || didExit ? nil : process
    }

    private var canWrite: Bool {
        liveProcess != nil && stdinHandle != nil
    }

    init(
        command: AgentLaunchCommand,
        launchEnvironment: [String: String] = LaunchEnvironment.shared.values,
        commandTimeout: Duration = defaultCommandTimeout,
        gracePeriod: Duration = .seconds(ProcessQuitPolicy.gracePeriod),
        stopTimeout: Duration = defaultStopTimeout
    ) {
        self.launch = command
        self.launchEnvironment = launchEnvironment
        self.commandTimeout = commandTimeout
        self.gracePeriod = gracePeriod
        self.stopTimeout = stopTimeout
    }

    // Shell convention for death by signal; without it a crashed chat would look like a clean finish.
    nonisolated private static func exitCode(of process: Process) -> Int32 {
        switch process.terminationReason {
        case .uncaughtSignal: signalExitCodeBase + process.terminationStatus
        default: process.terminationStatus
        }
    }

    // MARK: Lifecycle

    func start() throws {
        guard process == nil else { return }
        let process = Process()
        process.executableURL = launch.executable
        process.arguments = launch.arguments
        process.currentDirectoryURL = launch.currentDirectory
        process.environment = launchEnvironment.merging(launch.environment) { _, override in override }

        let stdin = Pipe()
        let stdout = Pipe()
        let stderr = Pipe()
        process.standardInput = stdin
        process.standardOutput = stdout
        process.standardError = stderr
        process.terminationHandler = { [weak self] finished in
            let code = Self.exitCode(of: finished)
            Task { @MainActor in self?.processTerminated(code) }
        }
        try process.run()

        // A write to a pipe whose reader is gone must fail with EPIPE, not raise SIGPIPE in the app.
        _ = fcntl(stdin.fileHandleForWriting.fileDescriptor, F_SETNOSIGPIPE, 1)

        let (stream, continuation) = AsyncStream.makeStream(of: PiRPCInbound.self)
        let stdoutPump = PiRPCLinePump(continuation: continuation, closedMarker: .stdoutClosed) { line in
            PiRPCCodec.decode(line).map(PiRPCInbound.record)
        }
        stdoutPump.attach(to: stdout.fileHandleForReading)
        let stderrPump = PiRPCLinePump(continuation: continuation, closedMarker: .stderrClosed) { line in
            .stderrLine(String(decoding: line, as: UTF8.self))
        }
        stderrPump.attach(to: stderr.fileHandleForReading)

        self.process = process
        stdinHandle = stdin.fileHandleForWriting
        pumps = [stdoutPump, stderrPump]
        inboundContinuation = continuation
        consumer = Task { @MainActor [weak self] in
            for await item in stream {
                self?.handle(item)
            }
        }
    }

    func shutdown() {
        guard liveProcess != nil, escalation == nil else { return }
        if let handle = stdinHandle {
            stdinHandle = nil
            writeQueue.async { try? handle.close() }
        }
        escalation = Task { @MainActor [weak self] in
            guard let self else { return }
            let grace = gracePeriod
            let stop = stopTimeout
            try? await Task.sleep(for: grace)
            guard !Task.isCancelled, let pid = processID else { return }
            Darwin.kill(pid, SIGTERM)
            try? await Task.sleep(for: stop)
            guard !Task.isCancelled, let pid = processID else { return }
            Darwin.kill(pid, SIGKILL)
        }
    }

    func forceKill() {
        guard let pid = processID else { return }
        Darwin.kill(pid, SIGKILL)
    }

    // MARK: Commands

    func prompt(
        _ text: String,
        images: [PromptImage],
        whileRunning: StreamingBehavior?
    ) async throws -> PromptDisposition {
        // A prompt that opens an extension dialog is answered only after the dialog, so it never times out.
        let response = try await request(.prompt(message: text, images: images, streaming: whileRunning), timeout: nil)
        return PiRPCCodec.disposition(from: response.data)
    }

    func abort() async throws {
        _ = try await request(.abort, timeout: commandTimeout)
    }

    func clearQueue() async throws -> (steering: [String], followUp: [String]) {
        let response = try await request(.clearQueue, timeout: commandTimeout)
        return PiRPCCodec.queue(from: response.data)
    }

    func answer(dialogID: String, with answer: ConversationDialogAnswer) throws {
        guard canWrite else { throw ConversationDriverError.notRunning }
        write(PiRPCCodec.encode(.extensionUIResponse(id: dialogID, answer: answer), id: dialogID), commandID: nil)
    }

    func state() async throws -> ConversationSessionInfo {
        let command = PiRPCCommand.getState
        let response = try await request(command, timeout: commandTimeout)
        guard let info = PiRPCCodec.sessionInfo(from: response.data) else {
            throw ConversationDriverError.malformedResponse(command.wireName)
        }
        return info
    }

    func messages() async throws -> [ConversationMessage] {
        PiRPCCodec.messages(from: try await request(.getMessages, timeout: commandTimeout).data)
    }

    func entries() async throws -> [ConversationEntry] {
        PiRPCCodec.entries(from: try await request(.getEntries, timeout: commandTimeout).data)
    }

    func sessionStats() async throws -> ConversationStats {
        let command = PiRPCCommand.getSessionStats
        let response = try await request(command, timeout: commandTimeout)
        guard let stats = PiRPCCodec.stats(from: response.data) else {
            throw ConversationDriverError.malformedResponse(command.wireName)
        }
        return stats
    }

    func availableModels() async throws -> [ConversationModel] {
        PiRPCCodec.models(from: try await request(.getAvailableModels, timeout: commandTimeout).data)
    }

    func availableThinkingLevels() async throws -> [String] {
        PiRPCCodec.thinkingLevels(from: try await request(.getAvailableThinkingLevels, timeout: commandTimeout).data)
    }

    func setThinkingLevel(_ level: String) async throws {
        _ = try await request(.setThinkingLevel(level), timeout: commandTimeout)
    }

    func setModel(provider: String, modelID: String) async throws {
        _ = try await request(.setModel(provider: provider, modelID: modelID), timeout: commandTimeout)
    }

    func commands() async throws -> [ConversationCommand] {
        PiRPCCodec.commands(from: try await request(.getCommands, timeout: commandTimeout).data)
    }

    // MARK: Request plumbing

    private func request(_ command: PiRPCCommand, timeout: Duration?) async throws -> PiRPCResponse {
        guard canWrite else { throw ConversationDriverError.notRunning }
        let id = UUID().uuidString
        let data = PiRPCCodec.encode(command, id: id)
        let name = command.wireName
        let response = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<PiRPCResponse, Error>) in
            let timer = timeout.map { limit in
                Task { @MainActor [weak self] in
                    try? await Task.sleep(for: limit)
                    guard !Task.isCancelled else { return }
                    self?.expire(id)
                }
            }
            pending[id] = Pending(command: name, continuation: continuation, timeout: timer)
            write(data, commandID: id)
        }
        guard response.success else {
            throw ConversationDriverError.rejected(command: name, message: response.error ?? "")
        }
        return response
    }

    private func write(_ data: Data, commandID: String?) {
        guard let handle = stdinHandle else { return }
        writeQueue.async { [weak self] in
            do {
                try handle.write(contentsOf: data)
            } catch {
                Task { @MainActor in self?.writeFailed(commandID, error: error) }
            }
        }
    }

    private func writeFailed(_ commandID: String?, error: Error) {
        Diagnostics.process.info("pi rpc write failed: \(error.localizedDescription, privacy: .public)")
        guard let commandID, let entry = pending.removeValue(forKey: commandID) else { return }
        entry.timeout?.cancel()
        entry.continuation.resume(throwing: ConversationDriverError.notRunning)
    }

    private func expire(_ id: String) {
        guard let entry = pending.removeValue(forKey: id) else { return }
        entry.continuation.resume(throwing: ConversationDriverError.timeout(entry.command))
    }

    private func resolve(_ response: PiRPCResponse) {
        // A response to a command nobody waits for any more (timed out) is dropped.
        guard let id = response.id, let entry = pending.removeValue(forKey: id) else { return }
        entry.timeout?.cancel()
        entry.continuation.resume(returning: response)
    }

    // MARK: Inbound

    private func handle(_ item: PiRPCInbound) {
        // A record that arrives after the exit was reported must not revive the session.
        if didExit, case .record = item { return }
        switch item {
        case .record(.response(let response)):
            resolve(response)
        case .record(.events(let events)):
            for event in events { onEvent?(event) }
        case .stderrLine(let line):
            // Diagnostics only: Pi warns on stderr even when healthy, so it is never treated as failure.
            Diagnostics.process.info("pi rpc stderr: \(line)")
            lastStderrLines.append(line)
            if lastStderrLines.count > Self.stderrLineLimit {
                lastStderrLines.removeFirst(lastStderrLines.count - Self.stderrLineLimit)
            }
        case .stdoutClosed:
            stdoutClosed = true
            completeExitIfReady()
        case .stderrClosed:
            stderrClosed = true
            completeExitIfReady()
        }
    }

    private func processTerminated(_ code: Int32?) {
        didTerminate = true
        terminationCode = code
        escalation?.cancel()
        escalation = nil
        if stdoutClosed && stderrClosed {
            completeExit()
        } else {
            drainTask = Task { @MainActor [weak self] in
                try? await Task.sleep(for: Self.stdoutDrainTimeout)
                guard !Task.isCancelled else { return }
                self?.completeExit()
            }
        }
    }

    /// Exit is reported only after both pipes drained, so the last events and the end of a crash trace are not lost.
    private func completeExitIfReady() {
        guard didTerminate, stdoutClosed, stderrClosed else { return }
        completeExit()
    }

    private func completeExit() {
        guard !didExit else { return }
        didExit = true
        drainTask?.cancel()
        drainTask = nil
        // Without shutdown() nothing else closes the write end, which would leak the descriptor.
        if let handle = stdinHandle {
            stdinHandle = nil
            writeQueue.async { try? handle.close() }
        }
        for pump in pumps { pump.stop() }
        pumps = []
        let failed = pending
        pending = [:]
        for entry in failed.values {
            entry.timeout?.cancel()
            entry.continuation.resume(throwing: ConversationDriverError.exited)
        }
        inboundContinuation?.finish()
        inboundContinuation = nil
        consumer = nil
        onExit?(terminationCode)
    }
}
