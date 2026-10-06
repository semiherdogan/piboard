import AppKit
import Foundation

protocol ExternalAppServicing: Sendable {
    func isAvailable(_ app: ExternalApp) -> Bool
    func open(_ url: URL, in app: ExternalApp) async throws
}

enum ExternalApp: String, CaseIterable, Codable, Sendable {
    case vsCode
    case cursor
    case zed
    case iTerm
    case warp
    case terminal
    case finder

    enum Kind: Sendable {
        case editor
        case terminal
        case fileManager
    }

    private static let vsCodeBundleIdentifier = "com.microsoft.VSCode"
    private static let cursorBundleIdentifier = "com.todesktop.230313mzl4w4u92"
    private static let zedBundleIdentifier = "dev.zed.Zed"
    private static let iTermBundleIdentifier = "com.googlecode.iterm2"
    private static let warpBundleIdentifier = "dev.warp.Warp-Stable"
    private static let terminalBundleIdentifier = "com.apple.Terminal"
    private static let vsCodeCLIPaths = ["/usr/local/bin/code", "/opt/homebrew/bin/code"]
    private static let cursorCLI = "cursor"
    private static let zedCLI = "zed"

    static let editors = allCases.filter { $0.kind == .editor }
    static let terminals = allCases.filter { $0.kind == .terminal }

    var title: String {
        switch self {
        case .vsCode: "Visual Studio Code"
        case .cursor: "Cursor"
        case .zed: "Zed"
        case .iTerm: "iTerm"
        case .warp: "Warp"
        case .terminal: "Terminal"
        case .finder: "Finder"
        }
    }

    var systemImage: String {
        switch self {
        case .vsCode: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow.rays"
        case .zed: "bolt"
        case .iTerm: "terminal"
        case .warp: "terminal.fill"
        case .terminal: "apple.terminal"
        case .finder: "folder"
        }
    }

    var kind: Kind {
        switch self {
        case .vsCode, .cursor, .zed: .editor
        case .iTerm, .warp, .terminal: .terminal
        case .finder: .fileManager
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .vsCode: [Self.vsCodeBundleIdentifier]
        case .cursor: [Self.cursorBundleIdentifier]
        case .zed: [Self.zedBundleIdentifier]
        case .iTerm: [Self.iTermBundleIdentifier]
        case .warp: [Self.warpBundleIdentifier]
        case .terminal: [Self.terminalBundleIdentifier]
        case .finder: []
        }
    }

    // Not used for opening (LaunchServices handles folders); kept for a future CLI fallback.
    var cliCandidates: [String] {
        switch self {
        case .vsCode: Self.vsCodeCLIPaths
        case .cursor: [Self.cursorCLI]
        case .zed: [Self.zedCLI]
        case .iTerm, .warp, .terminal, .finder: []
        }
    }
}

enum ExternalAppError: Error, Equatable, LocalizedError {
    case notInstalled(ExternalApp)
    case openFailed(String)

    var errorDescription: String? {
        switch self {
        case .notInstalled(let app):
            "\(app.title) is not installed."
        case .openFailed(let detail):
            detail
        }
    }
}

final class ExternalAppService: ExternalAppServicing {
    func isAvailable(_ app: ExternalApp) -> Bool {
        app == .finder || applicationURL(for: app) != nil
    }

    /// Editors open a folder URL as a workspace; Terminal, iTerm and Warp open a new window
    /// (or tab) whose working directory is that folder.
    func open(_ url: URL, in app: ExternalApp) async throws {
        if app == .finder {
            guard NSWorkspace.shared.selectFile(nil, inFileViewerRootedAtPath: url.path) else {
                throw ExternalAppError.openFailed("Finder could not open \(url.path).")
            }
            return
        }
        guard let appURL = applicationURL(for: app) else {
            throw ExternalAppError.notInstalled(app)
        }
        do {
            _ = try await NSWorkspace.shared.open([url], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            throw ExternalAppError.openFailed(error.localizedDescription)
        }
    }

    private func applicationURL(for app: ExternalApp) -> URL? {
        app.bundleIdentifiers.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }
}
