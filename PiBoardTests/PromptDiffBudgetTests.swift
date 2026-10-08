import Foundation
import Testing
@testable import PiBoard

struct PromptDiffBudgetTests {
    private static func fileDiff(name: String, contentLines: Int, lineLength: Int = 6) -> String {
        var lines = ["diff --git a/\(name) b/\(name)", "--- a/\(name)", "+++ b/\(name)", "@@ -1,\(contentLines) +1,\(contentLines) @@"]
        let content = String(repeating: "x", count: max(lineLength - 1, 0))
        lines.append(contentsOf: (0..<contentLines).map { " \(content)\($0)" })
        return lines.joined(separator: "\n") + "\n"
    }

    @Test func headerListsEveryChangeWithItsKindLabelEvenWhenTheDiffIsEmpty() {
        let changes = [GitChange(status: "??", path: "new.txt"), GitChange(status: " M", path: "changed.txt")]

        let text = PromptDiffBudget.render(diff: .empty, changes: changes)

        #expect(text.contains(PromptDiffBudget.filesHeader))
        #expect(text.contains("New new.txt"))
        #expect(text.contains("Modified changed.txt"))
    }

    @Test func aDiffWithMoreThanTheFileLimitOmitsTheRest() {
        let fileCount = 25
        let unified = (0..<fileCount).map { Self.fileDiff(name: "file\($0).txt", contentLines: 2) }.joined()
        let diff = GitDiff.make(unified: unified)
        #expect(diff.files.count == fileCount)

        let text = PromptDiffBudget.render(diff: diff, changes: [])

        let shownBodies = diff.files.prefix(PromptDiffBudget.maxFiles).map(\.path)
        for path in shownBodies {
            #expect(text.contains(path))
        }
        #expect(text.contains(String(format: PromptDiffBudget.moreFilesFormat, fileCount - PromptDiffBudget.maxFiles)))
    }

    @Test func aFileOverTheLinesPerFileLimitIsClipped() {
        let contentLines = 196
        let fileText = Self.fileDiff(name: "big.txt", contentLines: contentLines)
        let totalLines = fileText.split(separator: "\n", omittingEmptySubsequences: false).count
        let expectedOmitted = totalLines - PromptDiffBudget.maxLinesPerFile

        let clipped = PromptDiffBudget.clipLines(fileText)

        #expect(clipped.contains(String(format: PromptDiffBudget.moreLinesFormat, expectedOmitted)))
    }

    @Test func theTotalByteBudgetStopsBeforeEveryFileIsIncluded() {
        // Each file stays under the per-file line limit, but its lines are long enough that ten
        // of them together blow the total byte budget.
        let tenKilobyteFileLines = 140
        let unified = (0..<10).map { Self.fileDiff(name: "file\($0).txt", contentLines: tenKilobyteFileLines, lineLength: 70) }.joined()
        let diff = GitDiff.make(unified: unified)
        #expect(!diff.isTruncated)

        let text = PromptDiffBudget.render(diff: diff, changes: [])

        #expect(text.utf8.count <= PromptDiffBudget.maxBytes)
        #expect(!text.contains("file9.txt"))
    }

    @Test func aTruncatedDiffStartsWithTheFileListAndStaysWithinTheByteBudget() {
        let unified = (0..<5).map { Self.fileDiff(name: "file\($0).txt", contentLines: 500) }.joined()
        let diff = GitDiff.make(unified: unified)
        #expect(diff.isTruncated)

        let changes = (0..<5).map { GitChange(status: " M", path: "file\($0).txt") }
        let text = PromptDiffBudget.render(diff: diff, changes: changes)

        #expect(text.hasPrefix(PromptDiffBudget.filesHeader))
        #expect(text.utf8.count <= PromptDiffBudget.maxBytes)
    }

    @Test func subjectsTrimsDropsEmptiesKeepsThreeAndTruncatesALongOne() {
        let longSubject = String(repeating: "a", count: 200)
        let raw = [" feat: a ", "", "  ", "fix: b", "chore: c", "docs: d", longSubject]

        let subjects = PromptDiffBudget.subjects(raw)

        #expect(subjects == ["feat: a", "fix: b", "chore: c"])

        let truncated = PromptDiffBudget.subjects([longSubject])
        #expect(truncated.count == 1)
        #expect(truncated[0].count == PromptDiffBudget.maxSubjectLength)
        #expect(truncated[0].hasSuffix("..."))
    }
}
