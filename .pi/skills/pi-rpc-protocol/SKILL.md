---
name: pi-rpc-protocol
description: "Reference for the pi --mode rpc JSON protocol: strict JSONL framing (LF-only delimiter, stdout redirected to stderr), all commands sent to stdin (prompt, steer, follow_up, abort, new_session, get_state, set_model, cycle_model, get_available_models, set_thinking_level, compact, set_auto_compaction, set_auto_retry, bash, get_session_stats, export_html, switch_session, fork, get_commands), all events emitted to stdout (agent_start, agent_end, turn_start, turn_end, message_start, message_update, message_end, tool_execution_start, tool_execution_update, tool_execution_end, auto_compaction_start, auto_compaction_end, auto_retry_start, auto_retry_end, extension_error, model_select), extension UI sub-protocol, error responses, id correlation, and message_update delta types. Load when writing or debugging pi_acme Ada RPC communication or any subprocess integration with pi."
---

# pi RPC Protocol Reference

Source of truth: `dist/modes/rpc/rpc-mode.js`, `dist/modes/rpc/rpc-types.d.ts`,
`dist/modes/rpc/rpc-client.js`, `dist/modes/rpc/jsonl.js`,
`dist/core/agent-session.d.ts` in the `@mariozechner/pi-coding-agent` package.
The official narrative docs are in `docs/rpc.md` (same package).

---

## Invocation

```
pi --mode rpc [OPTIONS]
```

Relevant CLI options:

| Flag | Meaning |
|------|---------|
| `--session UUID` | Resume an existing session |
| `--model PROVIDER/ID` | Select model at startup |
| `--system-prompt PATH` | Path to a `.agent.md` system-prompt file |
| `--no-session` | Disable session persistence (useful in tests) |
| `--no-tools` | Disable all built-in tools |
| `--no-extensions` | Do not load any extensions |
| `--extension PATH` | Load one TypeScript extension |
| `--session-dir PATH` | Override session storage directory |
| `--thinking LEVEL` | Initial thinking level |

---

## Transport & Framing

- **stdin** → commands (one JSON object per line)
- **stdout** → events and responses (one JSON object per line)
- **stderr** → pi diagnostics / logging

**Critical:** pi's RPC mode immediately redirects `process.stdout` to
`process.stderr`:

```js
process.stdout.write = ((...args) => rawStderrWrite(...args));
```

This means every `console.log`, diagnostic, and third-party library that
writes to stdout is silently rerouted to stderr. Only the explicit
`output(obj)` calls in `rpc-mode.js` produce real stdout lines.

### JSONL framing rules (from `jsonl.js`)

- Records are delimited by `\n` (LF) **only**.
- A trailing `\r` is stripped from each line before parsing (tolerates
  CRLF input from Windows clients).
- **Never** split on U+2028 or U+2029 — those characters are valid inside
  JSON strings. Node's `readline` is non-compliant for this reason; the
  `attachJsonlLineReader` helper was written to replace it.
- Each output record is `JSON.stringify(obj) + "\n"`.

---

## Request / Response Correlation

Every command may carry an optional `id` field (any string). If present,
the response will echo the same `id`. Events never carry an `id`.

```json
{"id": "req-1", "type": "prompt", "message": "Hello"}
```

```json
{"id": "req-1", "type": "response", "command": "prompt", "success": true}
```

---

## Commands (stdin → pi)

All commands are JSON objects with a `"type"` field and an optional `"id"`.

### Prompting

#### `prompt`
Send a user prompt. Returns immediately; LLM response streams as events.

```json
{"type": "prompt", "message": "Fix the bug in foo.c"}
```

With images:
```json
{"type": "prompt", "message": "What is in this image?",
 "images": [{"type": "image", "data": "<base64>", "mimeType": "image/png"}]}
```

If the agent is already streaming you **must** add `streamingBehavior`:
- `"steer"` — deliver after current tool-call batch, before next LLM call
- `"followUp"` — deliver only when agent fully finishes

Without `streamingBehavior` while streaming, the command returns an error.

Extension commands (`/mycommand`) execute immediately even during streaming.
Skill commands (`/skill:name`) and prompt templates are expanded before sending.

Response: `{"type":"response","command":"prompt","success":true}`

