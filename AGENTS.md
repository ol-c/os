You are running in a vm, so you have full control of installing new things, launching things to take over and test, and running anything you want to test updates you make.

# Purpose of this Project

To provide a secure and safe OS based on nixOS and using a browser for all UI.

We will develop together by progressively implementing features described in this file.

Make edits to this file as we adjust plans.

We will mark things done as we finish them. For something to qualify as finished, it must have excellent test coverage.

# Planning Rule

We will define milestones by the proof they provide, not by premature tooling or architecture decisions.

That means:
- We should decide what we need to demonstrate first.
- We should choose the minimum implementation needed to demonstrate it.
- We should avoid locking in VM, boot, networking, or build orchestration details before they are justified by a milestone.

# Milestones

## Completed Milestones

Milestones 1, 2, 3, and 4 are complete. The implementation checklist below is the retained history for completed work.

- Milestone 1 proved a reproducible NixOS guest boot on an Ubuntu host.
- Milestone 2 proved an in-guest graphical browser UI.
- Milestone 3 proved browser-based system controls.
- Milestone 4 proved synced in-VM development against a host-shared repo.

## Milestone 5: First-Time Setup and Persistence

Goal:
- Implement first boot onboarding and persist machine state.

Success criteria:
- A fresh machine state shows onboarding on first boot.
- Completing setup writes durable machine state.
- A later boot of the same machine state skips onboarding.
- Automated tests can bypass the manual setup flow through a test prefill path.

Question this milestone answers:
- Can the system transition cleanly from unconfigured to configured state?

## Milestone 6: Development Loop

Goal:
- Tighten the build and launch workflow for normal development.

Milestone 6 decisions:
- Keep the Firefox source-tree development loop aligned with the Firefox source selected by the repo's pinned nixpkgs input by default.
- Define a fixed in-VM Firefox development checkout and build-cache location outside the tracked ol-c repo contents.
- Use nested KVM on the Ubuntu host for the current in-ol-c VM development proof.
- Expose the parent VM's boot image directory into the ol-c guest at `/vm-images` so child VM tests can reuse a prebuilt image.
- Use `/var/lib/ol-c/vms` as the guest-side runtime workspace for child VM launch temp files and logs.
- Keep the full Firefox source tree and reusable Firefox build artifacts out of this repo.
- Namespace Firefox source checkouts, build outputs, and reusable cache state by Firefox identity, including version, source URL or source name, source hash, and nixpkgs revision.
- Provide a mechanism to populate the in-VM Firefox checkout from the pinned nixpkgs Firefox source and to reuse or prebuild artifacts where practical.
- Treat the in-VM Firefox source loop as a proof and development loop, not as the distro packaging source of truth.
- After a Firefox source behavior change is validated in the VM, refresh the repo patch artifact and run the packaged Nix gates intentionally.
- Rely on nixpkgs as the primary Firefox packaging and security-update source for now.
- Keep newer-than-nixpkgs Firefox support as a future escape hatch only if nixpkgs update latency becomes unacceptable.
- Do not make ol-c responsible for packaging a newer Firefox than nixpkgs as part of this milestone.
- Before relying on nixpkgs for timely security updates, move the repo off unsupported `nixos-24.11` to a currently supported NixOS branch and keep that branch current.

Success criteria:
- The build flow is predictable.
- The launch flow is predictable.
- Rebuild versus reuse behavior is explicit.
- The workflow supports fast iteration without undermining reproducibility.
- The in-VM Firefox source loop records the exact Firefox and nixpkgs identity being tested.
- A developer can validate Firefox source-tree behavior in the guest before refreshing `patches/firefox/packaged/0001-close-last-tab-to-localhost.patch`.
- The final packaged build path remains the gate for what the distro will ship.

Examples of things that may belong here:
- Build orchestration
- Artifact manifests
- Overlays or snapshots
- Better launch scripts
- Efficiently launching a Firefox source-tree build from inside the VM to test patch edits before refreshing `patches/firefox/packaged/0001-close-last-tab-to-localhost.patch`
- Updating the pinned NixOS branch as part of keeping development and security assumptions honest
- Recording Firefox source identity and build-output identity for source-tree test runs
- Future explicit support for a repo-declared newer Firefox track, if nixpkgs update latency proves unacceptable

