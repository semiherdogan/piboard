import Foundation
import Testing
@testable import PiBoard

struct TerminalLinkTests {
    /// Creates a real directory with the given files, because resolution is defined by what is on
    /// disk: a path that does not exist is never a link.
    private func withWorkingDirectory(
        files: [String],
        _ body: (URL) throws -> Void
    ) throws {
        let root = URL(fileURLWithPath: NSTemporaryDirectory()).appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for file in files {
            let url = root.appendingPathComponent(file)
            try FileManager.default.createDirectory(at: url.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data().write(to: url)
        }
        try body(root.standardizedFileURL)
    }

    // MARK: Web addresses

    @Test func allowedSchemesOpenAsWebAddresses() throws {
        for link in ["https://example.com/path", "http://example.com", "mailto:someone@example.com"] {
            let target = TerminalLink.target(for: link, workingDirectory: URL(fileURLWithPath: "/tmp"))
            #expect(target == .web(URL(string: link)!), "\(link)")
        }
    }

    @Test func otherSchemesAreRefused() {
        for link in ["ssh://host/x", "git://host/repo", "tel:+905551112233", "magnet:?xt=urn:btih:abc", "javascript:alert(1)", "x-apple-script://run"] {
            #expect(TerminalLink.target(for: link, workingDirectory: URL(fileURLWithPath: "/tmp")) == nil, "\(link)")
        }
    }

    @Test func blankLinksResolveToNothing() {
        #expect(TerminalLink.target(for: "   ", workingDirectory: URL(fileURLWithPath: "/tmp")) == nil)
    }

    // MARK: Files

    @Test func absolutePathResolvesToTheFile() throws {
        try withWorkingDirectory(files: ["main.swift"]) { root in
            let path = root.appendingPathComponent("main.swift").path
            #expect(TerminalLink.target(for: path, workingDirectory: root) == .file(URL(fileURLWithPath: path), line: nil, column: nil))
        }
    }

    @Test func relativePathResolvesAgainstTheWorkingDirectory() throws {
        try withWorkingDirectory(files: ["Sources/App/main.swift"]) { root in
            let expected = root.appendingPathComponent("Sources/App/main.swift")
            #expect(TerminalLink.target(for: "Sources/App/main.swift", workingDirectory: root) == .file(expected, line: nil, column: nil))
        }
    }

    @Test func sourceLocationIsKept() throws {
        try withWorkingDirectory(files: ["main.swift"]) { root in
            let expected = root.appendingPathComponent("main.swift")
            #expect(TerminalLink.target(for: "main.swift:42", workingDirectory: root) == .file(expected, line: 42, column: nil))
            #expect(TerminalLink.target(for: "main.swift:42:10", workingDirectory: root) == .file(expected, line: 42, column: 10))
        }
    }

    // A file really named "notes:12" must win over reading the same text as line 12 of "notes".
    @Test func anExistingNameEndingInALocationIsNotSplit() throws {
        try withWorkingDirectory(files: ["notes:12"]) { root in
            let expected = root.appendingPathComponent("notes:12")
            #expect(TerminalLink.target(for: "notes:12", workingDirectory: root) == .file(expected, line: nil, column: nil))
        }
    }

    @Test func pathsThatDoNotExistAreRefused() throws {
        try withWorkingDirectory(files: []) { root in
            #expect(TerminalLink.target(for: "missing.swift", workingDirectory: root) == nil)
            #expect(TerminalLink.target(for: "missing.swift:12:3", workingDirectory: root) == nil)
            #expect(TerminalLink.target(for: "/no/such/place", workingDirectory: root) == nil)
        }
    }

    @Test func parentDirectoryStepsAreResolvedBeforeTheCheck() throws {
        try withWorkingDirectory(files: ["Sources/main.swift"]) { root in
            let nested = root.appendingPathComponent("Sources")
            let expected = root.appendingPathComponent("Sources/main.swift")
            #expect(TerminalLink.target(for: "../Sources/main.swift", workingDirectory: nested) == .file(expected, line: nil, column: nil))
        }
    }

    @Test func fileURLsResolveLikePaths() throws {
        try withWorkingDirectory(files: ["My Notes.md"]) { root in
            let expected = root.appendingPathComponent("My Notes.md")
            let link = URL(fileURLWithPath: expected.path).absoluteString
            #expect(TerminalLink.target(for: link, workingDirectory: root) == .file(expected, line: nil, column: nil))
        }
    }

    @Test func fileURLsPointingNowhereAreRefused() throws {
        try withWorkingDirectory(files: []) { root in
            #expect(TerminalLink.target(for: "file:///no/such/place", workingDirectory: root) == nil)
        }
    }

    // MARK: Editor handoff

    @Test func vsCodeFamilyCarriesTheSourceLocation() {
        let file = URL(fileURLWithPath: "/Users/x/Projects/app/main.swift")
        #expect(ExternalApp.vsCode.sourceLocationURL(for: file, line: 42, column: 10)?.absoluteString == "vscode://file/Users/x/Projects/app/main.swift:42:10")
        #expect(ExternalApp.vsCode.sourceLocationURL(for: file, line: 42, column: nil)?.absoluteString == "vscode://file/Users/x/Projects/app/main.swift:42")
        #expect(ExternalApp.cursor.sourceLocationURL(for: file, line: 7, column: nil)?.absoluteString == "cursor://file/Users/x/Projects/app/main.swift:7")
    }

    @Test func appsWithoutALocationSchemeGetNoURL() {
        let file = URL(fileURLWithPath: "/Users/x/main.swift")
        for app in [ExternalApp.zed, .iTerm, .warp, .terminal, .finder] {
            #expect(app.sourceLocationURL(for: file, line: 1, column: nil) == nil, "\(app)")
        }
    }
}
