import Foundation

struct SSEEvent: Equatable, Sendable {
    var event: String?
    var data: String
    var id: String?
}

/// Incremental parser for `text/event-stream`. Chunks may end anywhere, so an incomplete trailing
/// line stays buffered until the next feed.
struct SSEParser {
    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")
    private static let colon = UInt8(ascii: ":")
    private static let space = UInt8(ascii: " ")
    private static let dataField = "data"
    private static let eventField = "event"
    private static let idField = "id"
    private static let dataSeparator = "\n"

    private var buffer: [UInt8] = []
    private var event: String?
    private var id: String?
    private var dataLines: [String] = []

    mutating func feed(_ bytes: some Collection<UInt8>) -> [SSEEvent] {
        buffer.append(contentsOf: bytes)
        var events: [SSEEvent] = []
        var lineStart = buffer.startIndex
        while let newline = buffer[lineStart...].firstIndex(of: Self.lineFeed) {
            var line = buffer[lineStart..<newline]
            if line.last == Self.carriageReturn {
                line = line.dropLast()
            }
            if let dispatched = process(line) {
                events.append(dispatched)
            }
            lineStart = buffer.index(after: newline)
        }
        buffer.removeSubrange(buffer.startIndex..<lineStart)
        return events
    }

    private mutating func process(_ line: ArraySlice<UInt8>) -> SSEEvent? {
        if line.isEmpty {
            return dispatch()
        }
        // Comment lines (heartbeats) start with a colon.
        if line.first == Self.colon {
            return nil
        }
        let name: ArraySlice<UInt8>
        var value: ArraySlice<UInt8> = []
        if let separator = line.firstIndex(of: Self.colon) {
            name = line[line.startIndex..<separator]
            value = line[line.index(after: separator)...]
            if value.first == Self.space {
                value = value.dropFirst()
            }
        } else {
            name = line
        }
        let text = String(decoding: value, as: UTF8.self)
        switch String(decoding: name, as: UTF8.self) {
        case Self.dataField: dataLines.append(text)
        case Self.eventField: event = text
        case Self.idField: id = text
        default: break
        }
        return nil
    }

    private mutating func dispatch() -> SSEEvent? {
        defer {
            event = nil
            id = nil
            dataLines = []
        }
        guard !dataLines.isEmpty else { return nil }
        return SSEEvent(event: event, data: dataLines.joined(separator: Self.dataSeparator), id: id)
    }
}
