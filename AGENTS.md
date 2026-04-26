You are running in a vm, so you have full control of installing new things, launching things to take over and test, and running anything you want to test updates you make.

# Purpose

Build a secure NixOS-based OS whose primary user interface is the browser.

This file is the working project brief. Keep it current as decisions change. A task is only complete when it has strong automated coverage.

# Planning Rule

Define milestones by the proof they provide, not by premature architecture choices.

- Decide what must be demonstrated.
- Choose the minimum implementation that proves it.
- Avoid locking in VM, boot, networking, packaging, or orchestration details before a milestone requires them.

# Roadmap

## Completed Milestones

- Milestone 1: reproducible NixOS guest boot on an Ubuntu host.
- Milestone 2: graphical in-guest browser UI.
- Milestone 3: browser-based system controls.
- Milestone 4: synced in-VM development against a host-shared repo.
- Milestone 5: first-boot onboarding, persistent machine state, and a test-prefill path.

## Milestone 6: Development Loop

Goal:
- Make the normal development loop predictable, fast, and reproducible.

Key decisions:
- Keep the Firefox source-tree loop aligned with the Firefox source selected by pinned `nixpkgs`.
- Treat source-tree validation as a development proof, not as the distro packaging source of truth.
- Keep the final packaged Nix build path as the release gate for shipped Firefox changes.
- Keep full Firefox source trees and reusable build artifacts out of this repo.
- Namespace Firefox source checkouts, build outputs, and caches by Firefox identity, including version, source identity, source hash, and `nixpkgs` revision.
- Use nested KVM for the current in-ol-c VM development proof.
- Expose the parent image directory at `/vm-images` so child VM tests can reuse prebuilt images.
- Use `/var/lib/ol-c/vms` for child VM runtime state, temp files, and logs.
- Keep nixpkgs/NixOS as the primary Firefox and security-update source for now.
- Treat newer-than-nixpkgs Firefox support as an escape hatch only if update latency becomes a real problem.
- Embedded VM creation should allow for setting up a test user account, so we can skip authentication for tests for user layer changes

Success criteria:
- Build and launch behavior are predictable.
- Rebuild versus reuse behavior is explicit.
- Fast iteration does not undermine reproducibility.
- `patched-firefox` or the source-tree loop records the exact Firefox and `nixpkgs` identity being tested.
- A developer can validate Firefox behavior in the guest before refreshing `patches/firefox/packaged/0001-close-last-tab-to-localhost.patch`.
- The packaged build remains the gate for what ships.

Question this milestone answers:
- Do we have a practical, repeatable development workflow?

## Milestone 7: Self-Hosted Development

Goal:
- Decide whether developing ol-c from inside ol-c is a primary workflow or a later capability.

Success criteria:
- “Develop inside the OS” is defined concretely.
- Editing, building, testing, and nested-virtualization constraints are understood.
- We decide whether self-hosting is primary or deferred.

Question this milestone answers:
- Can the OS become a practical environment for developing itself?

## Milestone 8: Browser Accountability and Activity Visibility

Goal:
- Show users what sites are doing with sensitive browser capabilities and persistent state.

Key decisions:
- This is currently deprioritized behind the Milestone 6 work.
- The first proof is visibility-only, not control-oriented.
- Include aggregate CPU, memory, and network accounting alongside important capability events.
- Treat this as browser-shell product UI, not as devtools.
- Prefer browser-internal instrumentation and first-party UI over extension APIs.

Success criteria:
- The UI shows important current and recent site or tab activity.
- The first version covers a defined set of high-value events such as screen capture, camera, microphone, persistent storage, service workers, and background workers where practical.
- CPU, memory, and network usage are attributable in a user-comprehensible way.
- Automated tests cover the event-to-UI contract with deterministic triggers or hooks.

Out of scope:
- Enforcement controls such as throttling, suspension, or kill.
- Raw telemetry dumps or broad developer tooling.

Question this milestone answers:
- Can the browser act as a trustworthy activity ledger?

## Milestone 9: User-Facing System Updates and Rollback

Goal:
- Deliver OS and browser updates through the browser System page without requiring users to operate NixOS directly.

Key decisions:
- Firefox updates should arrive through ol-c system updates, not Firefox self-update.
- Users should not compile Firefox locally as part of normal updates.
- The browser System page is the product surface for update discovery, install, progress, reboot, and rollback.
- Rollback should use NixOS generations.
- Patch drift against upstream Firefox should block publication rather than silently freezing users on an old browser.

