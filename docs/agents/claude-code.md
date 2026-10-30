# Claude Code adapter: spike findings

Verified 29 October 2026 against Claude Code 2.1.294, the native build installed by the official installer (`~/.local/bin/claude` is a symlink to `~/.local/share/claude/versions/2.1.294`), logged in through claude.ai, on macOS 27. Result: go. Verified range: 2.1.294 only; retest the title glyphs and hook payloads on the next minor.

## How it is shaped

- One native binary per user, self-updating, no server. Everything PiBoard needs is on the CLI plus hooks.
- Sessions are JSONL files: `~/.claude/projects/<encoded cwd>/<session-id>.jsonl`. The encoded cwd is the resolved path (`/private/var/...` for `/var/...`) with every `/` and `.` replaced by `-`. The project folder also holds a `memory/` directory shared by all sessions of that cwd. The file appears on the first prompt, not at launch.
- `~/.claude/sessions/<pid>.json` is a registry of live sessions (`pid`, `sessionId`, `cwd`, `kind`). Read-only interest at most; PiBoard owns the process anyway.
- Trust dialog: the first launch in a directory asks "Is this a project you trust?", default answer "No, exit". It is per exact directory; a subdirectory of a trusted project asks again, so every new worktree asks once. It renders in PiBoard's terminal and the user answers there.
- Hooks: `--settings '<json>'` adds settings for one launch on top of the user's files. Hook handlers of `type: "http"` receive the event JSON as a POST body and accept `{}` as the response. No script file and no shell are involved.
- `--bare` skips settings and hooks but also skips OAuth and the keychain: with a claude.ai login it answers "Not logged in". Never use it.
- `--tools <tools...>` is variadic: a positional prompt placed after `--tools ""` is swallowed as a tool name. Put the prompt last and keep `--tools` away from it, or send the prompt on stdin in print mode.

## Verified calls

| Need | Call | Verified behaviour |
| --- | --- | --- |
| Session id before spawn | `claude --session-id <uuid> --name <title> [--settings <json>] [prompt]` | The id is used as is; print mode echoes it in `session_id`. `--name` is stored as a `custom-title` entry. Two live sessions with the same name: the second gets a random suffix, harmless. |
| Resume | `claude --resume <id>` | Works from any cwd; the file stays in its original project folder. PiBoard must enforce "never resume a worktree session in the project root" itself. An unknown id in print mode prints `No conversation found with session ID: ...` and exits 0. |
| Does the session exist | glob `~/.claude/projects/*/<id>.jsonl` | One file per id across all project folders. Hooks also deliver `transcript_path`. |
| Working or idle | terminal title, OSC 0 | Emitted in a plain pty (`TERM=xterm-256color`, no `TERM_PROGRAM`). The title is `<glyph> <session name>`: U+25D0 or U+25D1 (half-filled circles, spinner frames) while busy, U+2733 (eight-spoked asterisk) when idle. Returns to U+2733 after an Esc or Ctrl+C interrupt. Also shows U+2733 while a permission prompt waits, so it cannot signal needs-input on its own. Undocumented, so pinned to the verified version. |
| OSC 9;4 | setting `terminalProgressBarEnabled` (default true) | Never emitted in a pty, with or without `TERM_PROGRAM=ghostty` or `iTerm.app`. Not usable. |
| Hook events | `--settings` with http hooks on `127.0.0.1` | Observed: `UserPromptSubmit` (`session_id`, `prompt`, `session_title`, `permission_mode`), `PreToolUse` and `PermissionRequest` (`tool_name`, `tool_input`; fire for `Write` and for `AskUserQuestion`), `Notification` with `notification_type: permission_prompt` about 6 s after the request, `Stop` (`last_assistant_message`), `SessionEnd` (`reason`). An interrupt fires nothing. `StopFailure`, `PostToolUse`, `PermissionDenied` were configured and not observed. |
| Headless one-shot | `echo <prompt> \| claude -p --tools "" --no-session-persistence --output-format json` | JSON with `result`, `session_id`, `is_error`, `num_turns`, `total_cost_usd`, `usage`. No file is written. Takes `--model`. |
| Delete | none for a foreground session | `claude rm <id>` is documented for `--bg` sessions and was not tested on a foreground id. `claude purge [path]` deletes all state of a project and is far too wide. |
| Summary data | JSONL entries | `custom-title.customTitle`, `last-prompt.lastPrompt`, `user` and `assistant` entries with `timestamp`, `message.content` and `message.model`, `assistant.message.usage` (`input_tokens`, `output_tokens`, `cache_read_input_tokens`, `cache_creation_input_tokens`), `cost-state` (`totalCostUSD`, `totalDuration`, `modelUsage`, `totalLinesAdded`, `totalLinesRemoved`). `user` entries also carry tool results as content blocks, so turns are the user entries whose content is a string or a text block. One API response is written as several `assistant` entries sharing `message.id` and `usage`; count and sum per id. |
| Version and login | `claude --version`, `claude auth status` | `2.1.294 (Claude Code)`; JSON with `loggedIn` and `authMethod`. |

