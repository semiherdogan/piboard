# Development

## Environment setup

1. Install Xcode 27 and select it: `sudo xcode-select -s /Applications/Xcode.app`.
2. Install the Metal Toolchain once. SwiftTerm ships a Metal shader, so builds fail without it:

   ```sh
   xcodebuild -downloadComponent MetalToolchain
   ```

3. Install xcodegen: `brew install xcodegen`.
4. Build: `make build`. The first run downloads Node 24 into `Runtime/node` (see below).

Apple Silicon only. `ARCHS` is `arm64` because the bundled Node binary is arm64.

## xcodegen workflow

`project.yml` is the source of truth. `PiBoard.xcodeproj`, `PiBoard/Resources/Info.plist` and `PiBoard/Resources/PiBoard.entitlements` are generated and gitignored.

- Never edit the Xcode project directly; change `project.yml` and run `make generate`.
- New Swift files under `PiBoard/` or `PiBoardTests/` are picked up by the next `make generate`.
- Info.plist keys (`SUFeedURL`, `SUPublicEDKey`, versions) live under `targets.PiBoard.info.properties` in `project.yml`.
- Swift packages: SwiftTerm (`from: 1.20.0`) and Sparkle (`from: 2.10.0`).

### Bundled Node

`scripts/fetch-node.sh` downloads `node-v24.21.0-darwin-arm64.tar.gz` from nodejs.org, checks its SHA-256 against the pinned value and unpacks it to `Runtime/node` (gitignored). It is a no-op if the right version is already there. `make generate` runs it when `Runtime/node/bin/node` is missing. `project.yml` copies `Runtime/node` into the app as `Contents/Resources/node`.

To bump Node: change `NODE_VERSION` and both SHA-256 values in the script, delete `Runtime/node`, run `make build`, then `make verify-bundle`.

## Makefile targets

| Target | What it does |
| --- | --- |
| `make fetch-node` | Runs `scripts/fetch-node.sh` |
| `make generate` | Fetches Node if missing, then `xcodegen generate` |
| `make build` | Generate, then Debug build into `build/DerivedData` |
| `make test` | Generate, then run `PiBoardTests` |
| `make run` | Build, quit any running PiBoard (gracefully, then `pkill`), open the Debug app |
| `make verify-bundle` | Runs the bundled `node --version` from the built app, also with an empty environment |
| `make appicon` | Regenerates `AppIcon.appiconset` and `Design/appicon-preview.png` from `Design/appicon-1024-source.png` |
| `make release-dry-run` | Ad-hoc signed `0.0.0` beta zip in `build/release` (see [RELEASING.md](RELEASING.md)) |
| `make clean` | Deletes `PiBoard.xcodeproj` and `build/` |

## Coding conventions

These are the conventions the codebase follows. Match them in new code.

