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
    private static let patterns: [(activity: AgentActivity, bytes: [UInt8])] = [(.working, working), (.idle, idle)]
    /// A sequence can straddle two reads, so this many trailing bytes are kept for the next scan.
    private static let carryLength = max(working.count, idle.count) - 1

    private var carry: [UInt8] = []

    /// Returns the activity changes found in `bytes`, in the order they appear.
    mutating func scan(_ bytes: some RandomAccessCollection<UInt8>) -> [AgentActivity] {
        var found: [AgentActivity] = []
        var index = bytes.startIndex

        // The carry is shorter than any pattern, so a match that starts in it must end in the new
        // bytes: it is new, and it was not reportable before. Later carry positions would overlap it.
        for start in carry.indices {
            guard let (activity, consumed) = matchAcrossBoundary(from: start, bytes) else { continue }
            found.append(activity)
            index = bytes.index(bytes.startIndex, offsetBy: consumed)
            break
        }

        while index < bytes.endIndex {
            guard let (activity, length) = Self.match(bytes, at: index) else {
                index = bytes.index(after: index)
                continue
            }
            found.append(activity)
            index = bytes.index(index, offsetBy: length)
        }

        updateCarry(with: bytes)
        return found
    }

    /// Matches a pattern whose head is `carry[start...]` and whose tail opens `bytes`.
    private func matchAcrossBoundary(
        from start: Int,
        _ bytes: some RandomAccessCollection<UInt8>
    ) -> (AgentActivity, consumed: Int)? {
        let carried = carry[start...]
        for (activity, pattern) in Self.patterns {
            let remaining = pattern.count - carried.count
            guard remaining > 0, bytes.count >= remaining,
                  carried.elementsEqual(pattern.prefix(carried.count)),
                  bytes.prefix(remaining).elementsEqual(pattern.suffix(remaining))
            else { continue }
            return (activity, remaining)
        }
        return nil
    }

    private static func match<Bytes: RandomAccessCollection<UInt8>>(
        _ bytes: Bytes,
        at index: Bytes.Index
    ) -> (AgentActivity, length: Int)? {
        for (activity, pattern) in patterns {
            guard bytes.distance(from: index, to: bytes.endIndex) >= pattern.count else { continue }
            let end = bytes.index(index, offsetBy: pattern.count)
            if bytes[index..<end].elementsEqual(pattern) { return (activity, pattern.count) }
        }
        return nil
    }

    private mutating func updateCarry(with bytes: some RandomAccessCollection<UInt8>) {
        if bytes.count >= Self.carryLength {
            carry = Array(bytes.suffix(Self.carryLength))
        } else {
            // Bounded by the carry length plus a chunk shorter than it.
            carry = Array((carry + bytes).suffix(Self.carryLength))
        }
    }
}
