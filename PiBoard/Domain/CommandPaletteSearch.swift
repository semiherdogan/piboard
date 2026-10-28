import Foundation

/// One row of the command palette.
struct CommandPaletteItem: Identifiable, Equatable, Sendable {
    enum Kind: Equatable, Sendable {
        case project(Project)
        case task(BoardTask, projectName: String)
    }

    static let projectSystemImage = "folder"
    static let taskSystemImage = "square.text.square"
    private static let taskSubtitleSeparator = " / "

    let kind: Kind

    var id: UUID {
        switch kind {
        case .project(let project): project.id
        case .task(let task, _): task.id
        }
    }

    var title: String {
        switch kind {
        case .project(let project): project.name
        case .task(let task, _): task.title
        }
    }

    /// Abbreviated path for a project, "<project> / <status title>" for a task.
    var subtitle: String {
        switch kind {
        case .project(let project): ProjectPathService.abbreviated(project.path)
        case .task(let task, let projectName): projectName + Self.taskSubtitleSeparator + task.status.title
        }
    }

    var systemImage: String {
        switch kind {
        case .project: Self.projectSystemImage
        case .task: Self.taskSystemImage
        }
    }
}

/// Ranks projects and tasks against what the user typed. Matching is case and diacritic
/// insensitive so "cig" finds the same word with any accents; a blank query lists everything, projects first.
enum CommandPaletteSearch {
    static let maxResults = 30

    private static let titlePrefixScore = 4
    private static let titleWordPrefixScore = 3
    private static let titleContainsScore = 2
    private static let promptContainsScore = 1
    private static let noMatchScore = 0
    // Latin-ASCII also folds letters that diacritic folding keeps apart, such as the Turkish dotless i.
    private static let asciiTransform = StringTransform("Any-Latin; Latin-ASCII")
    private static let foldingOptions: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]

    static func results(query: String, projects: [Project], tasks: [BoardTask]) -> [CommandPaletteItem] {
        let projectNames = Dictionary(projects.map { ($0.id, $0.name) }, uniquingKeysWith: { first, _ in first })
        let items = projects.map { CommandPaletteItem(kind: .project($0)) }
            + tasks.map { CommandPaletteItem(kind: .task($0, projectName: projectNames[$0.projectId] ?? "")) }

        let needle = normalize(query.trimmingCharacters(in: .whitespacesAndNewlines))
        guard !needle.isEmpty else { return Array(items.prefix(maxResults)) }

        let scored = items.enumerated().compactMap { offset, item -> (offset: Int, score: Int, item: CommandPaletteItem)? in
            let value = score(item, needle: needle)
            return value > noMatchScore ? (offset, value, item) : nil
        }
        let ranked = scored.sorted { $0.score != $1.score ? $0.score > $1.score : $0.offset < $1.offset }
        return ranked.prefix(maxResults).map(\.item)
    }

    private static func score(_ item: CommandPaletteItem, needle: String) -> Int {
        let title = normalize(item.title)
        if title.hasPrefix(needle) { return titlePrefixScore }
        if title.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(needle) }) {
            return titleWordPrefixScore
        }
        if title.contains(needle) { return titleContainsScore }
        if case .task(let task, _) = item.kind, normalize(task.prompt).contains(needle) {
            return promptContainsScore
        }
        return noMatchScore
    }

    private static func normalize(_ text: String) -> String {
        (text.applyingTransform(asciiTransform, reverse: false) ?? text).folding(options: foldingOptions, locale: nil)
    }
}

/// Where a palette selection lands.
enum CommandPaletteRouting {
    enum Destination: Equatable { case terminal, board }

    /// A task the user can watch goes to its terminal; everything else lands on the board.
    static func destination(for task: BoardTask, hasLiveSession: Bool) -> Destination {
        task.status == .inProgress && (task.sessionID != nil || hasLiveSession) ? .terminal : .board
    }
}
