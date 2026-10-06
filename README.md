# PiBoard

PiBoard is a native macOS Kanban board for running the [Pi coding agent](https://github.com/earendil-works/pi) (`@earendil-works/pi-coding-agent`) on your local projects. Each project gets a board with Backlog, In Progress and Done. When you move a task to In Progress, you review its prompt, choose the current working tree or an isolated Git worktree, and start Pi in a real terminal embedded in the app, one terminal per task. PiBoard manages its own Pi install and a bundled Node runtime, so nothing needs to be installed globally. It is for developers who already use Pi in a terminal and want several agent tasks per repository organized, resumable and kept apart.

## Screenshots

Not added yet. Put PNGs in [`docs/images/`](docs/images/) and link them here:

| File | Shows |
| --- | --- |
| `docs/images/board.png` | A project board with cards in all three columns and the sidebar |
| `docs/images/preparation.png` | The preparation sheet with a dirty working tree warning |
| `docs/images/terminal.png` | The terminal workspace with Pi running and the header visible |
| `docs/images/settings.png` | Settings > Pi Runtime |

## Features

### Board

- Projects are local folders; each has its own board. Add by folder picker or by dropping a folder on the sidebar.
- Three columns with custom drag to reorder within and across columns; order is saved to SQLite in one transaction.
- Moving to In Progress opens a preparation sheet. It never starts Pi on its own.
- Done is always a manual move.
- Missing project folders get a banner with Locate Folder.

### Pi sessions and terminal

- Real PTY terminal (SwiftTerm) per task; leaving the terminal does not stop Pi.
- Each task keeps one Pi session id, written before launch; Resume Pi reopens it with `--session <id>`, also after an app restart.
- Plan first: optionally appends a "plan before coding" instruction to the prompt.
- Stop with confirmation (SIGTERM, then SIGKILL after 5 s); quitting the app asks before stopping running sessions.
- Focus mode, right-click Copy, Copy Trimmed and Paste, configurable font, line height, cursor, scrollback and Option as Meta.

### Git and worktrees

- Preflight before every launch: shows the dirty file list and offers Use Worktree Instead or Run Anyway.
- Only one Pi session per project's current working tree; a second one is blocked.
- Optional managed worktree per task on branch `piboard/<id>-<slug>`, created from `HEAD`. Worktree tasks can run in parallel.
- Explicit Remove Worktree with a warning for uncommitted changes; the branch is always kept.

### Pi runtime

- Bundled Node 24 inside the app; Pi is launched by absolute path, never from `PATH`.
- Pi is installed per version under Application Support with install, verify, activate, rollback and remove; a failed update keeps the active version.
- Your `~/.pi/agent` (auth, settings, skills, extensions, sessions, trust) is reused as is and never modified.

### Portability

- Export a project and its tasks to `<name>.piboard.json`; import by menu or by dropping the file on the sidebar.
- Machine-specific data (session ids, worktrees) is not exported.
- Open In: VS Code, Cursor, Zed, Terminal, iTerm, Warp or Finder, at the project or task working directory.

### Updates

- Sparkle self-updates with EdDSA-signed releases.
- Stable or Beta channel, automatic checks, and PiBoard > Check for Updates...

## Requirements

| Item | Needed for |
| --- | --- |
| macOS 26 | Running |
| Apple Silicon (arm64) | Running; the bundled Node binary is arm64 only |
| Xcode 27 | Building from source |
| [xcodegen](https://github.com/yonaskolb/XcodeGen) (`brew install xcodegen`) | Building from source |
| Metal Toolchain, once: `xcodebuild -downloadComponent MetalToolchain` | Building from source; SwiftTerm contains a Metal shader |

No global Node or Pi install is needed. If you already use Pi, PiBoard reuses `~/.pi/agent` and never writes to it.

## Install

1. Download the newest `PiBoard-<version>.zip` from [Releases](https://github.com/semiherdogan/piboard/releases). All releases so far are betas.
2. Unzip and move `PiBoard.app` to `/Applications`.
3. Open it. Releases are ad-hoc signed and not notarized, so macOS blocks the first launch:
   - macOS 26: open System Settings > Privacy & Security, click Open Anyway next to the PiBoard message, and confirm. (Right-click > Open no longer bypasses Gatekeeper since macOS 15.)
   - This is needed once per install.
4. In Settings > Pi Runtime, click Install Latest to install Pi.

### Updates

PiBoard checks `https://semiherdogan.github.io/piboard/appcast.xml` daily. Every update is verified against the EdDSA key built into the app, so updates install without Gatekeeper prompts.

- Settings > General > Updates: Check automatically, and Channel. Stable is the default; choose Beta to get beta builds.
- Check now: PiBoard > Check for Updates...

Pi itself is updated separately in Settings > Pi Runtime.

## Quick start

1. **Add a project.** Sidebar: New Project > New Project..., or drop a folder on the sidebar.
2. **Create a task.** New Task in the board header. Give it a title and a prompt.
3. **Move it to In Progress.** Drag the card. The preparation sheet opens.
4. **Prepare.** Edit the prompt, tick Plan first if you want a plan before code, and choose Current Working Tree (default) or New Worktree. Resolve any warning shown.
5. **Start Pi.** The terminal workspace replaces the board, with Pi running in it.
6. **Work in the terminal.** Type to Pi directly. Back to Board keeps Pi running; double-click the card to return. Use Resume Pi after Pi exits or after a restart.
7. **Move to Done yourself** when you are satisfied. PiBoard never does it for you.

Details: [User Guide](docs/user-guide.md).

## Build from source

```sh
make generate         # fetch Node 24 into Runtime/node if missing, then xcodegen
make build            # Debug build into build/DerivedData
make test             # run PiBoardTests
make run              # build, quit a running PiBoard, open the Debug app
make appicon          # regenerate the app icon from Design/appicon-1024-source.png
make release-dry-run  # ad-hoc signed 0.0.0 beta zip in build/release
make verify-bundle    # check the bundled node runs from the built app
```

`PiBoard.xcodeproj` is generated from `project.yml` and gitignored; do not edit it. See [Development](docs/development.md).

## Project layout

| Path | Purpose |
| --- | --- |
| `PiBoard/App` | Composition root (`AppEnvironment`), `BoardModel`, window, app delegate, paths, preferences |
| `PiBoard/Domain` | Value types and pure logic: tasks, statuses, ordering, export format, versions |
| `PiBoard/Persistence` | SQLite wrapper, repositories, numbered migrations |
| `PiBoard/Services` | PTY sessions, Pi process and runtime management, Git, worktrees, external apps, updates |
| `PiBoard/Features` | SwiftUI screens: Board, Preparation, Projects, Settings, TaskDetail, Terminal |
| `PiBoard/Shared` | Reusable components and utilities (logging) |
| `PiBoard/Resources` | Asset catalog; generated Info.plist and entitlements |
| `PiBoardTests` | Swift Testing suites |
| `scripts` | `fetch-node.sh`, `release.sh`, `make-appicon.swift` |
| `Design` | App icon source and preview |
| `Runtime` | Downloaded Node runtime (gitignored) |
| `docs` | Documentation |
| `.github/workflows` | Release workflow |

## Where data lives

Everything PiBoard writes is under `~/Library/Application Support/PiBoard/`:

| Path | Contents |
| --- | --- |
| `piboard.sqlite` | Projects, tasks, settings |
| `runtime/pi/versions/<version>/` | Installed Pi versions; `runtime/pi/current.json` points at the active one |
| `runtime/npm-cache/` | npm cache used for Pi installs |
| `worktrees/<project-id>/<task-id>/` | Managed Git worktrees |

Pi sessions stay where Pi keeps them, in `~/.pi/agent/sessions/`. Deleting a project or task in PiBoard never deletes repository files, worktrees or Pi sessions.

## Logging

```sh
log show --predicate 'subsystem == "dev.piboard"' --info
```

Categories: `ui`, `git`, `runtime`. See [Architecture](docs/architecture.md#diagnostics).

## Documentation

- [Documentation index](docs/README.md)
- [User Guide](docs/user-guide.md)
- [Architecture](docs/architecture.md)
- [Development](docs/development.md)
- [Testing](docs/testing.md)
- [Releasing](docs/RELEASING.md)
- [V1 Spec](docs/spec.md) (Turkish, with deviations)

## License

License: not yet chosen.
