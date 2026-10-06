import SwiftUI

private let sheetWidth: CGFloat = 560
private let sheetHeight: CGFloat = 460

struct TaskPreparationView: View {
    let taskID: UUID
    @Environment(AppEnvironment.self) private var environment
    @Environment(\.dismiss) private var dismiss
    @State private var prompt: String = ""
    @State private var runContext: RunContext = .current
    @State private var errorMessage: String?
    @State private var showsStartFreshConfirmation = false

    private enum Readiness {
        case runtimeMissing
        case currentTreeBusy(ownerTaskID: UUID)
        case ready
    }

    private var board: BoardModel { environment.board }

    private var task: BoardTask? {
        board.tasks.first { $0.id == taskID }
    }

    private var project: Project? {
        guard let task else { return nil }
        return board.projects.first { $0.id == task.projectId }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if let task, let project {
                header(task: task, project: project)
                promptSection
                runInSection
                statusLine
                Spacer(minLength: 0)
                footer(task: task, project: project)
            } else {
                ContentUnavailableView("Task Not Found", systemImage: "exclamationmark.triangle")
            }
        }
        .padding(20)
        .frame(width: sheetWidth, height: sheetHeight)
        .onAppear {
            runContext = .current
            prompt = task?.prompt ?? ""
        }
    }

    private func header(task: BoardTask, project: Project) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(task.title)
                .font(.title3.weight(.semibold))
            Text("\(project.name) \u{B7} \(Self.abbreviatedPath(project.path))")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var promptSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Initial Prompt")
                .font(.caption)
                .foregroundStyle(.secondary)
            PromptEditor(text: $prompt, minHeight: 100)
        }
    }

    private var runInSection: some View {
        VStack(alignment: .leading, spacing: 4) {
            Picker("Run in", selection: $runContext) {
                ForEach(RunContext.allCases, id: \.self) { context in
                    Text(context.title)
                        .tag(context)
                        .disabled(context == .worktree)
                }
            }
            .pickerStyle(.radioGroup)
            Text("New Worktree: Available in a later milestone")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
    }

    @ViewBuilder
    private var statusLine: some View {
        switch readiness {
        case .runtimeMissing:
            HStack {
                Label("Pi runtime is not installed.", systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Spacer()
                SettingsLink {
                    Text("Open Settings")
                }
            }
        case .currentTreeBusy(let ownerTaskID):
            Label("\(ownerTitle(for: ownerTaskID)) is already running Pi in this working tree.", systemImage: "lock.fill")
                .foregroundStyle(.orange)
        case .ready:
            Label("Ready to start.", systemImage: "checkmark.circle")
                .foregroundStyle(.secondary)
        }
        if let errorMessage {
            Text(errorMessage)
                .font(.caption)
                .foregroundStyle(.red)
        }
    }

    private func footer(task: BoardTask, project: Project) -> some View {
        HStack {
            Spacer()
            Button("Cancel") { dismiss() }
            if task.piSessionId != nil {
                Button("Start Fresh") { showsStartFreshConfirmation = true }
                Button("Resume Pi") { resume(task: task, project: project) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isReady)
            } else {
                Button("Start Pi") { start(task: task, project: project) }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isReady)
            }
        }
        .confirmationDialog(
            "Start a new Pi session?",
            isPresented: $showsStartFreshConfirmation
        ) {
            Button("Start Fresh", role: .destructive) {
                board.setPiSessionID(nil, for: task.id)
                start(task: task, project: project)
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("The previous session stays on disk and can no longer be resumed from this task.")
        }
    }

    private var readiness: Readiness {
        guard case .ready = environment.piRuntime.status else { return .runtimeMissing }
        if runContext == .current,
           let project,
           let owner = environment.processes.currentTreeOwners[PiProcessManager.canonicalPath(project.path)],
           owner != taskID {
            return .currentTreeBusy(ownerTaskID: owner)
        }
        return .ready
    }

    private var isReady: Bool {
        if case .ready = readiness { return true }
        return false
    }

    private func ownerTitle(for ownerTaskID: UUID) -> String {
        board.tasks.first { $0.id == ownerTaskID }?.title ?? "Another task"
    }

    private func start(task: BoardTask, project: Project) {
        errorMessage = nil
        let sessionID = UUID()
        board.setPiSessionID(sessionID, for: task.id)
        board.setRunContext(runContext, for: task.id)
        board.updatePrompt(prompt, for: task.id)
        do {
            _ = try environment.processes.start(
                task: task,
                project: project,
                runContext: runContext,
                prompt: prompt,
                sessionID: sessionID,
                runtime: environment.piRuntime
            )
            board.openTerminalTaskID = task.id
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func resume(task: BoardTask, project: Project) {
        errorMessage = nil
        guard let sessionID = task.piSessionId else { return }
        board.setRunContext(runContext, for: task.id)
        do {
            _ = try environment.processes.resume(
                task: task,
                project: project,
                runContext: runContext,
                sessionID: sessionID,
                runtime: environment.piRuntime
            )
            board.openTerminalTaskID = task.id
            dismiss()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private static func abbreviatedPath(_ url: URL) -> String {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let path = url.path
        if path.hasPrefix(home) {
            return "~" + path.dropFirst(home.count)
        }
        return path
    }
}
