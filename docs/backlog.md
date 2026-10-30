# Backlog

Ordered work plan from the October 2026 review. Phases ship independently; items inside a phase are in execution order. Every phase ends with `make test`; items that touch `Features/` also run `make ui-test`.

Estimates assume one person who knows the codebase.

## Phase 0: Cleanup (done, 28 October 2026)

1. **MIT license.** Add `LICENSE` at the repository root and replace the "not yet chosen" line in README. Verification: file exists, README links to it. 15 min.
2. **Documentation catch-up.** `docs/user-guide.md` FAQ answers about session file deletion and shell PATH are stale, and the Open In list lacks VSCodium, Sublime Text and Kiro. `docs/architecture.md` still says Pi gets PiBoard's own process environment, that `startLoginShell` is unused, and its Diagnostics table lacks the `process` category. Verification: `rg "never copies|own process environment|unused" docs` returns nothing. 30 min.
3. **Inspector write debounce.** `TaskInspectorView` writes title and prompt to SQLite on every keystroke. Keep local `@State`, write to `BoardModel` after 300 ms of inactivity or on focus loss. Acceptance: typing 10 characters produces one UPDATE. Verification: `BoardModelTests`, `make ui-test`. 1 h.
4. **Start Fresh consistency.** `TerminalWorkspaceView.startFresh` applies Plan first from preferences without showing the prompt. Route it through the preparation sheet (`board.pendingPreparationTaskID`) instead. Acceptance: Start Fresh from the terminal always passes through the sheet. Verification: `make ui-test`. 1 h.

## Phase 1: Quick wins (done, 28 October 2026)

1. **Interrupt button.** Terminal header button next to Stop Pi that calls `PTYSession.interrupt()`, enabled only while running, with an `AccessibilityID`. Verification: `PTYSessionTests` sends SIGINT to a `sleep` child, `make ui-test`. 1 h.
2. **showTerminalProgress hint.** New read-only `PiSettingsProbe` service reads `~/.pi/agent/settings.json`; when `terminal.showTerminalProgress` is missing, the board shows a one-time banner with an "Open settings.json" button. Acceptance: nothing is written under `~/.pi/agent`. Verification: unit test with a fake settings file. 2 h.
3. **TerminalProgressScanner without copying.** `carry + bytes` allocates a new array per pty read. Check matches that cross the carry boundary separately instead of concatenating. Acceptance: existing `TerminalProgressScannerTests` pass unchanged. 1 h.
4. **Split AppEnvironment.init.** Extract a `TestingConfiguration` struct (UI testing root, isRunningTests, fake runtime entry) and split the 150-line init into two private functions. Acceptance: same behaviour, `AppEnvironmentRecoveryTests` pass. 2 h.

## Phase 2: Keyboard and repeated work (done, 28 October 2026)

1. **Shortcut actions.** Add `newTask`, `backToBoard`, `toggleInspector`, `toggleChanges`, `stopPi` to `ShortcutAction`; handle them in `AppEnvironment.perform`. The Settings list grows automatically. Verification: `KeyboardShortcutTests`, `make ui-test`. Half a day.
2. **Prompt templates.** `SettingKey.promptTemplates` as a JSON list, editable in Settings > General, with an "Insert template" menu in `NewTaskSheet` and the preparation sheet. Verification: `AppPreferencesTests` round trip. 3 h.
3. **Duplicate Task.** Card context menu and inspector action. Copies title and prompt to the end of Backlog; session and worktree fields stay empty. Verification: `BoardModelTests`. 1 h.

## Phase 3: Worktree finish flow (done, 28 October 2026)

1. **Push.** Push button in `TerminalChangesPanel` and `CommitSheet`; `GitTerminalRunner` already runs push in a pty, add `--set-upstream` when there is no upstream. Verification: `GitWriteServiceTests` against a bare remote. 3 h.
2. **Open Pull Request.** `GitRemoteURL.compareURL(base:head:)` for GitHub, GitLab and Bitbucket. After a push the button opens it in the browser. Verification: `GitRemoteURLTests`. 3 h.
3. **Worktree reminder on Done.** Moving a worktree task to Done shows a banner when the branch is not pushed and the worktree still exists, with a Remove Worktree shortcut. Information only; Done stays manual. 2 h.

## Phase 4: Task summary and session history (done, 28 October 2026)

Depends on the read-only access pattern from Phase 1.2.

