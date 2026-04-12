# pi_acme — Agent Instructions

## Project Overview

**pi_acme** is an Ada reimplementation of the Python script at
`/home/gtnoble/Projects/pi-acme/pi-acme`. Refer to that script as the
reference implementation when behaviour is unclear or a feature needs to be
ported.

The project is an acme text editor frontend for the `pi` coding agent. It
spawns `pi --mode rpc` as a subprocess, communicates with it over JSON-line
pipes, and presents a live interactive window inside acme.

**plan9port** (acme, plumber, 9P utilities) is installed at `/usr/local/plan9`.
The `PLAN9` environment variable should point there; binaries such as
`acmeevent` live in `/usr/local/plan9/bin/`.

Two executables are built:
- `bin/pi_acme` — the main frontend (opens a `+pi` acme window)
- `bin/pi_list_sessions` — lists saved pi sessions for the current directory

## Language & Build System

- **Language:** Ada 2022 (GNAT/GCC)
- **Build system:** [Alire](https://alire.ada.dev/) (`alr`) with a GPRbuild project (`pi_acme.gpr`)
- **Dependency:** `gnatcoll` ≥ 25.0.0 (JSON, OS, process utilities)

### Build commands

```sh
# Build (development profile, default)
alr build

# Build release
alr build --release

# Run tests
cd test && alr run pi_acme_test
```

Object files go to `obj/<profile>/`, binaries to `bin/`.

## Source Layout

```
src/
  pi_acme.adb            -- Entry point; parses --session / --model / --agent flags
  pi_acme_app.ads/.adb   -- App_State (protected object), Options, Run procedure
  pi_rpc.ads/.adb        -- Spawns `pi --mode rpc`; Send / Read_Line / Read_Stderr_Line
  acme.ads/.adb          -- Root package; Win_File_Path helper
  acme-window.ads/.adb   -- Acme window operations over Nine_P (Append, Ctl, etc.)
  acme-event_parser.ads/.adb  -- Parses acme event-file records
  acme-raw_events.ads/.adb    -- Low-level raw event byte feeding / Next_Event
  nine_p.ads             -- 9P2000 constants, Qid, Byte_Array, Byte_Vectors
  nine_p-proto.ads/.adb  -- 9P message encode/decode
  nine_p-client.ads/.adb -- 9P client: Ns_Mount, Open, Read_Once, Write, Clunk
  session_lister.ads/.adb -- Reads ~/.pi/agent/sessions/ for pi_list_sessions
tools/
  pi_list_sessions.adb   -- Entry point for the session listing utility
test/src/                -- AUnit-based test suite
```

## Architecture

`Pi_Acme_App.Run` drives the application with six Ada tasks running concurrently:

| Task | Responsibility |
|---|---|
| `Pi_Stdout_Task` | Reads JSON events from `pi --mode rpc` stdout; dispatches via `Dispatch_Pi_Event` |
| `Pi_Stderr_Task` | Forwards pi stderr lines to the acme window body |
| `Acme_Event_Task` | Reads the acme window event file via 9P; handles Send/Stop/New/Clear tag commands |
| `Plumb_Model_Task` | Reads the `/pi-model` plumb port; forwards model selections to pi |
| `Plumb_Session_Task` | Reads the `/pi-session` plumb port; updates session ID in `App_State` |
| `Plumb_Thinking_Task` | Reads the `/pi-thinking` plumb port; forwards thinking-level changes to pi |

All shared mutable state lives in `App_State`, a protected object. Each task
opens its own `Nine_P.Client.Fs` connection to avoid cross-task 9P contention.
The `Addr_Mutex` inside `Acme.Window.Win` serialises the addr→data write pair.

`Dispatch_Pi_Event` is a pure procedure (no tasks inside it) that maps incoming
pi JSON event types to acme window mutations:

- `agent_start / agent_end` — update streaming state, request stats
- `message_update` — stream `thinking_delta`, `text_delta` etc. to the window body
- `tool_execution_start / tool_execution_end` — show compact tool call summaries
- `message_end` — capture token counts
- `model_select` — update model and context-window size in state
- `response` — handle replies to `get_state`, `abort`, `new_session`, `get_session_stats`

## 9P / Acme VFS Conventions

- The acme namespace is mounted with `Ns_Mount ("acme")`.
- The plumb namespace is mounted with `Ns_Mount ("plumb")`.
- Window control is done by writing to `/N/ctl`, body via addr=$ + `/N/data`,
  tag via `/N/tag`, and events are read from `/N/event`.
- `Acme.Window` operations take an explicit `not null access Nine_P.Client.Fs`
  so each task can pass its own connection — **never share an `Fs` across tasks**.

## Pi RPC Protocol

`Pi_RPC` wraps `pi --mode rpc`. Messages are single-line JSON objects:

**Outbound (to pi):**
```json
{"type":"get_state"}
{"type":"prompt","message":"<text>"}
{"type":"abort"}
{"type":"new_session"}
{"type":"set_model","provider":"<p>","modelId":"<id>"}
{"type":"set_thinking_level","level":"<low|medium|high>"}
{"type":"get_session_stats"}
```

**Inbound (from pi):** JSON event stream — see `Dispatch_Pi_Event` for the full
set of handled types (`agent_start`, `agent_end`, `message_update`,
`tool_execution_start`, `tool_execution_end`, `message_end`, `model_select`,
`response`).

## Ada Style Guide

**Always load the `ada-style-guide` skill before reading, writing, or reviewing
any Ada source in this project.** The skill is located at
`/home/gtnoble/.pi/agent/skills/ada-style-guide/SKILL.md`. All code must
conform to the guidelines it defines.

## Coding Conventions

- Follow existing Ada style: two-space indentation, `--  double-dash` comments,
  package specs fully document the public API.
- New packages should mirror the existing split: `.ads` holds the spec with
  complete comments, `.adb` holds the body.
- Prefer `Ada.Strings.Unbounded.Unbounded_String` for variable-length strings
  stored in records; use plain `String` for transient values.
- Protected objects and task types should be declared as `type`s (not singletons)
  so they can be tested in isolation.
- Never share a `Nine_P.Client.Fs` or `Nine_P.Client.File` between tasks.
- Error handling: catch exceptions at task boundaries, append a `[!] ...` line
  to the acme window, and signal shutdown where appropriate.
- `GNATCOLL.JSON` is the JSON library; use `Read` / `Get_Str` / `Get_Int` helpers.

## Testing

Tests live in `test/src/` and use AUnit. Each source unit has a corresponding
`*_tests.adb`. Integration tests that need a live acme/9P server are in
`acme_integration_tests.adb` and `nine_p_integration_tests.adb`.

Run the full suite:
```sh
cd test && alr run pi_acme_test
```

When adding new functionality, add unit tests first (TDD preferred). Integration
tests that require a running acme instance should be guarded and clearly marked.