Question this milestone answers:
- Do we have a development workflow that is practical and repeatable?

## Milestone 7: Self-Hosted Development

Goal:
- Evaluate and possibly support development from inside the OS itself.

Success criteria:
- We define what “develop inside the OS” actually means.
- We understand the constraints around editing, building, testing, and nested virtualization.
- We decide whether self-hosting is a primary workflow or a later capability.

Question this milestone answers:
- Can this OS become a practical environment for developing itself?

## Milestone 8: Browser Accountability and Activity Visibility

Goal:
- Expose important browser-site behaviors in a user-facing browser interface so users can understand what sites are doing with sensitive browser capabilities and persistent browser state.

Milestone 8 decisions:
- De-prioritize this milestone behind the current roadmap.
- Make the first proof visibility-only, not control-oriented.
- Include aggregate CPU, memory, and network accounting alongside important event tracking in the first version.
- Treat this as a product capability of the browser shell, not as a developer or devtools feature.
- Prefer browser-internal instrumentation and first-party UI over standard extension APIs.

Success criteria:
- The browser UI shows important current and recent activity for sites or tabs.
- At minimum, the milestone demonstrates visibility for a defined set of high-value events such as screen capture, camera access, microphone access, persistent storage use or grant, service worker install or active state, and background worker activity where practical.
- The browser UI shows aggregate CPU, memory, and network usage attributable to a tab, site, or origin.
- The UI can show both what is happening now and a recent history or timeline of important events.
- Event data is attributable to a tab, site, or origin in a way users can understand.
- Automated tests cover the event-to-UI contract with deterministic triggers or test hooks.

Out of scope:
- Throttling, suspension, kill, or policy enforcement controls
- Broad developer tooling or raw internal telemetry dumps

Question this milestone answers:
- Can the browser act as a trustworthy activity ledger that tells users what sites are doing with sensitive browser capabilities and persistent browser state?

## Milestone 9: User-Facing System Updates and Rollback

Goal:
- Deliver OS and browser security updates through the browser System page without requiring users to understand or operate NixOS directly.

Milestone 9 decisions:
- Treat Firefox self-update as incompatible with the ol-c update model; Firefox updates should arrive through ol-c system updates.
- Use nixpkgs/NixOS as the primary source for Firefox security updates unless concrete latency problems justify carrying a repo-declared newer Firefox package track.
- Users should not compile Firefox locally as part of normal updates.
- ol-c should consume prebuilt, signed or otherwise verified update artifacts before offering an update to users.
- Depend on the release artifact and binary distribution proofs before treating browser-facing updates as a user-ready product path.
- The browser System page is the intended product surface for update availability, install actions, update progress, reboot prompts, and rollback.
- Rollback should use NixOS generations rather than browser-level self-update state.
- The update path should make patch drift visible early: if an upstream Firefox update breaks the ol-c Firefox patch, that should block publication in CI/release work rather than silently holding users on an old browser.

Success criteria:
- The browser System page can show when an ol-c update is available.
- A user can opt in to install an available update without invoking Nix commands.
- The installed update uses prebuilt artifacts rather than compiling large packages such as Firefox on the user's machine.
- A user can move back to a previous known system generation if an update is undesirable or broken.
- The update mechanism records enough version information to explain what Firefox, nixpkgs, and ol-c revision are active.
- Automated tests cover the browser-to-update-service contract with deterministic fakes or controlled test hooks.

Question this milestone answers:
- Can ol-c keep browser and OS security updates user-friendly, timely, and reversible?

## Milestone 10: Prebuilt Release Artifacts

Goal:
- Produce ol-c release artifacts that users can install or boot without running `nix build`.

Success criteria:
- A trusted local or CI builder can produce the current `.#ol-c-image` release artifact from a validated repo state.
- The release output records the ol-c revision, nixpkgs revision, Firefox version, image output path, artifact hashes, and build logs.
- The release path proves the Firefox patch gates and VM boot gate before an artifact is considered publishable.
- The release artifact can be consumed by a downstream install or boot workflow without rebuilding Firefox or the OS on the user's machine.
- Automated tests cover the release manifest contract with deterministic local artifacts or fakes.

Question this milestone answers:
- Can ol-c turn a validated repo state into a reusable downstream install artifact?

