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

Firefox in the guest is packaged from pinned nixpkgs with a repo-local browser frontend patch. The normal VM uses the fast packaged target, which repacks the pinned nixpkgs Firefox browser chrome assets instead of recompiling Firefox for every JavaScript-only OL-C shell edit.

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
- the browser tab title shows the executing shell command while a command runs, shows the current directory at an idle shell prompt, and follows title updates from running programs when they emit them

The terminal stack uses a first-party `xterm.js` frontend with `ttyd` kept only as the PTY backend. The OL-C localhost HTTPS service creates a fresh backend instance on each `/terminal` visit, serves the terminal client itself, and keeps the backend alive while the browser terminal websocket is connected.

Session behavior for this proof:
- `/terminal` always creates a fresh shell
- reload creates a new shell instead of reattaching
- there is no user-visible session picker or durable terminal persistence yet
- when the root shell exits, the terminal page asks Firefox to close that tab instead of showing an ended-session interface
- connected terminal websockets keep their backend alive indefinitely, including when the tab is unfocused
- unexpected websocket disconnects are treated as transport interruptions and get a bounded reconnect grace period before cleanup
- the page sends a best-effort close signal when it leaves so clean tab closure can terminate the backend immediately
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

The repo has three distinct Firefox gates. Use them for different purposes.

### 1. Fast packaged path

Use this when you need a deterministic Nix package and VM image for browser frontend edits without waiting for a full Firefox source compile.

```sh
git add README.md flake.nix nix/firefox-localhost-fast.nix nix/modules/graphical-session.nix tests/test-build-vm.sh patches/firefox/0001-close-last-tab-to-localhost.patch AGENTS.md
nix build .#firefox-localhost --print-build-logs
./launch-vm
```

Then validate inside the VM by closing the final Firefox tab with the tab close button or `Ctrl+W` and confirming that Firefox stays open on `https://localhost`.

`.#firefox-localhost` is the default packaged target used by `.#ol-c-image`. It starts from pinned nixpkgs Firefox and applies the runtime browser chrome hunks from `patches/firefox/0001-close-last-tab-to-localhost.patch` into the Firefox `omni.ja` archives that contain the matching runtime assets. The rewritten jars are normal zip-format jars for fast local packaging. The fast package removes packaged startup/script caches, writes Firefox `.purgecaches` markers, and the VM launches Firefox with `MOZ_PURGE_CACHES=1` so patched chrome JavaScript is loaded instead of stale bytecode. Use the full source compatibility path when optimized Firefox packaging behavior itself matters. The fast path is intentionally limited to browser frontend assets such as `browser-commands.js`, `browser.js`, and `tabbrowser.js`.

The overlay rebuilds both `firefox-unwrapped` and the `firefox` wrapper. This matters because the wrapper records the unwrapped store path it launches; overriding only `firefox-unwrapped` can leave the visible browser process running the original unwrapped Firefox.

The VM graphical session launches the patched `firefox-unwrapped` executable directly while this proof is being stabilized. That keeps the visible browser process tied to the patched runtime assets and avoids wrapper indirection during the Milestone 3 browser-shell proof.

Inside the guest, confirm the running package was built by this fast path with:

```sh
cat /run/current-system/sw/lib/firefox/ol-c-localhost-patch.txt
```

`Ctrl+N`, `Ctrl+T`, the toolbar new-tab controls, and closing the final tab should all land on `https://localhost`. The fast package rewrites the browser chrome call sites in `browser-commands.js`, `browser.js`, and `tabbrowser.js` while leaving Firefox's global `BROWSER_NEW_TAB_URL` getter intact, so `https://localhost` keeps normal page title handling instead of being treated as Firefox's built-in new-tab page.

### 2. Full source compatibility path

Use this when you need to prove that the repo-local Firefox patch still applies through the nixpkgs Firefox source build pipeline.

```sh
nix build .#firefox-localhost-source --print-build-logs
```

This is slower because it appends the repo patch to `firefox-unwrapped` before Firefox is built. Keep it as the final compatibility gate for Firefox updates, source patch drift, and any patch that touches C++, Rust, WebIDL, build files, generated interfaces, preprocessing-sensitive files, or test registration.

### 3. Fast Firefox source iteration

Use this when you are actively changing Firefox behavior and need quick feedback.

The intended inner loop is:
- boot the normal guest and use the in-browser terminal at `https://localhost/terminal`
- work in a Firefox source checkout from inside the guest
- validate the behavior change in that faster loop first
- once the behavior is correct, export or refresh the repo patch at `patches/firefox/0001-close-last-tab-to-localhost.patch`
- rerun the fast packaged path above, then use the full source compatibility path as the source-build gate

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
- `flake.nix` package `.#firefox-localhost-source`

When the Firefox source change is validated, update the patch file, rerun the fast packaged build and launch flow above, run the full source compatibility path when the patch or Firefox version changes, and keep `tests/test-build-vm.sh` aligned with the expected packaging contract.

Firefox updates should be handled by bumping the repo's pinned nixpkgs input, refreshing the patch if it drifts, and rerunning the repo tests, the full source compatibility path, and a VM smoke boot.

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
