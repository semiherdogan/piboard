import Foundation

/// Decides which items take a row and the gap above each, so one agent turn reads as a group.
enum ConversationTimelineLayout {
    /// A contiguous run of thinking and tool items, folded under a "Worked for" header.
    struct Turn: Equatable, Identifiable {
        let id: UUID
        let activity: [ConversationItem]
        let startedAt: Date
        let endedAt: Date
        /// True while the agent is still producing this run, which is only the trailing run of the live turn.
        let isLive: Bool

        var duration: TimeInterval { endedAt.timeIntervalSince(startedAt) }
    }

    struct Row: Identifiable, Equatable {
        enum Content: Equatable {
            case item(ConversationItem)
            case turn(Turn)
        }

        let content: Content
        let topSpacing: CGFloat

        var id: UUID {
            switch content {
            case .item(let item): item.id
            case .turn(let turn): turn.id
            }
        }
    }

    static let withinTurnSpacing: CGFloat = 6
    static let betweenTurnsSpacing: CGFloat = 20
    static let turnHeaderTopSpacing: CGFloat = 14

    static func rows(for items: [ConversationItem], hidesThinking: Bool, isRunning: Bool = false) -> [Row] {
        var rows: [Row] = []
        var turn: [ConversationItem] = []
        for item in items {
            if isUser(item) {
                appendTurn(turn, isLive: false, hidesThinking: hidesThinking, to: &rows)
                turn = []
                rows.append(Row(content: .item(item), topSpacing: rows.isEmpty ? 0 : betweenTurnsSpacing))
            } else {
                turn.append(item)
            }
        }
        // Only the trailing agent turn can still be streaming.
        appendTurn(turn, isLive: isRunning, hidesThinking: hidesThinking, to: &rows)
        return rows
    }

    private static func appendTurn(_ turn: [ConversationItem], isLive: Bool, hidesThinking: Bool, to rows: inout [Row]) {
        let visible = turn.filter { !(hidesThinking && isThinking($0)) }
        var spacing = rows.isEmpty ? 0 : betweenTurnsSpacing
        var index = 0
        while index < visible.count {
            let item = visible[index]
            guard isActivity(item) else {
                rows.append(Row(content: .item(item), topSpacing: spacing))
                spacing = withinTurnSpacing
                index += 1
                continue
            }
            // Only a contiguous run folds, so text and notices keep their place between the headers.
            var end = index
            while end < visible.count, isActivity(visible[end]) { end += 1 }
            let activity = Array(visible[index..<end])
            let reachesEnd = end == visible.count
            let endedAt = (reachesEnd ? activity.last : visible[end])?.createdAt ?? item.createdAt
            let header = Turn(id: item.id, activity: activity, startedAt: item.createdAt, endedAt: endedAt, isLive: isLive && reachesEnd)
            // A header that opens the turn sits like the first row of a turn; one inside a turn is tighter.
            let headerSpacing = rows.isEmpty ? 0 : (index == 0 ? betweenTurnsSpacing : turnHeaderTopSpacing)
            rows.append(Row(content: .turn(header), topSpacing: headerSpacing))
            spacing = withinTurnSpacing
            index = end
        }
    }

    private static func isUser(_ item: ConversationItem) -> Bool {
        if case .user = item.kind { return true }
        return false
    }

    private static func isThinking(_ item: ConversationItem) -> Bool {
        if case .thinking = item.kind { return true }
        return false
    }

    private static func isActivity(_ item: ConversationItem) -> Bool {
        switch item.kind {
        case .thinking, .toolCall: true
        case .user, .assistant, .compaction, .notice: false
        }
    }
}
