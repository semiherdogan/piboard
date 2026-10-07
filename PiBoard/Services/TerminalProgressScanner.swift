import Foundation

/// Reads Pi's activity off the raw pty stream by spotting its OSC 9;4 progress sequences.
///
/// SwiftTerm parses these too, but it consumes them for its own progress bar and its handler is
/// not overridable from outside the package. Scanning the bytes PiBoard already receives avoids
/// depending on package internals and keeps the detection unit testable.
///
/// Pi writes exactly two sequences: `ESC ] 9 ; 4 ; 3 BEL` when a turn starts, repeated once a
/// second as a keepalive, and `ESC ] 9 ; 4 ; 0 BEL` when the agent ends.
struct TerminalProgressScanner {
    private static let working: [UInt8] = Array("\u{1b}]9;4;3\u{07}".utf8)
    private static let idle: [UInt8] = Array("\u{1b}]9;4;0\u{07}".utf8)
    /// A sequence can straddle two reads, so this many trailing bytes are kept for the next scan.
    private static let carryLength = max(working.count, idle.count) - 1

    private var carry: [UInt8] = []

    /// Returns the activity changes found in `bytes`, in the order they appear.
    mutating func scan(_ bytes: [UInt8]) -> [AgentActivity] {
        // The carry was already scanned on its own; only matches that cross into the new bytes are
        // new, and those necessarily end at or after the join.
        let joinIndex = carry.count
        let buffer = carry + bytes
        carry = Array(buffer.suffix(Self.carryLength))

        var found: [AgentActivity] = []
        var index = 0
        while index < buffer.count {
            guard let (activity, length) = Self.match(buffer, at: index) else {
                index += 1
                continue
            }
            // A match is new exactly when it ends past the join; anything before it was already
            // reported on the previous scan.
            if index + length > joinIndex {
                found.append(activity)
            }
            index += length
        }
        return found
    }

    private static func match(_ buffer: [UInt8], at index: Int) -> (AgentActivity, length: Int)? {
        if matches(working, in: buffer, at: index) { return (.working, working.count) }
        if matches(idle, in: buffer, at: index) { return (.idle, idle.count) }
        return nil
    }

    private static func matches(_ pattern: [UInt8], in buffer: [UInt8], at index: Int) -> Bool {
        guard index + pattern.count <= buffer.count else { return false }
        for offset in 0..<pattern.count where buffer[index + offset] != pattern[offset] {
            return false
        }
        return true
    }
}
