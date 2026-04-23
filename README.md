# ol-c Prototype

This repo currently has one graphical QEMU/KVM development VM that boots the current ol-c browser surface.

## Current VM

Build the current VM image with:

```sh
./build-vm
```

Proof of success:
- QEMU opens a VM window
- Firefox launches automatically inside the guest
- Firefox opens `https://localhost` as a normal interactive browser session
- the browser window is maximized to fill the VM display
- Closing the final tab keeps the window open and reopens `https://localhost`

Build and launch it with:

```sh
./launch-vm
```

## Firefox Build Paths

ol-c uses pinned nixpkgs Firefox for both browser package paths. We do not carry a separate Firefox source or version.

| Path | Use it for | What it proves |
| --- | --- | --- |
| `.#firefox-localhost` | Normal VM and packaged browser checks | The guest can run the patched browser chrome used by `.#ol-c-image` without a full Firefox source compile. |
| `.#firefox-localhost-source` | Final source-build compatibility gate | The repo patch still applies through the pinned nixpkgs Firefox source build pipeline. |
| `patched-firefox` | In-VM operator loop | A developer can launch a patched runtime from the installed Firefox without evaluating the dirty `/source` flake. |

Normal VM validation:

```sh
nix build .#firefox-localhost --print-build-logs
./build-vm
./launch-vm
```

Heavy source-build validation:

```sh
./build-firefox-source-remote
nix build .#firefox-localhost-source --print-build-logs
```

The source gate is intentionally slower. It appends the repo patch to pinned nixpkgs `firefox-unwrapped` before Firefox is built. The remote wrapper moves that heavy compile off the local machine and imports the resulting Nix closure; the follow-up local `nix build` should reuse that imported result for the same repo state.

`launch-vm` uses a browser tab as the default VM display. QEMU exposes the VM display through a local-only VNC WebSocket endpoint, and a small repo-owned viewer page uses pinned noVNC assets to render the VM screen in the browser. It also mounts this repo read-write inside the guest at `/source` using QEMU virtiofs, so the in-browser terminal can edit the same source tree that is visible on the host.

The browser display path uses the repo-pinned patched QEMU package exposed as `.#qemu-olc`. The patch preserves horizontal wheel events from noVNC/QEMU VNC and carries them through the USB HID tablet path as AC Pan events. The browser frontend keeps QEMU vdagent clipboard support enabled, disables vdagent mouse forwarding, and disables legacy PS/2/vmport input so VNC pointer input reaches the patched USB tablet path. This build is separate from the VM image and can be built explicitly:

```sh
nix build .#qemu-olc --print-out-paths --no-link
```

For debugging with an already-built QEMU binary:

```sh
OLC_QEMU_BIN=/path/to/qemu-system-x86_64 ./launch-vm
```

`launch-vm` boots from a disposable qcow2 overlay whose virtual size defaults to `64G`, so the guest has enough temporary `/nix` space for development builds without mutating the built base image. Override it when needed:

```sh
OLC_VM_DISK_SIZE=96G ./launch-vm
```

Before booting, `launch-vm` also verifies that the host source directory can create files and directories. If that check fails, the guest would mount `/source` in a state where existing files may be editable but new files cannot be created, which is not a valid synced-development setup. When the host `virtiofsd` supports it, the launcher maps guest `demo` UID/GID `1000:1000` to the host launcher UID/GID so in-guest edits create host-owned files instead of depending on matching numeric IDs.

The browser display path is local development only for now: the viewer server and QEMU VNC WebSocket listener bind to `127.0.0.1`. If the browser does not open automatically, use the printed `browser url:` line.

SPICE remains available as an explicit fallback, and SDL/GTK remain available as direct QEMU display fallbacks:

```sh
OLC_QEMU_FRONTEND=spice ./launch-vm
OLC_QEMU_FRONTEND=sdl ./launch-vm
OLC_QEMU_FRONTEND=gtk ./launch-vm
OLC_QEMU_DISPLAY='gtk,gl=off,zoom-to-fit=off' ./launch-vm
```

The SDL and GTK scaling knobs are also overrideable for direct-display debugging:

```sh
OLC_QEMU_SDL_VIDEO_HIGHDPI_DISABLED=0 ./launch-vm
OLC_QEMU_GDK_SCALE=2 OLC_QEMU_GDK_DPI_SCALE=0.5 ./launch-vm
```

## Milestone 4 In-VM Development

`./launch-vm` mounts the host repo into the guest at:

```sh
/source
```

The mount is read-write. The `demo` user is pinned to UID `1000` and primary GID `1000`. When the host `virtiofsd` supports ID translation, `./launch-vm` maps that guest identity to the host user running the launcher so in-guest file creation works even when the host repo owner uses a different numeric UID or GID. If `virtiofsd` does not support ID translation, the host repo still needs permissions that allow the guest numeric identity to create files and directories.

