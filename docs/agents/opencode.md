# OpenCode adapter: spike findings

Verified 28 October 2026 against OpenCode v2.2.0 installed at `~/.opencode/bin/opencode` (official installer, not npm), on macOS 27. Result: go. The v1 documentation this plan was first written against (`serve`, `attach <url>`, no client-chosen ids) no longer applies.

## How v2 is shaped

- One shared background server per user: `opencode serve --service`, started on demand by any client. `opencode service status` prints its URL (for example `http://127.0.0.1:49374`; the port changes between starts). `opencode service start|stop|restart|get|set|unset` manage it.
- HTTP basic auth: user `opencode`, password in `~/.config/opencode/service.json` (`{"password": "..."}`). PiBoard reads that file read-only.
- `--standalone` runs a private server; `--server <url>` connects to an explicit one and then needs `OPENCODE_PASSWORD` in the environment (it does not read `service.json`).
- The API lives under `/api/...`; the OpenAPI document is `GET /openapi.json` (about 320 KB). Everything the TUI does goes through this API.
- Sessions live in `~/.local/share/opencode/opencode.db` (SQLite). PiBoard never opens it; everything goes through the API.
- Data paths: `opencode debug paths` prints data, config, cache, state, log and db locations.

## Verified calls

| Need | Call | Verified behaviour |
| --- | --- | --- |
| Create a session with PiBoard's id | `POST /api/session` body `{"id":"ses_<32 hex>","title":"<task title>","location":{"directory":"<cwd>"}}` | 200 with the session; `Session.ID` must match `^ses`, a raw UUID is rejected (`InvalidRequestError`). Without `location` the session lands in the server's home directory. |
| Does the session exist | `GET /api/session/{id}` | 200 with `{"data":{...}}`; missing id returns `{"_tag":"SessionNotFoundError",...}` |
| Sessions of a directory | `GET /api/session?directory=<cwd>` | Only sessions whose `location.directory` matches |
| Delete | `DELETE /api/session/{id}` | 204; afterwards GET is 404 |
| Launch the TUI on that session | pty child `opencode --session <id> <cwd>` | Opens the pre-created session (title visible, no second session created). `--session <new id>` alone does not create a row until the first prompt; `opencode run -s <new id>` does create it, in the cwd. |
| Activity | `GET /api/event?types=session.execution.started&types=session.execution.succeeded&types=session.execution.failed&types=session.execution.interrupted&types=permission.asked&types=form.created` (SSE, repeated `types` accepted) | First event `server.connected`, then `: heartbeat` comments. Observed for one turn: `session.execution.started` then `session.execution.failed`, both with `data.sessionID`. `succeeded` and `interrupted` are the same family in the enum and were not observed because the free model's quota was exhausted. |
| Is anything running | `GET /api/session/active` | `{"data":{"<sessionID>":{"type":"running"}}}`; sessions absent are idle |
| Wait for idle | `POST /api/experimental/session/{id}/wait` | Blocks until the agent loop is idle; returned at once for a failed turn |
| Prompt without the TUI | `POST /api/session/{id}/prompt` body `{"text":"..."}` | 200 with the user message; `text` is required, there is no `parts` array |
| Summary data | `GET /api/session/{id}` | `title`, `tokens` (`input`, `output`, `reasoning`, `cache.read`, `cache.write`), `cost`, `time.created/updated`, `outcome`; messages via `GET /api/session/{id}/message` |

Full event type list is in the `types` query parameter enum of `/api/event` in `openapi.json`. It also has `session.idle` and `session.status`; neither fired in the observed failed turn.

The event stream is volatile by contract: a slow consumer is disconnected and events during a disconnection are lost. After a reconnect, `GET /api/session/active` resynchronises the Working state.

## Decisions for the adapter

1. **Server.** Use the user's shared background service, discovered with `opencode service status` (start it with `opencode service start` when the output is empty), password from `service.json`. This is how every OpenCode client works, so the user's own `opencode` sees PiBoard's sessions and no second server competes for the database. A PiBoard-owned `opencode serve --port` with `--server` on the TUI stays as a fallback if the shared service proves unreliable.
2. **Session identity.** PiBoard generates `ses_` plus a lowercase UUID without dashes, sends `POST /api/session` with that id, the task title and the cwd, writes the id to SQLite, then spawns the TUI. The server call comes first so a failed call leaves no dangling id in SQLite; the id still exists before the process does, which keeps the invariant. `prepareSession` is therefore async and can fail (server unreachable), which the preparation sheet shows like a missing runtime.
3. **Activity.** One SSE connection per PiBoard run, filtered to the execution, permission and form events, demultiplexed by `data.sessionID` into each task's `AgentActivityTracker`. `started` is working; `succeeded`, `failed`, `interrupted` are idle; `permission.asked` and `form.created` raise `needsInput`. No OSC scanning for this agent.
4. **Runtime.** OpenCode is user-installed: the official installer puts it at `~/.opencode/bin/opencode`, it self-updates with `opencode upgrade`, and it owns a background service. A PiBoard-managed versioned copy would run a second version against the same database, so the adapter resolves the binary from `~/.opencode/bin/opencode`, then the login-shell `PATH`, and Settings shows the detected version with no install button. Phase 7 step 2 shrinks to that.
5. **Deletion.** `DELETE /api/session/{id}` through the adapter; `DeletionActions` calls `deleteSession` instead of removing a file. Pi keeps its file delete.
6. **Commit messages.** `OpenCodeCommitMessageGenerator` creates a throwaway session, calls `POST /api/session/{id}/generate` with the prompt and deletes the session. Verified 30 October 2026 on v2.2.2: no tools run, no history is kept, and the session is gone afterwards.
7. **Summary.** `GET /api/session/{id}` supplies name, tokens and cost directly; the last assistant text comes from the newest assistant message in `/message`. `SessionSummary` fits without changes.

## Open items

- Observe one successful turn (after the free quota resets, or with a paid model) to confirm `session.execution.succeeded` and whether `session.idle` or `session.status` add anything.
- Permission prompts and forms render inside the TUI; confirm the SSE `permission.asked` fires for a TUI-driven turn, not only API-driven ones.
- `service.json` password rotation: re-read the file on a 401.