#### `steer`
Queue a mid-run steering message (equivalent to `prompt` + `streamingBehavior:"steer"`).
Skill commands and templates are expanded. Extension commands are **not** allowed.

```json
{"type": "steer", "message": "Stop and do this instead"}
```

Response: `{"type":"response","command":"steer","success":true}`

#### `follow_up`
Queue a follow-up after the agent finishes.

```json
{"type": "follow_up", "message": "After you are done, also do Y"}
```

Response: `{"type":"response","command":"follow_up","success":true}`

#### `abort`
Abort the current operation.

```json
{"type": "abort"}
```

Response: `{"type":"response","command":"abort","success":true}`

#### `new_session`
Start a fresh session. Can be cancelled by a `session_before_switch` extension handler.

```json
{"type": "new_session"}
{"type": "new_session", "parentSession": "/path/to/parent.jsonl"}
```

Response:
```json
{"type":"response","command":"new_session","success":true,"data":{"cancelled":false}}
```

---

### State

#### `get_state`
Returns current session state.

```json
{"type": "get_state"}
```

Response `data`:
```json
{
  "model": {/* Model object, or null */},
  "thinkingLevel": "medium",
  "isStreaming": false,
  "isCompacting": false,
  "steeringMode": "all",
  "followUpMode": "one-at-a-time",
  "sessionFile": "/path/to/session.jsonl",
  "sessionId": "abc12345",
  "sessionName": "my-work",
  "autoCompactionEnabled": true,
  "messageCount": 5,
  "pendingMessageCount": 0
}
```

`sessionName` is omitted if not set. `model` is a full **Model** object (see below) or `null`.

#### `get_messages`
Returns all messages in the conversation.

```json
{"type": "get_messages"}
```

Response `data`: `{"messages": [/* AgentMessage array */]}`

---

### Model

#### `set_model`
Switch to a specific model. Validates that the model is in the registry and
that an API key is available.

```json
{"type": "set_model", "provider": "anthropic", "modelId": "claude-sonnet-4-20250514"}
```

Response `data`: full **Model** object.

Error if not found: `{"success":false,"error":"Model not found: anthropic/bad-id"}`

#### `cycle_model`
Cycle to the next available model (uses `--models` scoped list if set).
Returns `null` data when only one model is available.

```json
{"type": "cycle_model"}
```

Response `data`:
```json
{"model": {/* Model */}, "thinkingLevel": "medium", "isScoped": false}
```

#### `get_available_models`
List all configured models.

```json
{"type": "get_available_models"}
```

Response `data`: `{"models": [/* Model array */]}`

---

### Thinking

Valid thinking levels: `"off"` `"minimal"` `"low"` `"medium"` `"high"` `"xhigh"`
(`"xhigh"` is only supported by OpenAI codex-max models.)

#### `set_thinking_level`

```json
{"type": "set_thinking_level", "level": "high"}
```

Response: `{"type":"response","command":"set_thinking_level","success":true}`

#### `cycle_thinking_level`
Cycles through available levels. Returns `null` data if the model does not
support thinking.

```json
{"type": "cycle_thinking_level"}
```

Response `data`: `{"level": "high"}` or `null`

---

### Queue Modes

#### `set_steering_mode`
Controls how steering messages are delivered.

- `"all"` — deliver all queued steers after the current tool-call batch
- `"one-at-a-time"` — deliver one steer per completed assistant turn (default)

```json
{"type": "set_steering_mode", "mode": "one-at-a-time"}
```

#### `set_follow_up_mode`

- `"all"` — deliver all follow-ups when agent finishes
- `"one-at-a-time"` — deliver one follow-up per agent completion (default)

```json
{"type": "set_follow_up_mode", "mode": "all"}
```

Both respond: `{"type":"response","command":"set_steering_mode","success":true}` etc.

---

### Compaction

#### `compact`
Manually compact the conversation context. Aborts any current agent operation first.

```json
{"type": "compact"}
{"type": "compact", "customInstructions": "Focus on code changes only"}
```

Response `data`:
```json
{
  "summary": "Summary of the conversation...",
  "firstKeptEntryId": "abc123",
  "tokensBefore": 150000,
  "details": {}
}
```

#### `set_auto_compaction`

```json
{"type": "set_auto_compaction", "enabled": true}
```

---

### Retry

