import Foundation
import Testing
@testable import PiBoard

struct MarkdownIncrementalTests {
    private static let samples = [
        "one\ntwo\n\nthree",
        "# Title\nintro line\n- a\n- b\n  nested\nlazy\n\n1. x\n2. y\n\n## Next\nafter",
        "before\n```swift\nlet a = 1\n\nlet b = 2\n```\nafter\n\n```\nopen fence",
        "para\n\n\n\n- item\n\n  indented after blank\ntext **bold** and `code`\n",
        "```py\nprint(1)\n```\n```\n```\n- a\n# h\n",
        "é ü 日本語\n\n- ünï\n- çödé\n\n```\n日本\n```",
        "",
    ]

    private static func chain(_ text: String, step: Int) -> [(prefix: String, parsed: MarkdownBlocks.Parsed)] {
        var results: [(String, MarkdownBlocks.Parsed)] = []
        var previous: MarkdownBlocks.Parsed?
        var length = 0
        let characters = Array(text)
        repeat {
            length = min(length + step, characters.count)
            let prefix = String(characters[0..<length])
            let parsed = MarkdownBlocks.parse(prefix, continuing: previous)
            results.append((prefix, parsed))
            previous = parsed
        } while length < characters.count
        return results
    }

    @Test(arguments: [1, 2, 7])
    func everyStepEqualsTheFullSplit(step: Int) {
        for sample in Self.samples {
            for (prefix, parsed) in Self.chain(sample, step: step) {
                #expect(parsed.blocks == MarkdownBlocks.split(prefix), "prefix: \(prefix.debugDescription)")
            }
        }
    }

    @Test func parseWithoutPreviousEqualsSplit() {
        for sample in Self.samples {
            #expect(MarkdownBlocks.parse(sample).blocks == MarkdownBlocks.split(sample))
        }
    }

    @Test func aShorterTextFallsBackToAFullSplit() {
        let long = MarkdownBlocks.parse("one\n\ntwo\n\nthree")
        let short = MarkdownBlocks.parse("one", continuing: long)
        #expect(short.blocks == [.paragraph("one")])
    }

    @Test func theSameTextReturnsTheCachedResult() {
        let first = MarkdownBlocks.parse("a\n\nb")
        #expect(MarkdownBlocks.parse("a\n\nb", continuing: first) == first)
    }

    @Test func closedBlocksAreNotRebuiltWhileStreaming() {
        let first = MarkdownBlocks.parse("closed\n\nopen")
        let next = MarkdownBlocks.parse("closed\n\nopen more", continuing: first)
        #expect(next.blocks == [.paragraph("closed"), .paragraph("open more")])
    }
}
