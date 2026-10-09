# Testing

## Running tests

```sh
make test
```

This regenerates the Xcode project and runs the `PiBoard` scheme's test action (`PiBoardTests`, hosted in the app) on `platform=macOS` with derived data in `build/DerivedData`. Tests use Swift Testing (`import Testing`, `@Test`, `#expect`); the only XCTest case is the monkey UI test below, which is not part of this target.

Hosted tests never reach the network or Sparkle: `AppEnvironment` detects `XCTestConfigurationFilePath` and skips the npm registry check and the updater. Databases in tests are `:memory:`, except the corruption recovery tests, which use files in unique temp directories like every other on-disk fixture.

To run one suite from Xcode, open `PiBoard.xcodeproj` after `make generate` and use the test navigator.

## Monkey UI test

```sh
make ui-test
```

`PiBoardUITests/MonkeyTests.swift` launches the app with `--ui-testing` (in-memory database seeded with `SampleData`, no Sparkle, no notifications) and clicks around at random. Pi is replaced by `PiBoardUITests/FakePi.swift`, a Node script installed as the runtime entry through `--ui-testing-pi-entry=`. It runs in a real pty, emits OSC 9;4 progress, streams colored turns plus periodic 3000-line bursts, reacts to typed input and handles SIGTERM and SIGHUP; it never contacts a model. The shell drawer starts a real `/bin/sh`. After every step it checks that the toolbar still responds and that at most two terminal views exist at once (one workspace terminal plus one drawer) and at most one sheet is open; every 10 steps it clicks the first project and expects the board title. The first failure stops the run and reports the step, the action and the seed.

- `PIBOARD_MONKEY_SEED` (default 1) and `PIBOARD_MONKEY_STEPS` (default 200) control the run; the same seed replays the same clicks. xcodebuild only forwards them to the runner with a `TEST_RUNNER_` prefix: `TEST_RUNNER_PIBOARD_MONKEY_SEED=7 TEST_RUNNER_PIBOARD_MONKEY_STEPS=50 make ui-test`.
- XCUITest needs the host terminal to have Accessibility and Automation permission.
- It is not part of `make test` or of the release build; run it locally before changes to views are merged.

## Suites

236 `@Test` declarations in 36 files (counted with `rg -c "@Test" PiBoardTests`). A parameterized test counts once.

### Board and ordering (60)

| Suite | Tests | Covers |
| --- | --- | --- |
| `BoardModelTests` | 21 | Task and project CRUD, moves and reload, preparation trigger, stop-and-move confirmation, terminal and inspector state, selected project restore, missing worktree on load, 200-task move under 100 ms |
| `BoardDragTargetingTests` | 12 | Drop column and index from pointer location and card frames |
| `TaskOrderingTests` | 8 | Reorder within and across columns, `0..<N` normalization |
| `TaskPresentationTests` | 9 | Card badges: resumable, running, missing worktree; terminal header "Not running" |
| `BoardDragControllerTests` | 4 | Drag begin, end with and without target, cancel |
| `DropIndexingTests` | 4 | Drop index from pointer position, dragged card excluded |
| `TaskStatusTests` | 2 | Raw values match the SQLite CHECK constraint |

### Persistence (16)

| Suite | Tests | Covers |
| --- | --- | --- |
| `TaskRepositoryTests` | 5 | Field round trips, status CHECK constraint, ordering, transaction rollback |
| `MigrationRunnerTests` | 4 | Fresh database reaches latest version, idempotence, schema, position backfill |
| `ProjectRepositoryTests` | 4 | Round trip, ordering, update, foreign key cascade |
| `AppEnvironmentRecoveryTests` | 3 | Fresh database, corrupt file and WAL/SHM sidecars moved aside and replaced |

### Projects and portability (22)

| Suite | Tests | Covers |
| --- | --- | --- |
| `ProjectExporterTests` | 17 | Round trip without machine fields, `~` path, spec sample, unsupported version, malformed files, unknown status, blank name, missing path import, position normalization |
| `ProjectPathServiceTests` | 5 | Canonicalization, symlinks, existence, `~` abbreviation |

### Git and worktrees (30)

