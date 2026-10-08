# User Guide

PiBoard has no keyboard shortcuts in V1 apart from Find in Terminal (Cmd+F) and the ones you record yourself in Settings > Shortcuts. Every action is a button, a menu item or a context menu item.

## Projects

A project is a local folder. Each project has its own board.

| Action | How |
| --- | --- |
| Add | Sidebar footer: New Project > New Project..., enter a name, Choose... a folder, Add. The empty sidebar also shows Add Project. |
| Add by drop | Drop a folder from Finder onto the sidebar. The New Project sheet opens with that folder filled in. |
| Edit | Right-click the project > Edit Project..., or Project Options (board header) > Edit Project... Name and folder can change. |
| Copy path, Finder | Right-click the project, or the copy and folder icons next to the path in the board header. |
| Delete | Right-click > Delete Project... Removes the project and its tasks from PiBoard only. Files, Git worktrees and Pi session history are not touched. |
| Export | Right-click > Export Project..., or Project Options > Export Project... Writes `<name>.piboard.json`. |
| Import | Sidebar footer: New Project > Import Project..., or drop a `.piboard.json` file on the sidebar. |

### Missing folder

If the folder was moved or deleted, the sidebar row shows a warning icon and the board shows "Project folder not found" with Locate Folder... and Edit Project... Pi cannot start until the folder is found.

The folder of a project cannot change while a current-tree Pi session runs in it. Stop the session first.

### Export format

Exports contain only machine-independent data: project name, path with the home folder written as `~`, and each task's title, prompt, status and position. Session ids, run contexts and worktrees are not exported. Import always creates a new project; if the path does not exist on this Mac, the import still succeeds and the board offers Locate Folder.

## Board

Three columns: Backlog, In Progress, Done. The header shows the project name, path, Git status (branch plus "Clean" or "N changes", or "Not a Git repository", with a refresh button), Open in for your preferred editor, New Task and Project Options.

| Action | How |
| --- | --- |
| Create a task | New Task in the header. Title and an optional prompt. New tasks go to the bottom of Backlog. |
| Move or reorder | Drag a card within a column or to another column. The other cards make room while you drag. |
| Select | Click a card. |
| Edit | Double-click a card without a live session to open the inspector (title, prompt, status, run info, Open, Delete). The toolbar Inspector button toggles it too. On a task terminal the same button toggles the Changes panel. |
| Open terminal | Double-click an In Progress card that has a live session, or use its terminal button. |
| Context menu | Edit Task..., Open Terminal or Prepare and Start Pi... (In Progress only), Open in editor and terminal, Remove Worktree... (when the task has one), Move to Backlog / In Progress / Done, Delete Task. |

Terminal (toolbar) opens a login shell in the project folder at the bottom of the board. Hiding it keeps the shell running; Close or `exit` ends it. Shells end when the project is deleted or PiBoard quits. It is also available on a task's terminal screen, and View > Toggle Terminal toggles it. It has no default key; set one in Settings > Shortcuts.

Rules worth knowing:

- Moving a card from Backlog to In Progress opens the preparation sheet. It does not start Pi.
- Moving a card with a running Pi out of In Progress asks "Pi is still running for this task. Stop it and move?". Stop and Move stops Pi first.
- Pi exiting never moves a card. Done is your decision.
- Deleting a task does not delete Pi session files.

## Preparation sheet

Opens after a Backlog to In Progress move, or from Prepare and Start Pi...

| Part | Behavior |
| --- | --- |
| Initial Prompt | Editable. Saved to the task when Pi starts. Empty is allowed: Pi starts without an initial message. |
| Plan first | Appends the plan-first text (Settings > General) to the prompt sent to Pi. The stored task prompt stays unchanged. The checkbox state is remembered. |
| Run in | Current Working Tree (always the default) or New Worktree. New Worktree is disabled for folders that are not Git repositories. |
| Status line | "Checking working tree...", then "Ready to start." or a warning. |

Dirty working tree (current tree only): the sheet lists the changed files and offers:

- Cancel: close the sheet; the task stays In Progress.
- Use Worktree Instead: switch to New Worktree. Worktrees branch from `HEAD`, so uncommitted changes are not copied.
- Run Anyway: start Pi in the dirty tree.

Blocked states (Start Pi is disabled):

| Message | Fix |
| --- | --- |
| Pi runtime is not installed. | Open Settings > Pi Runtime and install. |
| Project folder is missing. Locate it first. | Locate Folder on the board. |
| `<task>` is already running Pi in this working tree. | Stop that task, or choose New Worktree. |
| Git check failed: ... | Starting in the current tree is still allowed. |

Opening a task that already has a session resumes it in the terminal, using the run context the session was started in. Start Fresh is offered instead of Start Pi; it asks for confirmation, then starts a new session; the old one stays on disk but can no longer be resumed from this task.

## Terminal workspace

Replaces the board when Pi starts or when you open a task's terminal. Leaving it never stops Pi.

Header, left to right:

- Back to Board.
- Task title; subtitle with path, branch and run context.
- Status badge: Starting, Running, Stopping, Finished, Exited (code).
- Stop Pi: asks for confirmation, sends SIGTERM, and kills the process after 5 seconds if it has not exited.
- Resume Pi: shown after Pi exits.
- Find in Terminal (magnifying glass, or Cmd+F): opens SwiftTerm's search bar; it selects and scrolls to the current match.
- Open In menu: preferred editor and terminal, opened at the task's working directory.
- More menu (worktree tasks only): Remove Worktree...

When Pi exits, an overlay shows "Pi exited (code)" with Resume Pi and Back to Board. Opening a task that has a saved session resumes Pi automatically; after Stop Pi or a crash, Resume Pi is a button.

