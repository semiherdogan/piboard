# User Guide

PiBoard has no keyboard shortcuts in V1 apart from Find in Terminal (Cmd+F) and the ones you record yourself in Settings > Shortcuts. Every action is a button, a menu item or a context menu item.

## Projects

A project is a local folder. Each project has its own board.

| Action | How |
| --- | --- |
| Add | Sidebar footer: New Project > New Project..., enter a name, Choose... a folder, pick the default agent, Add. The empty sidebar also shows Add Project. |
| Add by drop | Drop a folder from Finder onto the sidebar. The New Project sheet opens with that folder filled in. |
| Edit | Right-click the project > Edit Project..., or Project Options (board header) > Edit Project... Name, folder and default agent can change. |
| Copy path, Finder | Right-click the project, or the copy and folder icons next to the path in the board header. |
| Delete | Right-click > Delete Project... Removes the project and its tasks from PiBoard, stops their agents, removes their managed worktrees and deletes their Pi session files. The confirmation lists all of it. Repository files are never touched. |
| Export | Right-click > Export Project..., or Project Options > Export Project... Writes `<name>.piboard.json`. |
| Import | Sidebar footer: New Project > Import Project..., or drop a `.piboard.json` file on the sidebar. |

### Missing folder

If the folder was moved or deleted, the sidebar row shows a warning icon and the board shows "Project folder not found" with Locate Folder... and Edit Project... Pi cannot start until the folder is found.

The folder of a project cannot change while a current-tree Pi session runs in it. Stop the session first.

### Export format

Exports contain only machine-independent data: project name, path with the home folder written as `~`, default agent, and each task's title, prompt, status, position and agent. Session ids, run contexts and worktrees are not exported. Import always creates a new project; if the path does not exist on this Mac, the import still succeeds and the board offers Locate Folder.

## Board

Three columns: Backlog, In Progress, Done. The header shows the project name, path, Git status (branch plus "Clean" or "N changes", or "Not a Git repository", with a refresh button), Open in for your preferred editor, New Task and Project Options.

| Action | How |
| --- | --- |
| Create a task | New Task in the header. Title and an optional prompt. New tasks go to the bottom of Backlog. Insert Template adds a saved snippet to the prompt. |
| Move or reorder | Drag a card within a column or to another column. The other cards make room while you drag. |
| Select | Click a card. |
| Edit | Double-click a card without a live session to open the inspector (title, prompt, status, run info including the Agent row, Open, Duplicate, Delete). The inspector's Session section shows name, turns, model, tokens, cost when the provider reports one, last activity and the last message. The toolbar Inspector button toggles it too. On a task terminal the same button toggles the Changes panel. |
| Open terminal | Double-click an In Progress card that has a live session, or use its terminal button. |
| Context menu | Edit Task..., Duplicate Task, Open Terminal or Prepare and Start Pi... (In Progress only), Stop Pi (while Pi runs; asks only when the agent is still working), Open in editor and terminal, Migrate to (a task with a session that is not running), Remove Worktree... (when the task has one), Move to Backlog / In Progress / Done, Delete Task. |
| Card status | Dots before the title: green pulsing while the agent works, grey while Pi is idle at its prompt, blue when it finished while you were away, orange when the agent is waiting for your answer (OpenCode permissions and questions). The badge below reads Working or Idle. An idle Pi shows a small stop button at the bottom right; one click stops it, no confirmation. Each card shows its agent (Pi or OpenCode) as the first badge below the prompt. Below the prompt, the first line of the agent's last message appears once a session exists. |
| Clear Done | Clear in the Done column header. Asks first, then deletes every Done task of the project like Delete Task does. |

Terminal (toolbar) opens a login shell in the project folder at the bottom of the board. Hiding it keeps the shell running; Close or `exit` ends it. Shells end when the project is deleted or PiBoard quits. It is also available on a task's terminal screen, and View > Toggle Terminal toggles it. It has no default key; set one in Settings > Shortcuts.

Rules worth knowing:

- Moving a card from Backlog to In Progress opens the preparation sheet. It does not start Pi.
- Moving a card with a running Pi out of In Progress asks "Pi is still running for this task. Stop it and move?". Stop and Move stops Pi first.
- Pi exiting never moves a card. Done is your decision.
- Deleting a task, clearing Done or deleting a project also deletes the Pi session files of those tasks. The confirmation says how many.

## Command palette

View > Command Palette... (record a key for it in Settings > Shortcuts) opens a search over all projects and tasks. Type to filter, arrows to move, Enter to open: a task with a session opens its terminal, any other task or a project opens the board with it selected. Matching ignores case and accents.

## Agents

PiBoard runs Pi (installed by PiBoard), OpenCode or Claude Code (both installed by you, see Settings > OpenCode and Settings > Claude Code). The project default applies to new tasks; the preparation sheet can override it per task. OpenCode tasks need its background service, which PiBoard starts on demand; their sessions live in OpenCode's own database and are deleted through it. Claude Code tasks run the `claude` binary found at ~/.local/bin/claude or on your shell PATH; sign in once by running `claude` and `/login` in any terminal. Their sessions are the JSONL files under ~/.claude/projects; deleting a task deletes that file. The first launch in a new worktree shows Claude Code's trust question in the terminal; answer it there.