Success criteria:
- Users can discover, install, and roll back updates from the browser.
- Updates use prebuilt verified artifacts rather than local heavy builds.
- The active `ol-c`, `nixpkgs`, and Firefox versions are visible.
- Automated tests cover the browser-to-update-service contract.

Question this milestone answers:
- Can ol-c keep browser and OS updates user-friendly, timely, and reversible?

## Milestone 10: Prebuilt Release Artifacts

Goal:
- Produce ol-c release artifacts that downstream users can install or boot without running `nix build`.

Success criteria:
- A trusted local or CI builder can produce `.#ol-c-image` from a validated repo state.
- Release output records the ol-c revision, `nixpkgs` revision, Firefox version, artifact path, hashes, and logs.
- The release path proves Firefox patch gates and VM boot before publication.
- Automated tests cover the release manifest contract.

Question this milestone answers:
- Can ol-c turn a validated repo state into a reusable downstream artifact?

## Milestone 11: Verified Binary Distribution

Goal:
- Publish verifiable ol-c artifacts and Nix closures so users download trusted binaries instead of compiling locally.

Success criteria:
- Published artifacts include signatures, hashes, or an equivalent verification mechanism.
- Install or update fails closed on missing or untrusted verification data.
- The distribution path can provide the Nix closure required by the release artifact.
- Automated tests cover both verification success and failure.

Question this milestone answers:
- Can users safely consume ol-c builds without trusting local compilation?

## Milestone 12: Installer and First Install Path

Goal:
- Provide an install flow that consumes a prebuilt verified ol-c release artifact.

Success criteria:
- A non-developer can install or boot ol-c without invoking Nix commands.
- The first install path does not compile Firefox or other large packages locally.
- Installed state remains compatible with first-time setup and persistence.
- The installed `ol-c`, `nixpkgs`, and Firefox versions are recorded.
- Automated tests cover the installer contract.

Question this milestone answers:
- Can a non-developer get ol-c onto hardware or a VM quickly and repeatably?

# Current Capabilities

- `https://localhost/terminal` provides fresh in-browser terminal sessions.
- `https://localhost/edit` provides a browser text editor that uses the active signed-in user's filesystem permissions.
- `edit` from an in-browser terminal opens `/edit`, and `edit <path>` opens a specific file.
- The normal `./launch-vm` path uses a browser tab as the VM display through local-only QEMU VNC WebSocket plus pinned noVNC assets.
- `launch-vm` also exposes a local-only QMP socket and prints it as `qmp socket:`.
- `launch-vm` can wait for the guest `olc-vm-ready` journal marker and surface readiness failures.
- In-VM development uses a host-shared repo mounted at `/source` via `virtiofs`.
- Nested `olc-launch-test-vm` launches default to a cheap child-boot path and print a reconnect URL for browser viewing.
- `olc-vmctl` provides low-level QMP control primitives including `key`, `type`, `move`, `click`, `screenshot`, and `raw`.
- Firefox localhost shell behavior opens new tabs to `https://localhost/` and replaces last-tab closure with a localhost tab.

# Current Focus

Active milestone:
- Milestone 6.

Immediate next task:
- Record the exact Firefox and `nixpkgs` identity for `patched-firefox` runs so developers can prove what runtime they validated before refreshing `patches/firefox/packaged/0001-close-last-tab-to-localhost.patch`.

Current Milestone 6 direction:
- `patched-firefox` is the one-command in-VM operator path for launching a patched Firefox from the installed runtime.
- Normal VM launch and pending Firefox patch testing stay separate: `./launch-vm` boots the packaged system from `patches/firefox/packaged`, while `patched-firefox` applies `packaged` first and `pending` second.
- `patched-firefox` must not evaluate the dirty local `/source` flake on its launch path.
- The fast path should reuse the installed runtime, symlink unchanged files, and rebuild only mutable `omni.ja` assets.
- Packaged Firefox patches live under `patches/firefox/packaged/`; dev-only fast-loop patches live under `patches/firefox/pending/`.
- Keep the packaged Nix paths explicitly blind to `patches/firefox/pending` in tests.

Parallel Milestone 6 track:
- Define a host-driven VM operator proof where a host launches a VM, submits work, watches it happen live, and verifies completion through shared artifacts and logs.
- Use the shared `/source` mount as the first host-to-guest control channel rather than requiring guest networking first.
- Keep the embedded browser viewer as the human observation surface, not the main automation API.
- Use a guest-resident operator path for visible work where appropriate, with `xdotool` available for first-pass GUI automation.
- Prefer a parent-to-child Firefox BiDi bridge for page-level control of a child VM's browser session; keep `olc-vmctl` as the lower-level fallback for raw input and screenshots.