| Suite | Tests | Covers |
| --- | --- | --- |
| `WorktreeServiceTests` | 9 | Create, reuse, remove, re-create with existing branch, branch mismatch, plain folder, non-repository, slug and managed path |
| `GitServiceTests` | 7 | Repository info, status, porcelain parsing (renames, NUL separators), not-a-repository |
| `WorktreeActionsTests` | 6 | Clean, dirty and missing removal flows, block while running (fake services) |
| `ProjectGitStatusModelTests` | 5 | Header Git status states (fake service) |
| `WorktreeResumeCheckTests` | 3 | Resume target for a valid, deleted and non-Git worktree |

### Pi process and terminal (58)

| Suite | Tests | Covers |
| --- | --- | --- |
| `PiProcessManagerTests` | 14 | Launch errors, resume session check, current-tree lock, worktree launches skip the lock, active session count, versions in use |
| `TerminalTextTrimmerTests` | 7 | Copy Trimmed |
| `PiSessionLocatorTests` | 6 | Pi session directory encoding, agent directory override, session file lookup |
| `LiveProcessRegistryTests` | 5 | Registry file round trip and removal, live and dead pid checks, orphan filter |
| `PTYSessionTests` | 5 | Real PTY child: output and exit code, SIGTERM, SIGKILL fallback, window size, default appearance |
| `TerminalAppearanceTests` | 5 | Font fallback, size, line height, live session restyle |
| `CurrentTreeLockTests` | 4 | Acquire, re-acquire by owner, conflict, release |
| `PiLaunchCommandTests` | 4 | Argument arrays for new and resume |
| `PromptComposerTests` | 4 | Plan first suffix handling |
| `PTYRuntimeStateTests` | 2 | State helpers |
| `ShellResolverTests` | 2 | Login shell lookup |

### Pi runtime (26)

| Suite | Tests | Covers |
| --- | --- | --- |
| `PiRuntimeManagerTests` | 16 | Status from `current.json`, install, verify (`--version`, `--help`), activate, rollback, remove, retention, failed update keeps active, update check interval, install environment |
| `SemanticVersionTests` | 6 | Parsing and ordering |
| `BundledNodeTests` | 2 | Bundled Node lookup |
| `PiRuntimePathsTests` | 2 | On-disk layout |

### App, preferences, updates, external apps (24)

| Suite | Tests | Covers |
| --- | --- | --- |
| `AppPreferencesTests` | 9 | Defaults, persistence, clamping, scrollback fallback, cursor style |
| `ExternalAppTests` | 8 | Finder availability, task target folder, preferences, open errors (fake service) |
| `UpdateServiceTests` | 7 | Placeholder key detection, channels, version string (fake updater) |

## Real processes in tests

- **PTY.** `PTYSessionTests` spawns `/bin/sh` in a real PTY through SwiftTerm: captures output and exit code, checks that a child ignoring SIGTERM is SIGKILLed after the grace period, and that `stty size` reports a non-zero size before the view has a frame.
- **Process liveness.** `LiveProcessRegistryTests` spawns `/bin/sleep` and `/usr/bin/true` to check pid liveness, start time and the orphan filter; nothing is ever sent to a process the test did not start.
- **Git.** `GitServiceTests`, `WorktreeServiceTests` and `WorktreeResumeCheckTests` use `GitTestRepository`, which creates throwaway repositories under the system temp directory with `/usr/bin/git` and never touches the PiBoard checkout. They require Git to be installed.
- **Not real:** npm installs and Pi verification use a fake command runner; Sparkle uses a fake updater; worktree removal flows and header Git status use fake services. Pi itself is never launched by the test suite.

## Recovery scenarios

