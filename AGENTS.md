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

## Milestone 1: Reproducible Guest Boot

Goal:
- Boot a reproducible nixOS-based guest on an Ubuntu host.

Milestone 1 decisions:
- Use QEMU as a development backend for fast local iteration.
- Use a minimal custom nixOS guest owned by this repo.
- Require KVM acceleration on the Ubuntu host.
- Boot a normal disk image rather than using direct kernel boot.
- Treat serial output as the proof surface for success.

Success criteria:
- There is one documented host setup path.
- There is one documented command to build and boot the guest.
- The guest boots successfully in a repeatable way.
- Serial output includes a deterministic success marker: `MILESTONE1_BOOT_OK`.

Out of scope:
- Browser UI
- First-time setup flow
- Persistent machine state
- Self-hosted development inside the guest
- VM backend abstraction
- Auto-build manifests, overlays, and snapshot management beyond the minimum needed to boot

Question this milestone answers:
- Can we reliably build and run the base OS at all?

## Milestone 2: In-Guest Browser UI

Goal:
- Boot a graphical guest session and launch a real browser inside the VM.

Milestone 2 decisions:
- Use the same QEMU development backend as Milestone 1.
- Keep the browser inside the VM rather than using the host browser.
- Use a graphical QEMU window instead of a serial-only boot flow.
- Autologin into a lightweight graphical session and start Firefox automatically.
- Use Firefox itself as the visible UI shell for the guest session.

Success criteria:
- The guest boots into a graphical session.
- QEMU opens a visible VM display window on the host.
- Firefox launches automatically inside the guest.
- Firefox opens as a normal interactive browser session and fills the VM display.

Out of scope:
- Remote browser access from the host
- Full onboarding
- Durable setup state
- Rich product behavior beyond proving the browser surface exists

Question this milestone answers:
- Can the OS launch and visibly present a real browser inside the guest itself?

## Milestone 3: Browser-Based System Controls

Goal:
- Expose the core computer management controls through the browser interface inside the guest.

Milestone 3 decisions:
- Keep the browser as the primary control surface rather than introducing a separate native settings app.
- Use `https://localhost` inside the guest as the initial Milestone 3 browser origin, served locally by a Node.js process on port `443`.
- Use `https://localhost/terminal` as the next Milestone 3 proof surface: each access should create a fresh in-guest browser terminal session.
- Keep the Firefox localhost patch work, including opening new tabs to `https://localhost`, as a deferred follow-on after the browser terminal proof.
- Focus on the basic machine controls users expect immediately: Wi-Fi and general network state, battery and power status, volume, display brightness, appearance mode such as light mode and dark mode, and Bluetooth.
- Prioritize proving visibility and control of live system state over polishing the final information architecture.
- Prefer the minimum guest-side services and browser UI needed to demonstrate these controls end to end.

Success criteria:
- The browser UI shows current state for the core device utilities we care about.
- The browser UI can trigger changes for the controls that are meant to be interactive.
- At minimum, the milestone demonstrates browser-accessible management for Wi-Fi or network state, battery or power status when available, volume, brightness, appearance mode, and Bluetooth state.
- The guest reflects user-triggered changes in a way that is observable and testable.
- Automated tests cover the browser-to-system control contract with deterministic fakes or controlled test hooks where direct hardware access is not reliable.

Question this milestone answers:
- Can the browser act as the basic control panel for managing the computer itself?

## Milestone 4: Synced In-VM Development

Goal:
- Enable practical development from inside the guest against a host-shared ol-c repo.

Milestone 4 decisions:
- Use QEMU `virtiofs` as the only supported first shared-directory path.
- Mount the whole ol-c repo into the guest, read-write.
- Treat the shared host repo as the durable source of truth.
- Allow in-guest Codex-assisted development against that mounted repo.
- Use the in-VM workflow to validate browser-surface changes before updating packaged artifacts.
- Defer efficient Firefox source-tree launch and patch validation from inside the VM to a later development-loop milestone.
- Keep final Nix packaging and VM-image integration as a separate explicit step after in-VM validation.

Success criteria:
- There is one documented host setup path for synced in-VM development.
- There is one documented command to launch the VM with the shared repo mounted.
- The mounted repo is visible and writable inside the guest at a fixed path.
- A developer can edit files inside the VM and see those changes immediately on the host.
- A developer can validate a browser-surface change inside the VM without rebuilding the full Nix-packaged image on every source edit.
- After validation, the developer can update the repo patch artifact and run the final packaged build path intentionally.