1. **Session reader.** `PiSessionReader` service reads the session jsonl line by line: last assistant message, turn count, model, token totals. Domain type `SessionSummary`; I/O stays in Services. Verification: unit tests with fixture jsonl files. 1 day.
2. **Card and inspector display.** First line of the last message on the card, a Session section in the inspector with summary and turn list. Refreshed on `onAgentSettled`. Verification: `TaskPresentationTests`, `make ui-test`. Half a day.
3. **Cost.** When the jsonl carries usage, show tokens and an estimated cost in the inspector; hide the row otherwise. Half a day.

## Phase 5: Command palette (done, 28 October 2026)

Depends on Phase 2.1.

1. Recordable Cmd+K shortcut, search across projects and tasks, selecting opens the terminal or the board. Verification: `make ui-test`. 1 day.

## Phase 6: Agent abstraction (done, 28 October 2026)

Goal: PiBoard drives "an agent", with Pi as the first implementation, so a second tool is an adapter and not a rewrite. No behaviour change in this phase; it ships on its own.

Facts that shape the design (verified 28 October 2026 against opencode.ai/docs and the anomalyco/opencode `dev` branch):

| Concern | Pi | OpenCode |
| --- | --- | --- |
| Distribution | npm package, JS run by the bundled Node | npm `opencode-ai` with a platform binary in `opencode-darwin-arm64`; Node is not involved at run time |
| Session id | `--session-id <uuid>` assigned before spawn | Cannot be assigned on the CLI; `--session <id>` only continues. `POST /session` on the server returns the id |
| Session store | `~/.pi/agent/sessions/<cwd>/*.jsonl` | `~/.local/share/opencode/opencode.db` (SQLite) |
| Activity signal | OSC 9;4 progress in the pty | None in the pty. Server SSE `/event`: `session.execution.started`, `succeeded`, `interrupted`, `failed`, `permission.asked`, `form.created` |
| Desktop notification | PiBoard derives it from OSC 9;4 | TUI emits OSC 9 only with `attention.enabled` and only while blurred; not usable as a signal |