The localhost UI service uses the packaged Nix store source by default, but when `/source/localhost-ui/server.mjs` exists it runs the service from `/source` instead. The source preview supervisor watches `/source/localhost-ui`; when those files change it restarts the HTTPS UI service. Refresh `https://localhost/` in Firefox to see server-side UI updates.

For terminal client changes, run this inside `/source/terminal-client`:

```sh
npm run watch
```

That rebuilds `dist/terminal.js` as `src` changes. The rebuilt assets are used by the stable terminal service after the VM image or service is refreshed.

The terminal service is intentionally stable and separate from the reloadable UI preview service. `https://localhost/terminal` remains the user-facing entry point, but the terminal page loads assets and connects its backend websocket directly to the stable terminal backend on `https://localhost:9443`. Existing terminal tabs keep running while `ol-c-ui` restarts. Rebuilt terminal client assets apply to newly opened `/terminal` tabs after the VM image or stable terminal service is updated. Firefox binary and browser chrome package changes still use the intentional packaged workflow below.

The guest also exposes a basic browser text editor at:

```sh
https://localhost/edit
```

From `https://localhost/terminal`, run:

```sh
edit
edit localhost-ui/server.mjs
```

`edit` opens a new `/edit` browser tab rooted at the current directory. `edit <path>` opens that file, resolving relative paths from the current directory. The editor uses CodeMirror 6, stores unsaved drafts in browser local storage, reads and writes with the demo user's filesystem permissions, and follows the existing terminal font/color-scheme settings plus the global light/dark appearance mode. It intentionally reuses the terminal settings contract rather than adding separate editor preferences.

The guest includes a `codex` command for in-VM development. From `https://localhost/terminal`, run:

```sh
cd /source
codex
```

The wrapper uses `npx` to run the pinned `@openai/codex` CLI, defaults to `CODEX_MODEL=gpt-5.4`, and passes `--dangerously-bypass-approvals-and-sandbox` so Codex can make full-system development changes inside this disposable VM. The `demo` user has passwordless `sudo` through the `wheel` group for the same reason. This is a development VM convenience, not the intended production OS security posture.

## Nested In-VM VM Development

With nested KVM enabled on the Ubuntu host, the ol-c guest can start a child ol-c VM from an ol-c terminal tab and view that child VM in another browser tab.

The host launcher exposes the image it booted from to the parent guest at:

```sh
/vm-images
```

Inside `https://localhost/terminal`, run:

```sh
olc-launch-test-vm
```

The wrapper:
- uses `/source` as the editable repo when it is the expected `ol-c-source` virtiofs mount
- uses the first bootable image in `/vm-images` unless `OLC_VM_IMAGE=/path/to/image.qcow2` is set
- uses `/var/lib/ol-c/vms` for child VM runtime temp files
- starts the child VM through the same browser-tab display path as host `./launch-vm`
- prints a reconnect URL for the child VM screen

If you want to test a specific prebuilt image inside the parent guest:

```sh
OLC_VM_IMAGE=/vm-images/guest.qcow2 olc-launch-test-vm
```

This proof prefers image reuse over building a full image inside the parent VM. Local in-guest `./build-vm` remains guarded by the `/nix` free-space check.

## Nix Layout

`vm-screen/server.mjs` is the browser viewer used by the default launcher. It serves a local page and pinned noVNC assets; QEMU provides the VNC WebSocket endpoint directly, so this path does not require `remote-viewer` or `websockify`.

`nix/ol-c.nix` is the current guest entry point. It imports focused modules from `nix/modules/`:
- `base.nix` owns boot, qemu guest support, serial console, hostname, and NixOS state version
- `users.nix` owns root/demo users, autologin, demo home, and shell prompt
- `packages.nix` owns the shared guest package list
- `localhost-ui.nix` owns the generated localhost TLS material, trusted CA, stable `ol-c-terminal` service, and reloadable `ol-c-ui` service
- `graphical-session.nix` owns X, matchbox, SPICE guest integration, Firefox profile setup, and browser launch

The localhost HTTPS service source lives in `localhost-ui/server.mjs`. The stable terminal service source lives in `localhost-ui/terminal-server.mjs`. Nix wires both into the guest and provides the runtime paths for TLS material, terminal assets, `ttyd`, and bash.

## Milestone 3 Terminal Proof

The next Milestone 3 proof is a browser terminal at `https://localhost/terminal`.

Proof of success:
- opening `https://localhost/terminal` shows a working terminal inside the guest browser
- each fresh visit to `/terminal` creates a new terminal session
- common full-screen terminal programs such as `vim`, `less`, and `top` behave correctly enough for normal use
- the browser tab title shows the executing shell command while a command runs, shows the current directory at an idle shell prompt, and follows title updates from running programs when they emit them

