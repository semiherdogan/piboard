# PiBoard: notes for coding agents

PiBoard is a native macOS app (SwiftUI, Swift 6, macOS 26) that runs the Pi coding agent in a kanban board: one Pi session per task, each in a real PTY terminal, optionally in its own Git worktree. Node and Pi are bundled or installed by the app, never taken from `PATH`.

Read this file, then the doc that matches your task. Do not read the whole `docs/` folder up front.

## Build and test

Everything goes through the Makefile. Do not call `xcodebuild` or `swift test` yourself.

```sh
make generate   # fetch Node into Runtime/node if missing, then xcodegen
make build      # Debug build into build/DerivedData
make test       # PiBoardTests (Swift Testing), builds first
make ui-test    # PiBoardUITests: randomized monkey test against a fake Pi, about 7 minutes; or ONLY=MonkeyTests/<test> for one test
make run        # build, quit a running PiBoard, open the Debug app
make screenshots # regenerate docs/images (README) from demo data through a UI test
```

- `PiBoard.xcodeproj` is generated from `project.yml` and gitignored. New Swift files are picked up automatically; never edit the project file.
- `make test` is the verification for any code change. Run it before reporting done. The suite takes a few minutes; do not skip it.
- `make ui-test` is required in addition whenever a change touches `Features/`, `MainWindow`, `TerminalHostView`, `PTYSession` or anything that presents, swaps or removes views. It launches the app with `--ui-testing` (in-memory database, fake Pi in a real pty, no network) and clicks around for 200 steps, failing on dead clicks, stacked terminal views or a stray sheet. A failure prints `step=`, `action=` and `seed=`; replay it with `TEST_RUNNER_PIBOARD_MONKEY_SEED=<seed> make ui-test`. Details in `docs/testing.md`.
- New interactive controls get an `AccessibilityID` so the monkey test can reach them.
- Strict concurrency is on (`SWIFT_STRICT_CONCURRENCY: complete`). Zero warnings is the bar.
- The build needs Xcode 27, xcodegen and the Metal toolchain. If `make generate` fails on a missing toolchain, say so instead of working around it.

## Where things live

