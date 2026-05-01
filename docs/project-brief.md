# ol-c Project Brief

## Purpose

Build a secure NixOS-based OS whose primary user interface is the browser.

## Planning Rule

Define milestones by the proof they provide, not by premature architecture choices.

- Decide what must be demonstrated.
- Choose the minimum implementation that proves it.
- Avoid locking in VM, boot, networking, packaging, or orchestration details before a milestone requires them.

## Roadmap

### Completed Milestones

- Milestone 1: reproducible NixOS guest boot on an Ubuntu host.
- Milestone 2: graphical in-guest browser UI.
- Milestone 3: browser-based system controls.
- Milestone 4: synced in-VM development against a host-shared repo.
- Milestone 5: first-boot onboarding, persistent machine state, and a test-prefill path.
- Milestone 6: predictable, fast, and reproducible Firefox and VM development loop.

### Milestone 6: Development Loop

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
- Embedded VM creation should allow for setting up a test user account, so tests can skip authentication for user-layer changes.

Success criteria:
- Build and launch behavior are predictable.
- Rebuild versus reuse behavior is explicit.
- Fast iteration does not undermine reproducibility.
- The source-tree loop records the exact Firefox and `nixpkgs` identity being tested.
- A developer can validate Firefox behavior in the guest before refreshing `patches/firefox/packaged/0001-close-last-tab-to-localhost.patch`.
- The packaged build remains the gate for what ships.

Question this milestone answers:
- Do we have a practical, repeatable development workflow?

### Milestone 7: Self-Hosted Development

Goal:
- Decide whether developing ol-c from inside ol-c is a primary workflow or a later capability.

Success criteria:
- “Develop inside the OS” is defined concretely.
- Editing, building, testing, and nested-virtualization constraints are understood.
- We decide whether self-hosting is primary or deferred.

Question this milestone answers:
- Can the OS become a practical environment for developing itself?

### Milestone 8: Browser Accountability and Activity Visibility

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

### Milestone 9: User-Facing System Updates and Rollback

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

### Milestone 10: Prebuilt Release Artifacts

Goal:
- Produce ol-c release artifacts that downstream users can install or boot without running `nix build`.

Success criteria:
- A trusted local or CI builder can produce `.#ol-c-image` from a validated repo state.
- Release output records the ol-c revision, `nixpkgs` revision, Firefox version, artifact path, hashes, and logs.
- The release path proves Firefox patch gates and VM boot before publication.
- Automated tests cover the release manifest contract.

Question this milestone answers:
- Can ol-c turn a validated repo state into a reusable downstream artifact?

### Milestone 11: Verified Binary Distribution

Goal:
- Publish verifiable ol-c artifacts and Nix closures so users download trusted binaries instead of compiling locally.

Success criteria:
- Published artifacts include signatures, hashes, or an equivalent verification mechanism.
- Install or update fails closed on missing or untrusted verification data.
- The distribution path can provide the Nix closure required by the release artifact.
- Automated tests cover both verification success and failure.

Question this milestone answers:
- Can users safely consume ol-c builds without trusting local compilation?

### Milestone 12: Installer and First Install Path

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

## Deferred Decisions

The following are intentionally not locked in yet:

- Networking model
- Browser UI stack after the current Firefox proof
- Automatic rebuild policy
- Persistent overlays and snapshots beyond the current QEMU `-snapshot` dev behavior
- First-time setup data shape
- Long-term VM backend choice outside these milestones

These decisions should be made when a later milestone actually requires them.