#### `set_auto_retry`
Enable/disable automatic retry on transient errors (overloaded, rate limit, 5xx).

```json
{"type": "set_auto_retry", "enabled": true}
```

#### `abort_retry`
Cancel an in-progress retry delay.

```json
{"type": "abort_retry"}
```

---

### Bash

#### `bash`
Execute a shell command, adding output to the agent's conversation context.

```json
{"type": "bash", "command": "ls -la"}
```

Response `data`:
```json
{
  "output": "total 48\n...",
  "exitCode": 0,
  "cancelled": false,
  "truncated": false
}
```

When truncated: `"truncated": true, "fullOutputPath": "/tmp/pi-bash-abc.log"`

**Important:** The bash output is included in the LLM context only on the
*next* `prompt` call, not immediately. No event is emitted for it.

#### `abort_bash`

```json
{"type": "abort_bash"}
```

---

### Session Management

#### `get_session_stats`

```json
{"type": "get_session_stats"}
```

Response `data`:
```json
{
  "sessionFile": "/path/to/session.jsonl",
  "sessionId": "abc12345",
  "userMessages": 5,
  "assistantMessages": 5,
  "toolCalls": 12,
  "toolResults": 12,
  "totalMessages": 22,
  "tokens": {
    "input": 50000,
    "output": 10000,
    "cacheRead": 40000,
    "cacheWrite": 5000,
    "total": 105000
  },
  "cost": 0.45
}
```

**Token counting note:** The full context sent to the API per turn equals
`input + cacheRead + cacheWrite`. Using only `input` understates the context
after the first turn because most tokens are served from cache.

#### `export_html`

```json
{"type": "export_html"}
{"type": "export_html", "outputPath": "/tmp/session.html"}
```

Response `data`: `{"path": "/tmp/session.html"}`

#### `switch_session`
Load a different session file. Can be cancelled by an extension.

```json
{"type": "switch_session", "sessionPath": "/path/to/session.jsonl"}
```

Response `data`: `{"cancelled": false}`

#### `fork`
Create a new fork from a previous user message entry.

```json
{"type": "fork", "entryId": "abc123ef"}
```

Response `data`: `{"text": "The original prompt...", "cancelled": false}`

#### `get_fork_messages`
Get the list of user messages available for forking.

```json
{"type": "get_fork_messages"}
```

Response `data`:
```json
{"messages": [{"entryId": "abc123ef", "text": "First prompt..."}]}
```

#### `get_last_assistant_text`

```json
{"type": "get_last_assistant_text"}
```

Response `data`: `{"text": "The assistant's response..."}` or `{"text": null}`

#### `set_session_name`
Set a display name for the current session (must be non-empty).

```json
{"type": "set_session_name", "name": "my-feature-work"}
```

Response: `{"type":"response","command":"set_session_name","success":true}`

---

### Commands

#### `get_commands`
List all invocable commands (extension commands, prompt templates, skills).

```json
{"type": "get_commands"}
```

Response `data`:
```json
{
  "commands": [
    {"name": "fix-tests", "description": "Fix failing tests",
     "source": "prompt", "location": "project", "path": "/proj/.pi/agent/prompts/fix-tests.md"},
    {"name": "skill:brave-search", "description": "Web search",
     "source": "skill", "location": "user", "path": "/home/user/.pi/agent/skills/..."},
    {"name": "my-cmd", "source": "extension", "path": "/path/to/ext.ts"}
  ]
}
```

`source`: `"extension"` | `"prompt"` | `"skill"`
`location`: `"user"` | `"project"` | `"path"` (absent for extensions)

---

## Events (pi → stdout)

Events are streamed as JSON lines to stdout during agent operation. They do **not** carry an `id` field (only responses do). Both events and responses share the same stdout stream; distinguish them by `type === "response"`.

### Summary table

| `type` | When emitted |
|--------|-------------|
| `model_select` | Startup; model change |
| `agent_start` | `prompt` received, agent begins |
| `agent_end` | Agent fully done (one per user prompt) |
| `turn_start` | New LLM call begins |
| `turn_end` | LLM call + its tool calls complete |
| `message_start` | Message begins streaming |
| `message_update` | Streaming delta (text / thinking / tool call) |
| `message_end` | Message fully received (contains usage) |
| `tool_execution_start` | Tool begins executing |
| `tool_execution_update` | Tool streams partial output |
| `tool_execution_end` | Tool done |
| `auto_compaction_start` | Auto-compaction triggered |
| `auto_compaction_end` | Auto-compaction finished |
| `auto_retry_start` | Transient error, retry scheduled |
| `auto_retry_end` | Retry succeeded or failed |
| `extension_error` | Extension threw an error |