| Path | What |
| --- | --- |
| `PiBoard/App` | `AppEnvironment` (composition root, every service is injected here), `BoardModel` in `AppModel.swift`, `MainWindow`, `AppPreferences` |
| `PiBoard/Domain` | Value types and pure logic, no I/O: `BoardTask`, `TaskStatus`, `TaskRuntimeState`, ordering, export format; `Domain/Conversation` holds the chat model and `ConversationReducer` |
| `PiBoard/Persistence` | SQLite wrapper, repositories, numbered migrations, `SettingKey` |
| `PiBoard/Services` | `AgentProcessManager` (asks the task's `AgentAdapter`, `PiAgent` today, for launch and session checks), `PTYSession`, `PiLaunchCommand`, `PiRuntimeManager`, Git, worktrees, notifications, `PiSessionLocator`; `Services/Conversation` holds the chat driver (`PiRPCDriver`) and `ConversationSession` |
| `PiBoard/Features` | SwiftUI screens: Board, Preparation, Projects (sidebar), Settings, TaskDetail (task details sheet), Terminal |
| `PiBoardTests` | One file per subject. Fakes live next to the tests that use them (`FakeGitService`, `FakeWorktreeService`, ...) |
| `scripts` | `fetch-node.sh` (bundled Node, trimmed), `release.sh` (Sparkle appcast and deltas) |
| `docs` | `architecture.md`, `development.md`, `user-guide.md`, `testing.md`, `RELEASING.md` (starts with the beta release runbook) |

## Conventions that are checked in review

Full list in `docs/development.md`. The ones agents most often get wrong:

- No magic literals. A label, flag, key or threshold gets a named constant on the owning type or a `private let` at the top of the file. Compare enums by case, never by raw value.
- Comments say why, in one line. No banners, no narration, no TODOs.
- Build processes as executable plus argument array. Never a shell string.
- UI-facing models are `@MainActor @Observable`. Blocking work goes off the main actor. Callbacks from SwiftTerm or Sparkle come through bridge objects.
- Layering: Domain has no I/O, Persistence knows nothing about UI, views reach services only through `AppEnvironment`.
- Services with a protocol get a fake in tests. Prefer extending an existing fake over a new one.
- Workflow state (`BoardTask.status`, persisted) and runtime state (`AgentProcessManager.runtimeStates`, memory only) are separate. Never derive one from the other.
- No `.keyboardShortcut` on views. Shortcuts are recorded by the user in Settings and dispatched by `ShortcutDispatcher`.
- Left Pi-flavoured on purpose under the Pi-off rule: the quit dialog, the orphaned "Pi processes" banner, "Stop the running Pi session" and "Pi needs your input". Do not generalize them without being asked.
- `~/.pi/agent` belongs to the user. The only thing PiBoard writes there is deleting a session file when its task is deleted. The same holds for `~/.claude`: PiBoard only deletes `<session id>.jsonl` when its task is deleted.

## Invariants (do not break)

- Done is never automatic. Only a user move writes `status = done`.
- Moving to In Progress opens the preparation sheet; it never spawns Pi.
- The session id is written to SQLite before the process is spawned, and only an explicit Start Fresh replaces it.
- A migration never deletes or edits the source session; the task keeps `previous_agent` and `previous_session_id`, and only task deletion removes both.
- One current-tree Pi session per project by default (`CurrentTreeLock`). The user can override with Start Anyway or Resume Anyway; such a session never takes or releases the lock.
- A task holds at most one live session, terminal or chat; launching the other interface while one is active throws `otherInterfaceActive`.
- Leaving the terminal never stops Pi. The PTY belongs to `PTYSession`, which belongs to `AgentProcessManager`, not to a view.
- A worktree session is never resumed in the project root.

## Screens and flows

Each screen has one source file; start there.

| Screen | File | Notes |
| --- | --- | --- |
| Sidebar | `Features/Projects/ProjectSidebarView.swift` | One flat list (`SidebarOutline`): one-line project rows, each followed by its session rows (In Progress tasks with a session, rules in `SidebarSessions`, folded state in `BoardModel.collapsedProjectIDs`). A session row opens its terminal; a project click shows the board, a second click folds. Projects reorder by drag or Move Up/Down (`projects.position`). Status dots at the end of the project row, counting only tasks without a row: green pulsing = agent working, grey = Pi alive and idle, blue = finished while you were away (`TaskAttention`). |
| Board | `Features/Board/BoardView.swift`, `BoardColumnView.swift`, `TaskCardView.swift` | Three columns, or the session list when the global `AppPreferences.projectLayout` is List (segmented `projectLayoutPicker` in the toolbar and Settings > General > Project view write the same preference; `BoardView` swaps only the columns area). Done header has Clear (confirmed, deletes every Done task). Cards show the same dots plus a Working/Idle badge; an idle Pi gets a small stop button, the context menu has Stop Pi (confirmed only while working) and "Migrate to <agent>" for tasks with a session, running or not (the sheet stops a running source at confirm, with a dialog only while it is working). All deletions go through `DeletionPlan` and `DeletionActions`, which also stop agents, remove worktrees and delete Pi session files. |
| Session list | `Features/Board/ProjectSessionListView.swift` | List layout: every task of the project in one flat list (`SessionListOrdering`: live first, then `updatedAt`), nothing archived. Row: agent symbol, title, the sidebar's status dot, last prompt or task prompt first line, relative time, interface glyph, worktree branch, status caption. Click only selects (accent fill, stronger than hover); double-click opens the workspace (task with a session) or, for a task without one, `BoardModel.prepareSession` (Backlog moves to the end of In Progress and opens the preparation sheet, In Progress opens it, Done opens task details). Task details through the toolbar Task Details button or Edit Task in the context menu. Context menu has the card's items (Open, Stop, Edit, Duplicate, Migrate, preferred Open In apps, Commit, Remove Worktree, Delete) plus a Status submenu through `requestMove` that appends to the target column; the card's Move to items are replaced by it. In this layout the toolbar button reads New Session and `NewTaskSheet(startsImmediately:)` adds the task, moves it to In Progress and opens preparation after the sheet dismisses (`BoardModel.taskToPrepareAfterNewTask`). |
| Preparation sheet | `Features/Preparation/TaskPreparationView.swift` | Prompt, Plan first, Current Working Tree or New Worktree. Preflight: runtime ready, folder exists, tree lock, git status. Dirty tree offers Use Worktree Instead or Run Anyway; a locked tree offers Start Anyway or Resume Anyway. For an agent that supports chat, an "Open in" Terminal | Chat picker and, for Pi, a per-project trust toggle ("Load this project's .pi extensions and skills"; chat cannot ask for trust). |
| Chat workspace | `Features/Conversation/ConversationView.swift` | The native chat for a task whose interface is Chat, shown by the workspace instead of the terminal; the header Terminal \| Chat picker switches through `SessionInterfaceSwitcher` (stops the live process, resumes the same session in the other view). Timeline of user messages, assistant Markdown (paragraphs, headings, bullet and numbered lists, fenced code; `MarkdownBlocks`) and each run of thinking and tool items folded under a "Worked for" header (`ConversationTimelineLayout`, `ConversationTurnView`; a live run has no toggle and folds when it ends). Pending agent dialogs show as `ConversationDialogCard` above the composer. Turn headers carry the agent symbol. `ConversationComposer` (agent chip, which reads "Pi · architect" when an extension such as pi-open-agents set an active agent, read from `get_entries` at start and resume and kept current by live `entry_appended` events, a quiet caption with the extensions' status texts, and status dot): Return sends, Shift+Return adds a line, Escape aborts, a send during a run is queued (shown as "Queued" chips), attachments by picker or drop (images up to 5 MB travel as image blocks, other files as paths), model and thinking pickers; typing `/` opens a command list from `get_commands` (`SlashCommands`; arrows move, Return or Tab insert, Escape closes; an unlisted `/word` warns first with Send Anyway); paste adds clipboard images or files (`ChatAttachment.pasteContent`); top-right Thinking and Tool details toggles write the Settings preferences. Views that must not redraw per streamed delta read `ConversationSession.liveStatus`, not `state`. A failed send gives the message back. |
| Migration sheet | `Features/Preparation/SessionMigrationView.swift` | "Migrate to <agent>": editable handoff summary, Include assistant replies and changed files, Plan first, run context (current tree or the task's worktree), readiness for the target agent, including the same agent as a fresh-session handoff. A running source shows a caption and a "Stop and Migrate" button; confirming stops it through `AgentProcessManager.stopAndWait` (opening the sheet stops nothing) and re-reads the transcript unless the summary was edited. Rules in `SessionMigration`; launch rolls back through `BoardModel.undoMigration`. |
| Terminal workspace | `Features/Terminal/TerminalWorkspaceView.swift`, `TerminalHostView.swift` | `SessionInfoStrip` below the header (your last prompt, clickable to find it in the terminal; model, turns, tokens, cost). Subtitle ends with `PathActionButtons` (copy path, Finder, remote web page; shared with the board header). Header: badge (Working, Idle, Exited...), Interrupt, Stop Pi, Resume Pi, find, Copy Last Reply, Open In split button (preferred editor, menu with every installed app), worktree menu. Resume runs automatically when a task with a session is opened; a locked tree shows a Resume Anyway banner. Changes panel on the right commits with a Pi-generated message. |
| Task details | `Features/TaskDetail/TaskDetailView.swift` | Sheet: title, prompt, status, run info, delete. Board only. Actions that open another sheet or dialog close it first through `BoardModel.closeTaskDetail(then:)`. |
| Settings | `Features/Settings/*` | General (Plan first, Project view, external apps, commit message agent, updates), Terminal, Shortcuts, Pi Runtime (install, rollback, extensions, Commit Messages model and extension paths used by Pi; Pi can be switched off, at least one agent stays enabled, `AppPreferences.defaultAgent` is the first enabled one, and the board's Pi banners follow it through `RuntimeBannerRule`), Claude Code (detected binary, login state, commit message model). OpenCode and Claude Code rows offer Install (vendor script, confirmed) and Update (the tool's own command) through `RuntimeSetupRunner`. |

## How Pi is driven

- Interactive sessions: `PiAgent` (one of three `AgentAdapter`s) builds `PiLaunchCommand.newSession` or `.resume`, run under the bundled Node with the active Pi version from `PiRuntimeManager`.
- Chat is offered only when `AgentAdapter.supportsConversation` is true; it gates the preparation picker and the workspace header picker. Other agents stay terminal only.
- Chat sessions: `PiAgent.conversationLaunchCommand` runs Pi with `--mode rpc`; `PiRPCDriver` speaks JSONL on its stdio, `ConversationSession` reduces events into `ConversationState`, and `AgentProcessManager.startConversation` or `resumeConversation` owns it; see docs/agents/pi-rpc.md.
- Agent activity: `TerminalProgressScanner` reads Pi's OSC 9;4 progress sequences from the PTY stream; `AgentActivityTracker` debounces them into "settled" (notification plus blue dot); `PTYSession.agentActivity` exposes working or idle live. OpenCode: `OpenCodeEventStream` reads the server's SSE events and feeds the same tracker; `needsInput` (orange dot) means a permission or question is waiting in the terminal. Claude Code: terminal title glyph plus hooks (see the Claude Code bullet).
- Commit messages: the generator is chosen in Settings > General (`CommitMessageGeneratorRouter`). Pi: `PiCommitMessageGenerator` runs Pi headless with `--no-tools --no-extensions --no-skills --no-context-files --no-session`; Settings can add `--model` and `--extension` paths, needed when the user's provider comes from an extension package. Claude Code: `claude -p --tools "" --no-session-persistence --output-format text --max-turns 1 --system-prompt ... -- <prompt>` with an optional `--model`. OpenCode: a throwaway session on the background service, `POST /api/session/{id}/generate`, then the session is deleted.
- Session files live in `~/.pi/agent/sessions/<encoded cwd>/<timestamp>_<uuid>.jsonl`; `PiSessionLocator` finds them.
- OpenCode: `OpenCodeAgent` launches the user-installed binary with `--session <id> [--prompt <text>] <cwd>` against the shared background service (`OpenCodeService`, `OpenCodeClient`); see docs/agents/opencode.md.
- Claude Code: `ClaudeCodeAgent` launches the user-installed `claude` with `--session-id <uuid> --name <title> [--settings <hooks json>] -- <prompt>` or `--resume <id>`; `TerminalTitleScanner` reads working/idle off the terminal title, `ClaudeCodeHooks` plus `LoopbackHookServer` receive `PermissionRequest` for needs-input; sessions under `~/.claude/projects` via `ClaudeSessionLocator`, summaries via `ClaudeSessionReader`; see docs/agents/claude-code.md.

## Diagnostics

Loggers are in `Shared/Utilities/Diagnostics.swift`, subsystem `dev.piboard`, categories `ui`, `git`, `runtime`, `process`. The `ui` category logs at notice level so it is persisted and readable after a quit; the others are info level. Never log prompt text or credentials.

```sh
log show --predicate 'subsystem == "dev.piboard"' --info --last 30m
log show --predicate 'subsystem == "dev.piboard" AND category == "ui"' --last 1d
```

For a frozen window: `docs/development.md`, "Troubleshooting a UI freeze".

## Git

Agents do not commit, stage, stash or switch branches in this repo. Leave changes in the working tree and report what changed. Read-only git is fine.
