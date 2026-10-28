# Backlog

Ordered work plan from the October 2026 review. Phases ship independently; items inside a phase are in execution order. Every phase ends with `make test`; items that touch `Features/` also run `make ui-test`.

Estimates assume one person who knows the codebase.

## Phase 0: Cleanup (done, 28 October 2026)

1. **MIT license.** Add `LICENSE` at the repository root and replace the "not yet chosen" line in README. Verification: file exists, README links to it. 15 min.
2. **Documentation catch-up.** `docs/user-guide.md` FAQ answers about session file deletion and shell PATH are stale, and the Open In list lacks VSCodium, Sublime Text and Kiro. `docs/architecture.md` still says Pi gets PiBoard's own process environment, that `startLoginShell` is unused, and its Diagnostics table lacks the `process` category. Verification: `rg "never copies|own process environment|unused" docs` returns nothing. 30 min.
3. **Inspector write debounce.** `TaskInspectorView` writes title and prompt to SQLite on every keystroke. Keep local `@State`, write to `BoardModel` after 300 ms of inactivity or on focus loss. Acceptance: typing 10 characters produces one UPDATE. Verification: `BoardModelTests`, `make ui-test`. 1 h.
4. **Start Fresh consistency.** `TerminalWorkspaceView.startFresh` applies Plan first from preferences without showing the prompt. Route it through the preparation sheet (`board.pendingPreparationTaskID`) instead. Acceptance: Start Fresh from the terminal always passes through the sheet. Verification: `make ui-test`. 1 h.

## Phase 1: Quick wins (1 day)

1. **Interrupt button.** Terminal header button next to Stop Pi that calls `PTYSession.interrupt()`, enabled only while running, with an `AccessibilityID`. Verification: `PTYSessionTests` sends SIGINT to a `sleep` child, `make ui-test`. 1 h.
2. **showTerminalProgress hint.** New read-only `PiSettingsProbe` service reads `~/.pi/agent/settings.json`; when `terminal.showTerminalProgress` is missing, the board shows a one-time banner with an "Open settings.json" button. Acceptance: nothing is written under `~/.pi/agent`. Verification: unit test with a fake settings file. 2 h.
3. **TerminalProgressScanner without copying.** `carry + bytes` allocates a new array per pty read. Check matches that cross the carry boundary separately instead of concatenating. Acceptance: existing `TerminalProgressScannerTests` pass unchanged. 1 h.
4. **Split AppEnvironment.init.** Extract a `TestingConfiguration` struct (UI testing root, isRunningTests, fake runtime entry) and split the 150-line init into two private functions. Acceptance: same behaviour, `AppEnvironmentRecoveryTests` pass. 2 h.

## Phase 2: Keyboard and repeated work (1 day)

1. **Shortcut actions.** Add `newTask`, `backToBoard`, `toggleInspector`, `toggleChanges`, `stopPi` to `ShortcutAction`; handle them in `AppEnvironment.perform`. The Settings list grows automatically. Verification: `KeyboardShortcutTests`, `make ui-test`. Half a day.
2. **Prompt templates.** `SettingKey.promptTemplates` as a JSON list, editable in Settings > General, with an "Insert template" menu in `NewTaskSheet` and the preparation sheet. Verification: `AppPreferencesTests` round trip. 3 h.
3. **Duplicate Task.** Card context menu and inspector action. Copies title and prompt to the end of Backlog; session and worktree fields stay empty. Verification: `BoardModelTests`. 1 h.

## Phase 3: Worktree finish flow (1 day)

1. **Push.** Push button in `TerminalChangesPanel` and `CommitSheet`; `GitTerminalRunner` already runs push in a pty, add `--set-upstream` when there is no upstream. Verification: `GitWriteServiceTests` against a bare remote. 3 h.
2. **Open Pull Request.** `GitRemoteURL.compareURL(base:head:)` for GitHub, GitLab and Bitbucket. After a push the button opens it in the browser. Verification: `GitRemoteURLTests`. 3 h.
3. **Worktree reminder on Done.** Moving a worktree task to Done shows a banner when the branch is not pushed and the worktree still exists, with a Remove Worktree shortcut. Information only; Done stays manual. 2 h.

## Phase 4: Task summary and session history (2 days)

Depends on the read-only access pattern from Phase 1.2.

1. **Session reader.** `PiSessionReader` service reads the session jsonl line by line: last assistant message, turn count, model, token totals. Domain type `SessionSummary`; I/O stays in Services. Verification: unit tests with fixture jsonl files. 1 day.
2. **Card and inspector display.** First line of the last message on the card, a Session section in the inspector with summary and turn list. Refreshed on `onAgentSettled`. Verification: `TaskPresentationTests`, `make ui-test`. Half a day.
3. **Cost.** When the jsonl carries usage, show tokens and an estimated cost in the inspector; hide the row otherwise. Half a day.

## Phase 5: Command palette (1 day)

Depends on Phase 2.1.

1. Recordable Cmd+K shortcut, search across projects and tasks, selecting opens the terminal or the board. Verification: `make ui-test`. 1 day.