---

### `model_select`
Emitted at startup (before any response) and whenever the model changes.

```json
{
  "type": "model_select",
  "model": {
    "id": "claude-sonnet-4-20250514",
    "name": "Claude Sonnet 4",
    "provider": "anthropic",
    "contextWindow": 200000,
    "maxTokens": 16384,
    "reasoning": true,
    "input": ["text", "image"],
    "cost": {"input": 3.0, "output": 15.0, "cacheRead": 0.3, "cacheWrite": 3.75}
  }
}
```

### `agent_start`

```json
{"type": "agent_start"}
```

### `agent_end`
Emitted exactly once per user prompt when all turns complete.
Contains the full list of messages generated during the run. Clients that
only need the live stream can ignore the `messages` array (it can be large).

```json
{"type": "agent_end", "messages": [/* AgentMessage array */]}
```

### `turn_start` / `turn_end`
One turn = one LLM call + all resulting tool calls.

```json
{"type": "turn_start"}
```

```json
{"type": "turn_end", "message": {/* AssistantMessage */}, "toolResults": [/* ... */]}
```

### `message_start` / `message_end`

```json
{"type": "message_start", "message": {/* AgentMessage */}}
{"type": "message_end",   "message": {/* AgentMessage — includes usage */}}
```

The `message_end` `message.usage` object:
```json
{
  "input": 100,
  "output": 50,
  "cacheRead": 40000,
  "cacheWrite": 5000,
  "cost": {"input": 0.0003, "output": 0.00075, "cacheRead": 0, "cacheWrite": 0, "total": 0.00105}
}
```

Full context for a turn = `input + cacheRead + cacheWrite`.

### `message_update` (streaming deltas)

```json
{
  "type": "message_update",
  "message": {/* partial AgentMessage */},
  "assistantMessageEvent": { "type": "<delta-type>", ... }
}
```

The `message` field contains the cumulative partial message. The
`assistantMessageEvent.partial` field (a full partial message) can be large;
clients that do not need it should discard it.

Delta types for `assistantMessageEvent`:

| `type` | Meaning | Key extra fields |
|--------|---------|-----------------|
| `start` | Streaming started | — |
| `text_start` | Text block opened | `contentIndex` |
| `text_delta` | Text chunk | `contentIndex`, `delta` |
| `text_end` | Text block closed | `contentIndex`, `content` |
| `thinking_start` | Thinking block opened | `contentIndex` |
| `thinking_delta` | Thinking chunk | `contentIndex`, `delta` |
| `thinking_end` | Thinking block closed | `contentIndex` |
| `toolcall_start` | Tool call started | `contentIndex` |
| `toolcall_delta` | Tool call arg chunk | `contentIndex`, `delta` |
| `toolcall_end` | Tool call complete | `contentIndex`, `toolCall` |
| `done` | Message generation done | `stopReason` |
| `error` | Error during generation | `reason` (`"aborted"` or `"error"`) |

Stop reasons: `"stop"`, `"length"`, `"toolUse"`, `"error"`, `"aborted"`

### `tool_execution_start`

```json
{
  "type": "tool_execution_start",
  "toolCallId": "call_abc123",
  "toolName": "bash",
  "args": {"command": "ls -la"}
}
```

### `tool_execution_update`
Partial (streaming) tool output. `partialResult` contains *accumulated* output so far.

```json
{
  "type": "tool_execution_update",
  "toolCallId": "call_abc123",
  "toolName": "bash",
  "args": {"command": "ls -la"},
  "partialResult": {
    "content": [{"type": "text", "text": "partial output so far..."}],
    "details": {"truncation": null, "fullOutputPath": null}
  }
}
```

### `tool_execution_end`

```json
{
  "type": "tool_execution_end",
  "toolCallId": "call_abc123",
  "toolName": "bash",
  "result": {
    "content": [{"type": "text", "text": "total 48\n..."}],
    "details": {"truncation": null, "fullOutputPath": null}
  },
  "isError": false
}
```