- **English** for identifiers, comments, docs and UI strings. Exceptions are user content such as the Turkish default Plan first text.
- **Comments explain why**, constraints or gotchas, usually in one line. No comments that restate the code, no banners, no TODOs.
- **No magic literals.** Strings and numbers that mean something get a name: `private let` constants at the top of a file (`quitGracePeriod`, `terminalName`), `static let` on the owning type (`WorktreeService.branchPrefix`, `GitCommandRunner.defaultTimeout`), or an enum (`SettingKey`, `TaskStatus`, `ExternalApp`). Comparisons use the enum case, not its raw value. Values shared with scripts say so ("Must match ... in scripts/release.sh").
- **No keyboard shortcuts in V1.** Do not add `.keyboardShortcut`. Every action needs a visible button or menu item. Terminal keys belong to Pi.
- **Strict concurrency.** Swift 6, `SWIFT_STRICT_CONCURRENCY: complete`, zero warnings. UI-facing models are `@MainActor @Observable`. Blocking work goes to `Task.detached` or a `@concurrent nonisolated` function. Non-isolated callbacks (SwiftTerm, Sparkle) go through bridge objects or `MainActor.assumeIsolated` where the callback is documented to arrive on the main thread.
- **Layering.** Domain has no I/O. Persistence knows nothing about UI. Services are injected through `AppEnvironment`; services with a protocol (`GitServicing`, `WorktreeServicing`, `ExternalAppServicing`, `PiRuntimeCommandRunning`, `UpdaterControlling`) get fakes in tests.
- **Workflow vs runtime state.** Never derive one from the other; see [architecture.md](architecture.md#key-invariants).
- **Processes.** Build commands as executable plus argument array. Never go through a shell string.

## Diagnostics

Loggers live in `PiBoard/Shared/Utilities/Diagnostics.swift` (subsystem `dev.piboard`, categories `ui`, `git`, `runtime`). Log identifiers and paths with `privacy: .public`; never log prompt text or credentials.

```sh
log show --predicate 'subsystem == "dev.piboard"' --info --last 30m
log stream --predicate 'subsystem == "dev.piboard"' --info
```

### Troubleshooting a UI freeze

The `ui` category exists so a frozen window can be explained after the fact. Work from cheap to expensive:

1. **Logs.** `log show --predicate 'subsystem == "dev.piboard" AND category == "ui"' --info --last 10m`. The last events (sheet presented, terminal attach, inspector dismissed) show what the UI was doing. Terminal attach and detach lines include frame, bounds and first responder.
2. **Sample.** While the window is frozen:

   ```sh
   sample PiBoard 5 -file /tmp/piboard-sample.txt
   ```

   Read the main thread (Thread 0 / `com.apple.main-thread`) call graph. A spin in SwiftUI layout, AttributeGraph or `NSHostingView` points at a view update loop; a stack inside `waitpid`, `read` or `queue.sync` points at blocking work on the main actor.
3. **lldb.** For a live, exact stack:

   ```sh
   lldb -p "$(pgrep -x PiBoard)"
   (lldb) thread backtrace all
   (lldb) detach
   ```

   Detach before quitting lldb so the app keeps running.
4. Fix the cause, then add a log line in the `ui` category if the state transition was not visible in step 1.

Fixes made this way are recorded in code comments, for example deferring `openTerminalTaskID` so the board is not removed mid-gesture (`BoardModel.openTerminal`) and moving the terminal swap to the sheet's `onDismiss`.

## Adding a migration

1. Create `PiBoard/Persistence/Migrations/Migration00N_<Name>.swift`:

   ```swift
   enum Migration003_AddTaskColor {
       static let migration = Migration(
           version: 3,
           sql: """
           ALTER TABLE tasks ADD COLUMN color TEXT NULL;
           """
       )
   }
   ```

2. Append it to `MigrationRunner.all`. Versions must increase by one.
3. Never edit a migration that has shipped; add a new one.
4. Update the domain type, the repository read and write code, and `ProjectExportDocument` only if the field is portable.
5. Add a test in `MigrationRunnerTests` (schema and data after migrating) and repository round-trip tests.
6. `make test`.

Each migration runs in its own transaction together with the `user_version` bump, so a failing migration leaves the database at the previous version.

## Adding a setting

1. Add a case to `SettingKey` in `PiBoard/Persistence/SettingsRepository.swift` with a snake_case raw value. The raw value is stored in the `settings` table, so never rename it.
2. Add a named default (a `static let` on the owning type, such as `TerminalScrollback.defaultLines`).
3. Add a property to `AppPreferences` with a `didSet` that skips unchanged values and writes through `settingsRepository`, and load it in `init` with the default as fallback. Clamp or validate stored values on load.
4. If the setting changes live terminals, read it in `AppEnvironment.observeTerminalPreferences` and apply it in `PTYSession.apply`.
5. Add the control to the right Settings tab (`SettingsView`, `TerminalSettingsView` or `PiRuntimeSettingsView`).
6. Add tests to `AppPreferencesTests`: default, round trip, invalid stored value.

Settings owned by a service (update channel, Pi latest version) are read and written by that service through its own `SettingsRepository`, not through `AppPreferences`.
