import AppKit
import Foundation

protocol ExternalAppServicing: Sendable {
    func isAvailable(_ app: ExternalApp) -> Bool
    /// Nil when the app is not installed; Finder resolves through its bundle identifier.
    func applicationURL(for app: ExternalApp) -> URL?
    func open(_ url: URL, in app: ExternalApp) async throws
    /// Opens the file scrolled to `line`. Apps without a scheme that carries a source location
    /// just open the file, so the caller never has to check which app can do what.
    func open(_ file: URL, line: Int, column: Int?, in app: ExternalApp) async throws
}

enum ExternalApp: String, CaseIterable, Codable, Sendable {
    case vsCode
    case vsCodium
    case cursor
    case zed
    case sublimeText
    case kiro
    case phpStorm
    case intelliJ
    case webStorm
    case pyCharm
    case goLand
    case rubyMine
    case cLion
    case rider
    case rustRover
    case androidStudio
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
    private static let vsCodiumBundleIdentifier = "com.vscodium"
    private static let cursorBundleIdentifier = "com.todesktop.230313mzl4w4u92"
    private static let zedBundleIdentifier = "dev.zed.Zed"
    private static let sublimeText4BundleIdentifier = "com.sublimetext.4"
    private static let sublimeText3BundleIdentifier = "com.sublimetext.3"
    private static let kiroBundleIdentifier = "dev.kiro.desktop"
    private static let phpStormBundleIdentifier = "com.jetbrains.PhpStorm"
    private static let intelliJUltimateBundleIdentifier = "com.jetbrains.intellij"
    private static let intelliJCommunityBundleIdentifier = "com.jetbrains.intellij.ce"
    private static let webStormBundleIdentifier = "com.jetbrains.WebStorm"
    private static let pyCharmProfessionalBundleIdentifier = "com.jetbrains.pycharm"
    private static let pyCharmCommunityBundleIdentifier = "com.jetbrains.pycharm.ce"
    private static let goLandBundleIdentifier = "com.jetbrains.goland"
    private static let rubyMineBundleIdentifier = "com.jetbrains.rubymine"
    private static let cLionBundleIdentifier = "com.jetbrains.CLion"
    private static let riderBundleIdentifier = "com.jetbrains.rider"
    private static let rustRoverBundleIdentifier = "com.jetbrains.rustrover"
    private static let androidStudioBundleIdentifier = "com.google.android.studio"
    private static let jetBrainsFamilySystemImage = "hammer"
    private static let iTermBundleIdentifier = "com.googlecode.iterm2"
    private static let warpBundleIdentifier = "dev.warp.Warp-Stable"
    private static let terminalBundleIdentifier = "com.apple.Terminal"
    private static let finderBundleIdentifier = "com.apple.finder"
    private static let vsCodeCLIPaths = ["/usr/local/bin/code", "/opt/homebrew/bin/code"]
    private static let vsCodiumCLI = "codium"
    private static let cursorCLI = "cursor"
    private static let zedCLI = "zed"
    private static let sublimeTextCLI = "subl"
    private static let kiroCLI = "kiro"
    private static let vsCodeURLScheme = "vscode"
    private static let vsCodiumURLScheme = "vscodium"
    private static let cursorURLScheme = "cursor"
    // Both VS Code and its forks read the location off the end of the path in this host.
    private static let sourceLocationURLHost = "file"

    static let editors = allCases.filter { $0.kind == .editor }
    static let terminals = allCases.filter { $0.kind == .terminal }

    var title: String {
        switch self {
        case .vsCode: "Visual Studio Code"
        case .vsCodium: "VSCodium"
        case .cursor: "Cursor"
        case .zed: "Zed"
        case .sublimeText: "Sublime Text"
        case .kiro: "Kiro"
        case .phpStorm: "PhpStorm"
        case .intelliJ: "IntelliJ IDEA"
        case .webStorm: "WebStorm"
        case .pyCharm: "PyCharm"
        case .goLand: "GoLand"
        case .rubyMine: "RubyMine"
        case .cLion: "CLion"
        case .rider: "Rider"
        case .rustRover: "RustRover"
        case .androidStudio: "Android Studio"
        case .iTerm: "iTerm"
        case .warp: "Warp"
        case .terminal: "Terminal"
        case .finder: "Finder"
        }
    }

    var systemImage: String {
        switch self {
        case .vsCode, .vsCodium: "chevron.left.forwardslash.chevron.right"
        case .cursor: "cursorarrow.rays"
        case .zed: "bolt"
        case .sublimeText: "doc.text"
        case .kiro: "sparkles"
        case .phpStorm, .intelliJ, .webStorm, .pyCharm, .goLand, .rubyMine, .cLion, .rider, .rustRover, .androidStudio:
            Self.jetBrainsFamilySystemImage
        case .iTerm: "terminal"
        case .warp: "terminal.fill"
        case .terminal: "apple.terminal"
        case .finder: "folder"
        }
    }

