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
- Display a local milestone page inside the guest browser as the proof target.

Success criteria:
- The guest boots into a graphical session.
- QEMU opens a visible VM display window on the host.
- Firefox launches automatically inside the guest.
- The visible in-guest page includes a deterministic success marker: `MILESTONE2_BROWSER_OK`.

Out of scope:
- Remote browser access from the host
- Full onboarding
- Durable setup state
- Rich product behavior beyond proving the browser surface exists

Question this milestone answers:
- Can the OS launch and visibly present a real browser inside the guest itself?

## Milestone 3: First-Time Setup and Persistence

Goal:
- Implement first boot onboarding and persist machine state.

Success criteria:
- A fresh machine state shows onboarding on first boot.
- Completing setup writes durable machine state.
- A later boot of the same machine state skips onboarding.
- Automated tests can bypass the manual setup flow through a test prefill path.

Question this milestone answers:
- Can the system transition cleanly from unconfigured to configured state?

## Milestone 4: Development Loop

Goal:
- Tighten the build and launch workflow for normal development.

Success criteria:
- The build flow is predictable.
- The launch flow is predictable.
- Rebuild versus reuse behavior is explicit.
- The workflow supports fast iteration without undermining reproducibility.

Examples of things that may belong here:
- Build orchestration
- Artifact manifests
- Overlays or snapshots
- Better launch scripts

Question this milestone answers:
- Do we have a development workflow that is practical and repeatable?

## Milestone 5: Self-Hosted Development

Goal:
- Evaluate and possibly support development from inside the OS itself.

Success criteria:
- We define what “develop inside the OS” actually means.
- We understand the constraints around editing, building, testing, and nested virtualization.
- We decide whether self-hosting is a primary workflow or a later capability.

Question this milestone answers:
- Can this OS become a practical environment for developing itself?

# Current Focus

We are currently focused on Milestones 1 and 2.

Implementation status:
- [x] Chose QEMU for the first development backend.
- [x] Chose a minimal custom nixOS guest as the first boot target.
- [x] Chose serial output as the Milestone 1 proof surface.
- [x] Added a minimal nix guest definition with a deterministic Milestone 1 boot marker.
- [x] Added a simple build script and QEMU launch script for Milestone 1.
- [x] Added a graphical Milestone 2 guest with autologin and Firefox.
- [x] Added tests for the build and launch contract for both milestones.
- [ ] Verify the full Milestone 2 graphical boot and browser launch on an Ubuntu host with nix and QEMU/KVM installed.

# Deferred Decisions

The following are intentionally not locked in yet:
- Networking model
- Browser UI stack after the current Firefox proof
- Automatic rebuild policy
- Persistent overlays and snapshots beyond the current QEMU `-snapshot` dev behavior
- First-time setup data shape
- Long-term VM backend choice outside these milestones

These decisions should be made when a later milestone actually requires them.
