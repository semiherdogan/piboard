import Testing
@testable import PiBoard

struct SessionTranscriptTests {
    @Test func noteChangedFileDeduplicatesAndIgnoresEmpty() {
        var transcript = SessionTranscript()

        transcript.noteChangedFile("a.swift")
        transcript.noteChangedFile("")
        transcript.noteChangedFile("b.swift")
        transcript.noteChangedFile("a.swift")

        #expect(transcript.changedFiles == ["a.swift", "b.swift"])
    }

    @Test func appendDropsBlankText() {
        var transcript = SessionTranscript()

        transcript.append(.user, text: " \n", timestamp: nil)
        transcript.append(.assistant, text: "ok", timestamp: nil)

        #expect(transcript.messages == [SessionTranscript.Message(role: .assistant, text: "ok", timestamp: nil)])
    }

    @Test func lastAssistantReplyIsTheNewestAssistantMessage() {
        var transcript = SessionTranscript()

        transcript.append(.assistant, text: "first", timestamp: nil)
        transcript.append(.user, text: "again", timestamp: nil)
        transcript.append(.assistant, text: "a long line\nthat keeps its own breaks", timestamp: nil)
        transcript.append(.user, text: "pending question", timestamp: nil)

        #expect(transcript.lastAssistantReply == "a long line\nthat keeps its own breaks")
    }

    @Test func lastAssistantReplyIsNilWithoutAssistantMessages() {
        var transcript = SessionTranscript()

        transcript.append(.user, text: "hello", timestamp: nil)

        #expect(transcript.lastAssistantReply == nil)
    }
}
