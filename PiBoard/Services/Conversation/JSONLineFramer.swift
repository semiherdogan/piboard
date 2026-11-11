import Foundation

/// Splits a byte stream into JSONL records on LF only. U+2028 and U+2029 are legal inside JSON
/// strings, so any `String` or `readline` style splitting would cut records apart.
struct JSONLineFramer: Sendable {
    private static let lineFeed = UInt8(ascii: "\n")
    private static let carriageReturn = UInt8(ascii: "\r")

    private var buffer = Data()
    /// Leading bytes of `buffer` already known to hold no LF, so a growing partial line is not rescanned.
    private var scannedCount = 0

    /// Returns the complete, non-empty lines in `data`; a partial tail waits for the next call.
    mutating func append(_ data: Data) -> [Data] {
        buffer.append(data)
        var lines: [Data] = []
        var start = buffer.startIndex
        var searchFrom = buffer.startIndex + scannedCount
        while let newline = buffer[searchFrom...].firstIndex(of: Self.lineFeed) {
            var line = buffer[start..<newline]
            if line.last == Self.carriageReturn { line = line.dropLast() }
            if !line.isEmpty { lines.append(Data(line)) }
            start = buffer.index(after: newline)
            searchFrom = start
        }
        if start != buffer.startIndex {
            buffer = Data(buffer[start...])
        }
        scannedCount = buffer.count
        return lines
    }
}