## Milestone 11: Verified Binary Distribution

Goal:
- Publish verifiable ol-c artifacts and Nix closures so user machines download trusted binaries instead of compiling Firefox or the OS.

Success criteria:
- Published artifacts include hashes and signatures or an equivalent verification mechanism.
- A fresh machine can verify artifact provenance before install or update.
- Missing, mismatched, or untrusted verification data prevents install or update.
- The distribution path can provide the Nix closure needed by the release artifact without requiring local source builds.
- Automated tests cover verification success and failure cases with deterministic local fixtures.

Question this milestone answers:
- Can users safely consume ol-c builds without trusting local compilation?

## Milestone 12: Installer and First Install Path

Goal:
- Provide a first install flow that consumes a prebuilt verified ol-c release artifact.

Success criteria:
- A user can install or boot ol-c from a published release artifact without invoking Nix commands.
- The first install path does not compile Firefox or other large OS packages on the user's machine.
- Installed machine state remains compatible with first-time setup and persistence.
- The installer records enough version information to explain what ol-c revision, nixpkgs revision, and Firefox version were installed.
- Automated tests cover the installer contract using local fake artifacts or controlled test hooks.

Question this milestone answers:
- Can a non-developer get ol-c onto hardware or a VM quickly and repeatably?

# Current Capabilities

These are implemented capabilities that should remain visible even when the active work has moved on:
- `https://localhost/terminal` provides fresh in-browser terminal sessions.
- `https://localhost/edit` provides a browser text editor for local files using the active signed-in user's filesystem permissions.
- The editor uses CodeMirror 6, stores unsaved drafts in browser local storage, and follows the shared terminal font, color scheme, and global light or dark appearance.
- `edit` from an in-browser terminal opens a new `/edit` tab rooted at the current directory, and `edit <path>` opens that file.
- The normal host launch path uses a browser tab as the default VM display, backed by local-only QEMU VNC WebSocket plus pinned noVNC assets.
- SPICE, SDL, and GTK remain explicit development display fallbacks.
- Browser-tab wheel capture preserves horizontal and vertical repeated steps and leftover delta before reaching QEMU.
- Firefox localhost shell behavior opens new tabs to `https://localhost/` and replaces last-tab closure with a localhost tab.
- In-VM development can use a host-shared repo mounted at `/source` through QEMU `virtiofs`.

# Current Focus

Milestones 1, 2, 3, and 4 are complete.

We are currently focused on Milestone 6.

Immediate next task:
- Record exact Firefox and nixpkgs identity for `patched-firefox` runs so developers can prove what runtime they validated before refreshing `patches/firefox/packaged/0001-close-last-tab-to-localhost.patch`.

Next steps from the patched-Firefox fast-loop attempt:
- Preserve the useful decision that `patched-firefox` should be the one-command operator path for launching a patched Firefox from inside the VM.
- Keep the useful decision that normal VM launch and pending browser patch testing are separate paths: `./launch-vm` should boot the regular packaged system from `patches/firefox/packaged`, while `patched-firefox` should be the explicit command for applying and launching pending Firefox patches from `patches/firefox/pending` on top of the packaged baseline.
- Keep the useful finding that the command must not evaluate the local `/source` flake on the launch path, because that causes Nix to copy the dirty source tree into the store before the browser can start.
- Keep the useful finding that a source-checkout workflow and an operator fast-launch workflow should be separate paths: source identity, checkout population, and full patch refresh are useful, but they should not sit on the critical path for `patched-firefox`.
- Keep the useful finding that the fast runtime should use the installed Firefox runtime, symlink unchanged runtime files, and copy only mutable `omni.ja` files before repacking browser chrome assets.
- `patched-firefox` now resolves `patch`, `filterdiff`, `zip`, and `unzip` through fixed Nix store paths instead of relying on the active system profile.
- `patched-firefox` now tolerates an unset `HOME` by resolving the passwd home directory before computing its default profile path.
- `patched-firefox` now infers `DISPLAY=:0` when the browser terminal session omits `DISPLAY` and `/tmp/.X11-unix/X0` exists.
- Packaged Firefox patches now live under `patches/firefox/packaged/`, and dev-only fast-loop patches now live under `patches/firefox/pending/`.
- A small explicit Sync/FxA UI patch exists at `patches/firefox/packaged/0002-hide-sync-fxa-ui.patch` and is part of the ordered packaged Firefox patch stack.
- The latest `patched-firefox` patch succeeded and the VM rebuild worked, preserving the new explicit in-VM operator path.
- The built `patched-firefox` command was smoke-tested inside the current ol-c guest with a temporary workspace/profile; it inferred the active X display, generated a patched runtime from `/run/current-system/sw/lib/firefox`, reached the Firefox exec path, and the generated `browser/omni.ja` contained both the localhost and Sync/FxA patch markers.
- Keep the boundary explicit in tests: packaged Nix paths must ignore `patches/firefox/pending`, and `patched-firefox` must apply `packaged` first and `pending` second.

