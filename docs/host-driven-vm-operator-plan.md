# Host-Driven VM Operator Plan

## Goal

Let the host launch an ol-c VM, submit work to it, and observe that work live through the existing embedded VM browser viewer or through browser surfaces inside the guest such as `https://localhost/terminal`.

This is a Milestone 6 development-loop capability, not a product security model.

## Existing Pieces We Can Reuse

- `./launch-vm` already prints a browser viewer URL and reconnect URL for the VM screen.
- The browser viewer already injects normal user input through noVNC into the guest.
- The guest already has stable localhost services for terminal and editor access.
- The guest already resolves the active signed-in console user instead of assuming `demo`.
- The guest already ships `xdotool`, which is enough for first-pass GUI automation inside the session.
- Host and guest already share a live writable tree at `/source`.
- Host and guest already share a journal mirror at `/source/.olc-debug/journal/current.journal`.

The shortest path is to build a guest-resident operator service and use the shared `/source` tree as the host↔guest control channel.

## Recommended Architecture

### 1. Keep `launch-vm` as the host entrypoint

Do not make the host talk to the guest over an ad hoc network API first.

The host should continue to:

- boot the VM
- print the viewer URL and reconnect URL
- expose `/source` and `/vm-images`
- record machine lineage for logs

That keeps launch and control separate.

### 2. Add a guest operator service

Add a small service inside the guest, for example `olc-vm-operator`, that:

- watches a fixed shared control directory such as `/source/.olc-debug/operator/current`
- reads request files written by the host
- executes actions as the active signed-in console user when possible
- writes structured status, logs, and result artifacts back to the shared directory
- mirrors progress into journald with a stable identifier

This should be a first-party service, not a browser extension and not an external GUI bot running on the host.

### 3. Use a file-backed control queue first

Use the shared `virtiofs` repo mount for v1:

- host writes `request.json`
- guest claims it atomically
- guest writes `state.json`
- guest appends step logs
- guest writes `result.json`

Why this is the right first transport:

- no guest networking changes
- works for nested VMs too because `/source` is already the shared rendezvous point
- easy to inspect manually from host or guest
- easy to replay in tests with fixtures

### 4. Support two execution modes

The operator service should support a narrow hybrid model, not only GUI playback.

Mode 1: `shell`

- run a command or script as the active signed-in user
- use this for fast, deterministic work such as editing files, running tests, checking logs, launching `olc-firefox-source mach run`, or opening a terminal tab

Mode 2: `gui`

- use `xdotool` against the active X session for actions that need user-like interaction
- examples: focus Firefox, open a tab, type into the UI, click a button, navigate setup/login flows

Rule:
- prefer `shell` when it proves the behavior
- use `gui` only when the proof needs visible browser-session interaction

### 5. Make observability first-class

Each request should record:

- request id
- host enqueue time
- guest claim time
- target VM machine id and boot id
- active user identity
- execution mode
- steps started/completed
- final status
- artifact paths

And the service should emit a concise journal stream so the host can answer “what is the VM doing right now?” without guessing.

## Why Not Drive noVNC Directly From The Host

Pure host-side event injection into the viewer is not the best primary control plane.

Problems:

- it is focus-sensitive and timing-sensitive
- it is harder to test deterministically
- it is harder to recover from partial UI drift
- it gives poor semantic logs compared with a guest-resident operator
- it does not naturally scale to “open a terminal and inspect state” workflows

noVNC input remains useful for human observation and manual intervention. It should stay the viewing surface, not the main automation API.

## First Proof We Should Build

Success criteria for the first host-driven operator proof:

- Host runs `./launch-vm` and gets a reconnect URL.
- Host submits a request into the shared operator directory.
- Guest operator service picks up the request and logs that it claimed it.
- Guest opens a new Firefox tab to `https://localhost/terminal`.
- Guest types and runs a simple visible command such as `whoami` or `hostnamectl`.
- Host can watch that happen live in the viewer tab.
- Host can inspect the result from the shared operator status files and the mirrored journal.

This is enough to prove “host can tell the VM to do something user-like and watch it happen”.

## Suggested Interface

Host-side helper:

- `olc-vm-send --vm <id-or-path> --mode shell -- cmd...`
- `olc-vm-send --mode gui --plan plan.json`

Guest-side service contract:

- request directory: `/source/.olc-debug/operator/current/requests`
- claimed directory: `/source/.olc-debug/operator/current/running`
- result directory: `/source/.olc-debug/operator/current/results`

Example request shape:

```json
{
  "id": "2026-04-24T22-00-00Z-open-terminal",
  "mode": "gui",
  "summary": "Open terminal tab and run hostnamectl",
  "steps": [
    { "action": "focus-firefox" },
    { "action": "new-tab", "url": "https://localhost/terminal" },
    { "action": "type", "text": "hostnamectl\n" }
  ]
}
```

The schema should stay intentionally small at first.

## Test Plan

- Unit tests for request parsing, claiming, and result writing.
- Unit tests for routing requests into `shell` versus `gui` executors.
- Fake executor tests for progress, failure, timeout, and cancellation behavior.
- VM contract test that confirms the operator service is installed and watching the shared control directory.
- End-to-end test VM flow:
  - launch VM
  - enqueue request fixture
  - assert guest writes claimed and completed state
  - assert expected journal lines exist

## Follow-On Work After The First Proof

- Add a nested-VM Firefox BiDi bridge so a parent can ask a child-resident helper to create and proxy BiDi actions against the child's live Firefox session, instead of depending on unreachable child-local `127.0.0.1` WebSocket endpoints.
- Add `open-localhost-page`, `keystroke`, `click-image-anchor`, and `wait-for-window` helpers.
- Add screenshots or lightweight video snapshots as result artifacts.
- Add a browser-visible operator status page in localhost UI if needed.
- Add explicit cancellation and timeout handling.
- Add child-VM awareness so the same host control path can target nested VMs.