## Phase 6: Agent abstraction (2 days)

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
   `PiAgent` is a move of `PiLaunchCommand`, `PiSessionLocator`, `TerminalProgressScanner` wiring and the session file delete from `DeletionActions`. `PiProcessManager` becomes `AgentProcessManager` and asks the task's adapter. Verification: `PiProcessManagerTests` and `PiLaunchCommandTests` pass with the Pi adapter unchanged. 1 day.
3. **AgentRuntime protocol.** `status`, `activeEntry`, `installLatest`, `versions`, `rollback`, `versionsInUse`. `PiRuntimeManager` is the first implementation. `PiInstallRunner` takes a package descriptor: npm name, entry path, whether the entry is a Node script or a native binary. Settings gets one runtime tab per agent kind. Verification: `PiRuntimeManagerTests`. Half a day.
4. **UI strings.** "Stop Pi", "Resume Pi", "Pi exited", badge labels and `AccessibilityID`s derive from `AgentKind.title`. Verification: `TaskPresentationTests`, `make ui-test`.
5. **Fakes.** `FakeAgentAdapter` and `FakeAgentRuntime` next to the tests that use them. All 475 tests green, `make ui-test` green.

## Phase 7: OpenCode (4 days)

Depends on Phase 6.

1. **Spike (1 day, go or no-go).** With OpenCode installed by hand: run `opencode serve --port <free port>`, create a session with `POST /session` carrying `title` and `location.directory`, open the TUI with `opencode attach http://127.0.0.1:<port> --dir <cwd> --session <id>` inside a pty, confirm the execution events arrive on `GET /event`, and confirm permission prompts and questions render in the attached TUI. Write the findings to `docs/agents/opencode.md`. If attach cannot carry a local session, stop here and park the phase.
2. **Runtime.** `OpenCodeRuntime` installs `opencode-ai` with the bundled npm into `runtime/opencode/versions/<v>`, entry is the binary under `node_modules/opencode-darwin-arm64/bin/opencode`, verification is `opencode --version`. Pin the version like Pi. 1 day.
3. **Server process.** `OpenCodeServer` picks a free port, runs `opencode serve` as a child managed like `ShellSessions`, registers it in `LiveProcessRegistry`, stops it on quit. One server per PiBoard run, shared by every project. Half a day.
4. **Adapter.** `prepareSession` is `POST /session`; `sessionExists` is `GET /session/:id`; `deleteSession` is `DELETE /session/:id`. OpenCode's database is never touched directly. `activitySource` reads the SSE stream and feeds `AgentActivityTracker`: `started` is working, `succeeded`, `interrupted` and `failed` are idle, `permission.asked` and `form.created` raise a new `needsInput` activity. 1 day.
5. **UI.** Agent picker in the preparation sheet with the project default preselected; `needsInput` gets its own dot colour and a notification; fake `opencode` binary for `make ui-test`. Commit messages run `opencode run --model <m>` with every tool denied through `OPENCODE_PERMISSION`. Half a day.

## Phase 8: More agents

Each tool is one adapter plus one runtime, after a one-day spike that fills this matrix from the tool's current documentation. Nothing below is verified yet except where stated; verify before coding.

| Capability to check | Claude Code | Codex CLI | Gemini CLI |
| --- | --- | --- | --- |
| Package | `@anthropic-ai/claude-code`, Node script | `@openai/codex`, native binary per platform | `@google/gemini-cli`, Node script |
| Session id before spawn | Reported to accept `--session-id <uuid>`; verify | Not on the CLI; `codex resume <id>` continues, ids are UUIDs (verified 28 October 2026) | Not on the CLI; `--list-sessions` and `/resume` exist (verified) |
| Resume | `--resume <id>` | `codex resume <id>` | `--resume`, verify flag shape |
| Activity signal | Unknown; check for OSC progress or a hooks or `--output-format` event path | `codex app-server` exposes an event protocol; `exec --json` for one-shot | Unknown; check hooks or checkpoint events |
| Headless one-shot without tools | `-p` with `--tools ""` | `codex exec` with `--sandbox read-only` | `-p`, verify tool denial |
| Session delete | Verify | `codex delete <id>` (verified) | Verify |

Rules for every new agent:

- Session id is in SQLite before the process exists. A tool that cannot preassign gets a server or one-shot path that returns the id first, like OpenCode. Discovering the id after spawn by listing sessions is the last resort and must be recorded as an invariant deviation in `docs/architecture.md`.
- A tool with no activity signal still works: dots and notifications stay silent, the badge shows Running instead of Working or Idle, and the preparation sheet says so once.
- The tool's own data directory is never written by PiBoard. Deleting a session goes through the tool's CLI or API.
- Runtime installs stay under `~/Library/Application Support/PiBoard/runtime/<kind>/`, versioned, with the same keep-three retention. A tool that cannot be installed this way is "user installed", resolved through the login shell `PATH` and shown as such in Settings.
- Every adapter ships with a fake binary for `make ui-test` and a `Fake<Kind>Adapter` for unit tests.

## Parked

- CI workflow running `make test` on push and pull requests.
- Pi extension and skill manager (spec section 38). Owner: Semih, separate investigation.
- Auto-starting the next Backlog task when an agent settles. Rejected: conflicts with "In Progress never spawns Pi".
