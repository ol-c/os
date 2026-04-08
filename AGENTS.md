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

Success criteria:
- There is one documented host setup path.
- There is one documented command to build and boot the guest.
- The guest boots successfully in a repeatable way.
- Boot success is visible through serial log, console output, or another equally direct proof.

Out of scope:
- Browser UI
- First-time setup flow
- Persistent machine state
- Self-hosted development inside the guest

Question this milestone answers:
- Can we reliably build and run the base OS at all?

## Milestone 2: Reachable Browser UI

Goal:
- Serve a minimal browser UI from inside the guest and reach it from the host.

Success criteria:
- The guest boots into a running networked system.
- The host can open a browser page served by the guest.
- The page can be intentionally minimal and only needs to prove the browser-first UI model.

Out of scope:
- Full onboarding
- Durable setup state
- Rich product behavior

Question this milestone answers:
- Can the OS actually present its UI through the browser model?

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

We are currently focused on Milestone 1.

The next thing to decide is:
- What exact artifact we want to boot first.
- What the simplest acceptable proof of boot success is.
- Whether the first implementation should optimize for fastest prototype or long-term architecture.

# Deferred Decisions

The following are intentionally not locked in yet:
- Primary VM backend
- Direct kernel boot versus other boot paths
- Networking model
- Artifact manifest format
- Auto-build behavior in the launcher
- Persistent overlays and snapshots
- First-time setup data shape

These decisions should be made when a milestone actually requires them.