Supported-branch validation status:
- The repo has moved from unsupported `nixos-24.11` to `nixos-25.11`.
- The fast deterministic contract checks pass:
  - `node --test localhost-ui/*.test.mjs`
  - `cd terminal-client && npm test && npm run build`
  - `bash tests/test-build-vm.sh`
  - `bash tests/test-launch-vm.sh`
  - `bash tests/test-build-firefox-remote.sh`
  - `bash tests/test-olc-firefox-dev.sh`
- `./build-vm` succeeds as the minimum real Nix build gate for the NixOS branch update.
- `./build-vm` also succeeds after adding the in-guest Firefox development-loop tooling.
- `./launch-vm` boots into the graphical browser surface and loads the localhost UI.
- The patched packaged Firefox build succeeds and reports `Mozilla Firefox 149.0.2`; the store output includes the ol-c localhost patch marker for the patched runtime assets.
- The fast packaged Firefox output now records both `OLC_FIREFOX_LOCALHOST_PATCH_APPLIED=1` and `OLC_FIREFOX_FXA_SYNC_UI_PATCH_APPLIED=1`.
- `./build-vm` succeeds after adding the `patched-firefox` operator path and the explicit Sync/FxA patch artifact.
- `./build-firefox-source-remote`, fetch, and `nix build .#firefox-localhost-source --print-build-logs` succeed, and subsequent runs reuse the local Nix store output quickly.

In-VM validation note:
- When Codex is running inside the ol-c guest, it can identify that context with `hostnamectl`, `systemd-detect-virt`, and `findmnt -T /source`.
- If `/source` is mounted from `ol-c-source` with `virtiofs`, Codex should treat edits as host-synced repo edits and can validate browser-surface work directly inside the guest.
- When a graphical Firefox session is running in the guest, Codex may use available local GUI automation tools such as `xdotool` to actively drive the browser for validation.

Shared journal mirror note:
- The canonical logs remain the guest's local `journald` store; the host-visible mirror lives at `/source/.olc-debug/journal/current.journal`.
- That file is an aggregate journal across the current VM and any recursively embedded child VMs that share the same `/source`.
- When working from the shared repo view, prefer standard journal tools against that file, for example `journalctl --file=/source/.olc-debug/journal/current.journal`.
- When investigating one VM, first filter by `_MACHINE_ID`, then narrow to `_BOOT_ID`, and use `OLC_VM_MACHINE_ID`, `OLC_VM_BOOT_ID`, `OLC_VM_PARENT_MACHINE_ID`, and `OLC_VM_DEPTH` to reconstruct nested lineage.
- If Codex is running inside the specific target VM, prefer direct `journalctl` against the local system journal over the shared mirror.

Security and update planning note:
- The repo has moved from unsupported `nixos-24.11` to `nixos-25.11`, with host build and VM boot validation complete.
- Relying on nixpkgs for Firefox security updates is the preferred path, but only if ol-c tracks a supported branch promptly.
- Distribution-system work is now explicitly split into prebuilt release artifacts, verified binary distribution, first install, and browser-facing updates.
- User-facing ol-c updates should eventually be exposed through the browser System page and backed by prebuilt verified artifacts.
- Users should not need to operate NixOS directly or compile Firefox locally to receive browser security updates.
- Rollback should be exposed as an ol-c product action backed by NixOS generations.