1. **Domain.** `AgentKind` enum (`pi`, `opencode`, later others) with `title` and `shortTitle`. Migration003 adds `tasks.agent TEXT NOT NULL DEFAULT 'pi'` and `projects.default_agent`. `BoardTask.piSessionId: UUID?` becomes `sessionID: String?` because OpenCode ids look like `ses_...`; the column keeps its name. Export format gains `agent` per task, optional, default `pi`. Verification: `MigrationRunnerTests`, `TaskRepositoryTests`, `ProjectExporterTests`. Half a day.
2. **AgentAdapter protocol.** One adapter per kind, resolved through `AppEnvironment`. Contract:
   - `sessionIdentity`: `.preassigned` (adapter generates the id before spawn) or `.created` (adapter obtains the id from the tool before spawn). Both keep the invariant that the id is written to SQLite before the process exists.
   - `prepareSession(title:cwd:) async throws -> String`
   - `launchCommand(mode:cwd:) -> AgentLaunchCommand` (today's `PiLaunchCommand`, executable plus argument array)
   - `sessionExists(id:cwd:) async -> Bool?` (nil means unknown, let the tool decide)
   - `deleteSession(id:cwd:) async throws`
   - `activitySource`: `.ptyProgress` (scan OSC 9;4), `.serverEvents(AgentEventStream)` or `.none`
   - `headless(prompt:systemPrompt:) -> AgentLaunchCommand?` for commit messages; nil when the tool cannot run tool-less
   - `requiredUserSettingHint`: the one-time banner text (Pi: `showTerminalProgress`)
   `PiAgent` is a move of `PiLaunchCommand`, `PiSessionLocator`, `TerminalProgressScanner` wiring and the session file delete from `DeletionActions`. The manager is `AgentProcessManager` and asks the task's adapter. Verification: `AgentProcessManagerTests` and `PiLaunchCommandTests` pass with the Pi adapter unchanged. 1 day.

   Shipped shape (28 October 2026): `makeSessionID` is synchronous and `sessionExists`, `sessionFile` and `readSessionSummary` are file reads; there is no `prepareSession`, `deleteSession` or `headless` yet. OpenCode needs an async `prepareSession` (the server returns the id), `deleteSession` through its API instead of a file, and a `.serverEvents` activity source. Phase 7 step 4 extends the protocol and `DeletionActions` accordingly. Also open: an unknown `agent` raw value in SQLite falls back to `pi` and is rewritten on the next update; before a second kind ships, unknown kinds must be preserved or flagged instead.
3. **AgentRuntime protocol.** `status`, `activeEntry`, `installLatest`, `versions`, `rollback`, `versionsInUse`. `PiRuntimeManager` is the first implementation. `PiInstallRunner` takes a package descriptor: npm name, entry path, whether the entry is a Node script or a native binary. Settings gets one runtime tab per agent kind. Verification: `PiRuntimeManagerTests`. Half a day.

   Shipped (28 October 2026): `AgentRuntime` protocol, `AgentPackage` descriptor with `.nodeScript` and `.binary` entries, `AgentRuntimePaths(package:)`. Install, rollback and the Settings tab stay on `PiRuntimeManager` until a second runtime exists.
4. **UI strings.** "Stop Pi", "Resume Pi", "Pi exited", badge labels and `AccessibilityID`s derive from `AgentKind.title`. Verification: `TaskPresentationTests`, `make ui-test`.

   Shipped (28 October 2026): `AgentStrings` builds every agent-naming phrase from `AgentKind.title`; `AccessibilityID`s stay kind-neutral (`terminalStop`, `terminalResume`), which is what the monkey test needs.
5. **Fakes.** `FakeAgentAdapter` and `FakeAgentRuntime` next to the tests that use them. All 475 tests green, `make ui-test` green. Shipped (28 October 2026).

## Phase 7: OpenCode (done, 28 October 2026)

Depends on Phase 6.

1. **Spike (done, 28 October 2026).** Findings and decisions in `docs/agents/opencode.md`. Go.
2. **Runtime detection (half a day).** `OpenCodeRuntime: AgentRuntime` resolves the user-installed binary (`~/.opencode/bin/opencode`, then the login-shell `PATH`), reports the version from `opencode --version`, no install or rollback. Settings > Pi Runtime becomes a per-kind runtime list; OpenCode shows "Detected x.y.z at <path>" or "Not installed" with the installer link.

   Shipped (28 October 2026). `AgentKind.opencode` was added here rather than in step 5 because `AgentPackage.kind` needs it; no picker shows it yet.
3. **Server client (half a day).** `OpenCodeService`: discovers the shared background server with `opencode service status`, starts it when needed, reads the password from `~/.config/opencode/service.json` read-only, exposes a small typed client (`createSession`, `session`, `deleteSession`, `activeSessions`, `events`). Re-reads the password on 401.

    Shipped (28 October 2026), not wired into `AppEnvironment` until step 4.
4. **Adapter (1 day).** `AgentAdapter` gains `prepareSession(title:cwd:) async throws -> String` (Pi returns its UUID without I/O; OpenCode does `POST /api/session`), `deleteSession(id:cwd:) async throws` (Pi removes the file, OpenCode calls DELETE) and `activitySource = .serverEvents`. `OpenCodeAgent` launches `opencode --session <id> <cwd>`, checks existence with GET, reads the summary from GET plus `/message`. `DeletionActions` and `SessionSummaryStore` use the new calls. The id is still written to SQLite before the process exists.

   Shipped (28 October 2026). Deviations: `prepareSession(id:title:cwd:)` takes the id PiBoard made instead of returning one, because the server accepts a client id; `sessionFile` became `plannedSessionRemoval` plus `deleteSession`; the existence check moved from `AgentProcessManager.launch` to `AgentSessionResumer` so it can be async; `AgentProcessManager.setExternalActivity` is the entry point for step 5.
5. **Activity and UI (1 day).** `OpenCodeEventStream` keeps one SSE connection per run, filtered to execution, permission and form events, demultiplexed by `sessionID` into `AgentActivityTracker`; reconnect with backoff and resync from `/api/session/active`. New `needsInput` activity with its own dot colour and notification. Agent picker in the preparation sheet with the project default preselected; `AgentKind.opencode` is added here, not before. Fake `opencode` script for `make ui-test` (it must answer `--version`, `service status` and serve a tiny HTTP stub, or the UI test keeps OpenCode out of the picker). Picker and fake binary shipped (28 October 2026); AppEnvironment wiring of the fake is step 5c. Activity shipped (28 October 2026); picker and fake binary in 5b.
6. **Fake fidelity (done, 28 October 2026).** Turn-driven fake SSE, an active-session set, authenticated test controls, permission handling and reconnect gates, verified by `MonkeyTests.testOpenCodeActivityAndReconnectResync` (Working, Needs input, Working, Idle, and resync from the active set after a lost start and a lost completion). The UI-test branch of `AppEnvironment.makeOpenCode` isolates the runtime's home so the real install cannot shadow the fake. `make test` and `make ui-test` green. Teardown after a failing assertion was verified with a temporary `XCTFail`: no fake process or temp directory was left behind. The fake answers `/api/session/active` immediately like the real server, and the stream resyncs after `server.connected`. Details: `docs/testing.md`, Fake OpenCode fidelity.

## Phase 8: More agents (Claude Code done, Codex and Gemini parked)

Claude Code shipped on 29 October 2026 (steps 1 to 5 below); the spike findings and the open items (unverified interactive resume without a file, Esc on a pending permission prompt, untested spinner frames, untested claude rm) are in `docs/agents/claude-code.md`. Step 6 is next. Codex CLI and Gemini CLI stay parked until picked up; each starts with a one-day spike as described below.

Each tool is one adapter plus one runtime, after a one-day spike that fills this matrix from the tool's current documentation. Nothing below is verified yet except where stated; verify before coding.

| Capability to check | Claude Code | Codex CLI | Gemini CLI |
| --- | --- | --- | --- |
| Package | Native binary from the official installer, user-installed at `~/.local/bin/claude` (verified 2.1.294) | `@openai/codex`, native binary per platform | `@google/gemini-cli`, Node script |
| Session id before spawn | `--session-id <uuid>` plus `--name` (verified) | Not on the CLI; `codex resume <id>` continues, ids are UUIDs (verified 28 October 2026) | Not on the CLI; `--list-sessions` and `/resume` exist (verified) |
| Resume | `--resume <id>`, works from any cwd (verified) | `codex resume <id>` | `--resume`, verify flag shape |
| Activity signal | Terminal title glyph for working and idle plus http hooks via `--settings` for permission prompts; no OSC 9;4 (verified) | `codex app-server` exposes an event protocol; `exec --json` for one-shot | Unknown; check hooks or checkpoint events |
| Headless one-shot without tools | `-p --tools "" --no-session-persistence`, prompt on stdin, never `--bare` (verified) | `codex exec` with `--sandbox read-only` | `-p`, verify tool denial |
| Session delete | None on the CLI for foreground sessions; delete the JSONL file (needs sign-off) | `codex delete <id>` (verified) | Verify |

OpenCode v2 showed that a tool's CLI surface can change completely between majors; every adapter pins the version range it was verified against in its `docs/agents/<kind>.md`.

Rules for every new agent:

- Session id is in SQLite before the process exists. A tool that cannot preassign gets a server or one-shot path that returns the id first, like OpenCode. Discovering the id after spawn by listing sessions is the last resort and must be recorded as an invariant deviation in `docs/architecture.md`.
- A tool with no activity signal still works: dots and notifications stay silent, the badge shows Running instead of Working or Idle, and the preparation sheet says so once.
- The tool's own data directory is never written by PiBoard. Deleting a session goes through the tool's CLI or API.
- Runtime installs stay under `~/Library/Application Support/PiBoard/runtime/<kind>/`, versioned, with the same keep-three retention. A tool that cannot be installed this way is "user installed", resolved through the login shell `PATH` and shown as such in Settings.
- Every adapter ships with a fake binary for `make ui-test` and a `Fake<Kind>Adapter` for unit tests.

Claude Code steps (about 3.5 days):

1. **Kind, runtime, Settings (half a day).** `AgentKind.claudeCode`, a `ClaudeCodeRuntime` with `.userInstalled(executableName: "claude", knownPaths: ["~/.local/bin/claude"])`, version from `--version`, login state from `auth status`, a Settings tab like OpenCode's with no install button. Enabled through the Agents toggles. Done, 29 October 2026.
2. **Adapter and session reader (1 day).** `ClaudeCodeAgent`: `--session-id` plus `--name` for new sessions, `--resume` for resumes, `--settings` carrying the hook URL, prompt last. `ClaudeSessionLocator` globs `~/.claude/projects/*/<id>.jsonl`; `ClaudeSessionReader` fills `SessionSummary`; `deleteSession` removes the file after sign-off; `AgentStrings` coverage. Done, 29 October 2026.
3. **Activity (1 day).** `TerminalTitleScanner` for the OSC 0 glyph, `ClaudeCodeHookServer` on a loopback port, a new `AgentActivitySource` case, wiring in `AgentProcessManager`. Unit tests from a recorded title stream and the hook payload shapes in `docs/agents/claude-code.md`. Done, 29 October 2026.
4. **Fake binary and tests (half a day).** `FakeClaudeCode` for `make ui-test`: answers `--version` and `auth status`, emits title glyphs, posts hooks to the URL found in `--settings`, writes a JSONL under an isolated home. `FakeClaudeCodeAdapter` for unit tests. `make test` and `make ui-test` green. Done, 29 October 2026.
5. **Docs (quarter day).** `docs/architecture.md`, `docs/user-guide.md` (login, trust dialog per worktree), `docs/testing.md`, `AGENTS.md`. Done, 29 October 2026.
6. **Optional.** Claude Code as a Commit Messages generator through the headless path. Done, 30 October 2026: Settings > General picks the agent; OpenCode and Claude Code generators added.

## Phase 9: Session migration between agents (2 days) (done, 30 October 2026)

Verified 29 October 2026 against the Pi session format docs and OpenCode v2.2.0.

Goal: move a task's conversation from one agent to another (Pi to OpenCode or back) without losing what was discussed. Model context, prompt caches and tool records do not transfer between tools, so the design hands over a summary instead of copying a session.

Facts that shape it:

| Concern | Pi | OpenCode |
| --- | --- | --- |
| Export | Session JSONL is already an open format (`user`, `assistant`, `toolResult`, `compaction`, `model_change`) | `GET /api/experimental/session/{id}/export` or `opencode session export`: `{info, messages: [user, assistant, idle, ...]}` |
| Import | SDK only: `SessionManager.inMemory(cwd, options, entries)` and `importFromJsonl`; no CLI | `POST /api/experimental/session/import {info, messages, location}` or `opencode session import <file> --directory <cwd>`; experimental, may change inside v2 |
| Tool records | `toolCall` plus `toolResult`, Pi tool names | `Session.Message.Assistant.Tool`, OpenCode tool names; not convertible one to one |

Design: summarize and hand over.

1. **Handoff document (half a day).** `SessionHandoff` domain type and a `SessionHandoffRenderer` producing Markdown from a full read of the source: task prompt, user messages, assistant text replies (tool output excluded), the last N turns, changed files (Pi: `compaction.details.modifiedFiles`; OpenCode: `snapshot.files` on assistant messages), open points. Needs full-transcript readers: extend `PiSessionReader` with `transcript(file:)` and `OpenCodeClient` with `messages(sessionID:)` (already fetched for `lastAssistantText`). Pure domain, unit tested with fixtures from both formats. Claude Code is covered too (the text above was written for Pi and OpenCode). Changed files come from Pi `edit`/`write` tool calls, Claude `Edit`/`Write`/`MultiEdit`/`NotebookEdit` tool uses and OpenCode `snapshot.files`. Done, 30 October 2026.
2. **Model and schema (half a day).** Migration004 adds `tasks.previous_agent TEXT NULL` and `tasks.previous_session_id TEXT NULL`. `BoardModel.migrateTask(_:to:newSessionID:)` sets `agent` and `sessionID`, moves the old pair into the previous columns. The source session is never deleted or modified; deletion of the task later removes both through the adapters. Inspector shows "Migrated from <agent> session <id prefix>". Export format ignores the previous columns. Done, 30 October 2026.
3. **Flow and UI (1 day).** Card context menu and inspector action "Migrate to <agent>..." for every enabled agent other than the current one; disabled while the task's process is active. A sheet shows the rendered handoff (editable), toggles "Include assistant replies" and "Include changed files", Plan first, and the run context (current tree or the task's existing worktree). Confirm runs the normal launch path: new adapter `makeSessionID`, `prepareSession`, SQLite write, spawn with the handoff as the initial prompt. The invariants hold: the id is in SQLite before the process exists; one current-tree session per project; a worktree task keeps its worktree. Monkey test: no new action (the sheet needs a session); a deterministic UI test is optional. Unit tests cover the renderer, the model method and the repository round trip. Done, 30 October 2026.
4. **Out of scope for the first version.** Raw import into the target (`experimental/session/import` for OpenCode, SDK-only for Pi, and writing under `~/.pi/agent` is against the rules). Revisit if users ask for verbatim history; it would still drop tool records.

## Parked

- CI workflow running `make test` on push and pull requests.
- Pi extension and skill manager (spec section 38). Owner: Semih, separate investigation.
- Auto-starting the next Backlog task when an agent settles. Rejected: conflicts with "In Progress never spawns Pi".
