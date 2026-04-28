# Firefox Source Workflow Plan

## Goal

Use Firefox's normal source-tree development loop for ol-c browser work while keeping the repo's clean patch artifacts as the source of truth.

## Why

The runtime `omni.ja` patch path is useful for narrowly scoped operator checks, but it is too brittle to be the primary Firefox development workflow:

- source paths and runtime asset paths can diverge
- wrapper indirection can hide which Firefox binary is actually running
- runtime-only transforms are harder to trust than the standard `mach` loop

For Milestone 6, the main proof should be a practical shared source-tree workflow keyed to the exact Firefox source chosen by pinned `nixpkgs`.

This is the recommended Firefox development loop for browser behavior work. The shared source-tree path is the default path when we want confidence in the way Firefox itself expects to be developed.

## Workspace Layout

Use the shared repo-local gitignored directory:

```sh
/source/.olc-firefox/
```

Namespace each source instance by Firefox identity:

- Firefox version
- pinned Firefox source store hash
- pinned `nixpkgs` revision

Each instance contains:

- `cache/<identity>/firefox-....tar.xz`
- `cache/<identity>/source/`
- `source/`
- `objdir/`
- `profile/`
- `mozconfig`
- `manifest.env`

## Loop

1. Resolve the pinned Firefox source archive from `flake.lock` and `nixpkgs`.
2. Copy that tarball into the repo-local shared cache under `/source/.olc-firefox/cache/...`.
3. Extract it once into the shared pristine cache.
4. Copy from that pristine cache into the working instance directory.
5. Apply `patches/firefox/packaged/` first and `patches/firefox/pending/` second.
6. Reuse the same shared objdir for repeated `mach` builds.
7. Validate with the normal Firefox loop:
   - `./mach build faster`
   - `./mach build`
   - `./mach run`
8. Promote validated changes back into the repo patch stack.
9. Keep `.#firefox-localhost` and `.#firefox-localhost-source` as packaging and release gates.

For UI-only proof work, start by staging the change as a dev-only patch in `patches/firefox/pending/`, validate it in the shared source tree, and only then decide whether it should graduate into `patches/firefox/packaged/`.

## Initial Commands

The repo-level init command is `olc-init`:

- `./olc-init status`
- `./olc-init prepare`

The first helper command is `olc-firefox-source`:

- `olc-firefox-source prepare-cache`
- `olc-firefox-source prepare`
- `olc-firefox-source status`
- `olc-firefox-source env`
- `olc-firefox-source shell`
- `olc-firefox-source mach <args...>`
- `olc-firefox-source recreate`

`olc-firefox-source shell` and `olc-firefox-source mach ...` should enter a separate pinned Nix development environment for Firefox host tools, while continuing to use the same shared source tree and objdir under `/source/.olc-firefox/`. That environment should export the same WASI cross compiler, WASI sysroot, and libclang paths that nixpkgs uses for the packaged Firefox build.

## Recommended Proof Loop

Use this when you want a concrete end-to-end proof that the shared source-tree workflow is the fastest correct loop:

1. `./olc-init prepare`
2. `./olc-firefox-source prepare`
3. edit or add a patch under `patches/firefox/pending/`
4. `./olc-firefox-source shell`
5. `./mach build faster`
6. `./mach run`
7. confirm the browser behavior in that source-built Firefox window
8. keep the patch in `pending` if it is only a dev proof, or promote it into `packaged` if it is intended to ship

The current proof patch is `patches/firefox/pending/0003-add-plugin-button-dev-icon.patch`, which adds a dev-only appearance toggle button next to the unified extensions button so the loop has a visible browser-chrome result without changing the packaged VM build.

## Planned Follow-On Work

- record exact Firefox and `nixpkgs` identity in the shared source manifest and runtime manifests consistently
- add a helper to regenerate repo patches from the shared source tree
- add a launcher path that makes shared-source Firefox test windows visually unmistakable
