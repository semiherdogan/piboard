import Foundation
import Testing
@testable import PiBoard

struct MarkdownBlocksTests {
    @Test func splitsParagraphsOnBlankLines() {
        #expect(MarkdownBlocks.split("one\ntwo\n\nthree") == [.paragraph("one\ntwo"), .paragraph("three")])
    }

    @Test func fencedBlockWithLanguage() {
        let text = "before\n```swift\nlet a = 1\n```\nafter"
        #expect(MarkdownBlocks.split(text) == [
            .paragraph("before"),
            .code(language: "swift", text: "let a = 1"),
            .paragraph("after"),
        ])
    }

    @Test func fencedBlockWithoutLanguage() {
        #expect(MarkdownBlocks.split("```\na\n\nb\n```") == [.code(language: nil, text: "a\n\nb")])
    }

    @Test func unterminatedFenceKeepsWhatArrived() {
        #expect(MarkdownBlocks.split("hi\n```py\nprint(1)") == [.paragraph("hi"), .code(language: "py", text: "print(1)")])
    }

    @Test func emptyTextHasNoBlocks() {
        #expect(MarkdownBlocks.split("").isEmpty)
    }

    @Test func listAfterParagraphIsItsOwnBlock() {
        #expect(MarkdownBlocks.split("intro\n- a\n* b\n1. c\n12. d") == [
            .paragraph("intro"),
            .list([
                .init(ordinal: nil, text: "a"),
                .init(ordinal: nil, text: "b"),
                .init(ordinal: 1, text: "c"),
                .init(ordinal: 12, text: "d"),
            ]),
        ])
    }

    @Test func nestedIndentationStaysPlainTextOfTheItem() {
        #expect(MarkdownBlocks.split("- a\n  - b\n- c") == [
            .list([.init(ordinal: nil, text: "a\n  - b"), .init(ordinal: nil, text: "c")]),
        ])
    }

    @Test func blankLineEndsAList() {
        #expect(MarkdownBlocks.split("- a\n\n- b\n\ntext") == [
            .list([.init(ordinal: nil, text: "a")]),
            .list([.init(ordinal: nil, text: "b")]),
            .paragraph("text"),
        ])
    }

    @Test func markerWithoutSpaceIsNotAList() {
        #expect(MarkdownBlocks.split("-a\n1.5") == [.paragraph("-a\n1.5")])
    }

    @Test func headingsUpToLevelThree() {
        #expect(MarkdownBlocks.split("# One\n## Two\n### Three\n#### Four\n#Five") == [
            .heading(level: 1, text: "One"),
            .heading(level: 2, text: "Two"),
            .heading(level: 3, text: "Three"),
            .paragraph("#### Four\n#Five"),
        ])
    }

    @Test func headingInterruptsAParagraphAndAList() {
        #expect(MarkdownBlocks.split("a\n# H\n- x\n## I") == [
            .paragraph("a"),
            .heading(level: 1, text: "H"),
            .list([.init(ordinal: nil, text: "x")]),
            .heading(level: 2, text: "I"),
        ])
    }

    @Test func fenceKeepsListAndHeadingLinesAsCode() {
        #expect(MarkdownBlocks.split("```\n- x\n1. y\n# h\n```") == [.code(language: nil, text: "- x\n1. y\n# h")])
    }

    @Test func unterminatedFenceKeepsListLinesAsCode() {
        #expect(MarkdownBlocks.split("```\n- x\n1. y\n# h") == [.code(language: nil, text: "- x\n1. y\n# h")])
    }

    @Test func partialMarkersWhileStreamingStayPlain() {
        for partial in ["-", "1.", "#", "# "] {
            #expect(MarkdownBlocks.split(partial) == [.paragraph(partial)])
        }
        #expect(MarkdownBlocks.split("- ") == [.list([.init(ordinal: nil, text: "")])])
    }

    @Test func fenceOpeningInsideAListEndsTheList() {
        #expect(MarkdownBlocks.split("- a\n```\n- b\n```") == [
            .list([.init(ordinal: nil, text: "a")]),
            .code(language: nil, text: "- b"),
        ])
    }

    @Test func unindentedLineAfterAnItemContinuesIt() {
        #expect(MarkdownBlocks.split("- a\nb") == [.list([.init(ordinal: nil, text: "a b")])])
    }
}

