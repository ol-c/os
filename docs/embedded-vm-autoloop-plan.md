# Embedded In-VM Autonomous Dev Loop

## Summary

This is feasible with the current repo shape, and the shortest path is to treat it as a layered operator workflow inside the ol-c guest:

- run Codex inside the parent ol-c VM against live `/source`
- let it use the fastest proof surface first (`patched-firefox`, targeted tests, service restarts, localhost checks)
- escalate only when needed to an embedded child ol-c VM via `olc-launch-test-vm`
- keep edits on live `/source` so host, parent VM, and child-VM launch tooling all see the same tree immediately

This should be positioned as a development workflow, not a production trust model. The repo already says that in-guest `codex` runs with approvals bypassed and the first admin has passwordless `sudo`, which is exactly the right assumption for this proof.

## Current State

The repo already has most of the hard prerequisites:

- host repo is mounted read-write in the guest at `/source` via `virtiofs`
- the first human admin prefers UID `1000`, which preserves the synced-dev path
- the guest has a `codex` command intended for in-VM development
- the guest has a fast browser-runtime loop via `patched-firefox`
- the guest can boot a child ol-c VM through `olc-launch-test-vm`
- the parent launcher exposes boot images at `/vm-images`
- child-VM runtime state is already scoped to `/var/lib/ol-c/vms`

So the remaining work is not “make nested VMs possible”. It is “turn the existing pieces into a predictable autonomous operator loop”.

## Implementation Changes

### 1. Define one explicit autonomous workflow

Add a documented in-guest operator workflow with this order:

1. Analyze repo state in `/source`
2. Edit `/source`
3. Run targeted local checks first
4. If browser-runtime-only change: use `patched-firefox`
5. If system/session/boot behavior change: use `olc-launch-test-vm`
6. Collect proof artifacts and stop with a clear result

Do not make the agent choose between unrelated orchestration paths ad hoc. Encode this escalation order in docs and helper tooling.

### 2. Add a parent-VM orchestration wrapper

Add one in-guest command whose job is to drive the loop, not to replace Codex itself. For example:

- `olc-autoloop` or similar
- input: task description, optional changed paths, optional validation mode override
- behavior:
  - detects whether `/source` is the expected live repo mount
  - records task start metadata
  - runs Codex in `/source`
  - chooses validation tier from changed paths and task hints
  - invokes either:
    - repo tests only
    - `patched-firefox`
    - `olc-launch-test-vm`
  - stores logs and a result summary under a fixed runtime directory

This wrapper should orchestrate; it should not add a second agent system.

### 3. Make validation tiering deterministic

Use simple path-based routing first, not open-ended heuristics.

Recommended default routing:

- `localhost-ui/`, `terminal-client/`, docs-only, small JS/UI edits:
  - run targeted tests
  - optionally validate parent VM localhost surface
  - use `patched-firefox` only if browser chrome/runtime assets changed
- `patches/firefox/pending/`:
  - use `patched-firefox`
  - do not boot child VM by default
- `nix/modules/`, `launch-vm`, `build-vm`, session/login/setup, shared-repo, nested-VM launcher:
  - run contract tests
  - then boot child VM with `olc-launch-test-vm`
- changes that touch both runtime UI and system/session wiring:
  - do fast local checks first
  - then child VM

Keep this ruleset explicit in one place so the loop is explainable and stable.

### 4. Standardize artifact capture

Add one runtime directory for autonomous loop outputs, for example under `/var/lib/ol-c/autoloop` or inside the existing VM runtime area.

Capture:

- task description
- repo revision / dirty state
- changed files
- tests run
- `patched-firefox` manifest if used
- child VM reconnect URL and logs if used
- final pass/fail summary

This is necessary if the loop is meant to run autonomously and be trusted later.

### 5. Keep child-VM use narrow

Do not make the child VM the default for every task.

Use it only for:

- boot/login/setup/session changes
- nested-VM-launcher changes
- cases where visible browser-surface proof matters
- regressions that only reproduce in a fresh booted guest

For ordinary localhost UI or editor/terminal/backend work, stay in the parent guest unless escalation is required.

### 6. Preserve live `/source` as the default source model

Use the shared `/source` tree directly.

That fits the current repo assumptions:

- source preview already watches `/source/localhost-ui`
- parent and host already share this tree
- nested VM launch already expects `/source` as the editable repo

If isolation is needed later, add it as a second mode, not the default.

## Interfaces And Behavior

Add one documented operator entrypoint in the guest:

- command: `olc-autoloop`
- required input: task prompt
- optional input:
  - `--changed-path`
  - `--validation=tiered|runtime|child-vm|tests-only`
  - `--task-type=ui|firefox-runtime|system|boot`
- output:
  - concise terminal summary
  - path to saved logs/artifacts
  - child VM reconnect URL when child validation was used

No browser API changes are required for v1. This is an in-guest developer/operator capability.

## Test Plan

- Contract test for the new wrapper command:
  - chooses `/source` when mounted as expected
  - falls back cleanly if `/source` is unavailable
  - writes an artifact bundle and summary
- Routing tests:
  - `patches/firefox/pending/*` chooses `patched-firefox`
  - `nix/modules/*` chooses child VM validation
  - localhost-only edits do not boot a child VM by default
- Runtime smoke tests in guest:
  - a localhost UI task can complete with edits + tests only
  - a Firefox runtime patch task can complete via `patched-firefox`
  - a login/session task escalates to `olc-launch-test-vm`
- Failure handling:
  - Codex failure is captured and summarized
  - child VM launch failure is surfaced with logs
  - reconnect URL and runtime logs are preserved on failure
- Regression coverage:
  - no change to the existing host `./launch-vm` behavior
  - no change to packaged-vs-pending Firefox patch boundaries

## Assumptions

- This is a development-only capability and may run with broad privileges inside the disposable guest.
- The default source model is live `/source`, not an isolated copy.
- The default validation policy is tiered:
  - cheap local checks first
  - `patched-firefox` for browser-runtime tasks
  - child VM only when system/boot/session behavior needs proof
- Child-VM orchestration should remain explicit and narrow, not the default for all tasks.
- The goal is autonomous analyze/edit/run within the guest, not fully unattended release publishing or host-side orchestration.
