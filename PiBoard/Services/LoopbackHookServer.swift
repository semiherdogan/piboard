import Foundation
import Network

/// Receives the HTTP POSTs an agent's hooks send to PiBoard; the handler gets the request path and body.
protocol HookServing: AnyObject, Sendable {
    /// Starts listening on 127.0.0.1 and returns the port.
    func start(handler: @escaping @Sendable (_ path: String, _ body: Data) -> Void) async throws -> UInt16
}

enum LoopbackHookServerError: Error, Equatable, LocalizedError {
    case notReady
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .notReady: "The hook server did not become ready in time."
        case .failed(let detail): "The hook server could not start: \(detail)"
        }
    }
}

// Every mutable property is touched only on `queue`, which also runs the listener, the connections and the handler.
final class LoopbackHookServer: HookServing, @unchecked Sendable {
    private static let host: NWEndpoint.Host = "127.0.0.1"
    private static let maxConnections = 32
    private static let idleTimeout: DispatchTimeInterval = .seconds(10)
    private static let maxRequestBytes = 1 << 20
    private static let receiveChunkBytes = 64 * 1024
    private static let queueLabel = "dev.piboard.hook-server"
    private static let headerTerminator = Data("\r\n\r\n".utf8)
    private static let lineSeparator = "\r\n"
    private static let headerSeparator: Character = ":"
    private static let requestLineSeparator: Character = " "
    private static let requestLinePartCount = 3
    private static let queryMarker: Character = "?"
    private static let contentLengthHeader = "content-length"
    private static let okResponse = Data(
        "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: 2\r\nConnection: close\r\n\r\n{}".utf8
    )
    private static let badRequestResponse = Data(
        "HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n".utf8
    )

    private enum ParseResult {
        case incomplete
        case invalid
        case complete(path: String, body: Data)
    }

    /// Touched only on `queue`, where the listener's state handler runs.
    private final class ResumeGuard: @unchecked Sendable {
        var isResumed = false
    }

    private let queue = DispatchQueue(label: LoopbackHookServer.queueLabel)
    private var listener: NWListener?
    private var connections: [ObjectIdentifier: NWConnection] = [:]
    private var handler: (@Sendable (String, Data) -> Void)?

    func start(handler: @escaping @Sendable (_ path: String, _ body: Data) -> Void) async throws -> UInt16 {
        stop()
        let parameters = NWParameters.tcp
        parameters.requiredLocalEndpoint = .hostPort(host: Self.host, port: .any)
        let listener: NWListener
        do {
            listener = try NWListener(using: parameters)
        } catch {
            throw LoopbackHookServerError.failed(error.localizedDescription)
        }
        listener.newConnectionHandler = { [weak self] connection in self?.accept(connection) }
        queue.sync {
            self.listener = listener
            self.handler = handler
        }
        let queue = queue
        let port: UInt16
        do {
            port = try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<UInt16, Error>) in
                let guardFlag = ResumeGuard()
                listener.stateUpdateHandler = { state in
                    guard !guardFlag.isResumed else { return }
                    switch state {
                    case .ready:
                        guardFlag.isResumed = true
                        if let port = listener.port {
                            continuation.resume(returning: port.rawValue)
                        } else {
                            continuation.resume(throwing: LoopbackHookServerError.notReady)
                        }
                    case .failed(let error):
                        guardFlag.isResumed = true
                        continuation.resume(throwing: LoopbackHookServerError.failed(error.localizedDescription))
                    case .cancelled:
                        guardFlag.isResumed = true
                        continuation.resume(throwing: LoopbackHookServerError.notReady)
                    default:
                        break
                    }
                }
                listener.start(queue: queue)
            }
        } catch {
            stop()
            throw error
        }
        return port
    }

    func stop() {
        queue.sync {
            listener?.cancel()
            listener = nil
            connections.values.forEach { $0.cancel() }
            connections.removeAll()
            handler = nil
        }
    }

    private func accept(_ connection: NWConnection) {
        guard connections.count < Self.maxConnections else {
            connection.cancel()
            return
        }
        let id = ObjectIdentifier(connection)
        connections[id] = connection
        // Hooks are short POSTs, so anything lingering is not a hook.
        queue.asyncAfter(deadline: .now() + Self.idleTimeout) { [weak self] in
            self?.connections.removeValue(forKey: id)?.cancel()
        }
        connection.stateUpdateHandler = { [weak self] state in
            switch state {
            case .failed, .cancelled: self?.connections.removeValue(forKey: id)
            default: break
            }
        }
        connection.start(queue: queue)
        receive(on: connection, buffer: Data())
    }

    private func receive(on connection: NWConnection, buffer: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: Self.receiveChunkBytes) { [weak self] data, _, isComplete, error in
            guard let self else { return }
            var buffer = buffer
            if let data { buffer.append(data) }
            guard buffer.count <= Self.maxRequestBytes else {
                connection.cancel()
                return
            }
            switch Self.parse(buffer) {
            case .complete(let path, let body):
                handler?(path, body)
                reply(Self.okResponse, on: connection)
            case .invalid:
                reply(Self.badRequestResponse, on: connection)
            case .incomplete:
                if error != nil || isComplete {
                    connection.cancel()
                } else {
                    receive(on: connection, buffer: buffer)
                }
            }
        }
    }

    private func reply(_ response: Data, on connection: NWConnection) {
        connection.send(content: response, completion: .contentProcessed { _ in connection.cancel() })
    }

    private static func parse(_ buffer: Data) -> ParseResult {
        guard let terminator = buffer.range(of: headerTerminator) else { return .incomplete }
        guard let head = String(data: buffer[buffer.startIndex..<terminator.lowerBound], encoding: .utf8) else { return .invalid }
        let lines = head.components(separatedBy: lineSeparator)
        let requestLine = lines[0].split(separator: requestLineSeparator, omittingEmptySubsequences: true)
        guard requestLine.count == requestLinePartCount else { return .invalid }
        var contentLength = 0
        for line in lines.dropFirst() {
            guard let separator = line.firstIndex(of: headerSeparator) else { continue }
            let name = line[line.startIndex..<separator].trimmingCharacters(in: .whitespaces).lowercased()
            guard name == contentLengthHeader else { continue }
            let value = line[line.index(after: separator)...].trimmingCharacters(in: .whitespaces)
            guard let length = Int(value), length >= 0 else { return .invalid }
            contentLength = length
        }
        let bodyStart = terminator.upperBound
        guard buffer.endIndex - bodyStart >= contentLength else { return .incomplete }
        let target = requestLine[1]
        let path = target.split(separator: queryMarker, maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        return .complete(path: path, body: Data(buffer[bodyStart..<(bodyStart + contentLength)]))
    }
}
