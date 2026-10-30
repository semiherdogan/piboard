import Foundation

/// Drafts the message through a throwaway session on the shared OpenCode service; `generate` runs no tools and leaves no messages.
struct OpenCodeCommitMessageGenerator: CommitMessageGenerating {
    static let sessionTitle = "PiBoard commit message"
    private static let promptSeparator = "\n\n"

    let service: OpenCodeService
    /// A throwaway directory, like Pi's, so no project instructions leak into the message.
    let directory: URL

    init(service: OpenCodeService, directory: URL = FileManager.default.temporaryDirectory) {
        self.service = service
        self.directory = directory
    }

    func generate(_ context: CommitPromptContext) async throws -> String {
        let id = OpenCodeClient.makeSessionID()
        // The generate endpoint has no system prompt field, so the instructions travel in the prompt.
        let prompt = CommitMessagePrompt.systemPrompt + Self.promptSeparator + CommitMessagePrompt.prompt(for: context)
        let directory = directory
        let text: String
        do {
            text = try await service.withClient { client in
                _ = try await client.createSession(id: id, title: Self.sessionTitle, directory: directory)
                do {
                    let text = try await client.generate(sessionID: id, prompt: prompt)
                    try? await client.deleteSession(id: id)
                    return text
                } catch {
                    try? await client.deleteSession(id: id)
                    throw error
                }
            }
        } catch is CancellationError {
            throw CancellationError()
        } catch let error as OpenCodeService.Failure {
            throw CommitMessageGeneratorError.runtimeUnavailable(agent: .opencode, reason: error.localizedDescription)
        } catch {
            throw CommitMessageGeneratorError.failed(error.localizedDescription)
        }
        let message = CommitMessagePrompt.sanitize(text)
        guard !message.isEmpty else {
            throw CommitMessageGeneratorError.emptyResponse(agent: .opencode)
        }
        return message
    }
}
