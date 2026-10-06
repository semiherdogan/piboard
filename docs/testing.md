# Testing

## Running tests

```sh
make test
```

This regenerates the Xcode project and runs the `PiBoard` scheme's test action (`PiBoardTests`, hosted in the app) on `platform=macOS` with derived data in `build/DerivedData`. Tests use Swift Testing (`import Testing`, `@Test`, `#expect`); there are no XCTest cases.

Hosted tests never reach the network or Sparkle: `AppEnvironment` detects `XCTestConfigurationFilePath` and skips the npm registry check and the updater. Databases in tests are `:memory:`; files go to unique temp directories.

To run one suite from Xcode, open `PiBoard.xcodeproj` after `make generate` and use the test navigator.

## Suites

214 `@Test` declarations in 32 files (counted with `rg -c "@Test" PiBoardTests`). A parameterized test counts once.

### Board and ordering (58)

| Suite | Tests | Covers |
| --- | --- | --- |
| `BoardModelTests` | 21 | Task and project CRUD, moves and reload, preparation trigger, stop-and-move confirmation, terminal and inspector state, selected project restore, missing worktree on load, 200-task move under 100 ms |
| `BoardDragTargetingTests` | 12 | Drop column and index from pointer location and card frames |
| `TaskOrderingTests` | 8 | Reorder within and across columns, `0..<N` normalization |
| `TaskPresentationTests` | 7 | Card badges: resumable, running, missing worktree |
| `BoardDragControllerTests` | 4 | Drag begin, end with and without target, cancel |
| `DropIndexingTests` | 4 | Drop index from pointer position, dragged card excluded |
| `TaskStatusTests` | 2 | Raw values match the SQLite CHECK constraint |

### Persistence (13)

| Suite | Tests | Covers |
| --- | --- | --- |
| `TaskRepositoryTests` | 5 | Field round trips, status CHECK constraint, ordering, transaction rollback |
| `MigrationRunnerTests` | 4 | Fresh database reaches latest version, idempotence, schema, position backfill |
| `ProjectRepositoryTests` | 4 | Round trip, ordering, update, foreign key cascade |

### Projects and portability (22)

| Suite | Tests | Covers |
| --- | --- | --- |
| `ProjectExporterTests` | 17 | Round trip without machine fields, `~` path, spec sample, unsupported version, malformed files, unknown status, blank name, missing path import, position normalization |
| `ProjectPathServiceTests` | 5 | Canonicalization, symlinks, existence, `~` abbreviation |

### Git and worktrees (27)

| Suite | Tests | Covers |
| --- | --- | --- |
| `WorktreeServiceTests` | 9 | Create, reuse, remove, re-create with existing branch, branch mismatch, plain folder, non-repository, slug and managed path |
| `GitServiceTests` | 7 | Repository info, status, porcelain parsing (renames, NUL separators), not-a-repository |
| `WorktreeActionsTests` | 6 | Clean, dirty and missing removal flows, block while running (fake services) |
| `ProjectGitStatusModelTests` | 5 | Header Git status states (fake service) |

### Pi process and terminal (44)

| Suite | Tests | Covers |
| --- | --- | --- |
| `PiProcessManagerTests` | 11 | Launch errors, current-tree lock, worktree launches skip the lock, active session count, versions in use |
| `TerminalTextTrimmerTests` | 7 | Copy Trimmed |
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
- **Git.** `GitServiceTests` and `WorktreeServiceTests` use `GitTestRepository`, which creates throwaway repositories under the system temp directory with `/usr/bin/git` and never touches the PiBoard checkout. They require Git to be installed.
- **Not real:** npm installs and Pi verification use a fake command runner; Sparkle uses a fake updater; worktree removal flows and header Git status use fake services. Pi itself is never launched by the test suite.

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