## Preparation sheet

Opens after a Backlog to In Progress move, or from Prepare and Start Pi...

| Part | Behavior |
| --- | --- |
| Initial Prompt | Editable. Saved to the task when Pi starts. Empty is allowed: Pi starts without an initial message. |
| Plan first | Appends the plan-first text (Settings > General) to the prompt sent to Pi. The stored task prompt stays unchanged. The checkbox state is remembered. |
| Agent | Pi, OpenCode or Claude Code. Locked once the task has a session; Start Fresh unlocks it. A dropdown replaces the segments when more than three agents are enabled. |
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
| `<task>` is already running Pi in this working tree. | Stop that task, choose New Worktree, or click Start Anyway (Resume Anyway for a task with a session). Anyway runs both agents on the same files; use it for questions, not for changes. |
| Git check failed: ... | Starting in the current tree is still allowed. |

Opening a task that already has a session resumes it in the terminal, using the run context the session was started in. Start Fresh is offered instead of Start Pi; it asks for confirmation, then clears the session. The sheet stays open so you can change the agent or run context, then Start; the old session stays on disk but can no longer be resumed from this task.

### Migrating a task to another agent

Moves a task's conversation to a different agent. Open it from the card's context menu or the inspector's Run section: Migrate to > the agent. It is offered for tasks with a session that are not running, and for every enabled agent, including the current one, which is listed as "<agent> (new session)..." and starts a fresh session of the same agent with the summary as its first prompt (useful when the context is full).

The sheet shows a summary of the old session that becomes the new agent's first prompt: the task, its original prompt, the last turns of the conversation and the changed files. Edit it freely. Include assistant replies and Include changed files rebuild the summary; they are disabled once you edit it by hand. Plan first works as in the preparation sheet. A task with a worktree keeps it; otherwise the new agent runs in the current working tree, and a busy tree offers Start Anyway.

Migrate starts a new session and opens its terminal. The old session stays on disk untouched and is deleted with the task. The inspector's Session section shows a "Migrated from" row with the old agent and session. If the launch fails, the task goes back to the old agent and session. The agent badge appears on a card only once the task has a session.

## Terminal workspace

Replaces the board when Pi starts or when you open a task's terminal. Leaving it never stops Pi.

Header, left to right:

- Back to Board.
- Task title; subtitle with path, branch and run context.
- Status badge: Starting, Working, Idle, Stopping, Finished, Exited (code). Working and Idle come from Pi's progress reporting; Idle means Pi is waiting at its prompt.
- Stop Pi: asks for confirmation, sends SIGTERM, and kills the process after 5 seconds if it has not exited.
- Interrupt (octagon icon): sends Ctrl-C to Pi, which stops the current turn and returns to its prompt. The session stays alive; no confirmation.
- Resume Pi: shown after Pi exits.
- Find in Terminal (magnifying glass, or Cmd+F): opens SwiftTerm's search bar; it selects and scrolls to the current match.
- Open In button: click opens the task's working directory in the preferred editor (Settings > General); the arrow lists every installed editor, terminal and Finder. Apps show their own icons.
- More menu (worktree tasks only): Remove Worktree...

When Pi exits, an overlay shows "Pi exited (code)" with Resume Pi and Back to Board. Opening a task that has a saved session resumes Pi automatically; after Stop Pi or a crash, Resume Pi is a button. If another task already runs Pi in the same working tree, a banner names it and offers Resume Anyway. If the session file is gone, a banner offers Start Fresh..., which opens the preparation sheet so you can review the prompt before a new session starts.

Below the Changes panel header a sync row shows whether the branch is published and how many commits are waiting (Not published, N to push, Up to date). Push sends them without a commit, through the same console as Commit & Push. Open Pull Request opens the host's compare or merge request page for the branch against the remote's default branch; it needs a pushed branch and a browsable remote.

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
- Moving a task to Done does not remove its worktree. Merging is up to you or Pi. The board then shows a reminder naming the branch and whether it has unpushed commits, with Remove Worktree... and Dismiss.

Remove Worktree... (card context menu, inspector, or terminal More menu):

| Situation | Dialog | Effect |
| --- | --- | --- |
| Clean | Remove worktree? | `git worktree remove`; branch kept |
| Uncommitted changes | Remove worktree with uncommitted changes? (lists up to 10 files) | Remove Anyway runs `git worktree remove --force`; changes are lost; branch kept |
| Folder already gone | Worktree folder not found | Forget Worktree runs `git worktree prune` and clears the task's worktree fields |
| Pi running | Error: Stop the Pi session before removing the worktree. | Nothing |

After removal a task with a session cannot resume (the worktree is gone). The preparation sheet then shows "Worktree is missing or invalid" with Start Fresh in Current Tree.