Out of scope:
- Replacing the final Nix packaging path
- Multiple shared-folder backends
- Full self-hosting as the primary development model
- Multi-user sync, remote sync, or networked dev environments

Question this milestone answers:
- Can we make browser and Firefox development practical by working inside the VM against a shared repo, while keeping the host repo and Nix packaging as the final source of truth?

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
- A developer can validate Firefox source-tree behavior in the guest before refreshing `patches/firefox/0001-close-last-tab-to-localhost.patch`.
- The final packaged build path remains the gate for what the distro will ship.
- The normal host launch path should use a browser tab as the VM display by default, using local-only QEMU VNC WebSocket plus pinned noVNC assets, while keeping SPICE/SDL/GTK as explicit development fallbacks.

Examples of things that may belong here:
- Build orchestration
- Artifact manifests
- Overlays or snapshots
- Better launch scripts
- Efficiently launching a Firefox source-tree build from inside the VM to test patch edits before refreshing `patches/firefox/0001-close-last-tab-to-localhost.patch`
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
- ol-c should publish prebuilt, signed or otherwise verified update artifacts before offering an update to users.
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

# Current Focus

Milestones 1, 2, 3, and 4 are complete.

We are currently focused on Milestone 6.

Immediate next task:
- Refresh `patches/firefox/0001-close-last-tab-to-localhost.patch` for Firefox `149.0.2` from the `nixos-25.11` update; the current build fails because the `browser/base/content/browser.js` hunk no longer matches the extracted runtime asset.
- After the Firefox patch refresh, rerun the supported-branch validation build and boot checks.
- After the supported-branch update is proven, add a development-loop proof for efficiently launching a Firefox source-tree build from inside the VM to test patch edits.

Supported-branch validation next steps:
- Run the fast deterministic contract checks:
  - `node --test localhost-ui/*.test.mjs`
  - `cd terminal-client && npm test && npm run build`
  - `bash tests/test-build-vm.sh`
  - `bash tests/test-launch-vm.sh`
  - `bash tests/test-build-firefox-remote.sh`
- Run `./build-vm` as the minimum real Nix build gate for the NixOS branch update.
  - Current known blocker: Firefox `149.0.2` patch drift in `browser/base/content/browser.js`; refresh the repo patch before rerunning this gate.
- Run `./launch-vm` as the VM smoke proof that the rebuilt image still boots into the graphical browser surface.
- Run `nix build .#firefox-localhost-source --print-build-logs` before considering Firefox patch compatibility proven against the updated nixpkgs Firefox source build path.

In-VM validation note:
- When Codex is running inside the ol-c guest, it can identify that context with `hostnamectl`, `systemd-detect-virt`, and `findmnt -T /source`.
- If `/source` is mounted from `ol-c-source` with `virtiofs`, Codex should treat edits as host-synced repo edits and can validate browser-surface work directly inside the guest.
- When a graphical Firefox session is running in the guest, Codex may use available local GUI automation tools such as `xdotool` to actively drive the browser for validation.

Security and update planning note:
- The repo has been prepped to move from unsupported `nixos-24.11` to `nixos-25.11`; the host build and VM boot still need to prove the update.
- Relying on nixpkgs for Firefox security updates is the preferred path, but only if ol-c tracks a supported branch promptly.
- User-facing ol-c updates should eventually be exposed through the browser System page and backed by prebuilt artifacts.
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
- [ ] Move the repo from unsupported `nixos-24.11` to a currently supported NixOS branch and verify the VM still builds and boots.
- [x] Make the normal host VM launch use a browser tab as the default screen while keeping SPICE, SDL, and GTK available as explicit fallbacks.
- [x] Prove the first nested in-VM development launch: ol-c can run a child VM from the in-browser terminal using nested KVM, `/vm-images`, and the browser-tab screen flow.
- [ ] Add a development-loop proof for efficiently launching a Firefox source-tree build from inside the VM to test patch edits.

Known bugs to track:
- [x] Firefox localhost replacement is too fragile: when the last terminal tab closes itself after root shell exit, Firefox does not open a replacement `https://localhost` tab. The terminal page should not own this; fix the browser shell patch so all last-tab closure paths get the localhost replacement behavior.

# Deferred Decisions

The following are intentionally not locked in yet:
- Networking model
- Browser UI stack after the current Firefox proof
- Automatic rebuild policy
- Persistent overlays and snapshots beyond the current QEMU `-snapshot` dev behavior
- First-time setup data shape
- Long-term VM backend choice outside these milestones

These decisions should be made when a later milestone actually requires them.
