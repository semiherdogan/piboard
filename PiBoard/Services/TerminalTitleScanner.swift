import Foundation

/// Reads Claude Code's activity off the terminal title it sets with `ESC ] 0 ; <glyph> <name> BEL`.
///
/// Claude Code emits no OSC 9;4 in a pty, so the title glyph is the only in-band working/idle
/// signal, and unlike a turn-end event it returns to idle after an interrupt. Pinned to the
/// behaviour verified against Claude Code 2.1.294: a spinner glyph while working, an asterisk
/// when idle, an empty title on exit.
struct TerminalTitleScanner: TerminalActivityScanning {
    private static let esc: UInt8 = 0x1b
    private static let bel: UInt8 = 0x07
    private static let oscOpen = UInt8(ascii: "]")
    private static let stringTerminator = UInt8(ascii: "\\")
    private static let semicolon = UInt8(ascii: ";")
    private static let titleCommands: Set<UInt8> = [UInt8(ascii: "0"), UInt8(ascii: "1"), UInt8(ascii: "2")]
    private static let maxTitleLength = 256
    private static let workingGlyphs: Set<Character> = ["\u{25D0}", "\u{25D1}", "\u{25D2}", "\u{25D3}"]
    private static let idleGlyph: Character = "\u{2733}"

    private enum State {
        case text
        case escape
        case command
        case separator
        case title
    }

    private var state = State.text
    private var title: [UInt8] = []
    /// An ESC inside the title may start the `ESC \` terminator.
    private var pendingEscape = false

    mutating func scan(_ bytes: some RandomAccessCollection<UInt8>) -> [AgentActivity] {
        var found: [AgentActivity] = []
        for byte in bytes {
            if let activity = consume(byte) { found.append(activity) }
        }
        return found
    }

    private mutating func consume(_ byte: UInt8) -> AgentActivity? {
        switch state {
        case .text:
            if byte == Self.esc { state = .escape }
        case .escape:
            state = byte == Self.oscOpen ? .command : (byte == Self.esc ? .escape : .text)
        case .command:
            state = Self.titleCommands.contains(byte) ? .separator : (byte == Self.esc ? .escape : .text)
        case .separator:
            if byte == Self.semicolon {
                state = .title
                title.removeAll(keepingCapacity: true)
                pendingEscape = false
            } else {
                state = byte == Self.esc ? .escape : .text
            }
        case .title:
            return consumeTitleByte(byte)
        }
        return nil
    }

    private mutating func consumeTitleByte(_ byte: UInt8) -> AgentActivity? {
        if pendingEscape {
            pendingEscape = false
            if byte == Self.stringTerminator { return finishTitle() }
            // Any other byte after ESC abandons the title; ESC itself may open the next sequence.
            state = byte == Self.esc ? .escape : .text
            return nil
        }
        switch byte {
        case Self.bel:
            return finishTitle()
        case Self.esc:
            pendingEscape = true
        default:
            title.append(byte)
            if title.count > Self.maxTitleLength { state = .text }
        }
        return nil
    }

    private mutating func finishTitle() -> AgentActivity? {
        state = .text
        guard let glyph = String(decoding: title, as: UTF8.self).first else { return nil }
        if Self.workingGlyphs.contains(glyph) { return .working }
        if glyph == Self.idleGlyph { return .idle }
        return nil
    }
}