The terminal stack uses a first-party `xterm.js` frontend with `ttyd` kept only as the PTY backend. The stable ol-c terminal service creates a fresh backend instance on each `/terminal` visit, serves the terminal client itself, and keeps the backend alive while the browser terminal websocket is connected. The reloadable localhost HTTPS UI service only hands off the initial `/terminal` document; terminal assets, token requests, close requests, and websockets use the stable backend origin on port `9443` with short `/session/<token>/...` paths.

Session behavior for this proof:
- `/terminal` always creates a fresh shell
- reload creates a new shell instead of reattaching
- there is no user-visible session picker or durable terminal persistence yet
- when the root shell exits, the terminal page asks Firefox to close that tab instead of showing an ended-session interface
- connected terminal websockets keep their backend alive indefinitely, including when the tab is unfocused
- unexpected websocket disconnects are treated as transport interruptions and get a bounded reconnect grace period before cleanup
- transient token fetch failures during service restarts are retried briefly before the tab is treated as unrecoverable
- the page title shows the current directory at the shell prompt, the executing command while Bash starts a command, program-emitted titles while foreground programs run, and otherwise uses `ol-c terminal`

## Milestone 3 System Controls Proof

The next Milestone 3 browser controls proof is defined in `docs/milestone-3-system-controls.md`. The page style is defined in `docs/milestone-3-status-page-style.md`: a live Markdown-like status document with inline controls for values such as volume, appearance, Bluetooth, and network choice.

Proof of success:
- `https://localhost/` opens a system controls dashboard inside the guest browser
- the dashboard renders network, power, volume, brightness, appearance, and Bluetooth state from the localhost service's live event stream
- browser actions can drive supported control changes through the same localhost API contract
- deterministic fake adapters cover hardware-dependent controls in automated tests
- real guest adapters are added where QEMU exposes reliable system state

The first controls implementation should keep the browser contract separate from the guest system adapter, should use server-sent events for pushed status updates, and should make `OLC_SYSTEM_CONTROLS_BACKEND=fake` select the deterministic fake backend for tests.

Fake hardware capabilities can be composed with `OLC_HARDWARE_TEST` when the fake backend is selected:

```sh
OLC_SYSTEM_CONTROLS_BACKEND=fake OLC_HARDWARE_TEST=wifi:bluetooth:battery node localhost-ui/server.mjs
```

Supported capability tokens are `network`, `wifi`, `battery`, `audio`, `brightness`, `appearance`, and `bluetooth`. Convenience tokens are `none`, `desktop`, `laptop`, and `all`. Commas and colons are both accepted separators.

Run the system controls service tests with:

```sh
node --test localhost-ui/*.test.mjs
```

Run the current shell contract tests with:

```sh
bash tests/test-build-vm.sh
bash tests/test-launch-vm.sh
```

## Firefox Patch Workflow

