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

Milestone 2 proves that we can boot a graphical VM session and launch a real browser inside the guest.

Proof of success:
- QEMU opens a VM window
- Firefox launches automatically inside the guest
- the in-guest page displays `MILESTONE2_BROWSER_OK`

Run it with:

```sh
./launch-vm --milestone milestone2
```

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
