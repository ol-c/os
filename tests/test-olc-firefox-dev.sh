#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
NIX_DEVELOPMENT="${ROOT_DIR}/nix/modules/development.nix"
AGENTS="${ROOT_DIR}/AGENTS.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

test_patched_firefox_command_contract() {
  local contents
  contents="$(cat "${NIX_DEVELOPMENT}")"

  [[ "$contents" == *"writeShellScriptBin \"patched-firefox\""* ]] || fail "expected VM development profile to install patched-firefox"
  [[ "$contents" == *"base_runtime=\"''\${OLC_FIREFOX_BASE_RUNTIME:-/run/current-system/sw/lib/firefox}\""* ]] || fail "expected patched-firefox to default to the installed Firefox runtime"
  [[ "$contents" == *"source_root=\"''\${OLC_SOURCE_ROOT:-/source}\""* ]] || fail "expected patched-firefox to default to the shared source tree"
  [[ "$contents" == *"packaged_patch_dir=\"''\${OLC_FIREFOX_PACKAGED_PATCH_DIR:-\$source_root/patches/firefox/packaged}\""* ]] || fail "expected patched-firefox to default to /source packaged Firefox patches"
  [[ "$contents" == *"pending_patch_dir=\"''\${OLC_FIREFOX_PENDING_PATCH_DIR:-\$source_root/patches/firefox/pending}\""* ]] || fail "expected patched-firefox to default to /source pending Firefox patches"
  [[ "$contents" == *"workspace=\"''\${OLC_FIREFOX_DEV_WORKSPACE:-/var/lib/ol-c/firefox-dev}\""* ]] || fail "expected patched-firefox to use the fixed Firefox dev workspace"
  [[ "$contents" == *"if [ -z \"''\${HOME:-}\" ]; then"* ]] || fail "expected patched-firefox to tolerate an unset HOME"
  [[ "$contents" == *"getent passwd \"\$(id -u)\""* ]] || fail "expected patched-firefox to resolve HOME from passwd when unset"
  [[ "$contents" == *"/bin/cut -d: -f6"* ]] || fail "expected patched-firefox to extract HOME from the passwd entry"
  [[ "$contents" == *"profile=\"''\${OLC_FIREFOX_DEV_PROFILE:-\$HOME/.mozilla/firefox/ol-c.patched-dev}\""* ]] || fail "expected patched-firefox to use a dedicated dev profile"

  [[ "$contents" == *"patch_bin=\"\${pkgs.patch}/bin/patch\""* ]] || fail "expected patched-firefox to use a fixed patch path"
  [[ "$contents" == *"filterdiff_bin=\"\${pkgs.patchutils}/bin/filterdiff\""* ]] || fail "expected patched-firefox to use a fixed filterdiff path"
  [[ "$contents" == *"unzip_bin=\"\${pkgs.unzip}/bin/unzip\""* ]] || fail "expected patched-firefox to use a fixed unzip path"
  [[ "$contents" == *"zip_bin=\"\${pkgs.zip}/bin/zip\""* ]] || fail "expected patched-firefox to use a fixed zip path"

  [[ "$contents" == *"packaged_patches=()"* ]] || fail "expected patched-firefox to track packaged patches separately"
  [[ "$contents" == *"pending_patches=()"* ]] || fail "expected patched-firefox to track pending patches separately"
  [[ "$contents" == *"patches=()"* ]] || fail "expected patched-firefox to build a patch list without evaluating Nix"
  [[ "$contents" == *"done < <(\"\$find_bin\" \"\$packaged_patch_dir\" -maxdepth 1 -type f -name '*.patch' | \"\$coreutils_bin/sort\")"* ]] || fail "expected patched-firefox to discover packaged Firefox patch artifacts directly"
  [[ "$contents" == *"if [ -d \"\$pending_patch_dir\" ]; then"* ]] || fail "expected patched-firefox to treat the pending patch directory as optional"
  [[ "$contents" == *"done < <(\"\$find_bin\" \"\$pending_patch_dir\" -maxdepth 1 -type f -name '*.patch' | \"\$coreutils_bin/sort\")"* ]] || fail "expected patched-firefox to discover pending Firefox patch artifacts directly when present"
  [[ "$contents" == *"packaged_patches+=(\"\$patch_file\")"* ]] || fail "expected patched-firefox to record packaged patches in order"
  [[ "$contents" == *"pending_patches+=(\"\$patch_file\")"* ]] || fail "expected patched-firefox to record pending patches in order"
  [[ "$contents" == *"patches+=(\"\$patch_file\")"* ]] || fail "expected patched-firefox to build one ordered patch list"
  [[ "$contents" == *"error: Firefox packaged patch directory not found:"* ]] || fail "expected patched-firefox to require a packaged patch directory"
  [[ "$contents" == *"error: no Firefox packaged patches found in \$packaged_patch_dir"* ]] || fail "expected patched-firefox to require at least one packaged patch"
  [[ "$contents" != *"nix build"* ]] || fail "expected patched-firefox not to build through Nix"
  [[ "$contents" != *"nix eval"* ]] || fail "expected patched-firefox not to evaluate the flake"

  [[ "$contents" == *"./omni.ja|./browser/omni.ja"* ]] || fail "expected patched-firefox to copy only mutable omni.ja files"
  [[ "$contents" == *"cp\" -aL \"\$base_runtime/"* ]] || fail "expected patched-firefox to dereference installed omni.ja symlinks"
  [[ "$contents" == *"ln\" -s \"\$base_runtime/"* || "$contents" == *"ln\" -s \"\$base_runtime/"* ]] || fail "expected patched-firefox to symlink unchanged runtime files"
  [[ "$contents" == *"find_runtime_asset()"* ]] || fail "expected patched-firefox to locate runtime assets while validating the packaged baseline"
  [[ "$contents" == *"validate_packaged_firefox_baseline()"* ]] || fail "expected patched-firefox to validate the packaged Firefox baseline before applying pending patches"
  [[ "$contents" == *"apply_source_patch_to_runtime_asset()"* ]] || fail "expected patched-firefox to apply source patches to runtime assets"
  [[ "$contents" == *"\"\$patch_bin\" -R -d \"\$extract_dir\" -p1 --dry-run"* ]] || fail "expected patched-firefox to tolerate already-applied runtime hunks"
  [[ "$contents" == *"0001-close-last-tab-to-localhost.patch"* ]] || fail "expected patched-firefox to know the localhost runtime-safe patch"
  [[ "$contents" == *"0002-hide-sync-fxa-ui.patch"* ]] || fail "expected patched-firefox to know the Sync/FxA runtime-safe patch"
  [[ "$contents" == *"patched-firefox does not know how to fast-apply"* ]] || fail "expected patched-firefox to reject unknown patch artifacts"
  [[ "$contents" == *"olc-fxa-sync-ui-hidden"* ]] || fail "expected patched-firefox to validate the Sync/FxA UI marker"
  [[ "$contents" == *"validate_packaged_firefox_baseline"* ]] || fail "expected patched-firefox to validate the baseline before applying any pending patches"
  [[ "$contents" == *"for patch_file in \"''\${pending_patches[@]}\"; do"* ]] || fail "expected patched-firefox to apply only pending patches"
  [[ "$contents" != *"for patch_file in \"''\${patches[@]}\"; do"* ]] || fail "expected patched-firefox not to replay packaged patches against the runtime"
  [[ "$contents" == *"printf 'packaged_patch_dir=%s\\n' \"\$packaged_patch_dir\""* ]] || fail "expected patched-firefox to record the packaged patch directory in its runtime manifest"
  [[ "$contents" == *"printf 'pending_patch_dir=%s\\n' \"\$pending_patch_dir\""* ]] || fail "expected patched-firefox to record the pending patch directory in its runtime manifest"
  [[ "$contents" == *"printf 'validated_packaged_patches=%s\\n' \"''\${packaged_patches[*]}\""* ]] || fail "expected patched-firefox to record validated packaged patches in runtime order"
  [[ "$contents" == *"printf 'applied_pending_patches=%s\\n' \"''\${pending_patches[*]}\""* ]] || fail "expected patched-firefox to record applied pending patches in runtime order"

  [[ "$contents" == *"[ -z \"''\${DISPLAY:-}\" ] && [ -S /tmp/.X11-unix/X0 ]"* ]] || fail "expected patched-firefox to infer DISPLAY from the root X socket"
  [[ "$contents" == *"export DISPLAY=:0"* ]] || fail "expected patched-firefox to export inferred DISPLAY"
  [[ "$contents" == *"export MOZ_PURGE_CACHES=1"* ]] || fail "expected patched-firefox to purge Firefox caches"
  [[ "$contents" == *"rm\" -f \"\$generation/.purgecaches\" \"\$generation/browser/.purgecaches\""* ]] || fail "expected patched-firefox to replace packaged purge-cache symlinks"
  [[ "$contents" == *"exec \"\$generation/firefox\" --no-remote --profile \"\$profile\" --new-window \"\$url\""* ]] || fail "expected patched-firefox to launch the generated runtime directly"

  [[ "$contents" == *"d /var/lib/ol-c/firefox-dev 0775 root olc-admin -"* ]] || fail "expected VM to create a writable Firefox dev workspace for admins"
}

test_agents_records_firefox_dev_gate() {
  local contents
  contents="$(cat "${AGENTS}")"

  [[ "$contents" == *"bash tests/test-olc-firefox-dev.sh"* ]] || fail "expected AGENTS.md to record the Firefox dev-loop contract test"
}

test_patched_firefox_command_contract
test_agents_records_firefox_dev_gate

echo "PASS: olc-firefox-dev"