When `isError: true`, `result` may contain the error text. For error display,
use the first line of `result` content (up to ~80 chars).

### `auto_compaction_start` / `auto_compaction_end`

```json
{"type": "auto_compaction_start", "reason": "threshold"}
```

`reason`: `"threshold"` (context large) or `"overflow"` (context exceeded limit).

```json
{
  "type": "auto_compaction_end",
  "result": {"summary": "...", "firstKeptEntryId": "abc", "tokensBefore": 150000, "details": {}},
  "aborted": false,
  "willRetry": false
}
```

`willRetry: true` when `reason` was `"overflow"` and compaction succeeded —
pi will automatically re-send the prompt.
`result` is `null` and `aborted: true` if the user cancelled.
`result` is `null` and `errorMessage` present if compaction failed.

### `auto_retry_start` / `auto_retry_end`

```json
{
  "type": "auto_retry_start",
  "attempt": 1,
  "maxAttempts": 3,
  "delayMs": 2000,
  "errorMessage": "529 overloaded_error: Overloaded"
}
```

```json
{"type": "auto_retry_end", "success": true, "attempt": 2}
```

Final failure:
```json
{"type": "auto_retry_end", "success": false, "attempt": 3, "finalError": "529 overloaded_error: Overloaded"}
```

### `extension_error`

```json
{
  "type": "extension_error",
  "extensionPath": "/path/to/extension.ts",
  "event": "tool_call",
  "error": "Error message..."
}
```

---

## Error Responses

Failed commands:
```json
{
  "type": "response",
  "command": "set_model",
  "success": false,
  "error": "Model not found: bad/model"
}
```

JSON parse errors:
```json
{
  "type": "response",
  "command": "parse",
  "success": false,
  "error": "Failed to parse command: Unexpected token..."
}
```

Always check `success` before accessing `data`. Unknown commands also return
a `success: false` response with the unknown type in `error`.

---

## Extension UI Sub-Protocol

Extensions can request user interaction during a command. In RPC mode these
become a request/response exchange on top of the normal command/event stream.

Two categories:
- **Dialog** methods (`select`, `confirm`, `input`, `editor`): emit a request on
  stdout, then **block** until the client sends back a response on stdin with
  the matching `id`.
- **Fire-and-forget** methods (`notify`, `setStatus`, `setWidget`, `setTitle`,
  `set_editor_text`): emit a request on stdout, expect **no response**.

If a dialog request carries a `timeout` field (milliseconds), pi auto-resolves
with the default value when the timeout expires; the client does not need to
track timeouts.

### Requests (stdout)

All have `"type": "extension_ui_request"`, a unique `"id"`, and a `"method"`.

```json
{"type":"extension_ui_request","id":"uuid-1","method":"select",
 "title":"Allow dangerous command?","options":["Allow","Block"],"timeout":10000}

{"type":"extension_ui_request","id":"uuid-2","method":"confirm",
 "title":"Clear session?","message":"All messages will be lost."}

{"type":"extension_ui_request","id":"uuid-3","method":"input",
 "title":"Enter a value","placeholder":"type something..."}

{"type":"extension_ui_request","id":"uuid-4","method":"editor",
 "title":"Edit some text","prefill":"Line 1\nLine 2"}

{"type":"extension_ui_request","id":"uuid-5","method":"notify",
 "message":"Command blocked","notifyType":"warning"}

{"type":"extension_ui_request","id":"uuid-6","method":"setStatus",
 "statusKey":"my-ext","statusText":"Turn 3 running..."}

{"type":"extension_ui_request","id":"uuid-7","method":"setWidget",
 "widgetKey":"my-ext","widgetLines":["Line 1","Line 2"],
 "widgetPlacement":"aboveEditor"}

{"type":"extension_ui_request","id":"uuid-8","method":"setTitle",
 "title":"pi - my project"}

{"type":"extension_ui_request","id":"uuid-9","method":"set_editor_text",
 "text":"prefilled text"}
```

`notifyType`: `"info"` | `"warning"` | `"error"` (default `"info"`)
`widgetPlacement`: `"aboveEditor"` | `"belowEditor"` (default `"aboveEditor"`)
Clear a widget: send `"widgetLines": null` (or omit).
Clear a status: send `"statusText": null` (or omit).

