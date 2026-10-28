import Foundation

/// Reads Pi's session JSONL into a `SessionSummary`. Read-only: the file belongs to Pi.
enum PiSessionReader {
    // JSON keys and values of the Pi session format; see docs/session-format.md in the Pi repository.
    private enum Key {
        static let type = "type"
        static let message = "message"
        static let role = "role"
        static let content = "content"
        static let text = "text"
        static let model = "model"
        static let modelId = "modelId"
        static let usage = "usage"
        static let name = "name"
        static let timestamp = "timestamp"
        static let input = "input"
        static let output = "output"
        static let cacheRead = "cacheRead"
        static let cacheWrite = "cacheWrite"
        static let totalTokens = "totalTokens"
        static let cost = "cost"
        static let total = "total"
    }

    private enum EntryType {
        static let message = "message"
        static let sessionInfo = "session_info"
        static let modelChange = "model_change"
        static let usage = "usage"
        static let compaction = "compaction"
        static let branchSummary = "branch_summary"
    }

    private enum Role {
        static let user = "user"
        static let assistant = "assistant"
    }

    private enum BlockType {
        static let text = "text"
    }

    private struct ParseState {
        var summary = SessionSummary()
        var sawModelChange = false
    }

    // Pi writes compact JSON without spaces; a line with none of these is skipped unread.
    private static let interestingMarkers: [Data] = [
        #""role":"user""#,
        #""role":"assistant""#,
        #""type":"session_info""#,
        #""type":"model_change""#,
        #""type":"usage""#,
        #""type":"compaction""#,
        #""type":"branch_summary""#
    ].map { Data($0.utf8) }
    private static let newline: UInt8 = 0x0A
    private static let textBlockSeparator = "\n"

    static func read(file: URL) throws -> SessionSummary {
        summarize(try Data(contentsOf: file))
    }

    static func summarize(_ data: Data) -> SessionSummary {
        var state = ParseState()
        for line in data.split(separator: newline, omittingEmptySubsequences: true) {
            apply(line: line, to: &state)
        }
        return state.summary
    }

    private static func apply(line: Data, to state: inout ParseState) {
        guard interestingMarkers.contains(where: { line.range(of: $0) != nil }),
              let entry = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
              let type = entry[Key.type] as? String
        else { return }

        if let timestamp = (entry[Key.timestamp] as? String).flatMap(ISO8601Format.date(from:)) {
            state.summary.lastActivity = max(state.summary.lastActivity ?? timestamp, timestamp)
        }

        switch type {
        case EntryType.message:
            guard let message = entry[Key.message] as? [String: Any] else { return }
            applyMessage(message, to: &state)
        case EntryType.sessionInfo:
            if let name = entry[Key.name] as? String, !name.isEmpty {
                state.summary.name = name
            }
        case EntryType.modelChange:
            if let modelId = entry[Key.modelId] as? String {
                state.summary.model = modelId
                state.sawModelChange = true
            }
        case EntryType.usage, EntryType.compaction, EntryType.branchSummary:
            addUsage(of: entry, to: &state)
        default:
            break
        }
    }

    private static func applyMessage(_ message: [String: Any], to state: inout ParseState) {
        switch message[Key.role] as? String {
        case Role.user:
            if hasUserText(message[Key.content]) {
                state.summary.turnCount += 1
            }
        case Role.assistant:
            state.summary.assistantMessageCount += 1
            let text = textBlocks(of: message[Key.content]).joined(separator: textBlockSeparator)
            if !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                state.summary.lastAssistantText = text
            }
            if !state.sawModelChange, let model = message[Key.model] as? String {
                state.summary.model = model
            }
            addUsage(of: message, to: &state)
        default:
            break
        }
    }

    private static func hasUserText(_ content: Any?) -> Bool {
        if let string = content as? String {
            return !string.isEmpty
        }
        return !textBlocks(of: content).isEmpty
    }

    private static func textBlocks(of content: Any?) -> [String] {
        guard let blocks = content as? [[String: Any]] else { return [] }
        return blocks.compactMap { block in
            guard block[Key.type] as? String == BlockType.text else { return nil }
            return block[Key.text] as? String
        }
    }

    private static func addUsage(of container: [String: Any], to state: inout ParseState) {
        guard let usage = container[Key.usage] as? [String: Any] else { return }
        let cost = usage[Key.cost] as? [String: Any]
        state.summary.usage = state.summary.usage + SessionSummary.Usage(
            input: int(usage[Key.input]),
            output: int(usage[Key.output]),
            cacheRead: int(usage[Key.cacheRead]),
            cacheWrite: int(usage[Key.cacheWrite]),
            total: int(usage[Key.totalTokens]),
            cost: double(cost?[Key.total])
        )
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func double(_ value: Any?) -> Double {
        (value as? NSNumber)?.doubleValue ?? 0
    }
}