| Scenario | Expected behaviour | Verified by |
| --- | --- | --- |
| Restart with an In Progress task | Card shows "Resumable", terminal header shows "Not running"; nothing starts until Resume | `TaskPresentationTests.inProgressTaskWithSessionIsResumableWhenNotStarted`, `TaskPresentationTests.headerReadsNotRunningForSessionWithoutProcess`; manual: quit with a running task, relaunch, open the task |
| Missing Pi session file | Resume is refused with the session-not-found banner; a missing default sessions folder skips the check and lets Pi decide | `PiProcessManagerTests.resumeThrowsSessionNotFoundWhenSessionsDirectoryLacksFile`, `PiProcessManagerTests.resumeSkipsSessionCheckWhenSessionsDirectoryIsMissing`, `PiSessionLocatorTests`; manual: delete the task's `.jsonl` under `~/.pi/agent/sessions`, press Resume |
| Missing project path | Start and resume fail with "project path missing"; Pi is not spawned | `PiProcessManagerTests.startThrowsProjectPathMissingForNonexistentPath`, `PiProcessManagerTests.resumeThrowsProjectPathMissingForNonexistentPath` |
| Missing worktree | Card shows "Worktree missing"; resume never falls back to the project root | `WorktreeResumeCheckTests`, `PiProcessManagerTests.resumeThrowsWorktreeMissingForMissingWorktreePath`, `BoardModelTests.taskWithExternallyDeletedWorktreeLoadsAndReportsWorktreeMissing`, `TaskPresentationTests.missingWorktreeReplacesResumable` |
| Orphaned Pi processes after force quit | Next launch lists Pi children that are still alive, reparented to launchd and running the bundled Node; offers to stop or ignore them | `LiveProcessRegistryTests`; manual: start a task, `kill -9` PiBoard, relaunch, choose Stop |
| Corrupt database | File and WAL/SHM sidecars are moved to `.corrupt-<timestamp>`, an empty database is created and the startup note names the old file | `AppEnvironmentRecoveryTests` |
| Failed Pi update keeps active version | Active runtime stays ready on the previous version | `PiRuntimeManagerTests.failedUpdateKeepsActiveVersionReady` |
| App quit with running sessions | Quit asks for confirmation, then stops sessions (SIGTERM, SIGKILL after the grace period) and clears the live process registry | `PiProcessManagerTests.activeSessionCountCountsStartingRunningAndStopping`, `PTYSessionTests`; manual: quit with a running task, choose Stop and Quit, check no `node` child remains |

## Manual QA

UI flows, real Pi sessions and release behavior are checked by hand before a release. The lists below are the spec's acceptance criteria (section 36) and terminal quality bar (section 42.3), translated. Notes mark where V1 deliberately differs.

### V1 acceptance criteria (spec section 36)

- [ ] Multiple projects can be added; switching projects shows only that project's tasks.
- [ ] A project path can be changed later, and a missing path can be located again.
- [ ] Tasks can be reordered by drag within and across the three columns, and the order persists.
- [ ] Backlog to In Progress does not start Pi.
- [ ] An In Progress task's prompt can be edited before launch.
- [ ] Current Working Tree is selected by default.
- [ ] A dirty current tree shows a warning with the file list.
- [ ] A second active Pi task on the same current tree is hard blocked.
- [ ] Choosing a worktree creates an isolated worktree and Pi runs there.
- [ ] Pi is usable interactively in a real PTY.
- [ ] The active process keeps running when the task terminal is closed.
- [ ] The task's Pi session ID is stored and the session can be reopened.
- [ ] The task does not move to Done when Pi exits.
- [ ] The Pi runtime can be updated and rolled back independently of PiBoard updates.
- [ ] The user's `~/.pi/agent` environment is preserved.
- [ ] Project and task working directories can be opened in VS Code (V1: any configured editor or terminal).
- [ ] Project JSON export and import work.

### Terminal quality bar (spec section 42.3)

- [ ] Real PTY, user default shell, interactive startup; `~/.zshrc` loads for zsh users. (V1: Pi is the direct PTY child with the app environment; no login shell.)
- [ ] Shell environment is preserved, but the PiBoard-managed Node and Pi executables are not chosen through `PATH`.
- [ ] ANSI, 256-color, true-color, Unicode and emoji, alternate screen buffer, mouse reporting and resize work.
- [ ] Ctrl+C, Ctrl+D, Ctrl+Z, Option as Meta, selection, copy/paste and IME work.
- [ ] Smoke test: Pi, tmux, vim/neovim, git, npm and long-running CLIs.
- [ ] Scrollback defaults to 100,000 lines and is configurable; memory pressure is measured at high limits.
- [ ] Font family, size, line height, cursor and scrollback are changeable in Settings > Terminal.
- [ ] Terminal detach and reattach do not affect the process. Normal shell prompt remains usable after Pi exits. (V1: after exit the terminal shows the exit overlay with Resume; there is no shell.)
- [ ] The floating expand control switches to Focus Terminal mode with the same PTY, scrollback and process.
