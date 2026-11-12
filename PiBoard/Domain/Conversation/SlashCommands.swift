import Foundation

/// Filtering and checking of `/commands` against the list the agent reports; nothing else is treated as a command.
enum SlashCommands {
    private static let marker: Character = "/"

    /// What follows the slash while the user is still typing the command name; nil once there is any whitespace or no slash.
    static func fragment(in text: String) -> String? {
        guard text.first == marker, !text.contains(where: \.isWhitespace) else { return nil }
        return String(text.dropFirst())
    }

    /// Prefix matches first, then names that merely contain the fragment; each group keeps the agent's order.
    static func matches(for fragment: String, in commands: [ConversationCommand]) -> [ConversationCommand] {
        guard !fragment.isEmpty else { return commands }
        let needle = fragment.lowercased()
        var prefixed: [ConversationCommand] = []
        var containing: [ConversationCommand] = []
        for command in commands {
            let name = command.name.lowercased()
            if name.hasPrefix(needle) {
                prefixed.append(command)
            } else if name.contains(needle) {
                containing.append(command)
            }
        }
        return prefixed + containing
    }

    /// A fully typed command name is sent as it is; the list only completes partial names.
    static func isExact(fragment: String?, in commands: [ConversationCommand]) -> Bool {
        guard let fragment else { return false }
        return commands.contains { $0.name == fragment }
    }

    static func insertion(for command: ConversationCommand) -> String {
        "\(marker)\(command.name) "
    }

    /// The command name when the message starts with a `/word` the agent does not list; nil for paths, plain text and an unknown list.
    static func unknownCommand(in text: String, known: [ConversationCommand]) -> String? {
        guard !known.isEmpty else { return nil }
        let token = text.trimmingCharacters(in: .whitespacesAndNewlines).prefix { !$0.isWhitespace }
        guard token.first == marker, token.count > 1 else { return nil }
        let name = String(token.dropFirst())
        // A second slash makes it a file path, not a command.
        guard !name.contains(marker) else { return nil }
        return known.contains { $0.name == name } ? nil : name
    }
}
