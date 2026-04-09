#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_VM="${ROOT_DIR}/build-vm"
FLAKE_NIX="${ROOT_DIR}/flake.nix"
MILESTONE2_NIX="${ROOT_DIR}/nix/milestone2.nix"
FIREFOX_PATCH="${ROOT_DIR}/patches/firefox/0001-close-last-tab-to-localhost.patch"
TEST_TMP_ROOT="${ROOT_DIR}/.tmp-tests"
CASE_TMP=""

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

cleanup_case() {
  if [[ -n "$CASE_TMP" && -d "$CASE_TMP" ]]; then
    rm -rf "$CASE_TMP"
  fi
  CASE_TMP=""
}

setup_case() {
  cleanup_case
  mkdir -p "$TEST_TMP_ROOT"
  CASE_TMP="$(mktemp -d "${TEST_TMP_ROOT}/build.XXXXXX")"
  mkdir -p "${CASE_TMP}/fakebin" "${CASE_TMP}/out"

  cat >"${CASE_TMP}/fakebin/nix" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${CASE_TMP}/nix.args"
: > "${CASE_TMP}/out/image.qcow2"
printf '%s\n' "${CASE_TMP}/out"
EOF

  chmod +x "${CASE_TMP}/fakebin/nix"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  [[ "$expected" == "$actual" ]] || fail "expected [$expected], got [$actual]"
}

trap cleanup_case EXIT

test_requires_nix() {
  local output status
  setup_case
  rm -f "${CASE_TMP}/fakebin/nix"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${BUILD_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected build-vm to fail without nix"
  [[ "$output" == *"required command not found: nix"* ]] || fail "unexpected output: $output"
  cleanup_case
}

test_prints_resolved_image_path_for_milestone1() {
  local output args
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${BUILD_VM}" milestone1
  )"

  args="$(cat "${CASE_TMP}/nix.args")"
  [[ "$args" == *"build .#milestone1-image --print-out-paths --no-link"* ]] || fail "unexpected nix args: $args"
  assert_eq "${CASE_TMP}/out/image.qcow2" "$output"
  cleanup_case
}

test_prints_resolved_image_path_for_milestone2() {
  local output args
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${BUILD_VM}" milestone2
  )"

  args="$(cat "${CASE_TMP}/nix.args")"
  [[ "$args" == *"build .#milestone2-image --print-out-paths --no-link"* ]] || fail "unexpected nix args: $args"
  assert_eq "${CASE_TMP}/out/image.qcow2" "$output"
  cleanup_case
}

test_rejects_unknown_profile() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${BUILD_VM}" mystery \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected build-vm to reject unknown milestone"
  [[ "$output" == *"unsupported milestone: mystery"* ]] || fail "unexpected output: $output"
  cleanup_case
}