## Open In external apps

Supported: Visual Studio Code, VSCodium, Cursor, Zed, Sublime Text, Kiro (editors); Terminal, iTerm, Warp (terminals); Finder. Apps are found by bundle identifier; the Settings pickers mark missing ones "(not installed)".

- Project level (board header, sidebar): opens the project folder.
- Task level (card menu, inspector, terminal header): opens the worktree if the task runs in one that still exists, otherwise the project folder.

## Settings

Open from the sidebar footer Settings button or PiBoard > Settings.

### General

| Section | Options |
| --- | --- |
| Plan first | Text appended to the prompt when Plan first is checked. Default (Turkish): "Önce sadece bir plan çıkar. Ben onayladıktan sonra koda başlayacağız." |
| Prompt Templates | Named snippets. New Task and the preparation sheet show an Insert Template menu next to the prompt; inserting appends the template as a new paragraph. |
| External Apps | Preferred Editor and Terminal for Open In menus. Defaults: Visual Studio Code, Terminal. |
| Agents | Which agents the pickers offer. The default agent (Pi) cannot be turned off. |
| Commit Messages | Generate with: Pi, OpenCode or Claude Code among the enabled agents. A disabled agent falls back to Pi. |
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
- Actions: Toggle Terminal, New Task, Back to Board, Toggle Inspector, Toggle Changes Panel, Stop Pi, Command Palette. Task actions apply to the terminal on screen, otherwise to the selected card.
- Escape cancels a recording. Clear (the x button) removes the shortcut.
- Shortcuts work while PiBoard is the active app and take priority over the terminal, so Pi never sees a bound chord.

### Pi Runtime

- Status, installed version, latest version and last check time.
- Check for Updates, Install Latest (or Update to `<version>`), Rollback to `<previous version>`.
- Previous Versions: Activate or Remove each (the active version and versions used by running sessions cannot be removed).
- On failure: the reason, the npm log tail and Retry. The active version keeps working.
- User Environment: `~/.pi/agent` shown as Detected or Not found, with Open Folder, and Update Extensions.
- Commit Messages (applies when Pi is selected in General): Model (`provider/model`, empty lets Pi choose) and Extensions (one path per line, loaded on top of `--no-extensions`). Set the extension path when your provider comes from an extension package such as `pi-claude-bridge`, otherwise message generation fails with "No API key found for the selected model".

PiBoard keeps the newest 3 installed versions and deletes older ones after an install. A runtime change affects new launches only.

### OpenCode

Shows whether OpenCode is installed, its version and the executable PiBoard found (~/.opencode/bin/opencode or your shell PATH). PiBoard does not install or update OpenCode; use its installer.

### Claude Code

Shows whether Claude Code is installed, its version, the executable PiBoard found (~/.local/bin/claude or your shell PATH) and the login state from `claude auth status`. Refresh re-checks; the Install link opens Claude Code's install page. PiBoard does not install, update or sign in to Claude Code. Working and Idle come from the terminal title; Needs input comes from Claude Code hooks that PiBoard adds for its own launches (no changes to your ~/.claude/settings.json). The Commit Messages Model field (a model name or alias, empty lets Claude Code choose) applies when Claude Code is selected in General.

## FAQ

**Why does PiBoard never move a task to Done?**
Pi exiting says nothing about whether the work is right. Done is a human decision by design (spec section 2). PiBoard does not guess when Pi is waiting for input either.

**Where are Pi sessions stored?**
Where Pi stores them: `~/.pi/agent/sessions/`, grouped by working directory. PiBoard stores only the session UUID in `tasks.pi_session_id`. It reads that folder to check that a session exists before resuming, and it deletes a session file only when you delete the task, clear Done or delete the project, after the confirmation says so. It also reads them to show the session summary on the card and in the inspector. It never writes or modifies session files.

**How do I resume after quitting or restarting the Mac?**
Quitting stops running sessions (after a confirmation). Tasks stay In Progress. Open the task (double-click or Prepare and Start Pi...) and it resumes its saved session. Resume Pi is only needed after Stop Pi or a crash. Worktree tasks resume only if their worktree still exists.

**macOS says it cannot verify PiBoard on first launch.**
Releases are ad-hoc signed, not notarized. Allow it once; see [Install](../README.md#install). Updates installed through Sparkle do not ask again.

**Does PiBoard change my Pi configuration?**
No. It does not set `PI_CODING_AGENT_DIR` and never changes your configuration under `~/.pi/agent`. The only thing it removes there is the session file of a task you delete. Auth, settings, skills, extensions and trust decisions are shared with Pi in your normal terminal.

**My shell PATH or variables are missing inside Pi.**
PiBoard asks your login shell for its environment once at startup (`$SHELL -l -i`) and hands that to Pi, Git and npm, so `PATH` entries and variables from `~/.zshrc` are normally present. If the shell does not answer within 3 seconds, PiBoard falls back to the environment launchd gives GUI apps, which has only the system `PATH`. Check that your shell startup files do not block on input.