### Copy and paste

- Right-click in the terminal: Copy, Copy Trimmed (strips trailing spaces on each line and blank lines around the selection; indentation is kept), Paste, Select All.
- Pi captures the mouse (mouse reporting). Plain drags go to Pi, and the context menu then says "Hold Shift and drag to select in the terminal". Hold Shift while dragging to make a terminal selection, then right-click > Copy.
- Inside Pi, Ctrl+X copies the current selection when Pi's copy-on-select is off.

## Worktrees

Choose New Worktree in the preparation sheet to run Pi in an isolated checkout.

| Item | Value |
| --- | --- |
| Location | `~/Library/Application Support/PiBoard/worktrees/<project-id>/<task-id>/` |
| Base | Current `HEAD` of the project |
| Branch | `piboard/<first 8 chars of task id>-<slug of title>`, slug is ASCII, lowercase, max 40 chars (for example `piboard/1a2b3c4d-fix-login-redirect`) |
| Command | `git worktree add -b <branch> <path> HEAD` |

- Several worktree tasks of one project can run at the same time.
- Re-running a task whose worktree was removed checks out the existing branch again.
- Moving a task to Done does not remove its worktree. Merging is up to you or Pi.

Remove Worktree... (card context menu, inspector, or terminal More menu):

| Situation | Dialog | Effect |
| --- | --- | --- |
| Clean | Remove worktree? | `git worktree remove`; branch kept |
| Uncommitted changes | Remove worktree with uncommitted changes? (lists up to 10 files) | Remove Anyway runs `git worktree remove --force`; changes are lost; branch kept |
| Folder already gone | Worktree folder not found | Forget Worktree runs `git worktree prune` and clears the task's worktree fields |
| Pi running | Error: Stop the Pi session before removing the worktree. | Nothing |

After removal a task with a session cannot resume (the worktree is gone). The preparation sheet then shows "Worktree is missing or invalid" with Start Fresh in Current Tree.

## Open In external apps

Supported: Visual Studio Code, Cursor, Zed (editors); Terminal, iTerm, Warp (terminals); Finder. Apps are found by bundle identifier; the Settings pickers mark missing ones "(not installed)".

- Project level (board header, sidebar): opens the project folder.
- Task level (card menu, inspector, terminal header): opens the worktree if the task runs in one that still exists, otherwise the project folder.

## Settings

Open from the sidebar footer Settings button or PiBoard > Settings.

### General

| Section | Options |
| --- | --- |
| Plan first | Text appended to the prompt when Plan first is checked. Default (Turkish): "Önce sadece bir plan çıkar. Ben onayladıktan sonra koda başlayacağız." |
| External Apps | Preferred Editor and Terminal for Open In menus. Defaults: Visual Studio Code, Terminal. |
| Updates | Version, Check for Updates, last check time, Check automatically, Channel (Stable or Beta). |

### Terminal

| Option | Values |
| --- | --- |
| Font | System monospaced or an installed monospaced family |
| Size | 9 to 24 pt, default 13 |
| Line Height | 0.9 to 1.6, default 1.0 |
| Cursor | Block, Underline or Bar; Blink on or off |
| Scrollback | 10,000 / 50,000 / 100,000 (default) / 250,000 lines; applies to new sessions |
| Use Option as Meta | On by default; off lets Option type special characters |

Font, size, line height, cursor and Option changes apply to running terminals immediately.

### Shortcuts

- Record Shortcut: click the button, then press a chord that includes Cmd, Option or Control. The key is stored by its physical position, so it works on any keyboard layout.
- Escape cancels a recording. Clear (the x button) removes the shortcut.
- Shortcuts work while PiBoard is the active app and take priority over the terminal, so Pi never sees a bound chord.

### Pi Runtime

- Status, installed version, latest version and last check time.
- Check for Updates, Install Latest (or Update to `<version>`), Rollback to `<previous version>`.
- Previous Versions: Activate or Remove each (the active version and versions used by running sessions cannot be removed).
- On failure: the reason, the npm log tail and Retry. The active version keeps working.
- User Environment: `~/.pi/agent` shown as Detected or Not found, with Open Folder.

PiBoard keeps the newest 3 installed versions and deletes older ones after an install. A runtime change affects new launches only.

## FAQ

**Why does PiBoard never move a task to Done?**
Pi exiting says nothing about whether the work is right. Done is a human decision by design (spec section 2). PiBoard does not guess when Pi is waiting for input either.

**Where are Pi sessions stored?**
Where Pi stores them: `~/.pi/agent/sessions/`, grouped by working directory. PiBoard only stores the session UUID in `tasks.pi_session_id`. It never copies, reads or deletes session files.

**How do I resume after quitting or restarting the Mac?**
Quitting stops running sessions (after a confirmation). Tasks stay In Progress. Open the task (double-click or Prepare and Start Pi...) and it resumes its saved session. Resume Pi is only needed after Stop Pi or a crash. Worktree tasks resume only if their worktree still exists.

**macOS says it cannot verify PiBoard on first launch.**
Releases are ad-hoc signed, not notarized. Allow it once; see [Install](../README.md#install). Updates installed through Sparkle do not ask again.

**Does PiBoard change my Pi configuration?**
No. It does not set `PI_CODING_AGENT_DIR` and never writes to `~/.pi/agent`. Auth, settings, skills, extensions and trust decisions are shared with Pi in your normal terminal.

**My shell PATH or variables are missing inside Pi.**
Pi runs directly in the PTY with PiBoard's environment, not through your login shell. Apps started from Finder or the Dock do not read `~/.zshrc`.
