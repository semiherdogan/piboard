import Foundation

/// Reads Claude Code's session JSONL into a `SessionSummary`. Read-only: the file belongs to Claude Code.
enum ClaudeSessionReader {
    private enum Key {
        static let type = "type"
        static let customTitle = "customTitle"
        static let message = "message"
        static let id = "id"
        static let content = "content"
        static let text = "text"
        static let model = "model"
        static let usage = "usage"
        static let timestamp = "timestamp"
        static let inputTokens = "input_tokens"
        static let outputTokens = "output_tokens"
        static let cacheReadTokens = "cache_read_input_tokens"
        static let cacheWriteTokens = "cache_creation_input_tokens"
        static let totalCostUSD = "totalCostUSD"
        static let name = "name"
        static let input = "input"
        static let filePath = "file_path"
        static let notebookPath = "notebook_path"
    }

    private enum EntryType {
        static let customTitle = "custom-title"
        static let user = "user"
        static let assistant = "assistant"
        static let costState = "cost-state"
    }

    private enum BlockType {
        static let text = "text"
        static let toolUse = "tool_use"
    }

    private enum ClaudeTool {
        static let edit = "Edit"
        static let write = "Write"
        static let multiEdit = "MultiEdit"
        static let notebookEdit = "NotebookEdit"
    }

    /// The `input` key that holds the target path, per file-changing tool.
    private static let pathKeyByTool: [String: String] = [
        ClaudeTool.edit: Key.filePath,
        ClaudeTool.write: Key.filePath,
        ClaudeTool.multiEdit: Key.filePath,
        ClaudeTool.notebookEdit: Key.notebookPath
    ]

    private struct PendingAssistant {
        let id: String?
        let timestamp: Date?
        var texts: [String] = []
    }

    private static let newline: UInt8 = 0x0A
    private static let textBlockSeparator = "\n"
    private static let plainTimestampOptions: ISO8601DateFormatter.Options = [.withInternetDateTime]

    static func read(file: URL) throws -> SessionSummary {
        let data = try Data(contentsOf: file)
        var summary = SessionSummary()
        var lastAssistantID: String?
        for line in data.split(separator: newline, omittingEmptySubsequences: true) {
            guard let entry = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any] else { continue }
            apply(entry, to: &summary, lastAssistantID: &lastAssistantID)
        }
        let usage = summary.usage
        summary.usage.total = usage.input + usage.output + usage.cacheRead + usage.cacheWrite
        return summary
    }

    static func transcript(file: URL) throws -> SessionTranscript {
        transcript(try Data(contentsOf: file))
    }

    static func transcript(_ data: Data) -> SessionTranscript {
        var transcript = SessionTranscript()
        var pending: PendingAssistant?
        func flush() {
            guard let current = pending else { return }
            transcript.append(.assistant, text: current.texts.joined(separator: textBlockSeparator), timestamp: current.timestamp)
            pending = nil
        }
        for line in data.split(separator: newline, omittingEmptySubsequences: true) {
            guard let entry = (try? JSONSerialization.jsonObject(with: line)) as? [String: Any],
                  let message = entry[Key.message] as? [String: Any]
            else { continue }
            let timestamp = (entry[Key.timestamp] as? String).flatMap(date(from:))
            switch entry[Key.type] as? String {
            case EntryType.user:
                let content = message[Key.content]
                let text = (content as? String) ?? textBlocks(of: content).joined(separator: textBlockSeparator)
                // A user entry of only tool results is tool output and ends nothing.
                guard !text.isEmpty else { continue }
                flush()
                transcript.append(.user, text: text, timestamp: timestamp)
            case EntryType.assistant:
                let id = message[Key.id] as? String
                if id == nil || id != pending?.id {
                    flush()
                    pending = PendingAssistant(id: id, timestamp: timestamp)
                }
                pending?.texts.append(contentsOf: textBlocks(of: message[Key.content]))
                noteChangedFiles(in: message[Key.content], to: &transcript)
            default:
                break
            }
        }
        flush()
        return transcript
    }

    private static func noteChangedFiles(in content: Any?, to transcript: inout SessionTranscript) {
        guard let blocks = content as? [[String: Any]] else { return }
        for block in blocks where block[Key.type] as? String == BlockType.toolUse {
            guard let name = block[Key.name] as? String,
                  let pathKey = pathKeyByTool[name],
                  let path = (block[Key.input] as? [String: Any])?[pathKey] as? String
            else { continue }
            transcript.noteChangedFile(path)
        }
    }

    private static func apply(_ entry: [String: Any], to summary: inout SessionSummary, lastAssistantID: inout String?) {
        if let timestamp = (entry[Key.timestamp] as? String).flatMap(date(from:)) {
            summary.lastActivity = max(summary.lastActivity ?? timestamp, timestamp)
        }
        let message = entry[Key.message] as? [String: Any]
        switch entry[Key.type] as? String {
        case EntryType.customTitle:
            if let title = entry[Key.customTitle] as? String {
                summary.name = title
            }
        case EntryType.user:
            if hasUserText(message?[Key.content]) {
                summary.turnCount += 1
            }
        case EntryType.assistant:
            let id = message?[Key.id] as? String
            // Claude Code writes one entry per content block of a response, each repeating id and usage.
            let isContinuation = id != nil && id == lastAssistantID
            lastAssistantID = id
            if !isContinuation {
                summary.assistantMessageCount += 1
            }
            guard let message else { return }
            if let model = message[Key.model] as? String {
                summary.model = model
            }
            if !isContinuation {
                addUsage(of: message, to: &summary)
            }
            let text = textBlocks(of: message[Key.content]).joined(separator: textBlockSeparator)
            if !text.isEmpty {
                summary.lastAssistantText = text
            }
        case EntryType.costState:
            if let cost = entry[Key.totalCostUSD] as? NSNumber {
                summary.usage.cost = cost.doubleValue
            }
        default:
            break
        }
    }

    private static func hasUserText(_ content: Any?) -> Bool {
        content is String || !textBlocks(of: content).isEmpty
    }

    private static func textBlocks(of content: Any?) -> [String] {
        guard let blocks = content as? [[String: Any]] else { return [] }
        return blocks.compactMap { block in
            guard block[Key.type] as? String == BlockType.text else { return nil }
            return block[Key.text] as? String
        }
    }

    private static func addUsage(of message: [String: Any], to summary: inout SessionSummary) {
        guard let usage = message[Key.usage] as? [String: Any] else { return }
        summary.usage.input += int(usage[Key.inputTokens])
        summary.usage.output += int(usage[Key.outputTokens])
        summary.usage.cacheRead += int(usage[Key.cacheReadTokens])
        summary.usage.cacheWrite += int(usage[Key.cacheWriteTokens])
    }

    private static func int(_ value: Any?) -> Int {
        (value as? NSNumber)?.intValue ?? 0
    }

    private static func date(from string: String) -> Date? {
        if let date = ISO8601Format.date(from: string) {
            return date
        }
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = plainTimestampOptions
        return formatter.date(from: string)
    }
}
