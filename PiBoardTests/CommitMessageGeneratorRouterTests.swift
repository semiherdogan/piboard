import Testing
@testable import PiBoard

struct CommitMessageGeneratorRouterTests {
    private static let context = CommitPromptContext(diff: "diff", branch: nil, recentSubjects: [])

    @Test func routesToTheGeneratorOfTheSelectedKind() async throws {
        let router = CommitMessageGeneratorRouter(
            generators: [
                .pi: FakeCommitMessageGenerator(result: .success("from pi")),
                .claudeCode: FakeCommitMessageGenerator(result: .success("from claude")),
            ],
            selection: { .claudeCode }
        )

        #expect(try await router.generate(Self.context) == "from claude")
    }

    @Test func missingKindIsRuntimeUnavailable() async throws {
        let router = CommitMessageGeneratorRouter(
            generators: [.pi: FakeCommitMessageGenerator(result: .success("from pi"))],
            selection: { .opencode }
        )

        await #expect(
            throws: CommitMessageGeneratorError.runtimeUnavailable(
                agent: .opencode,
                reason: CommitMessageGeneratorRouter.missingGeneratorReason
            )
        ) {
            try await router.generate(Self.context)
        }
    }
}