struct ConversationTimelineLayoutTests {
    private let start = Date(timeIntervalSince1970: 1_000)

    private func item(_ kind: ConversationItem.Kind, at offset: TimeInterval = 0) -> ConversationItem {
        ConversationItem(kind: kind, createdAt: start.addingTimeInterval(offset))
    }

    private func tool(at offset: TimeInterval = 0) -> ConversationItem {
        item(.toolCall(ToolCallItem(callID: "1", name: "read", argumentsJSON: "{}")), at: offset)
    }

    private func spacings(_ items: [ConversationItem], hidesThinking: Bool = false) -> [CGFloat] {
        ConversationTimelineLayout.rows(for: items, hidesThinking: hidesThinking).map(\.topSpacing)
    }

    @Test func foldsActivityIntoOneHeaderAndSeparatesTurns() {
        let items = [
            item(.user(text: "q", imageCount: 0)),
            item(.thinking(text: "t")),
            tool(),
            item(.assistant(text: "a")),
            item(.user(text: "q2", imageCount: 0)),
            item(.assistant(text: "a2")),
        ]
        let rows = ConversationTimelineLayout.rows(for: items, hidesThinking: false)
        #expect(rows.count == 5)
        guard case .turn(let turn) = rows[1].content else {
            Issue.record("expected a turn header")
            return
        }
        #expect(turn.activity.count == 2)
        #expect(spacings(items) == [0, 20, 6, 20, 20])
    }

    @Test func turnWithoutActivityHasNoHeader() {
        let items = [item(.assistant(text: "a")), item(.notice(text: "n"))]
        let rows = ConversationTimelineLayout.rows(for: items, hidesThinking: false)
        #expect(rows.count == 2)
        #expect(rows.allSatisfy { if case .item = $0.content { true } else { false } })
        #expect(rows.map(\.topSpacing) == [0, 6])
    }

    @Test func hiddenThinkingAloneLeavesNoHeader() {
        let items = [
            item(.assistant(text: "a")),
            item(.thinking(text: "t")),
            item(.assistant(text: "b")),
        ]
        let rows = ConversationTimelineLayout.rows(for: items, hidesThinking: true)
        #expect(rows.count == 2)
        #expect(rows.map(\.topSpacing) == [0, 6])
    }

    @Test func hiddenThinkingKeepsTheHeaderForToolRows() {
        let items = [item(.thinking(text: "t"), at: 0), tool(at: 5), item(.assistant(text: "a"), at: 9)]
        let rows = ConversationTimelineLayout.rows(for: items, hidesThinking: true)
        guard case .turn(let turn) = rows.first?.content else {
            Issue.record("expected a turn header")
            return
        }
        #expect(turn.activity.count == 1)
        #expect(turn.duration == 4)
    }

    @Test func durationRunsFromFirstToLastItemOfTheTurn() {
        let items = [tool(at: 10), item(.assistant(text: "a"), at: 88)]
        let rows = ConversationTimelineLayout.rows(for: items, hidesThinking: false)
        guard case .turn(let turn) = rows.first?.content else {
            Issue.record("expected a turn header")
            return
        }
        #expect(turn.duration == 78)
        #expect(ConversationDuration.format(turn.duration) == "1m 18s")
    }

    @Test func trailingRunEndsWhenItsLastStepFinished() {
        var last = tool(at: 5)
        last.endedAt = start.addingTimeInterval(9)
        let rows = ConversationTimelineLayout.rows(for: [item(.user(text: "q", imageCount: 0)), last], hidesThinking: false)
        guard case .turn(let turn) = rows.last?.content else {
            Issue.record("expected a turn header")
            return
        }
        #expect(turn.endedAt == start.addingTimeInterval(9))
    }

    @Test func trailingRunWithoutEndTimeFallsBackToItsStart() {
        let rows = ConversationTimelineLayout.rows(for: [tool(at: 5)], hidesThinking: false)
        guard case .turn(let turn) = rows.last?.content else {
            Issue.record("expected a turn header")
            return
        }
        #expect(turn.endedAt == start.addingTimeInterval(5))
    }

