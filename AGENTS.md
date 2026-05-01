You are running in a VM, so you have full control of installing tools, launching local services, and running anything needed to validate changes.

# Purpose

Build a secure NixOS-based OS whose primary user interface is the browser.

# Agent Guidance

- Keep automated coverage strong. A task is only complete when the relevant automated checks have been run or you have a concrete reason they could not be run.
- Prefer milestones and implementation steps that prove behavior with the minimum necessary machinery.
- Do not lock in VM, boot, networking, packaging, or orchestration details before a milestone requires them.
- Keep the canonical project documents current when decisions or validation status change.

# Doc Map

- Project brief: [docs/project-brief.md](docs/project-brief.md)
  Purpose, planning rule, roadmap, and deferred decisions.
- Current status: [docs/current-status.md](docs/current-status.md)
  Current capabilities, active focus, and documented validation gates.
- Development notes: [docs/development-notes.md](docs/development-notes.md)
  In-VM workflow notes, Firefox source-loop notes, nested VM notes, and backlog items.

# Validation Expectations

- Prefer deterministic automated checks first.
- Validate browser-surface changes directly in the guest when the graphical session is live.
- When Firefox behavior changes are involved, keep the fast source-tree loop separate from packaged patch refresh and shipping gates.

# In-VM Operations

- If Codex is running inside the ol-c guest and `/source` is the `ol-c-source` `virtiofs` mount, treat edits as host-synced repo edits and validate browser-surface work directly in the guest.
- When a graphical Firefox session is live in the guest, local tools such as `xdotool` may be used for validation.
- For embedded VM analysis, prefer Firefox BiDi helpers for page-level control and `olc-vmctl` as the lower-level fallback.

# Shared Journal Mirror

- The canonical logs remain the guest's local `journald` store; the host-visible mirror lives under `/source/.olc-debug/journal`.
- Each VM mirrors its current boot into its own native journal file in that directory.
- When working from the shared repo view, prefer `journalctl --directory=/source/.olc-debug/journal`.
- The `olc-vm-ready` marker means the active local Firefox session has published its BiDi endpoint.
- When investigating one VM, filter by `_MACHINE_ID` first, then `_BOOT_ID`, and use `OLC_VM_MACHINE_ID`, `OLC_VM_BOOT_ID`, `OLC_VM_PARENT_MACHINE_ID`, and `OLC_VM_DEPTH` to reconstruct nested lineage.
