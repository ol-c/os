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

For fast Firefox patch iteration, use a separate upstream Firefox source checkout and validate the behavior there first. Once the patch is correct, export it into `patches/firefox/0001-close-last-tab-to-localhost.patch` and let this repo package it through the `firefox-localhost` derivation in `flake.nix`.

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