Related design notes:
- `docs/host-driven-vm-operator-plan.md` holds the current operator-proof plan.

# Validation Status

- The repo has moved from unsupported `nixos-24.11` to `nixos-25.11`.
- Fast deterministic checks currently passing:
  - `node --test localhost-ui/*.test.mjs`
  - `cd terminal-client && npm test && npm run build`
  - `bash tests/test-build-vm.sh`
  - `bash tests/test-launch-vm.sh`
  - `bash tests/test-build-firefox-remote.sh`
  - `bash tests/test-olc-firefox-dev.sh`
- `./build-vm` succeeds.
- `./launch-vm` boots to the graphical browser surface and loads the localhost UI.
- The packaged Firefox build succeeds and reports `Mozilla Firefox 149.0.2`.
- The fast packaged Firefox output records both `OLC_FIREFOX_LOCALHOST_PATCH_APPLIED=1` and `OLC_FIREFOX_FXA_SYNC_UI_PATCH_APPLIED=1`.
- `./build-firefox-source-remote`, fetch, and `nix build .#firefox-localhost-source --print-build-logs` succeed, with later local builds reusing the imported result.

# Working Notes

In-VM validation:
- If Codex is running inside the ol-c guest and `/source` is the `ol-c-source` `virtiofs` mount, treat edits as host-synced repo edits and validate browser-surface work directly in the guest.
- When a graphical Firefox session is live in the guest, local tools such as `xdotool` may be used for validation.

Host-driven live analysis:
- A parent ol-c guest can act as the effective host operator for a nested child VM by launching `olc-launch-test-vm`, opening the printed reconnect URL, and keeping that viewer open as the observation surface.
- For page-level analysis or DOM work inside a child Firefox session, prefer `olc-vm-bidi` over noVNC or QMP input injection.
- Use the reconnect URL as the human proof surface and BiDi results plus `journald` as the machine-verifiable proof surface.

Shared journal mirror:
- The canonical logs remain the guest's local `journald` store; the host-visible mirror lives under `/source/.olc-debug/journal`.
- Each VM mirrors its current boot into its own native journal file in that directory.
- When working from the shared repo view, prefer `journalctl --directory=/source/.olc-debug/journal`.
- The `olc-vm-ready` marker means the active local Firefox session has published its BiDi endpoint.
- When investigating one VM, filter by `_MACHINE_ID` first, then `_BOOT_ID`, and use `OLC_VM_MACHINE_ID`, `OLC_VM_BOOT_ID`, `OLC_VM_PARENT_MACHINE_ID`, and `OLC_VM_DEPTH` to reconstruct nested lineage.

# Deferred Decisions

The following are intentionally not locked in yet:
- Networking model
- Browser UI stack after the current Firefox proof
- Automatic rebuild policy
- Persistent overlays and snapshots beyond the current QEMU `-snapshot` dev behavior
- First-time setup data shape
- Long-term VM backend choice outside these milestones

These decisions should be made when a later milestone actually requires them.

# Quality of life improvements

These are non-priority tasks we can pick up any time as an option for the next thing to do, but are not pressing
- Current select boxes like mute and light/dark mode should be toggle buttons with appropriate unicode icons
- highlight URL bar when opening new tab (this was a regression from default behavior)
- Ctrl+S crashes firefox
- Future paste-into-VM fix: copy out of the browser-launched VM already works well. Paste should keep using the existing noVNC plus QEMU `qemu-vdagent` clipboard path, but keyboard paste needs to intercept `Ctrl+V` and host `Cmd+V` in capture phase before noVNC handles them, read host clipboard text during that user gesture, call `rfb.clipboardPasteFrom(text)`, then synthesize guest `Ctrl+V` so the active guest app actually pastes. Browser clipboard reads may be permission or prompt gated, so failure should show a concise hint.
- Ctrl+Shift+C should not open dev tools in vm, we should make that copy
- remove "connected" and "clipboard ready" chrome
- make sure password save offer on initial account creation doesn't show
- investigate browser terminal breakage after printing nested-child serial boot output with heavy raw OSC/ANSI control sequences; likely fix is to filter or redirect that boot stream before it hits the browser terminal session
- investigate Codex CLI exits back to a raw shell prompt during nested-child launch work; likely trigger is the same unfiltered serial boot/control-sequence stream reaching the interactive Codex terminal, so prefer redirecting child serial logs to files and only tailing filtered output on demand
- investigate Codex CLI exits during long `Working` periods with multiple background terminal sessions open; likely mitigation is to avoid stacked long-lived waits/pollers and prefer short explicit polling commands with no lingering background terminals
