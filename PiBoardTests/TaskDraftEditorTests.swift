import Foundation
import Testing
@testable import PiBoard

@MainActor
struct TaskDraftEditorTests {
    // Short enough to keep the suite fast, long enough that a cancellation still wins the race.
    private static let writeDelay: Duration = .milliseconds(30)

    private final class WriteLog {
        private(set) var writes: [(title: String, prompt: String)] = []
        func record(_ title: String, _ prompt: String) { writes.append((title, prompt)) }
    }

    private func editor(_ log: WriteLog) -> TaskDraftEditor {
        let editor = TaskDraftEditor(writeDelay: Self.writeDelay)
        editor.onWrite = { title, prompt in log.record(title, prompt) }
        return editor
    }

    @Test func typingSeveralCharactersWritesOnce() async {
        let log = WriteLog()
        let editor = editor(log)
        editor.load(title: "A", prompt: "p")
        editor.title = "Ab"
        editor.title = "Abc"
        editor.title = "Abcd"
        await editor.writeTask?.value
        #expect(log.writes.count == 1)
        #expect(log.writes.first?.title == "Abcd")
        #expect(log.writes.first?.prompt == "p")
    }

    @Test func flushWritesImmediatelyAndCancelsTheDelayedWrite() {
        let log = WriteLog()
        let editor = editor(log)
        editor.load(title: "A", prompt: "p")
        editor.prompt = "pq"
        editor.flush()
        #expect(log.writes.count == 1)
        #expect(log.writes.first?.title == "A")
        #expect(log.writes.first?.prompt == "pq")
        #expect(editor.writeTask == nil)
        #expect(!editor.hasPendingChanges)
    }

    @Test func loadDoesNotWrite() {
        let log = WriteLog()
        let editor = editor(log)
        editor.load(title: "A", prompt: "p")
        editor.load(title: "B", prompt: "q")
        #expect(editor.writeTask == nil)
        #expect(log.writes.isEmpty)
    }

    @Test func revertingToTheStoredValueCancelsTheWrite() {
        let log = WriteLog()
        let editor = editor(log)
        editor.load(title: "A", prompt: "p")
        editor.title = "Ab"
        editor.title = "A"
        #expect(editor.writeTask == nil)
        #expect(log.writes.isEmpty)
    }

    @Test func loadFlushesAPendingDraftFirst() {
        let log = WriteLog()
        let editor = editor(log)
        editor.load(title: "A", prompt: "p")
        editor.title = "Ab"
        editor.load(title: "B", prompt: "q")
        #expect(log.writes.count == 1)
        #expect(log.writes.first?.title == "Ab")
        #expect(log.writes.first?.prompt == "p")
        #expect(editor.title == "B")
    }

    @Test func flushWithoutChangesDoesNotWrite() {
        let log = WriteLog()
        let editor = editor(log)
        editor.load(title: "A", prompt: "p")
        editor.flush()
        #expect(log.writes.isEmpty)
    }
}
