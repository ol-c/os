# Development Notes

## In-VM Validation

- If Codex is running inside the ol-c guest and `/source` is the `ol-c-source` `virtiofs` mount, treat edits as host-synced repo edits and validate browser-surface work directly in the guest.
- When a graphical Firefox session is live in the guest, local tools such as `xdotool` may be used for validation.

## Standard Firefox Source Loop Notes

- Treat the shared source tree under `.olc-firefox/instances/.../source` as the fast working area. For UI iteration, edit that tree first instead of editing `patches/firefox/pending/*.patch` by hand.
- The fast inner loop in this VM is: edit the shared source tree, run `./olc-firefox-source mach build faster`, then relaunch the source-built browser with `DISPLAY=:0 XAUTHORITY=/home/jason/.Xauthority ./olc-firefox-source mach run -- --new-window about:blank`.
- When validating localhost startup or new-tab behavior specifically, relaunch on `https://localhost/` or through normal startup; `about:blank` bypasses that contract and is only the generic fast UI loop target.
- For a visible source-built browser inside an already-logged-in guest, prefer `olc-firefox-source open-window https://localhost/` over `mach run`. That helper launches `objdir/dist/bin/firefox` directly, disables Firefox DBus remoting and process handoff, resolves the live X session env automatically, and seeds an isolated profile with the same localhost trust prefs as the packaged session so `https://localhost/` does not fall back to the certificate warning page.
- Keep patch refresh separate from visual iteration. Once the browser UI looks correct, regenerate or refresh the pending patch from the live source diff, then rerun `bash tests/test-olc-firefox-source.sh` and `bash tests/test-firefox-localhost-patch.sh`.
- If `olc-firefox-source` warns that the existing instance uses a different patch fingerprint, that warning is expected after repo patch edits. Use `olc-firefox-source recreate` only when the shared source tree itself must be rebuilt from the repo patch stack; avoid it during rapid live-source iteration.
- The shared source workflow makes rebuild-versus-reuse behavior explicit, but first-time initialization is still expensive because the pinned Firefox source archive and build environment must be realized locally. A future speed-up option is to consume a trusted remote cache if the upstream Nix project provides one for this path, or to host an ol-c-controlled cache once that tradeoff is worth the operational cost.
- `mach run` from this shell does not inherit the desktop session automatically. A `no DISPLAY environment variable specified` failure is an environment issue here, not a Firefox build failure.
- Full clean source builds are much heavier than the fast loop in this VM. Prefer low parallelism such as `CARGO_BUILD_JOBS=2 ./olc-firefox-source mach build -j 2` or `./olc-firefox-source mach build -j 1` for clean proof builds; earlier higher-parallel runs were killed by OOM during mixed Rust and C++ compilation.
- The shared source loop currently depends on the repo defaults that keep Firefox on the standard Clang/lld toolchain, normalize `AS` and `HOST_AS` away from raw `as`, and keep WASI linker flags from leaking into native link steps.
- The direct browser-chrome new-tab path now uses the canonical `https://localhost/` URL through `BROWSER_NEW_TAB_URL`. Because that URL is not an `about:` page, `browser/components/tabbrowser/NewTabPagePreloading.sys.mjs` must keep preloading disabled for that path; otherwise Firefox can consume a preloaded hidden `about:blank` browser and surface a blank visible tab.
- Firefox browser-chrome Mochitest runs were not a dependable signal in this VM session because startup automation failed before the test body ran due to missing `DISPLAY`, leftover Mochitest helper processes and ports after failed runs, and a later Marionette startup error. For now, treat the shared source build, patch dry-run, repo shell guards, and live source-built browser behavior as the reliable Milestone 6 validation loop here.

## Host-Driven Live Analysis

- A parent ol-c guest can act as the effective host operator for a nested child VM by launching `olc-launch-test-vm`, opening the printed reconnect URL, and keeping that viewer open as the observation surface.
- For page-level analysis or DOM work inside a child Firefox session, prefer `olc-vm-bidi` over noVNC or QMP input injection.
- Use the reconnect URL as the human proof surface and BiDi results plus `journald` as the machine-verifiable proof surface.

## Shared Journal Mirror

- The canonical logs remain the guest's local `journald` store; the host-visible mirror lives under `/source/.olc-debug/journal`.
- Each VM mirrors its current boot into its own native journal file in that directory.
- When working from the shared repo view, prefer `journalctl --directory=/source/.olc-debug/journal`.
- The `olc-vm-ready` marker means the active local Firefox session has published its BiDi endpoint.
- When investigating one VM, filter by `_MACHINE_ID` first, then `_BOOT_ID`, and use `OLC_VM_MACHINE_ID`, `OLC_VM_BOOT_ID`, `OLC_VM_LIFECYCLE_ID`, `OLC_VM_PARENT_MACHINE_ID`, and `OLC_VM_DEPTH` to reconstruct nested lineage.

## Quality of Life Backlog

- Current select boxes like mute and light/dark mode should be toggle buttons with appropriate unicode icons.
- `Ctrl+S` crashes Firefox.
- `Ctrl+Shift+C` should not open dev tools in the VM; it should map to copy.
- Make sure the password-save offer on initial account creation does not show.
- Preserve and validate Firefox tabs/session state across Firefox-menu restart, guest shutdown, and viewer power-on by opening multiple tabs in a child VM and asserting they restore after the lifecycle completes.
- Investigate browser terminal breakage after printing nested-child serial boot output with heavy raw OSC/ANSI control sequences; likely fix is to filter or redirect that boot stream before it hits the browser terminal session.
- Investigate Codex CLI exits back to a raw shell prompt during nested-child launch work; the likely trigger is the same unfiltered serial boot/control-sequence stream reaching the interactive Codex terminal, so prefer redirecting child serial logs to files and only tailing filtered output on demand.
- Investigate Codex CLI exits during long `Working` periods with multiple background terminal sessions open; the likely mitigation is to avoid stacked long-lived waits or pollers and prefer short explicit polling commands with no lingering background terminals.
