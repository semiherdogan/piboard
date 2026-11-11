# Pi RPC adapter: spike findings

Verified 11 November 2026 against Pi 1.5.2 (PiBoard's own install, run under the bundled Node), on macOS 27. Model in the runs: `openai/gpt-6.1-sol`, thinking level `medium`, the user's real `~/.pi/agent` config. Result: usable as a headless control channel; nothing here is wired into the app yet.

Protocol docs ship with Pi under `node_modules/@earendil-works/pi-coding-agent/docs/` (`rpc.md`, `rpc-commands.md`, `rpc-extension-ui.md`, `json.md`). This file records what was observed, not what the docs promise.

## How RPC mode is shaped

- Launch: `node <pi>/dist/bundle/cli.js --mode rpc --session-dir <dir> [--session-id <uuid> --name <title> | --session <uuid>] [--approve]`, cwd is the project folder.
- Transport: one JSON object per line on stdin and stdout, strict LF framing. Parse the raw bytes and split on `\n` only; U+2028 and U+2029 may appear inside JSON strings.
- Commands carry an optional `id`; the matching `{"type":"response","command":...,"success":...,"id":...}` echoes it. An `id` does not mean "response": `extension_ui_request` always carries its own `id` (answer it with that id), and `bash_execution_update` repeats the command id. Route `response` by `type` plus id, and answer each `extension_ui_request` by its own id.
- Extension output (`setStatus`, `notify`, dialogs) arrives as `extension_ui_request` events, answered with `extension_ui_response`.
- stderr carries warnings only; stdout is protocol only.

## Verified calls

| Need | Call | Verified behaviour |
| --- | --- | --- |
| New session with PiBoard's id | flags `--session-id <uuid> --name "<title>"` | `get_state` returns `sessionId` equal to the uuid, `sessionName` equal to the title, `sessionFile` `<session-dir>/<start timestamp>_<uuid>.jsonl`. stderr prints `Warning: No project session found with id '<uuid>'; creating a new session with that id.` (harmless, exit stays 0). |
| State | `get_state` | About 0.6 s after spawn (startup). Keys: `model`, `thinkingLevel`, `isStreaming`, `isCompacting`, `steeringMode`, `followUpMode`, `sessionFile`, `sessionId`, `sessionName`, `autoCompactionEnabled`, `messageCount`, `pendingMessageCount`. `model` has `id`, `provider`, `reasoning`, `input` (`["text","image"]`), `contextWindow` (272000), plus more. `messageCount` was 1 before any prompt (a custom message). |
| Session file timing | none | The file does not exist after spawn or after `get_state`. It exists after the first prompt finished. Header line: `{"type":"session","version":3,"id":<uuid>,"timestamp":...,"cwd":"/private/tmp/..."}`; `cwd` is the symlink-resolved path. |
| Send a prompt | `prompt` `{"message":"..."}` | Response in 31 ms: `data.disposition` is `"started"`. Completion is the `agent_settled` event, not the response. |
| Turn events | (stream) | See "Event sequence". "pong" prompt: 4.8 s from send to `agent_settled`, text deltas joined are `pong`. |
| History | `get_messages` | `data.messages`. Roles seen: `custom`, `system`, `user`, `assistant`, `toolResult`. See "Message shapes". |
| Usage | `get_session_stats` | `userMessages`, `assistantMessages`, `toolCalls`, `toolResults`, `totalMessages`, `tokens` (`input`, `output`, `cacheRead`, `cacheWrite`, `total`), `cost` (USD number), `contextUsage` (`tokens`, `contextWindow`, `percent`), `sessionFile`, `sessionId`. After one "pong" turn: 6863 input tokens, 5 output, cost 0.0138. |
| Abort | `abort` | Response in 5 ms, `agent_settled` arrives in the same millisecond with `aborted: true`. |
| Steer | `steer` `{"message":"..."}` | Response `data.disposition` is `"queued"` in 1 ms. See "Steer". |
| Image | `prompt` with `"images":[{"type":"image","data":"<base64>","mimeType":"image/png"}]` | `disposition: started`. The user `message_start` echoes the image block. A 64x64 solid red PNG was answered "Red". The first 1x1 red PNG was answered "White", so tiny images are not a reliable test. |
| Models | `get_available_models` | 78 models (user's configured providers); first three `openai/chat-latest`, `openai/gpt-4`, `openai/gpt-4-turbo`. Model keys: `id`, `name`, `api`, `provider`, `baseUrl`, `reasoning`, `input`, `cost`, `contextWindow`, `maxTokens`, `compat`, `inputLimits`, `type`. |
| Thinking levels | `get_available_thinking_levels` | `data.levels` is `["low","medium","high","xhigh","max"]` for the active model. |
| Set thinking level | `set_thinking_level` `{"level":"low"}` | 1 ms, success; `get_state.thinkingLevel` is `low` afterwards; a `thinking_level_change` entry is appended to the session file, and a `thinking_level_changed` event arrives on stdout. |
| Shutdown | close stdin | Process exited with code 0 in 7 to 16 ms (all measured while idle), stderr empty apart from the startup warning. No signal needed when idle. |
| Resume | `--session <uuid>` with the same `--session-dir` | Found by id (no warning). `get_state` has the same `sessionId`, `sessionFile`, `sessionName`, restored `thinkingLevel` (`low`, as left), `messageCount` 12. `get_messages` returned all 12 earlier messages. A further prompt appended to the same file (18 lines at shutdown) and no second file was created. Opening the resumed session alone appended a `custom` entry (`active_agent`) from a user extension before any prompt, so resume can modify the file. |
| Project extension, no saved decision | no flag | `get_commands` lists 23 commands (user extensions and skills) and no `spike-confirm`. stderr empty: the project extension is skipped silently. Only the case with no saved decision was observed. |
| Project extension, trusted | `--approve` | `get_commands` lists `spike-confirm` with `source: "extension"`, `sourceInfo.scope: "project"`, `sourceInfo.path` of the project `.pi/extensions/spike.ts`. Total 24. |
| Extension dialog | `prompt` `/spike-confirm` | `extension_ui_request` `{"type":"extension_ui_request","id":"<uuid>","method":"confirm","title":"Spike","message":"Proceed?"}`. Reply `{"type":"extension_ui_response","id":"<same id>","confirmed":true}`; then a `notify` request `{"method":"notify","message":"confirmed: true"}`; then the prompt response with `disposition: "handled"`. No `agent_start`, no `agent_settled`. |
| Dialog cancelled | same, reply `{"type":"extension_ui_response","id":...,"cancelled":true}` | Extension sees `false`: notify says `confirmed: false`. Prompt response `handled`. |
| File mention | prompt `Summarise @README.md in five words.` | Passed through verbatim: the user `message_start` content is the single text block as typed. The model then called the `read` tool itself (`args: {"path":"README.md","offset":null,"limit":null}`) and answered "Tiny project for RPC experimentation." |
| Built-in TUI command | prompt `/help`, `/settings` | `disposition: started`: sent to the model as plain text, no error. `/settings` (a built-in per `slash-commands.md`) was answered by the model ("`/settings` reached me as a message"). `/help` is not a Pi built-in, so it was just text. |

## Event sequence

Plain turn ("Reply with exactly the word pong."), collapsed consecutive duplicates:

```
response(started) agent_start turn_start
message_start(system) message_end message_start(user) message_end
message_start(assistant) message_update:text_start message_update:text_delta message_update:text_end message_end
extension_ui_request x2 turn_end agent_end agent_settled
```

- Timings: response at 31 ms, assistant `message_start` at about 3.4 s (not time to first token), `agent_settled` at 4.8 s. In the image turn the prompt was sent at t=595 and the first `text_start` came at t=5221, 4.6 s later.
- A turn with reasoning also emits `message_update:thinking_start`, `thinking_delta` and `thinking_end` before the text updates (image turn, A-new-session.jsonl t=23418 to 28474).
- `agent_settled` has `{"type":"agent_settled","aborted":false}`. It comes after `agent_end`; treat it, not `agent_end`, as "idle".
- The two `extension_ui_request` events after each assistant message are `setStatus` updates from the user's own extensions (`claude-usage`, `context-rollover`, ...), with `statusKey` and an ANSI-colored `statusText`. At startup, before any command, several more `setStatus` events arrive. A client must ignore unknown methods.
- Tool turn (`@README.md`): `toolcall_start`, 14 `toolcall_delta`, `toolcall_end`, assistant `message_end`, `tool_execution_start`, `tool_execution_end`, a `message_start`/`message_end` for the tool result, `turn_end`, then a second `turn_start` with the text reply, `turn_end`, `agent_end`, `agent_settled`.

## Message shapes

- Top-level keys by role: `custom` (`role`, `customType`, `content` string, `display`, `timestamp`); `system` (`role`, `content` empty string, `sections`, `timestamp`, `toolsAdded`); `user` (`role`, `content` array of `text` and `image` blocks, `timestamp`); `assistant` (`role`, `content`, `api`, `provider`, `model`, `usage`, `stopReason`, `timestamp`, `responseId`, `rawStopReason`, `durationMs`, `thinkingLevel`).
- Assistant content block types seen: `thinking` (image turn, content was `thinking,text`), `text` (with a `textSignature` JSON string), `toolCall`.
- `usage`: `input`, `output`, `cacheRead`, `cacheWrite`, `reasoning`, `totalTokens`, `cost` (`input`, `output`, `cacheRead`, `cacheWrite`, `total`, `totalFromProvider`).
- The `system` message in `get_messages` and in `agent_end` is large (tool list, sections). Do not log it.

## Abort

- Prompt "Write the numbers 1 to 200", `abort` after the first `text_delta`: response success in 5 ms, `agent_settled.aborted` is `true` in the same millisecond, and the response frame arrives after `agent_settled` in the stream.
- Sequence tail: `text_delta`, `message_end`, `extension_ui_request x2`, `turn_end`, `agent_end`, `agent_settled`, `response`.
- The aborted assistant message in `get_messages`: `stopReason: "aborted"`, `errorMessage: "OpenAI Responses stream ended before a terminal response event"`, partial text kept (here just `1`), `usage` all zero. Pi recorded zero usage for the aborted turn although the stream ran about 3.8 s, so session cost under-reports aborted turns.

## Steer

- Prompt "Write the numbers 1 to 100", `steer` after the first delta: response `{"disposition":"queued"}`.
- `queue_update` `{"steering":["Stop counting ..."],"followUp":[]}` at once, and `{"steering":[],"followUp":[]}` when the message is consumed.
- Steering does not interrupt the running assistant message. The first reply streamed to the end (all 100 numbers, `stopReason: "stop"`), then a new `turn_start`, the queue cleared, the steer text became a user message and the assistant replied `steered`. One `agent_settled` for the whole run.

## Decisions for the adapter

1. **Session id.** `--session-id <uuid>` makes the id ours before spawn, which fits the invariant. The file appears only after the first completed prompt, so existence checks must not run before that. Whether `PiSessionLocator` finds it by the `_<uuid>.jsonl` suffix is to be verified, as is the default dir (`~/.pi/agent/sessions`). Project settings can set `sessionDir` (security.md line 55). Add `--session-dir` only if PiBoard wants isolation.
2. **Warning on stderr.** A new `--session-id` always prints the "No project session found" warning. Do not treat stderr output as failure.
3. **Idle detection.** `agent_settled` is the clean working-to-idle signal, with `aborted` for interrupts. Commands answered with `handled` (extension commands) emit no `agent_start` or `agent_settled`.
4. **Response is not completion.** `prompt` returns when the turn is accepted (`started`), or when a handled command finished (`handled`). Never await the response of a prompt that may open a dialog: the `/spike-confirm` response only arrives after the dialog is answered. Read stdout continuously and correlate by `id`.
5. **Dialogs.** Every UI method that expects an answer (`confirm`, and by the docs `select`, `input`, `editor`) blocks the command until an `extension_ui_response` with the same id arrives. A cancel is `{"cancelled":true}`. Fire-and-forget methods (`notify`, `setStatus`) need no reply. This maps onto the `needsInput` state.
6. **Trust.** Per `security.md` lines 61 to 80, precedence is: `--approve` or `--no-approve`, then an extension `project_trust` handler, then a saved decision in `~/.pi/agent/trust.json` (closest directory wins), then `defaultProjectTrust` (`"always"` loads; `"ask"` and `"never"` skip in RPC mode). Skipped project extensions give no stderr message. The spike only observed the case with no saved decision. Pass `--approve` only when the user granted trust inside PiBoard; otherwise pass no flag so Pi's own saved decision applies. Never pass `--no-approve`.
7. **Slash commands.** Extension and skill commands work through `prompt`. Built-in commands (list in `slash-commands.md`) are not guaranteed to run in RPC: `/settings` went to the model as text and burned tokens; the rest of the table was not tried. `/llama` and `/mcp` are listed there as built-ins, yet `get_commands` returned them as `extension` (results.json "10"). Use `get_commands` as the allowlist instead of a static filter.
8. **Cost.** Stats expose tokens and USD cost per session; the base prompt is about 6.9k input tokens, so even "pong" costs about 0.014 USD on this model. Cached input made later turns cheaper.
9. **Shutdown.** Closing stdin exited cleanly in 7 to 16 ms while idle. `rpc.md` line 93 says shutdown waits for pending work, so keep the usual SIGTERM then SIGKILL fallback after a grace period.
10. **Resume.** `--session <uuid>` plus the same session dir restores state and history and appends to the same file.

## Open items

- Without `--session-dir` the default location and encoded-cwd directory were not exercised; `PiSessionLocator` was not run against RPC-created files.
- `select`, `input`, `editor` dialogs and their cancel formats were not tried, only `confirm`.
- `follow_up`, `compact`, `new_session`, `switch_session`, `fork`, `get_last_assistant_text`, `bash` commands were not exercised.
- Whether an unanswered dialog has a timeout: closing stdin during one exited at once, but a live process waiting was only observed for 20 s without any timeout.
- Aborting mid-tool-call (not just mid-text) was not tried.
- Whether the first 1x1 image answered "White" is a model limitation or a Pi resize was not isolated.
- Behaviour with an expired provider login or no default model is untested.
