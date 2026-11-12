enum TaskAgentResolver {
    /// The project's default while it is enabled, otherwise the fallback.
    static func agent(for project: Project, enabled: [AgentKind], fallback: AgentKind) -> AgentKind {
        enabled.contains(project.defaultAgent) ? project.defaultAgent : fallback
    }
}
