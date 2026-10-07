import Foundation

/// Turns a Git remote into the address a browser can open.
///
/// Remotes are written in whatever form the user cloned with: an `scp`-style `git@host:path`, an
/// `ssh://` URL with a port, or an `https://` URL that may carry a username. None of those open in
/// a browser as they are, and the host decides nothing here: GitHub, Bitbucket and self-hosted
/// Forgejo all browse at `<host>/<path>`.
enum GitRemoteURL {
    private static let httpsScheme = "https"
    /// Schemes already browsable; the one in the remote is preserved so an internal HTTP-only
    /// server keeps working.
    private static let browsableSchemes: Set<String> = ["http", "https"]
    /// Transport-only schemes, rewritten to HTTPS.
    private static let rewrittenSchemes: Set<String> = ["ssh", "git"]
    private static let dotGitSuffix = ".git"
    private static let pathSeparator = "/"
    /// `user@host:path`, the form `git clone git@github.com:owner/repo.git` writes. The host part
    /// rejects slashes so a plain path such as `/Volumes/My Disk:2/repo` cannot match.
    private static let scpStylePattern = #"^[^/@]+@([^:/]+):(.+)$"#

    static func browseURL(for remote: String) -> URL? {
        let trimmed = remote.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }

        if let scpStyle = scpStyleURL(trimmed) {
            return scpStyle
        }
        guard let components = URLComponents(string: trimmed),
              let scheme = components.scheme?.lowercased(),
              let host = components.host, !host.isEmpty
        else { return nil }

        if browsableSchemes.contains(scheme) {
            return url(scheme: scheme, host: host, path: components.path)
        }
        // A port belongs to the transport, not to the web interface, so it is dropped.
        return rewrittenSchemes.contains(scheme) ? url(scheme: httpsScheme, host: host, path: components.path) : nil
    }

    private static func scpStyleURL(_ remote: String) -> URL? {
        guard !remote.contains("://"),
              let match = remote.range(of: scpStylePattern, options: .regularExpression),
              match.lowerBound == remote.startIndex, match.upperBound == remote.endIndex,
              let separator = remote.firstIndex(of: ":")
        else { return nil }
        let host = String(remote[remote.index(after: remote.firstIndex(of: "@")!)..<separator])
        return url(scheme: httpsScheme, host: host, path: String(remote[remote.index(after: separator)...]))
    }

    /// Rebuilt through `URLComponents` rather than string concatenation so the credentials and the
    /// port of the original remote cannot survive into the browsed URL.
    private static func url(scheme: String, host: String, path: String) -> URL? {
        // Slashes come off first: a remote written as `.../repo.git/` hides the suffix behind one.
        var normalized = path
        while normalized.hasSuffix(pathSeparator) {
            normalized.removeLast()
        }
        if normalized.hasSuffix(dotGitSuffix) {
            normalized.removeLast(dotGitSuffix.count)
        }
        guard !normalized.isEmpty, normalized != pathSeparator else { return nil }
        if !normalized.hasPrefix(pathSeparator) {
            normalized = pathSeparator + normalized
        }

        var components = URLComponents()
        components.scheme = scheme
        components.host = host
        components.path = normalized
        return components.url
    }
}