test_requires_bootable_image_in_output() {
  local output status
  setup_case

  cat >"${CASE_TMP}/fakebin/nix" <<EOF
#!/usr/bin/env bash
printf '%s\n' "${CASE_TMP}/out"
EOF
  chmod +x "${CASE_TMP}/fakebin/nix"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${BUILD_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected build-vm to fail without a bootable image"
  [[ "$output" == *"unable to locate a bootable disk image"* ]] || fail "unexpected output: $output"
  cleanup_case
}

test_milestone2_runs_firefox_borderless_and_maximized() {
  local contents
  contents="$(cat "${MILESTONE2_NIX}")"

  [[ "$contents" == *"SECUREOS_UI_SERVER_OK https://localhost"* ]] || fail "expected milestone2 to define a localhost HTTPS UI service"
  [[ "$contents" == *"server.listen(443, '127.0.0.1'"* ]] || fail "expected milestone2 to serve the UI on localhost:443"
  [[ "$contents" == *"user_pref(\"browser.tabs.inTitlebar\", 1);"* ]] || fail "expected milestone2 to keep Firefox tabs in the title bar"
  [[ "$contents" == *"user_pref(\"browser.tabs.drawInTitlebar\", true);"* ]] || fail "expected milestone2 to force Firefox titlebar drawing"
  [[ "$contents" == *"user_pref(\"browser.tabs.closeWindowWithLastTab\", false);"* ]] || fail "expected milestone2 to keep Firefox open when the last tab closes"
  [[ "$contents" == *"user_pref(\"browser.startup.homepage\", \"https://localhost\");"* ]] || fail "expected milestone2 to pin the Firefox home page to the in-guest HTTPS UI"
  [[ "$contents" == *"user_pref(\"security.enterprise_roots.enabled\", true);"* ]] || fail "expected milestone2 to trust the guest localhost certificate through system roots"
  [[ "$contents" == *"matchbox-window-manager -use_titlebar no -use_cursor yes &"* ]] || fail "expected milestone2 to launch matchbox without a title bar"
  [[ "$contents" == *"curl --silent --fail --cacert"* ]] || fail "expected milestone2 to wait for the localhost HTTPS UI before launching Firefox"
  [[ "$contents" == *"xdotool windowsize \"\$window_id\" 100% 100%"* ]] || fail "expected milestone2 to force Firefox to fill the screen"
  [[ "$contents" == *"firefox --no-remote --profile /home/demo/.mozilla/firefox/secureos.default --new-window https://localhost &"* ]] || fail "expected milestone2 to launch Firefox against the localhost UI"
  [[ "$contents" != *"openbox"* ]] || fail "expected milestone2 to avoid Openbox"
}

test_packages_firefox_with_localhost_patch() {
  local flake_contents patch_contents
  flake_contents="$(cat "${FLAKE_NIX}")"
  patch_contents="$(cat "${FIREFOX_PATCH}")"

  [[ "$flake_contents" == *"firefoxLocalhostPatch = ./patches/firefox/0001-close-last-tab-to-localhost.patch;"* ]] || fail "expected flake to define the repo-local Firefox patch"
  [[ "$flake_contents" == *"inputs.nixpkgs.follows = \"nixpkgs\";"* ]] || fail "expected nixos-generators to follow the repo nixpkgs input"
  [[ "$flake_contents" == *"firefoxPkgs = import nixpkgs {"* ]] || fail "expected flake to share one nixpkgs import for Firefox packaging and images"
  [[ "$flake_contents" == *"\"firefox-unwrapped\" = prev.\"firefox-unwrapped\".overrideAttrs"* ]] || fail "expected flake to override nixpkgs firefox-unwrapped"
  [[ "$flake_contents" == *"patches = (old.patches or []) ++ [ firefoxLocalhostPatch ];"* ]] || fail "expected flake to append the localhost patch to firefox-unwrapped"
  [[ "$flake_contents" == *"firefox-localhost = firefoxPkgs.firefox;"* ]] || fail "expected flake to expose the shared patched Firefox package"
  [[ "$flake_contents" == *"pkgs = firefoxPkgs;"* ]] || fail "expected generated images to use the same patched nixpkgs import"
  [[ "$flake_contents" == *"modules = [ milestone1Module ];"* ]] || fail "expected milestone1 image generation to avoid reapplying the overlay module"
  [[ "$flake_contents" == *"modules = [ milestone2Module ];"* ]] || fail "expected milestone2 image generation to avoid reapplying the overlay module"
  [[ "$patch_contents" == *"+        this.addTrustedTab(\"https://localhost\", {"* ]] || fail "expected Firefox patch to replace the last closed tab with localhost"
  [[ "$patch_contents" == *"browser_closeLastTab_loads_localhost.js"* ]] || fail "expected Firefox patch to add a browser regression test"
}

test_requires_nix
test_prints_resolved_image_path_for_milestone1
test_prints_resolved_image_path_for_milestone2
test_rejects_unknown_profile
test_requires_bootable_image_in_output
test_milestone2_runs_firefox_borderless_and_maximized
test_packages_firefox_with_localhost_patch

echo "PASS: build-vm"
