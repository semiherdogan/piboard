# Architecture

PiBoard is a single-target SwiftUI app (`PiBoard/`) with one unit test bundle (`PiBoardTests/`). Code is split into layers by folder; there are no Swift packages of its own. External dependencies: SwiftTerm (terminal emulator view and PTY process), Sparkle (self-update) and the system `libsqlite3`.

## Layers

| Layer | Folder | Responsibility |
| --- | --- | --- |
| App | `PiBoard/App` | Composition root, window and scene setup, app delegate (quit confirmation), file locations, user preferences. `BoardModel` lives in `AppModel.swift`. |
| Domain | `PiBoard/Domain` | Plain value types and pure logic: `Project`, `BoardTask`, `TaskStatus`, `RunContext`, `TaskRuntimeState`, `PTYRuntimeState`, `TaskOrdering`, `PromptComposer`, `ProjectExportDocument`, `SemanticVersion`. No I/O. |
| Persistence | `PiBoard/Persistence` | SQLite wrapper (`Database`, `Connection`), repositories for projects, tasks and settings, numbered migrations. |
| Services | `PiBoard/Services` | Processes, Git, files and the network: PTY sessions, Pi process lifecycle, Pi runtime install, Git and worktrees, external apps, export files, updates. |
| Features | `PiBoard/Features` | SwiftUI views and their small view models, one folder per screen: Board, Preparation, Projects, Settings, TaskDetail, Terminal. |
| Shared | `PiBoard/Shared` | Reusable view components (banner, status badge, prompt editor) and utilities (`Diagnostics` loggers, preview sample data). |

### App: composition root

`AppEnvironment` (`PiBoard/App/AppEnvironment.swift`) builds every long-lived object once and is injected into SwiftUI with `.environment(...)`:

- Opens `piboard.sqlite` and runs migrations. If that fails it falls back to an in-memory database and sets `startupError`, so the UI still works but nothing persists.
- Creates `BoardModel`, `AppPreferences`, `PiRuntimeManager`, `PiProcessManager`, `GitService`, `WorktreeService`, `ExternalAppActions`, `WorktreeActions` and `UpdateService`.
- Wires `PiRuntimeManager.versionsInUse` to the process manager, so a runtime version used by a live session is never deleted.
- Re-applies terminal preferences to every live session when they change.
- Detects hosted unit tests (`XCTestConfigurationFilePath`) and then skips the npm registry check and Sparkle.

