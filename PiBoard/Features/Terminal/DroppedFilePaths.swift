import Foundation

/// Turns files dropped on the terminal into the text that gets typed into it.
///
/// The terminal may be running Pi or a plain login shell, and the drop cannot tell which, so the
/// paths are quoted the way a POSIX shell needs them. Pi's prompt reads the quotes fine, while an
/// unquoted path with a space would silently split into two arguments in a shell.
enum DroppedFilePaths {
    private static let separator = " "
    private static let quote = "'"
    /// A single-quoted string cannot contain a quote, so it is closed, escaped and reopened.
    private static let escapedQuote = "'\\''"
    /// Characters that pass through every shell unchanged. Anything else forces quoting.
    private static let unquotedCharacters = CharacterSet.alphanumerics.union(CharacterSet(charactersIn: "./_-+,:@%="))

    /// Ends with a separator so the next drop or keystroke does not run into the last path.
    static func text(for urls: [URL]) -> String {
        guard !urls.isEmpty else { return "" }
        return urls.map { quoted($0.path) }.joined(separator: separator) + separator
    }

    static func quoted(_ path: String) -> String {
        guard path.isEmpty || path.unicodeScalars.contains(where: { !unquotedCharacters.contains($0) }) else {
            return path
        }
        return quote + path.replacingOccurrences(of: quote, with: escapedQuote) + quote
    }
}