### Responses (stdin) — dialog methods only

```json
{"type":"extension_ui_response","id":"uuid-1","value":"Allow"}
{"type":"extension_ui_response","id":"uuid-2","confirmed":true}
{"type":"extension_ui_response","id":"uuid-3","cancelled":true}
```

---

## Type Reference

### Model object

```json
{
  "id": "claude-sonnet-4-20250514",
  "name": "Claude Sonnet 4",
  "api": "anthropic-messages",
  "provider": "anthropic",
  "baseUrl": "https://api.anthropic.com",
  "reasoning": true,
  "input": ["text", "image"],
  "contextWindow": 200000,
  "maxTokens": 16384,
  "cost": {"input": 3.0, "output": 15.0, "cacheRead": 0.3, "cacheWrite": 3.75}
}
```

### AssistantMessage (from `message_end` / `agent_end`)

```json
{
  "role": "assistant",
  "content": [
    {"type": "text", "text": "Hello!"},
    {"type": "thinking", "thinking": "Internal reasoning..."},
    {"type": "toolCall", "id": "call_123", "name": "bash",
     "arguments": {"command": "ls"}}
  ],
  "api": "anthropic-messages",
  "provider": "anthropic",
  "model": "claude-sonnet-4-20250514",
  "usage": {"input": 100, "output": 50, "cacheRead": 0, "cacheWrite": 0},
  "stopReason": "stop",
  "timestamp": 1733234567890
}
```

### BashExecutionMessage (created by `bash` command, not tool calls)

```json
{
  "role": "bashExecution",
  "command": "ls -la",
  "output": "total 48\n...",
  "exitCode": 0,
  "cancelled": false,
  "truncated": false,
  "fullOutputPath": null,
  "timestamp": 1733234567890
}
```

---

## Bootstrap Sequence

On startup pi emits, before responding to any command:

1. A `model_select` event with the default model.

Best practice for clients:

```
1. Spawn: pi --mode rpc [flags]
2. Send:  {"type":"get_state"}
3. Read lines until response with command=="get_state" arrives.
   - Capture any model_select event that arrives first.
   - Extract sessionId, thinkingLevel, model from the get_state response data.
4. Begin normal command / event loop.
```

---

## pi_acme Implementation Notes

The Ada implementation uses the following mapping:

| Pi event | Ada handler |
|----------|-------------|
| `model_select` | Update `App_State.Current_Model`, `Context_Window` |
| `agent_start` | Set `Is_Streaming`, reset section, update status line |
| `agent_end` | Clear `Is_Streaming`, emit turn footer, send `get_session_stats` |
| `message_update` + `thinking_delta/end` | Stream to window with `│ ` prefix |
| `message_update` + `text_delta/end` | Stream to window body |
| `tool_execution_start` | Append `┌ ⚙ TOOL` header with llm-chat+ token |
| `tool_execution_end` | Replace `└ …<tok>` placeholder in-place with `✓`/`✗` |
| `message_end` | Capture `input+cacheRead+cacheWrite` and `output` token counts |
| `auto_compaction_start/end` | Display compaction separator |
| `auto_retry_start/end` | Update status, set `Is_Retrying` flag |
| `response` + `get_session_stats` | Store stats, append turn summary, append separator |
| `response` + `get_state` | Populate session ID, thinking level, model, context window |
| `response` + `new_session` | Follow up with `get_state` to refresh session ID |
| `response` + `set_model` | Update model in state and status line |

Commands used by pi_acme:

| Tag / action | Command sent |
|---|---|
| Send | `{"type":"prompt","message":"..."}` |
| Steer | `{"type":"prompt","message":"...","streamingBehavior":"steer"}` |
| Stop | `{"type":"abort"}` |
| New | `{"type":"new_session"}` |
| Model change (plumb) | `{"type":"set_model","provider":"...","modelId":"..."}` |
| Thinking change (plumb) | `{"type":"set_thinking_level","level":"..."}` |
| Session load (plumb) | restart subprocess with `--session UUID` |
| Startup / after new_session | `{"type":"get_state"}` |
| After agent_end (normal stop) | `{"type":"get_session_stats"}` |