## Decisions for the adapter

1. **Runtime.** User-installed: resolve `~/.local/bin/claude`, then the login-shell `PATH`. Settings shows the detected version and the login state from `auth status`, with no install button. A missing login is informational: Settings shows it, and Claude Code shows its own login prompt in the terminal.
2. **Session identity.** `makeSessionID` is a lowercase UUID, `prepareSession` is a no-op. New session: `claude --session-id <id> --name <task title> --settings <hooks json> -- <prompt>`, with the prompt passed after `--` because Claude Code reads a leading `-` as an option. Resume: `claude --resume <id> --settings <hooks json>`. The id is in SQLite before the process exists. `sessionExists` globs for the file; no file means the session never got a prompt, and the resumer offers Start Fresh as it does for Pi.
3. **Activity.** Two inputs feed one `AgentActivityTracker` per task. A `TerminalTitleScanner` next to `TerminalProgressScanner` reads OSC 0 titles off the pty bytes and maps the leading glyph: spinner frames are working, U+2733 is idle. A loopback `ClaudeCodeHookServer` (Network framework listener on 127.0.0.1, ephemeral port, one unguessable path per task) receives `PermissionRequest` as needs-input and `Stop`, `StopFailure` and `SessionEnd` as idle. The next busy title clears needs-input, which is what happens when the user answers the prompt. A new `AgentActivitySource` case describes this combination; the manager attaches the title scanner like the progress scanner and the adapter puts the server's URL into `--settings`. Hooks that cannot reach PiBoard fail silently and Claude keeps working. The listener starts asynchronously at app launch and in `prepareSession`; `--settings` is omitted when it is not up (needs-input is then unavailable, nothing else changes). A settle is suppressed while needs-input is pending so a permission prompt never reads as finished.
4. **Deletion.** Remove `~/.claude/projects/*/<id>.jsonl` and nothing else; `plannedSessionRemoval` names the file so the deletion sheet shows it. This is the same exception Pi already has to the "never write the tool's data directory" rule and it needs the owner's sign-off before it is coded. `memory/` and the project folder stay.
5. **Commit messages.** `ClaudeCodeCommitMessageGenerator` runs `-p --tools "" --no-session-persistence --output-format text --max-turns 1 --system-prompt ...` with the prompt as a positional argument after `--` (not stdin) and an optional `--model` from Settings. No file and no session are left behind. Pi stays the default.
6. **Summary.** A `ClaudeSessionReader` parses the JSONL: name from `custom-title`, turns from user entries with text, last assistant text from the newest `assistant` entry with a text block, usage summed from `assistant.message.usage`, cost from the last `cost-state`. `SessionSummary` fits without changes.
7. **Names.** `--name` gets the task title. The live-session suffix on a collision is cosmetic.

## Open items

- Interactive `--resume <id>` when no file exists yet (launched, never prompted): behaviour unverified; the resumer should not reach it because `sessionExists` returns false.
- Esc on a pending permission prompt: whether `Stop` fires is unverified. If it does not, needs-input stays until the next prompt or the next busy title.
- Other spinner frames (U+25D2, U+25D3) were not observed in the short turns; the scanner treats only U+25D0, U+25D1, U+25D2 and U+25D3 as busy and U+2733 as idle, and ignores any other title.
- `claude rm <id>` on a foreground session id was not tested.
- The probe used for the spike lived in `/tmp/piboard-spike/pty_hook_probe.py` (a pty plus a loopback http hook sink). Recreate it if the title or hook behaviour needs rechecking on a new version.