`AppDelegate` owns the quit confirmation (see [Process and terminal model](#process-and-terminal-model)).

### Persistence

- `Database` serializes all access to one SQLite connection on a private serial queue. Pragmas: `foreign_keys = ON`, `journal_mode = WAL` (file databases only), `busy_timeout = 5000`.
- Repositories: `ProjectRepository`, `TaskRepository` (including `applyOrdering`, which rewrites positions of the affected columns in one transaction) and `SettingsRepository` (typed key/value access keyed by the `SettingKey` enum).
- Migrations: `MigrationRunner.all` is an ordered list of `Migration(version:sql:)`. The runner reads `PRAGMA user_version` and applies every newer migration inside its own transaction, bumping `user_version` with it.

| Version | File | Change |
| --- | --- | --- |
| 1 | `Migration001_InitialSchema.swift` | `projects`, `tasks`, `settings` tables from spec section 11, plus index `tasks(project_id, status, position)` |
| 2 | `Migration002_NormalizeTaskPositions.swift` | Renumbers positions to `0..<N` per project and status (backfill for an old ordering bug) |

See [development.md](development.md#adding-a-migration) for how to add one.

### Services

| Service | File | What it does |
| --- | --- | --- |
| `PTYSession` | `Services/PTYSession.swift` | Owns one SwiftTerm `LocalProcess` (PTY child) and one `PiBoardTerminalView`. Starts the child, forwards output to the view, resizes the PTY, stops with SIGTERM then SIGKILL, decodes the `waitpid` status into an exit code. |
| `PiProcessManager` | `Services/PiProcessManager.swift` | One `PTYSession` per task. Enforces the current-tree lock, builds the launch command, tracks `runtimeStates` per task and the Pi version each session launched with. Implements `stopAll()` for quit. |
| `PiRuntimeManager` | `Services/PiRuntimeManager.swift` | Installs, verifies, activates, rolls back and removes versioned Pi installs under Application Support. Checks the npm registry for the latest version (at most once per 24 hours in the background). Keeps the newest 3 versions plus active and in-use ones. |
| `GitService` | `Services/GitService.swift` | Runs `/usr/bin/git` with a 15 s timeout: repository info (top level, HEAD branch), `status --porcelain` parsing, current branch. |
| `WorktreeService` | `Services/WorktreeService.swift` | Creates, validates, removes and prunes managed worktrees; owns branch naming and managed paths. |
| `ExternalAppService` | `Services/ExternalAppService.swift` | Resolves installed apps by bundle identifier and opens a folder with `NSWorkspace`. Finder uses `selectFile`. |
| `UpdateService` | `Services/UpdateService.swift` | Wraps Sparkle's `SPUStandardUpdaterController`; stores the update channel; reports "not configured" when `SUPublicEDKey` is missing or the placeholder. |
| Others | `BundledNode`, `PiLaunchCommand`, `PiRuntimePaths`, `PiRuntimeCommandRunner`, `ProjectExportService`, `ProjectPathService`, `ShellResolver` | Bundled Node lookup, argument array construction, on-disk runtime layout, subprocess runner for npm and verification, export/import, path canonicalization. |

### Features

| Folder | Main types |
| --- | --- |
| `Board` | `BoardView`, `BoardColumnView`, `TaskCardView`, `BoardDragController` and `BoardDragTargeting` (custom drag), `ProjectGitStatusRow`, `ExternalAppActions`, `WorktreeActions` |
| `Preparation` | `TaskPreparationView`: prompt, Plan first, run context, preflight, launch |
| `Projects` | `ProjectSidebarView` (folder and export-file drop), `NewProjectSheet`, `EditProjectSheet`, export/import panels |
| `TaskDetail` | `TaskInspectorView` |
| `Terminal` | `TerminalWorkspaceView`, `TerminalHostView` (`NSViewRepresentable`), `PiBoardTerminalView` (context menu), appearance and preferences |
| `Settings` | `SettingsView` (General), `TerminalSettingsView`, `PiRuntimeSettingsView` |

## Key invariants

From spec section 10.3, with where the code enforces them.

| Invariant | Enforcement |
| --- | --- |
| Done is never automatic | Nothing writes `status = done` except a user move. A Pi exit only changes `runtimeStates`. |
| In Progress is not Running | Workflow state (`BoardTask.status`, persisted) and runtime state (`PiProcessManager.runtimeStates`, memory only) are separate. Moving to In Progress opens the preparation sheet; it never spawns Pi. After a restart every task is `notStarted` at runtime. |
| One current-tree session per project | `PiProcessManager.CurrentTreeLock` maps canonical path to owner task. A second current-tree launch throws `currentTreeBusy`; the preparation sheet shows the block before that. Worktree launches skip the lock. The lock is released when the session exits. |
| Session id is never dropped | The UUID is written to `tasks.pi_session_id` before spawn. It is cleared only by an explicit, confirmed Start Fresh. Removing a worktree keeps the session id (and `run_context = worktree`) so the missing-worktree flow can explain why resume is impossible. |
| Closing the terminal does not kill Pi | The PTY belongs to `PTYSession`, which belongs to `PiProcessManager`, not to the view. |
| Never resume a worktree session in the project root | `PiProcessManager.launch` throws `worktreeMissing` for a missing worktree; the preparation sheet validates path and branch first. |

Moving a running task out of In Progress asks "Pi is still running for this task. Stop it and move?". Stop and Move stops the process and then moves the card; Cancel leaves both alone.

## Process and terminal model

```
TerminalWorkspaceView
  └── TerminalHostView (NSViewRepresentable, container NSView)
        └── PiBoardTerminalView (SwiftTerm TerminalView)   <- owned by PTYSession
PiProcessManager
  └── sessions[taskID] = PTYSession
        ├── LocalProcess (PTY master fd, child pid)
        └── PTYBridge (delegate for LocalProcess and TerminalView)
```

- **Ownership.** `PTYSession` creates the terminal view once and keeps it for the life of the session. Scrollback and screen state survive leaving the terminal.
- **Attach and detach.** `TerminalHostView.updateNSView` moves the session's view into a fresh container when the workspace appears and makes it first responder. `dismantleNSView` removes it and resigns first responder. The process is unaffected. Both events are logged in the `ui` category.
- **Sizing.** The container lays out the terminal view from its bounds. On the first real layout `syncWindowSize()` pushes rows and columns to the PTY, because SwiftTerm does not report a size change when the computed size equals the startup size.
- **Stop.** `terminate()` sends SIGTERM directly to the child and arms a 5 s fallback that sends SIGKILL. It does not call `LocalProcess.terminate()`, because that cancels SwiftTerm's exit monitor and the exit would never be observed.
- **Quit.** `AppDelegate.applicationShouldTerminate` counts active sessions. If any exist it shows "Quit PiBoard?" with "Stop and Quit" and "Cancel". On confirm, `PiProcessManager.stopAll()` sends SIGTERM to every session, waits up to 2 s for exits, then SIGKILLs survivors. Tasks keep their workflow state and can be resumed.
- **Focus mode.** The expand button switches the split view to detail only. Same PTY, same view.

## Launch data flow

What happens when a task goes from Backlog to a running Pi session.

1. **Drag.** `BoardDragController` tracks the card and computes the target column and index. On drop `BoardModel.requestMove` calls `move`: `TaskOrdering.reorder` updates the in-memory list optimistically, `TaskRepository.applyOrdering` writes the new positions in one transaction, and the snapshot is restored if the write fails. A Backlog to In Progress move sets `pendingPreparationTaskID`.
2. **Preparation.** `BoardView` presents `TaskPreparationView`. The prompt is editable, Plan first comes from the stored preference, and the run context is always reset to Current Working Tree.
3. **Preflight.** Readiness checks run first: Pi runtime ready, project folder exists, current tree not owned by another task. Then `GitService.repositoryInfo` decides whether New Worktree is available, and for the current tree `git status --porcelain` produces the dirty file list. A dirty tree offers Use Worktree Instead and Run Anyway.
4. **Worktree create (worktree only).** `WorktreeService.create` runs `git worktree add -b <branch> <managed-path> HEAD`, or checks out the existing branch if a previous worktree for the task was removed. Path and branch are saved to the task. On failure the task stays In Progress and the error is shown inline.
5. **UUID.** The sheet generates a new session UUID.
6. **DB write.** `pi_session_id`, `run_context` and the edited prompt are written to SQLite before any process exists.
7. **Spawn.** `PiProcessManager.start` validates the working directory, requires a ready runtime, takes the current-tree lock if needed, resolves the bundled Node and the active Pi entry, builds the argument array and starts a new `PTYSession`. The task becomes `starting`.
8. **Observe.** `withObservationTracking` on `PTYSession.state` maps PTY state into `runtimeStates` (`running`, then `exited(code)`), re-arming until exit, and releases the lock on exit. The sheet dismisses and the terminal workspace replaces the board.

Resume (`Resume Pi` in the sheet or the terminal workspace) follows steps 3, 7 and 8 with `--session <uuid>` in the context the session was started in. A worktree session is validated (path exists, is a worktree, branch matches) before resuming.

## Runtime layout on disk

```
PiBoard.app/Contents/Resources/node/            bundled Node 24 (copied from Runtime/node)
├── bin/node
└── lib/node_modules/npm/bin/npm-cli.js

~/Library/Application Support/PiBoard/
├── piboard.sqlite                              (+ -wal, -shm)
├── runtime/
│   ├── npm-cache/                              npm cache used for Pi installs
│   └── pi/
│       ├── current.json                        {"activeVersion": "...", "previousVersion": "..."}
│       └── versions/<x.y.z>/node_modules/@earendil-works/pi-coding-agent/dist/bundle/cli.js
└── worktrees/<project-uuid>/<task-uuid>/       managed Git worktrees
```

The spec placed Node under `Resources/runtime/node`; xcodegen copies the folder reference by name, so it is `Resources/node`.

Install sequence (`PiRuntimeManager.install`):

1. `node npm-cli.js install --prefix versions/<v> --no-audit --no-fund @earendil-works/pi-coding-agent@<v>` with a private npm cache. `NODE_OPTIONS` and npm prefix variables are stripped from the environment.
2. Verify: `node <entry> --version` must exit 0 and print the version, then `node <entry> --help` must exit 0 (20 s timeout each).
3. Activate: write `current.json` through a temp file and `replaceItemAt`.
4. Retention: delete installs beyond the newest 3, never the active one or one a live session uses.

A failed install deletes its version directory and leaves the active version untouched. Changing the active version never affects a running session; the entry path is resolved at launch only.

## How Pi is launched

- Executable: the absolute path of the bundled `node`. Pi is never looked up on `PATH`.
- Arguments (an array, never a shell string):
  - New: `<entry> --session-id <uuid> --name <task title> [<prompt>]`
  - Resume: `<entry> --session <uuid>`
- Working directory: the project folder (current tree) or the task worktree.
- Environment: PiBoard's own process environment, plus `TERM=xterm-256color` and `COLORTERM=truecolor`. `PI_CODING_AGENT_DIR` is never set, so Pi uses `~/.pi/agent` exactly like a normal terminal. PiBoard never reads or writes that folder.
- Pi is the direct child of the PTY, not a shell. When PiBoard is opened from Finder or the Dock, the environment is the one launchd gives GUI apps, so variables exported only in `~/.zshrc` are not present. When Pi exits, the terminal shows the exit overlay with Resume; there is no shell prompt afterwards. This differs from spec section 42.3, which asked for a user login shell (`PTYSession.startLoginShell` exists but is unused).

## Concurrency

- Swift 6 language mode with `SWIFT_STRICT_CONCURRENCY: complete`.
- Models and services that UI reads are `@MainActor @Observable` (`BoardModel`, `PiProcessManager`, `PiRuntimeManager`, `PTYSession`, `UpdateService`, `AppPreferences`).
- Blocking work leaves the main actor explicitly: npm install and verification in `Task.detached`, the registry request in a `@concurrent nonisolated` function, Git through `async` calls on a runner that uses its own queue.
- SwiftTerm's delegate protocols are synchronous and not actor isolated. `PTYBridge` is a plain object that implements `LocalProcessDelegate` and `TerminalViewDelegate` and hops to the main actor with `Task { @MainActor ... }`. The PTY window size is cached in a lock-protected `WindowSizeBox` because `getWindowSize()` can be called off the main thread.
- Sparkle and KVO callbacks arrive on the main thread and use `MainActor.assumeIsolated`.
- `Database` is `@unchecked Sendable`; its safety comes from the serial queue.
- `withObservationTracking` fires once, so observers (`observeState`, `observeTerminalPreferences`) re-arm themselves after each change.

## Diagnostics

All logs use subsystem `dev.piboard` (`PiBoard/Shared/Utilities/Diagnostics.swift`).

| Category | Logged events |
| --- | --- |
| `ui` | Inspector presented and dismissed, preparation sheet present and dismiss, open and close terminal, terminal attach, detach and initial layout (frame, bounds, first responder) |
| `git` | Preflight result, worktree create and validate, launch context and working directory |
| `runtime` | Pi install, activate, remove, retention cleanup |

```sh
log show --predicate 'subsystem == "dev.piboard"' --info --last 30m
log stream --predicate 'subsystem == "dev.piboard" AND category == "ui"' --info
```