    var kind: Kind {
        switch self {
        case .vsCode, .vsCodium, .cursor, .zed, .sublimeText, .kiro,
             .phpStorm, .intelliJ, .webStorm, .pyCharm, .goLand, .rubyMine, .cLion, .rider, .rustRover, .androidStudio: .editor
        case .iTerm, .warp, .terminal: .terminal
        case .finder: .fileManager
        }
    }

    var bundleIdentifiers: [String] {
        switch self {
        case .vsCode: [Self.vsCodeBundleIdentifier]
        case .vsCodium: [Self.vsCodiumBundleIdentifier]
        case .cursor: [Self.cursorBundleIdentifier]
        case .zed: [Self.zedBundleIdentifier]
        case .sublimeText: [Self.sublimeText4BundleIdentifier, Self.sublimeText3BundleIdentifier]
        case .kiro: [Self.kiroBundleIdentifier]
        case .phpStorm: [Self.phpStormBundleIdentifier]
        case .intelliJ: [Self.intelliJUltimateBundleIdentifier, Self.intelliJCommunityBundleIdentifier]
        case .webStorm: [Self.webStormBundleIdentifier]
        case .pyCharm: [Self.pyCharmProfessionalBundleIdentifier, Self.pyCharmCommunityBundleIdentifier]
        case .goLand: [Self.goLandBundleIdentifier]
        case .rubyMine: [Self.rubyMineBundleIdentifier]
        case .cLion: [Self.cLionBundleIdentifier]
        case .rider: [Self.riderBundleIdentifier]
        case .rustRover: [Self.rustRoverBundleIdentifier]
        case .androidStudio: [Self.androidStudioBundleIdentifier]
        case .iTerm: [Self.iTermBundleIdentifier]
        case .warp: [Self.warpBundleIdentifier]
        case .terminal: [Self.terminalBundleIdentifier]
        case .finder: [Self.finderBundleIdentifier]
        }
    }

    /// URL that opens `file` scrolled to a source location, or nil when the app registers no
    /// scheme that can express one. Zed and Kiro are absent because their URL syntax is unverified,
    /// and Sublime Text registers no scheme; they fall back to opening the file at the top, as do
    /// the JetBrains IDEs and Android Studio, whose file and line URL scheme is unverified.
    func sourceLocationURL(for file: URL, line: Int, column: Int?) -> URL? {
        let scheme: String
        switch self {
        case .vsCode: scheme = Self.vsCodeURLScheme
        case .vsCodium: scheme = Self.vsCodiumURLScheme
        case .cursor: scheme = Self.cursorURLScheme
        case .zed, .sublimeText, .kiro, .phpStorm, .intelliJ, .webStorm, .pyCharm, .goLand, .rubyMine, .cLion, .rider,
             .rustRover, .androidStudio, .iTerm, .warp, .terminal, .finder: return nil
        }
        var location = "\(file.path):\(line)"
        if let column {
            location += ":\(column)"
        }
        var components = URLComponents()
        components.scheme = scheme
        components.host = Self.sourceLocationURLHost
        components.path = location
        return components.url
    }

    // Not used for opening (LaunchServices handles folders); kept for a future CLI fallback.
    var cliCandidates: [String] {
        switch self {
        case .vsCode: Self.vsCodeCLIPaths
        case .vsCodium: [Self.vsCodiumCLI]
        case .cursor: [Self.cursorCLI]
        case .zed: [Self.zedCLI]
        case .sublimeText: [Self.sublimeTextCLI]
        case .kiro: [Self.kiroCLI]
        case .phpStorm, .intelliJ, .webStorm, .pyCharm, .goLand, .rubyMine, .cLion, .rider, .rustRover, .androidStudio,
             .iTerm, .warp, .terminal, .finder: []
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

    func open(_ file: URL, line: Int, column: Int?, in app: ExternalApp) async throws {
        guard let locationURL = app.sourceLocationURL(for: file, line: line, column: column) else {
            try await open(file, in: app)
            return
        }
        guard let appURL = applicationURL(for: app) else {
            throw ExternalAppError.notInstalled(app)
        }
        do {
            _ = try await NSWorkspace.shared.open([locationURL], withApplicationAt: appURL, configuration: NSWorkspace.OpenConfiguration())
        } catch {
            throw ExternalAppError.openFailed(error.localizedDescription)
        }
    }

    func applicationURL(for app: ExternalApp) -> URL? {
        app.bundleIdentifiers.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }
}
