# SecureOS Prototype

This repo currently has two concrete milestones implemented as guest images for QEMU/KVM development on Ubuntu.

## Milestone 1

Milestone 1 proves that we can repeatedly build and boot a minimal custom nixOS guest.

Proof of success:
- serial output includes `MILESTONE1_BOOT_OK`

Run it with:

```sh
./launch-vm --milestone milestone1
```

## Milestone 2

Milestone 2 proves that we can boot a graphical VM session and use a real browser inside the guest as the visible UI shell.

Proof of success:
- QEMU opens a VM window
- Firefox launches automatically inside the guest
- Firefox opens `https://localhost` as a normal interactive browser session
- the browser window is maximized to fill the VM display
- Closing the final tab keeps the window open and reopens `https://localhost`

Run it with:

```sh
./launch-vm --milestone milestone2
```

Firefox in the guest is packaged from nixpkgs with a repo-local source patch. The patch currently forces the last-tab replacement path to reopen `https://localhost` so the browser always returns to the local control surface.

## Firefox Patch Workflow

The repo has two distinct Firefox workflows. Use them for different purposes.

### 1. Reproducible packaged path

Use this when you need to prove that the repo-local Firefox patch still builds through Nix and still works in the guest image.

```sh
git add patches/firefox/0001-close-last-tab-to-localhost.patch tests/test-build-vm.sh flake.nix AGENTS.md
nix build .#firefox-localhost --print-build-logs
./launch-vm --milestone milestone2
```

Then validate inside the VM by closing the final Firefox tab with the tab close button or `Ctrl+W` and confirming that Firefox stays open on `https://localhost`.

This is the authoritative packaging check, but it is intentionally not the main edit-test-edit loop because rebuilding packaged Firefox is slow.

### 2. Fast Firefox source iteration

Use this when you are actively changing Firefox behavior and need quick feedback.

The intended inner loop is:
- make the behavior change in a separate Firefox source checkout
- validate it there first, ideally inside the VM when the change is part of the browser surface you want to experience in-guest
- once the behavior is correct, export or refresh the repo patch at `patches/firefox/0001-close-last-tab-to-localhost.patch`
- rerun the reproducible packaged path above

Until Milestone 4 is complete, that fast loop happens outside this repo's final Nix packaging path. Milestone 4 exists to make the fast loop practical inside the VM against a host-shared repo, while keeping this repo's packaged Nix build as the final verification gate.

The next Firefox behavior target for this workflow is:
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
sudo apt install -y qemu-system-x86 qemu-utils qemu-kvm
```

Install Nix using the standard installer for your environment, then confirm the required tools exist:

```sh
command -v nix
command -v qemu-system-x86_64
test -e /dev/kvm && echo "/dev/kvm present"
```

If `/dev/kvm` exists but is not accessible as your user, add your user to the `kvm` group and start a new shell session.
