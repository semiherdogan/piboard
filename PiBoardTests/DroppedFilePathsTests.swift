import Foundation
import Testing
@testable import PiBoard

struct DroppedFilePathsTests {
    @Test func plainPathIsInsertedUnquotedWithATrailingSpace() {
        #expect(DroppedFilePaths.text(for: [URL(fileURLWithPath: "/Users/x/Projects/app/main.swift")]) == "/Users/x/Projects/app/main.swift ")
    }

    @Test func severalFilesAreSeparatedBySpaces() {
        let urls = [URL(fileURLWithPath: "/tmp/a.txt"), URL(fileURLWithPath: "/tmp/b.txt")]
        #expect(DroppedFilePaths.text(for: urls) == "/tmp/a.txt /tmp/b.txt ")
    }

    @Test func noFilesProduceNoText() {
        #expect(DroppedFilePaths.text(for: []).isEmpty)
    }

    // Finder hands over directories as file URLs too, and `URL.path` drops the trailing slash
    // whether the URL was built with the directory flag or parsed from a slash-terminated string.
    @Test func foldersAreInsertedWithoutATrailingSlash() {
        let flagged = URL(fileURLWithPath: "/Users/x/Projects/app", isDirectory: true)
        #expect(DroppedFilePaths.text(for: [flagged]) == "/Users/x/Projects/app ")

        let slashTerminated = URL(string: "file:///Users/x/My%20Projects/app/")!
        #expect(DroppedFilePaths.text(for: [slashTerminated]) == "'/Users/x/My Projects/app' ")
    }

    @Test func foldersAndFilesCanBeDroppedTogether() {
        let urls = [
            URL(fileURLWithPath: "/Users/x/Projects/app", isDirectory: true),
            URL(fileURLWithPath: "/Users/x/Projects/app/main.swift"),
        ]
        #expect(DroppedFilePaths.text(for: urls) == "/Users/x/Projects/app /Users/x/Projects/app/main.swift ")
    }

    @Test func pathWithASpaceIsQuotedSoAShellKeepsItAsOneArgument() {
        #expect(DroppedFilePaths.quoted("/Users/x/My Documents/notes.md") == "'/Users/x/My Documents/notes.md'")
    }

    @Test func quotesInsideAPathAreEscaped() {
        #expect(DroppedFilePaths.quoted("/tmp/it's here.txt") == "'/tmp/it'\\''s here.txt'")
    }

    @Test func shellMetacharactersForceQuoting() {
        for path in ["/tmp/a&b", "/tmp/a$b", "/tmp/a;b", "/tmp/a*b", "/tmp/a(b)", "/tmp/a\nb"] {
            #expect(DroppedFilePaths.quoted(path) == "'\(path)'")
        }
    }

    // Shell metacharacters are all ASCII, and macOS hands out decomposed names, so the accent of
    // a decomposed "ö" must count as safe too or every such path would be needlessly quoted.
    @Test func nonAsciiNamesStayUnquoted() {
        #expect(DroppedFilePaths.quoted("/tmp/belgeler/özet.md") == "/tmp/belgeler/özet.md")
        #expect(DroppedFilePaths.quoted("/tmp/belgeler/o\u{308}zet.md") == "/tmp/belgeler/o\u{308}zet.md")
    }

    @Test func emptyPathBecomesAnEmptyQuotedArgument() {
        #expect(DroppedFilePaths.quoted("") == "''")
    }
}
