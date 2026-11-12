import Foundation

/// The one-line argument preview next to a tool call's name.
enum ToolCallSummary {
    static let maxLength = 80
    private static let preferredKeys = ["path", "command", "pattern", "query", "agent", "name"]
    private static let ellipsis = "\u{2026}"

    static func argumentSummary(json: String) -> String? {
        guard let data = json.data(using: .utf8),
              let object = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any]
        else { return nil }
        let preferred = preferredKeys.lazy.compactMap { object[$0] as? String }.first
        // Sorted so "the first string" does not change between renders of an unordered dictionary.
        let fallback = object.keys.sorted().lazy.compactMap { object[$0] as? String }.first
        guard let value = preferred ?? fallback else { return nil }
        let line = value.split(whereSeparator: \.isNewline).joined(separator: " ")
        guard line.count > maxLength else { return line }
        return String(line.prefix(maxLength - ellipsis.count)) + ellipsis
    }
}
