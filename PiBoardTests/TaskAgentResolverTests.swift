import Foundation
import Testing
@testable import PiBoard

struct TaskAgentResolverTests {
    private func project(defaultAgent: AgentKind) -> Project {
        Project(id: UUID(), name: "P", path: URL(fileURLWithPath: "/tmp/p"), defaultAgent: defaultAgent, createdAt: Date(), updatedAt: Date())
    }

    @Test func anEnabledProjectDefaultWins() {
        let agent = TaskAgentResolver.agent(for: project(defaultAgent: .opencode), enabled: [.pi, .opencode], fallback: .pi)
        #expect(agent == .opencode)
    }

    @Test func aDisabledProjectDefaultFallsBack() {
        let agent = TaskAgentResolver.agent(for: project(defaultAgent: .pi), enabled: [.claudeCode], fallback: .claudeCode)
        #expect(agent == .claudeCode)
    }
}