    @Test func keepsItemOrderWithOneHeaderPerContiguousRun() {
        let items = [
            tool(at: 0), item(.assistant(text: "a"), at: 4), tool(at: 6), item(.assistant(text: "b"), at: 10),
        ]
        let rows = ConversationTimelineLayout.rows(for: items, hidesThinking: false)
        let shape = rows.map { row -> String in
            if case .turn = row.content { "turn" } else { "item" }
        }
        #expect(shape == ["turn", "item", "turn", "item"])
        #expect(rows.map(\.id) == items.map(\.id))
        guard case .turn(let first) = rows[0].content else {
            Issue.record("expected a turn header")
            return
        }
        #expect(first.duration == 4)
        #expect(rows.map(\.topSpacing) == [0, 6, 14, 6])
    }

    @Test func onlyTheRunAtTheEndOfALiveTurnIsLive() {
        let items = [tool(at: 0), item(.assistant(text: "a"), at: 4), tool(at: 6)]
        let rows = ConversationTimelineLayout.rows(for: items, hidesThinking: false, isRunning: true)
        let live = rows.compactMap { row -> Bool? in
            if case .turn(let turn) = row.content { turn.isLive } else { nil }
        }
        #expect(live == [false, true])
    }

    @Test func onlyTheTrailingTurnIsLiveWhileRunning() {
        let items = [
            tool(), item(.user(text: "q", imageCount: 0)), tool(),
        ]
        let rows = ConversationTimelineLayout.rows(for: items, hidesThinking: false, isRunning: true)
        let live = rows.compactMap { row -> Bool? in
            if case .turn(let turn) = row.content { turn.isLive } else { nil }
        }
        #expect(live == [false, true])
    }
}

struct ConversationDurationTests {
    @Test func formatsSecondsMinutesAndHours() {
        #expect(ConversationDuration.format(0) == "0s")
        #expect(ConversationDuration.format(12.9) == "12s")
        #expect(ConversationDuration.format(59) == "59s")
        #expect(ConversationDuration.format(60) == "1m 0s")
        #expect(ConversationDuration.format(78) == "1m 18s")
        #expect(ConversationDuration.format(3599) == "59m 59s")
        #expect(ConversationDuration.format(7380) == "2h 3m")
    }

    @Test func negativeIntervalClampsToZero() {
        #expect(ConversationDuration.format(-5) == "0s")
    }
}

struct ReducerTimestampTests {
    @Test func itemsTakeTheInjectedClock() {
        var state = ConversationState()
        let moment = Date(timeIntervalSince1970: 42)
        ConversationReducer.apply(.notified(message: "hi"), to: &state) { moment }
        #expect(state.items.first?.createdAt == moment)
    }

    @Test func abortMidToolStampsEndTimeAtSettle() {
        var state = ConversationState()
        let started = Date(timeIntervalSince1970: 10)
        let settled = Date(timeIntervalSince1970: 50)
        ConversationReducer.apply(.toolExecutionStarted(id: "c1", name: "bash", argumentsJSON: "{}"), to: &state) { started }
        #expect(state.items.first?.endedAt == nil)
        ConversationReducer.apply(.runSettled(aborted: true), to: &state) { settled }
        #expect(state.items.first?.createdAt == started)
        #expect(state.items.first?.endedAt == settled)
    }

    @Test func toolExecutionEndStampsEndTime() {
        var state = ConversationState()
        let finished = Date(timeIntervalSince1970: 30)
        ConversationReducer.apply(.toolExecutionStarted(id: "c1", name: "bash", argumentsJSON: "{}"), to: &state) { Date(timeIntervalSince1970: 10) }
        ConversationReducer.apply(
            .toolExecutionEnded(id: "c1", name: "bash", resultText: "ok", isError: false, durationMs: nil),
            to: &state
        ) { finished }
        #expect(state.items.first?.endedAt == finished)
    }

