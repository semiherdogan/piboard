# PiBoard: notes for coding agents

PiBoard is a native macOS app (SwiftUI, Swift 6, macOS 26) that runs the Pi coding agent in a kanban board: one Pi session per task, each in a real PTY terminal, optionally in its own Git worktree. Node and Pi are bundled or installed by the app, never taken from `PATH`.

Read this file, then the doc that matches your task. Do not read the whole `docs/` folder up front.

## Build and test

Everything goes through the Makefile. Do not call `xcodebuild` or `swift test` yourself.

```sh
make generate   # fetch Node into Runtime/node if missing, then xcodegen
make build      # Debug build into build/DerivedData
make test       # PiBoardTests (Swift Testing), builds first
make run        # build, quit a running PiBoard, open the Debug app
```

- `PiBoard.xcodeproj` is generated from `project.yml` and gitignored. New Swift files are picked up automatically; never edit the project file.
- `make test` is the verification for any code change. Run it before reporting done. The suite takes a few minutes; do not skip it.
- Strict concurrency is on (`SWIFT_STRICT_CONCURRENCY: complete`). Zero warnings is the bar.
- The build needs Xcode 27, xcodegen and the Metal toolchain. If `make generate` fails on a missing toolchain, say so instead of working around it.

## Where things live

| Path | What |
| --- | --- |
| `PiBoard/App` | `AppEnvironment` (composition root, every service is injected here), `BoardModel` in `AppModel.swift`, `MainWindow`, `AppPreferences` |
| `PiBoard/Domain` | Value types and pure logic, no I/O: `BoardTask`, `TaskStatus`, `TaskRuntimeState`, ordering, export format |
| `PiBoard/Persistence` | SQLite wrapper, repositories, numbered migrations, `SettingKey` |
| `PiBoard/Services` | `PiProcessManager`, `PTYSession`, `PiLaunchCommand`, `PiRuntimeManager`, Git, worktrees, notifications, `PiSessionLocator` |
| `PiBoard/Features` | SwiftUI screens: Board, Preparation, Projects (sidebar), Settings, TaskDetail (inspector), Terminal |
| `PiBoardTests` | One file per subject. Fakes live next to the tests that use them (`FakeGitService`, `FakeWorktreeService`, ...) |
| `scripts` | `fetch-node.sh` (bundled Node, trimmed), `release.sh` (Sparkle appcast and deltas) |
| `docs` | `architecture.md`, `development.md`, `user-guide.md`, `testing.md`, `RELEASING.md` |

## Conventions that are checked in review

Full list in `docs/development.md`. The ones agents most often get wrong:

- No magic literals. A label, flag, key or threshold gets a named constant on the owning type or a `private let` at the top of the file. Compare enums by case, never by raw value.
- Comments say why, in one line. No banners, no narration, no TODOs.
- Build processes as executable plus argument array. Never a shell string.
- UI-facing models are `@MainActor @Observable`. Blocking work goes off the main actor. Callbacks from SwiftTerm or Sparkle come through bridge objects.
- Layering: Domain has no I/O, Persistence knows nothing about UI, views reach services only through `AppEnvironment`.
- Services with a protocol get a fake in tests. Prefer extending an existing fake over a new one.
- Workflow state (`BoardTask.status`, persisted) and runtime state (`PiProcessManager.runtimeStates`, memory only) are separate. Never derive one from the other.
- No `.keyboardShortcut` on views. Shortcuts are recorded by the user in Settings and dispatched by `ShortcutDispatcher`.
- `~/.pi/agent` belongs to the user. The only thing PiBoard writes there is deleting a session file when its task is deleted.

## Invariants (do not break)

- Done is never automatic. Only a user move writes `status = done`.
- Moving to In Progress opens the preparation sheet; it never spawns Pi.
- The session UUID is written to SQLite before the process is spawned, and only an explicit Start Fresh replaces it.
- One current-tree Pi session per project by default (`CurrentTreeLock`). The user can override with Start Anyway or Resume Anyway; such a session never takes or releases the lock.
- Leaving the terminal never stops Pi. The PTY belongs to `PTYSession`, which belongs to `PiProcessManager`, not to a view.
- A worktree session is never resumed in the project root.

## Screens and flows

Each screen has one source file; start there.

| Screen | File | Notes |
| --- | --- | --- |
| Sidebar | `Features/Projects/ProjectSidebarView.swift` | Project list. Status dots at the end of the path line: green pulsing = agent working, grey = Pi alive and idle, blue = finished while you were away (`TaskAttention`). |
| Board | `Features/Board/BoardView.swift`, `BoardColumnView.swift`, `TaskCardView.swift` | Three columns. Done header has Clear (confirmed, deletes every Done task). Cards show the same dots plus a Working/Idle badge; an idle Pi gets a small stop button, the context menu has Stop Pi (confirmed only while working). All deletions go through `DeletionPlan` and `DeletionActions`, which also stop agents, remove worktrees and delete Pi session files. |
| Preparation sheet | `Features/Preparation/TaskPreparationView.swift` | Prompt, Plan first, Current Working Tree or New Worktree. Preflight: runtime ready, folder exists, tree lock, git status. Dirty tree offers Use Worktree Instead or Run Anyway; a locked tree offers Start Anyway or Resume Anyway. |
| Terminal workspace | `Features/Terminal/TerminalWorkspaceView.swift`, `TerminalHostView.swift` | Header: badge (Working, Idle, Exited...), Stop Pi, Resume Pi, find, open-in-editor button, worktree menu. Resume runs automatically when a task with a session is opened; a locked tree shows a Resume Anyway banner. Changes panel on the right commits with a Pi-generated message. |
| Inspector | `Features/TaskDetail/TaskInspectorView.swift` | Title, prompt, status, run info, delete. Board only. |
| Settings | `Features/Settings/*` | General (Plan first, external apps, updates), Terminal, Shortcuts, Pi Runtime (install, rollback, extensions, Commit Messages model and extension paths). |

## How Pi is driven

- Interactive sessions: `PiLaunchCommand.newSession` or `.resume`, run under the bundled Node with the active Pi version from `PiRuntimeManager`.
- Agent activity: `TerminalProgressScanner` reads Pi's OSC 9;4 progress sequences from the PTY stream; `AgentActivityTracker` debounces them into "settled" (notification plus blue dot); `PTYSession.agentActivity` exposes working or idle live.
- Commit messages: `PiCommitMessageGenerator` runs Pi headless with `--no-tools --no-extensions --no-skills --no-context-files --no-session`. Settings can add `--model` and `--extension` paths, needed when the user's provider comes from an extension package.
- Session files live in `~/.pi/agent/sessions/<encoded cwd>/<timestamp>_<uuid>.jsonl`; `PiSessionLocator` finds them.

## Diagnostics

Loggers are in `Shared/Utilities/Diagnostics.swift`, subsystem `dev.piboard`, categories `ui`, `git`, `runtime`, `process`. Never log prompt text or credentials.

```sh
log show --predicate 'subsystem == "dev.piboard"' --info --last 30m
```

For a frozen window: `docs/development.md`, "Troubleshooting a UI freeze".

## Git

Agents do not commit, stage, stash or switch branches in this repo. Leave changes in the working tree and report what changed. Read-only git is fine.
