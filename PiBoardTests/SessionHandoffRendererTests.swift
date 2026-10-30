import Testing
@testable import PiBoard

struct SessionHandoffRendererTests {
    private typealias Renderer = SessionHandoffRenderer

    private func handoff(_ transcript: SessionTranscript) -> SessionHandoff {
        SessionHandoff(sourceAgent: .pi, taskTitle: "Fix login", taskPrompt: "Make login work", transcript: transcript)
    }

    private func transcript(turns: Int, files: [String] = []) -> SessionTranscript {
        var transcript = SessionTranscript()
        for index in 0..<turns {
            transcript.append(.user, text: "question \(index + 1)", timestamp: nil)
            transcript.append(.assistant, text: "answer \(index + 1)", timestamp: nil)
        }
        files.forEach { transcript.noteChangedFile($0) }
        return transcript
    }

    private var header: [String] {
        let source = AgentKind.pi.title
        return [
            Renderer.titlePrefix + source,
            Renderer.introPrefix + source + Renderer.introSuffix,
            Renderer.taskHeading,
            "Fix login",
            Renderer.promptHeading,
            "Make login work",
        ]
    }

    @Test func rendersEverythingWhenBothTogglesAreOn() {
        let expected = (header + [
            Renderer.conversationHeading,
            Renderer.userLabel + "question 1",
            Renderer.assistantLabel + "answer 1",
            Renderer.userLabel + "question 2",
            Renderer.assistantLabel + "answer 2",
            Renderer.changedFilesHeading,
            Renderer.fileBullet + "a.swift\n" + Renderer.fileBullet + "b.swift",
        ]).joined(separator: "\n\n")

        let rendered = Renderer.render(handoff(transcript(turns: 2, files: ["a.swift", "b.swift"])), options: SessionHandoffOptions())

        #expect(rendered == expected)
    }

    @Test func omitsAssistantRepliesWhenToggledOff() {
        var options = SessionHandoffOptions()
        options.includeAssistantReplies = false

        let rendered = Renderer.render(handoff(transcript(turns: 2)), options: options)

        #expect(rendered.contains(Renderer.userLabel + "question 2"))
        #expect(!rendered.contains(Renderer.assistantLabel))
    }

    @Test func omitsChangedFilesWhenToggledOffOrEmpty() {
        var off = SessionHandoffOptions()
        off.includeChangedFiles = false

        let withFiles = handoff(transcript(turns: 1, files: ["a.swift"]))
        #expect(!Renderer.render(withFiles, options: off).contains(Renderer.changedFilesHeading))
        #expect(Renderer.render(withFiles, options: SessionHandoffOptions()).contains(Renderer.changedFilesHeading))
        #expect(!Renderer.render(handoff(transcript(turns: 1)), options: SessionHandoffOptions()).contains(Renderer.changedFilesHeading))
    }

    @Test func keepsOnlyTheLastTurnsAndSaysSo() {
        var options = SessionHandoffOptions()
        options.maxTurns = 2

        let rendered = Renderer.render(handoff(transcript(turns: 5)), options: options)

        #expect(rendered.contains("\(Renderer.conversationHeading) (last 2 of 5 turns)"))
        #expect(!rendered.contains("question 3"))
        #expect(rendered.contains("question 4"))
        #expect(rendered.contains("answer 5"))
    }

    @Test func clipsLongMessages() {
        var transcript = SessionTranscript()
        transcript.append(.user, text: String(repeating: "a", count: Renderer.maxMessageCharacters + 50) + "  \n", timestamp: nil)

        let rendered = Renderer.render(handoff(transcript), options: SessionHandoffOptions())

        let clipped = String(repeating: "a", count: Renderer.maxMessageCharacters) + Renderer.clippedMarker
        #expect(rendered.contains(Renderer.userLabel + clipped))
        #expect(!rendered.contains(String(repeating: "a", count: Renderer.maxMessageCharacters + 1)))
    }

    @Test func dropsOldestTurnsWhenTheDocumentIsTooLarge() {
        var transcript = SessionTranscript()
        let body = String(repeating: "b", count: Renderer.maxMessageCharacters)
        for index in 1...20 {
            transcript.append(.user, text: "turn \(index) " + body, timestamp: nil)
        }
        var options = SessionHandoffOptions()
        options.maxTurns = 20

        let rendered = Renderer.render(handoff(transcript), options: options)

        #expect(rendered.utf8.count <= Renderer.maxTotalBytes)
        #expect(rendered.contains("turn 20 "))
        #expect(!rendered.contains("turn 1 "))
        #expect(rendered.contains("of 20 turns)"))
        #expect(rendered.hasPrefix(Renderer.titlePrefix))
        #expect(rendered.contains("Make login work"))
    }

    @Test func emptyTranscriptRendersTheNoConversationLine() {
        let rendered = Renderer.render(handoff(SessionTranscript()), options: SessionHandoffOptions())

        #expect(rendered == (header + [Renderer.noConversationLine]).joined(separator: "\n\n"))
    }
}
