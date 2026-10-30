import Foundation

/// Picks the generator for the agent chosen in Settings at the moment of each request.
struct CommitMessageGeneratorRouter: CommitMessageGenerating {
    static let missingGeneratorReason = "No commit message generator is registered."

    let generators: [AgentKind: any CommitMessageGenerating]
    let selection: @MainActor @Sendable () -> AgentKind

    func generate(_ context: CommitPromptContext) async throws -> String {
        let kind = await selection()
        guard let generator = generators[kind] else {
            throw CommitMessageGeneratorError.runtimeUnavailable(agent: kind, reason: Self.missingGeneratorReason)
        }
        return try await generator.generate(context)
    }
}
