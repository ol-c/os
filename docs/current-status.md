# Current Status

## Current Capabilities

- `https://localhost/terminal` provides fresh in-browser terminal sessions.
- `https://localhost/edit` provides a browser text editor that uses the active signed-in user's filesystem permissions.
- First boot launches Firefox in kiosk mode on `https://localhost/setup` so setup can own the browser surface until the first admin is created.
- `edit` from an in-browser terminal opens `/edit`, and `edit <path>` opens a specific file.
- The normal `./launch-vm` path uses a browser tab as the VM display through local-only QEMU VNC WebSocket plus pinned noVNC assets.
- `./launch-vm` also bridges guest audio into that browser viewer through a local-only raw PCM stream captured from a per-VM Pulse/PipeWire sink.
- The browser viewer supports text copy out of the VM and keyboard or browser-menu text paste into the VM through the QEMU vdagent clipboard path.
- Firefox's hamburger menu includes ol-c restart and shutdown actions that call the localhost power API; guest shutdown leaves the browser viewer open with a local power-on button.
- `launch-vm` also exposes a local-only QMP socket and prints it as `qmp socket:`.
- `launch-vm` coordinates expected guest shutdown/restart through a per-VM lifecycle directory under `/source/.olc-debug/vm-lifecycle`.
- `launch-vm` can wait for the guest `olc-vm-ready` journal marker and surface readiness failures.
- In-VM development uses a host-shared repo mounted at `/source` via `virtiofs`.
- Nested `olc-launch-test-vm` launches default to a cheap child-boot path and print a reconnect URL for browser viewing.
- `olc-vmctl` provides low-level QMP control primitives including `key`, `type`, `move`, `click`, `screenshot`, and `raw`.
- Firefox localhost shell behavior opens new tabs to `https://localhost/` and replaces last-tab closure with a localhost tab.
- Noto is the default OS, browser-shell, terminal, editor, and generic browser font family set; the bundled baseline is Noto base, CJK Sans, CJK Serif, and Color Emoji.

## Current Focus

Active milestone:
- Milestone 7.

Immediate next task:
- Decide whether self-hosting ol-c development inside ol-c should be a primary workflow or a later capability.

Current Milestone 6 direction:
- Make the standard Firefox source-tree loop the primary development path for Firefox behavior changes.
- Keep the inner iteration loop fast: edit the shared source tree first, rebuild and relaunch the source-built browser, and only refresh repo patch artifacts after the UI is validated.
- Use a repo-level init step to prepare reusable shared Firefox assets safely on any host.
- Keep a pristine pinned Firefox source cache and the writable per-instance source trees under the shared repo-local gitignored workspace so host and child VMs can reuse build work.
- Apply `patches/firefox/packaged` first and `patches/firefox/pending` second onto that shared source tree.
- Keep the packaged Nix build and source-build paths as the gates for what ships.
- Use `olc-firefox-source` as the one-command in-VM entrypoint for shared Firefox source work.
- Normal VM launch and pending Firefox patch testing stay separate: `./launch-vm` boots the packaged system from `patches/firefox/packaged`, while `olc-firefox-source` applies `packaged` first and `pending` second in the shared source tree.
- Packaged Firefox patches live under `patches/firefox/packaged/`; dev-only fast-loop patches live under `patches/firefox/pending/`.
- Keep the packaged Nix paths explicitly blind to `patches/firefox/pending` in tests.

Parallel Milestone 6 track:
- Define a host-driven VM operator proof where a host launches a VM, submits work, watches it happen live, and verifies completion through shared artifacts and logs.
- Use the shared `/source` mount as the first host-to-guest control channel rather than requiring guest networking first.
- Keep the embedded browser viewer as the human observation surface, not the main automation API.
- Use a guest-resident operator path for visible work where appropriate, with `xdotool` available for first-pass GUI automation.
- Prefer a parent-to-child Firefox BiDi bridge for page-level control of a child VM's browser session; keep `olc-vmctl` as the lower-level fallback for raw input and screenshots.

Related design notes:
- `docs/firefox-source-workflow-plan.md` holds the current shared source-tree workflow plan.
- `docs/host-driven-vm-operator-plan.md` holds the current operator-proof plan.
- Firefox tab/session preservation across Firefox-menu restart and shutdown is not guaranteed yet; a future task should configure session restore and validate restored tabs in child VMs after restart and after shutdown plus viewer power-on.

## Validation Status

- The repo has moved from unsupported `nixos-24.11` to `nixos-25.11`.
- Milestone 6 success criteria are confirmed:
  - Build and launch behavior are predictable.
  - Rebuild versus reuse behavior is explicit.
  - Fast iteration does not undermine reproducibility.
  - The source-tree loop records the exact Firefox and `nixpkgs` identity being tested.
  - A developer can validate Firefox behavior in the guest before refreshing `patches/firefox/packaged/0001-close-last-tab-to-localhost.patch`.
  - The packaged build remains the gate for what ships.
- Fast deterministic checks currently passing:
  - `node --test localhost-ui/*.test.mjs`
  - `node --test vm-screen/server.test.mjs`
  - `cd terminal-client && npm test && npm run build`
  - `bash tests/test-build-vm.sh`
  - `bash tests/test-launch-vm.sh`
  - `bash tests/test-noto-fonts.sh`
  - `bash tests/test-build-firefox-remote.sh`
  - `bash tests/test-firefox-localhost-patch.sh`
  - `bash tests/test-olc-firefox-source.sh`
- The recommended shared source-tree loop is documented in `README.md` and `docs/firefox-source-workflow-plan.md`.
- The current dev-only proof patch adds an appearance toggle button beside the unified extensions button from `patches/firefox/pending/0003-add-plugin-button-dev-icon.patch`.
- A full standard source build succeeded with `./olc-firefox-source mach build -j 1`, and the source-built browser launched successfully as `Mozilla Firefox 149.0.2`.
- Incremental browser-chrome rebuilds succeed with `./olc-firefox-source mach build faster`.
- The current pending proof patch dry-runs cleanly against a packaged-only source baseline before it is refreshed in the repo.
- `./build-vm` succeeds.
- `./launch-vm` boots to the graphical browser surface and loads the localhost UI.
- A nested child built from `./build-vm` has been manually validated through Firefox-menu restart, re-login, Firefox-menu shutdown, viewer power-on, and re-login using the shared journal mirror plus browser BiDi checks.
- The packaged Firefox build succeeds and reports `Mozilla Firefox 149.0.2`.
- The fast packaged Firefox output records `OLC_FIREFOX_LOCALHOST_PATCH_APPLIED=1`, `OLC_FIREFOX_FXA_SYNC_UI_PATCH_APPLIED=1`, and `OLC_FIREFOX_POWER_MENU_PATCH_APPLIED=1`.
- `./build-firefox-source-remote`, fetch, and `nix build .#firefox-localhost-source --print-build-logs` succeed, with later local builds reusing the imported result.
