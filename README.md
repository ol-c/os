# OL-C Prototype

This repo currently has one graphical QEMU/KVM development VM that boots the current OL-C browser surface.

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

`launch-vm` uses QEMU's SPICE display path by default and opens it with `remote-viewer`. This avoids the host HiDPI cursor-coordinate issues seen with QEMU's GTK window and the cursor escape roughness seen with QEMU's SDL window. SDL and GTK remain available as direct QEMU display fallbacks:

```sh
OLC_QEMU_FRONTEND=sdl ./launch-vm
OLC_QEMU_FRONTEND=gtk ./launch-vm
OLC_QEMU_DISPLAY='gtk,gl=off,zoom-to-fit=off' ./launch-vm
```

The SDL and GTK scaling knobs are also overrideable for direct-display debugging:

```sh
OLC_QEMU_SDL_VIDEO_HIGHDPI_DISABLED=0 ./launch-vm
OLC_QEMU_GDK_SCALE=2 OLC_QEMU_GDK_DPI_SCALE=0.5 ./launch-vm
```

Firefox in the guest is packaged from nixpkgs with a repo-local source patch. The patch currently forces the last-tab replacement path to reopen `https://localhost` so the browser always returns to the local control surface.

## Nix Layout

`nix/ol-c.nix` is the current guest entry point. It imports focused modules from `nix/modules/`:
- `base.nix` owns boot, qemu guest support, serial console, hostname, and NixOS state version
- `users.nix` owns root/demo users, autologin, demo home, and shell prompt
- `packages.nix` owns the shared guest package list
- `localhost-ui.nix` owns the generated localhost TLS material, trusted CA, and `ol-c-ui` service
- `graphical-session.nix` owns X, matchbox, SPICE guest integration, Firefox profile setup, and browser launch

The localhost HTTPS service source lives in `localhost-ui/server.mjs`. Nix wires it into the guest and provides the runtime paths for TLS material, terminal assets, `ttyd`, and bash.

## Milestone 3 Terminal Proof

The next Milestone 3 proof is a browser terminal at `https://localhost/terminal`.

Proof of success:
- opening `https://localhost/terminal` shows a working terminal inside the guest browser
- each fresh visit to `/terminal` creates a new terminal session
- common full-screen terminal programs such as `vim`, `less`, and `top` behave correctly enough for normal use
- the browser tab title follows the terminal title stream when the shell or running program emits one

The terminal stack uses a first-party `xterm.js` frontend with `ttyd` kept only as the PTY backend. The OL-C localhost HTTPS service creates a fresh backend instance on each `/terminal` visit, serves the terminal client itself, and keeps the backend tied to a page-owned lease rather than raw websocket presence.

Session behavior for this proof:
- `/terminal` always creates a fresh shell
- reload creates a new shell instead of reattaching
- there is no user-visible session picker or durable terminal persistence yet
- when the root shell exits, the terminal page asks Firefox to close that tab instead of showing an ended-session interface
- websocket disconnects are treated as transport interruptions, not terminal teardown
- the page renews its terminal lease while open and sends a best-effort close signal when it leaves
- the page title follows the terminal title stream when available and otherwise uses `OL-C Terminal`

## Firefox Patch Workflow

The repo has two distinct Firefox workflows. Use them for different purposes.

### 1. Reproducible packaged path

Use this when you need to prove that the repo-local Firefox patch still builds through Nix and still works in the guest image.

```sh
git add patches/firefox/0001-close-last-tab-to-localhost.patch tests/test-build-vm.sh flake.nix AGENTS.md
nix build .#firefox-localhost --print-build-logs
./launch-vm
```

Then validate inside the VM by closing the final Firefox tab with the tab close button or `Ctrl+W` and confirming that Firefox stays open on `https://localhost`.

This is the authoritative packaging check, but it is intentionally not the main edit-test-edit loop because rebuilding packaged Firefox is slow.

### 2. Fast Firefox source iteration

Use this when you are actively changing Firefox behavior and need quick feedback.

The intended inner loop is:
- boot the normal guest and use the in-browser terminal at `https://localhost/terminal`
- work in a Firefox source checkout from inside the guest
- validate the behavior change in that faster loop first
- once the behavior is correct, export or refresh the repo patch at `patches/firefox/0001-close-last-tab-to-localhost.patch`
- rerun the reproducible packaged path above

The next Firefox packaging proof is no longer the immediate next milestone task. The current next milestone proof is the browser terminal at `https://localhost/terminal`. After that lands, the same split still applies: validate Firefox source changes in the fast loop first, then use the packaged build as the final gate.

The next Firefox behavior target after the terminal proof is:
- opening a new tab should load `https://localhost/`
- closing the final tab must continue to reopen `https://localhost`

The new-tab behavior is additive. It should not replace or weaken the existing last-tab reopen behavior.

### Updating the repo patch

The packaged Firefox change in this repo lives at:
- `patches/firefox/0001-close-last-tab-to-localhost.patch`

The Nix packaging entry point is:
- `flake.nix` package `.#firefox-localhost`

When the Firefox source change is validated, update the patch file, rerun the build and launch flow above, and keep `tests/test-build-vm.sh` aligned with the expected packaging contract.

Firefox updates should be handled by bumping the repo's pinned nixpkgs input, refreshing the patch if it drifts, and rerunning the repo tests plus a VM smoke boot.

## Host Setup

Ubuntu host prerequisites:

```sh
sudo apt update
sudo apt install -y qemu-system-x86 qemu-utils qemu-kvm virt-viewer
```

`virt-viewer` provides the `remote-viewer` command used by `./launch-vm` to open the default SPICE VM display. Without it, the launcher will stop before booting the guest.

Install Nix using the standard installer for your environment, then confirm the required tools exist:

```sh
command -v nix
command -v qemu-system-x86_64
command -v remote-viewer
test -e /dev/kvm && echo "/dev/kvm present"
```

If `/dev/kvm` exists but is not accessible as your user, add your user to the `kvm` group and start a new shell session.