    @Test func loadedHistoryHasNoEndTimes() {
        var state = ConversationState()
        state.load(messages: [ConversationMessage(role: .assistant, blocks: [.toolCall(id: "c1", name: "read", argumentsJSON: "{}")])])
        #expect(state.items.first?.endedAt == nil)
    }

    @Test func loadUsesMessageTimestamps() {
        var state = ConversationState()
        var message = ConversationMessage(role: .user, blocks: [.text("q")])
        let moment = Date(timeIntervalSince1970: 99)
        message.timestamp = moment
        state.load(messages: [message])
        #expect(state.items.first?.createdAt == moment)
    }
}

struct ChatAttachmentTests {
    @Test func classifiesBySizeAndType() {
        #expect(ChatAttachment.classify(mimeType: "image/png", byteCount: ChatAttachment.maxImageBytes) == .image(mimeType: "image/png"))
        #expect(ChatAttachment.classify(mimeType: "image/png", byteCount: ChatAttachment.maxImageBytes + 1) == .imageTooLarge)
        #expect(ChatAttachment.classify(mimeType: nil, byteCount: ChatAttachment.maxImageBytes * 10) == .file)
    }

    @Test func recognisesTheSupportedImageTypes() {
        #expect(ChatAttachment.mimeType(for: URL(fileURLWithPath: "/a/b.png")) == "image/png")
        #expect(ChatAttachment.mimeType(for: URL(fileURLWithPath: "/a/b.JPG")) == "image/jpeg")
        #expect(ChatAttachment.mimeType(for: URL(fileURLWithPath: "/a/b.gif")) == "image/gif")
        #expect(ChatAttachment.mimeType(for: URL(fileURLWithPath: "/a/b.webp")) == "image/webp")
        #expect(ChatAttachment.mimeType(for: URL(fileURLWithPath: "/a/b.txt")) == nil)
    }

    @Test func payloadPutsEachPathOnItsOwnLineAfterTheText() {
        let attachments = [
            ChatAttachment(name: "a", source: .file(URL(fileURLWithPath: "/tmp/a.txt"))),
            ChatAttachment(name: "b c", source: .file(URL(fileURLWithPath: "/tmp/b c.txt"))),
            ChatAttachment(name: "i.png", source: .image(Data([1]), mimeType: "image/png")),
        ]
        let payload = ChatAttachment.payload(text: "look", attachments: attachments)
        #expect(payload.text == "look\n/tmp/a.txt\n'/tmp/b c.txt'")
        #expect(payload.images == [PromptImage(data: Data([1]), mimeType: "image/png")])
    }

    @Test func payloadWithoutTextStartsWithThePath() {
        let attachments = [ChatAttachment(name: "a", source: .file(URL(fileURLWithPath: "/tmp/a.txt")))]
        #expect(ChatAttachment.payload(text: "", attachments: attachments).text == "/tmp/a.txt")
    }
}

struct ToolCallSummaryTests {
    @Test func prefersKnownKeys() {
        #expect(ToolCallSummary.argumentSummary(json: #"{"a":"x","command":"ls -la","path":"/tmp"}"#) == "/tmp")
        #expect(ToolCallSummary.argumentSummary(json: #"{"a":"x","query":"q"}"#) == "q")
    }

    @Test func readsTheSubagentName() {
        #expect(ToolCallSummary.argumentSummary(json: #"{"agent":"implementer","task":"do it"}"#) == "implementer")
        #expect(ToolCallSummary.argumentSummary(json: #"{"task":"do it","name":"reviewer"}"#) == "reviewer")
    }

    @Test func fallsBackToFirstStringValue() {
        #expect(ToolCallSummary.argumentSummary(json: #"{"n":3,"zeta":"z","alpha":"a"}"#) == "a")
    }

    @Test func truncatesToLimit() {
        let long = String(repeating: "x", count: 200)
        let summary = ToolCallSummary.argumentSummary(json: #"{"command":"\#(long)"}"#)
        #expect(summary?.count == ToolCallSummary.maxLength)
    }

    @Test func nilWithoutStringValue() {
        #expect(ToolCallSummary.argumentSummary(json: #"{"n":3}"#) == nil)
        #expect(ToolCallSummary.argumentSummary(json: "not json") == nil)
    }
}