The build-path roles are summarized in [Firefox Build Paths](#firefox-build-paths). Use this section for the patch-specific workflow details.

### 1. Fast packaged path

Use this after browser frontend patch edits to package and boot the normal VM path.

```sh
git add README.md flake.nix nix/firefox-localhost-fast.nix nix/modules/graphical-session.nix tests/test-build-vm.sh patches/firefox/packaged/0001-close-last-tab-to-localhost.patch AGENTS.md
nix build .#firefox-localhost --print-build-logs
./launch-vm
```

Then validate inside the VM by closing the final Firefox tab with the tab close button or `Ctrl+W` and confirming that Firefox stays open on `https://localhost`.

`.#firefox-localhost` is the default packaged target used by `.#ol-c-image`. It applies the runtime browser chrome hunks from `patches/firefox/packaged/` into the Firefox `omni.ja` archives that contain the matching runtime assets. This fast path is intentionally limited to browser frontend assets such as `browser-commands.js`, `browser.js`, and `tabbrowser.js`.

The overlay rebuilds both `firefox-unwrapped` and the `firefox` wrapper. This matters because the wrapper records the unwrapped store path it launches; overriding only `firefox-unwrapped` can leave the visible browser process running the original unwrapped Firefox.

The VM graphical session launches the patched `firefox-unwrapped` executable directly while this proof is being stabilized. That keeps the visible browser process tied to the patched runtime assets and avoids wrapper indirection during the Milestone 3 browser-shell proof.

Inside the guest, confirm the running package was built by this fast path with:

```sh
cat /run/current-system/sw/lib/firefox/ol-c-localhost-patch.txt
```

`Ctrl+N`, `Ctrl+T`, the toolbar new-tab controls, and closing the final tab should all land on `https://localhost`. The fast package rewrites the browser chrome call sites in `browser-commands.js`, `browser.js`, and `tabbrowser.js` while leaving Firefox's global `BROWSER_NEW_TAB_URL` getter intact, so `https://localhost` keeps normal page title handling instead of being treated as Firefox's built-in new-tab page.

### 2. Full source compatibility path

Use this when the patch or Firefox version changes.

```sh
./build-firefox-source-remote
nix build .#firefox-localhost-source --print-build-logs
```

Keep this as the final compatibility gate for Firefox updates, source patch drift, and any patch that touches C++, Rust, WebIDL, build files, generated interfaces, preprocessing-sensitive files, or test registration.

### 3. Fast Firefox source iteration

Use this when you are actively changing Firefox behavior and need quick feedback.

The intended inner loop is:
- boot the normal guest and use the in-browser terminal at `https://localhost/terminal`
- edit dev-only browser chrome patch artifacts in `/source/patches/firefox/pending`
- run `patched-firefox` from inside the guest to launch a fast patched runtime
- validate the behavior change in that faster loop first
- once the behavior is correct and ready to ship, promote the patch into `patches/firefox/packaged/`
- rerun the fast packaged path above, then use the full source compatibility path as the source-build gate

The new-tab behavior is additive. It should not replace or weaken the existing last-tab reopen behavior.

`patched-firefox` is intentionally an operator launch path, not a build path. It uses the installed Firefox runtime at `/run/current-system/sw/lib/firefox`, symlinks unchanged runtime files into `/var/lib/ol-c/firefox-dev`, copies only mutable `omni.ja` files, applies the known runtime-safe browser chrome patches from `/source/patches/firefox/packaged` first and then `/source/patches/firefox/pending`, repacks the archives, infers `DISPLAY=:0` when the graphical session is active, and launches a dedicated dev profile.

The command must not run `nix build`, `nix eval`, or evaluate `/source/flake.nix`; that would copy the dirty source tree into the Nix store before Firefox can start.

### Updating the repo patch

The packaged Firefox change in this repo lives at:
- `patches/firefox/packaged/0001-close-last-tab-to-localhost.patch`
- `patches/firefox/packaged/0002-hide-sync-fxa-ui.patch`

The dev-only fast-loop directory is:
- `patches/firefox/pending/`

The Nix packaging entry point is:
- `flake.nix` package `.#firefox-localhost`
- `flake.nix` package `.#firefox-localhost-source`

Only patches in `patches/firefox/packaged/` are included in the normal packaged VM build. Files under `patches/firefox/pending/` are reserved for `patched-firefox` validation work and must not affect `./launch-vm`.

When the Firefox source change is validated, update the packaged patch file, rerun the fast packaged build and launch flow above, run the full source compatibility path when the patch or Firefox version changes, and keep `tests/test-build-vm.sh` aligned with the expected packaging contract.

Firefox updates should be handled by bumping the repo's pinned nixpkgs input, refreshing the patch if it drifts, and rerunning the repo tests, the full source compatibility path, and a VM smoke boot.

## Host Setup

Ubuntu host prerequisites:

```sh
sudo apt update
sudo apt install -y qemu-system-x86 qemu-utils qemu-kvm virtiofsd
```

`virtiofsd` provides the host daemon used to mount this repo at `/source` inside the guest and to expose the parent image directory at `/vm-images`. Without it, the launcher will stop before booting the guest.

`virt-viewer` is optional now. Install it only if you want the SPICE fallback:

```sh
sudo apt install -y virt-viewer
OLC_QEMU_FRONTEND=spice ./launch-vm
```

Install Nix using the standard installer for your environment, then confirm the required tools exist:

```sh
command -v nix
command -v qemu-system-x86_64
command -v virtiofsd
test -e /dev/kvm && echo "/dev/kvm present"
```

If `/dev/kvm` exists but is not accessible as your user, add your user to the `kvm` group and start a new shell session.

For nested in-VM VM development, enable nested KVM on the Ubuntu host.

Intel:

```sh
echo 'options kvm_intel nested=1' | sudo tee /etc/modprobe.d/kvm-intel-nested.conf
sudo modprobe -r kvm_intel
sudo modprobe kvm_intel
cat /sys/module/kvm_intel/parameters/nested
```

AMD:

```sh
echo 'options kvm_amd nested=1' | sudo tee /etc/modprobe.d/kvm-amd-nested.conf
sudo modprobe -r kvm_amd
sudo modprobe kvm_amd
cat /sys/module/kvm_amd/parameters/nested
```

Expected output is `Y` or `1`. After relaunching ol-c, confirm `/dev/kvm` exists inside the guest from `https://localhost/terminal`:

```sh
test -e /dev/kvm && echo "/dev/kvm present"
olc-launch-test-vm
```