Implementation status:
- [x] Chose QEMU for the first development backend.
- [x] Chose a minimal custom nixOS guest as the first boot target.
- [x] Chose serial output as the Milestone 1 proof surface.
- [x] Added a minimal nix guest definition with a deterministic Milestone 1 boot marker.
- [x] Added a simple build script and QEMU launch script for Milestone 1.
- [x] Added a graphical Milestone 2 guest with autologin and Firefox.
- [x] Added tests for the build and launch contract for both milestones.
- [x] Verified the full Milestone 2 graphical boot and browser launch on an Ubuntu host with nix and QEMU/KVM installed.
- [x] Simplified the normal VM launcher so `./launch-vm` always boots the current graphical Milestone 2 guest, with milestone validation handled by build and test scripts.
- [x] Moved the normal graphical launch path to SPICE with `remote-viewer`, while keeping SDL and GTK as direct-display fallbacks for debugging.
- [x] Consolidated the historical milestone Nix modules into one canonical ol-c module at `nix/ol-c.nix`.
- [x] Proved the current Firefox source-patch flow end to end by building the patched browser, booting the guest with it, and verifying that closing the final tab reopens `https://localhost`.
- [x] Add a browser terminal proof surface at `https://localhost/terminal` where each visit creates a fresh session.
- [x] Use a browser terminal frontend and backend path that are robust enough for advanced interactive terminal programs.
- [x] Make the terminal page title follow the shell title stream when available, with a fallback title when not available.
- [x] Investigate and fix the remaining extra line shown after terminal command output.
- [x] Keep terminal behavior modular enough to test independently, including closing the browser tab when the root terminal session exits instead of showing a dead terminal interface.
- [x] Extend the Firefox localhost shell behavior so opening a new tab also loads `https://localhost/` without regressing the final-tab reopen behavior. (fix the fragile tab exit bug as well)
- [x] Add a Google Compute Engine VM helper for remote patched-Firefox builds with Cloud Storage result handoff, provider-enforced timeout deletion, and explicit kill/fetch/cleanup commands.
- [x] Split the Firefox packaged workflow into a fast browser-frontend repack target and a full source-build compatibility target.
- [x] Replace the current 5 minute idle timeout with a more reliable terminal session cleanup strategy.
- [x] Define the Milestone 3 browser-based system controls proof surface and test strategy.
- [x] Implement the first browser-visible system status surfaces for core device utilities.
- [x] Implement browser-driven control flows for the selected Milestone 3 utilities.
- [x] Add excellent automated coverage for the browser-to-system control contract.
- [x] Define the Milestone 4 synced in-VM development proof surface and test strategy.
- [x] Add one supported host↔guest shared repo mount path using `virtiofs`.
- [x] Enable in-guest development against the shared tree with a fixed mount location.
- [x] Add source-backed preview for localhost UI from `/source`, with terminal sessions owned by a stable service so Codex-driven edits do not kill the active terminal.
- [x] Document the validate-inside-VM, then package-with-Nix workflow for browser-surface changes.
- [x] Prove synced in-VM development against the host ol-c repo mounted at `/source`.
- [x] Move the repo from unsupported `nixos-24.11` to a currently supported NixOS branch and verify the VM still builds and boots.
- [x] Make the normal host VM launch use a browser tab as the default screen while keeping SPICE, SDL, and GTK available as explicit fallbacks.
- [x] Prove the first nested in-VM development launch: ol-c can run a child VM from the in-browser terminal using nested KVM, `/vm-images`, and the browser-tab screen flow.
- [x] Add a basic localhost text editor at `https://localhost/edit` with terminal launch integration and terminal setting reuse.
- [x] Add a development-loop proof for efficiently launching patched Firefox browser chrome from inside the VM to test patch edits.
- [x] Improve browser-tab VM wheel capture so horizontal and vertical scroll preserve repeated steps and leftover delta before reaching QEMU.
- [x] Add a first-boot browser setup kiosk that creates the first human admin through `systemd-homed` with LUKS-backed storage.
- [x] Switch tty1 from fixed autologin to dynamic behavior: setup autologin only before the first admin exists, normal username/password login afterward.
- [x] Replace hardcoded `demo` runtime assumptions in localhost terminal and editor paths with active console user resolution.
- [x] Add a Milestone 5 automated test-prefill path that bypasses manual first-user setup in VM/system tests.

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
