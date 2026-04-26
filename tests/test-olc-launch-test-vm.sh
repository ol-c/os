#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
OLC_LAUNCH_TEST_VM="${ROOT_DIR}/olc-launch-test-vm"
TEST_TMP_ROOT="${OLC_TEST_TMP_ROOT:-${ROOT_DIR}/.tmp-tests}"
TEST_FAKE_BASH="${OLC_TEST_FAKE_BASH:-$(command -v bash)}"
TEST_SYSTEM_PATH="${OLC_TEST_SYSTEM_PATH:-$(dirname -- "$TEST_FAKE_BASH"):/usr/bin:/bin}"
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
  CASE_TMP="$(mktemp -d "${TEST_TMP_ROOT}/olc-launch-test-vm.XXXXXX")"
  mkdir -p "${CASE_TMP}/fakebin" "${CASE_TMP}/source" "${CASE_TMP}/images" "${CASE_TMP}/workspace" "${CASE_TMP}/novnc" "${CASE_TMP}/qemu-store/bin"
  : > "${CASE_TMP}/images/guest.qcow2"
  : > "${CASE_TMP}/kvm"
  chmod 0666 "${CASE_TMP}/kvm"

  cat >"${CASE_TMP}/fakebin/nix" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/nix.args"
printf '%s\n' "${CASE_TMP}/qemu-store"
EOF
  cat >"${CASE_TMP}/qemu-store/bin/qemu-system-x86_64" <<EOF
#!${TEST_FAKE_BASH}
exit 0
EOF
  chmod +x "${CASE_TMP}/fakebin/nix" "${CASE_TMP}/qemu-store/bin/qemu-system-x86_64"

  cat >"${CASE_TMP}/source/launch-vm" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$PWD" > "${CASE_TMP}/launch.pwd"
printf '%s\n' "\$*" > "${CASE_TMP}/launch.args"
printf '%s\n' "\${OLC_SOURCE_DIR:-}" > "${CASE_TMP}/launch.source-dir"
printf '%s\n' "\${OLC_VM_IMAGE:-}" > "${CASE_TMP}/launch.vm-image"
printf '%s\n' "\${OLC_QEMU_FRONTEND:-}" > "${CASE_TMP}/launch.frontend"
printf '%s\n' "\${OLC_QEMU_BIN:-}" > "${CASE_TMP}/launch.qemu-bin"
printf '%s\n' "\${OLC_NOVNC_DIR:-}" > "${CASE_TMP}/launch.novnc-dir"
printf '%s\n' "\${OLC_VM_SCREEN_OPEN_BROWSER:-}" > "${CASE_TMP}/launch.open-browser"
printf '%s\n' "\${OLC_VM_DISK_SIZE:-}" > "${CASE_TMP}/launch.disk-size"
printf '%s\n' "\${OLC_VM_FAST_BOOT:-}" > "${CASE_TMP}/launch.fast-boot"
printf '%s\n' "\${OLC_VM_NETWORK_MODE:-}" > "${CASE_TMP}/launch.network-mode"
printf '%s\n' "\${OLC_VM_WAIT_READY:-}" > "${CASE_TMP}/launch.wait-ready"
printf '%s\n' "\${OLC_VM_READY_TIMEOUT_SECONDS:-}" > "${CASE_TMP}/launch.ready-timeout"
printf '%s\n' "\${OLC_VM_READY_WARN_SECONDS:-}" > "${CASE_TMP}/launch.ready-warn"
printf '%s\n' "\${OLC_SHARE_VM_IMAGES:-}" > "${CASE_TMP}/launch.share-vm-images"
printf '%s\n' "\${TMPDIR:-}" > "${CASE_TMP}/launch.tmpdir"
printf '%s\n' "\${OLC_VM_PARENT_MACHINE_ID:-}" > "${CASE_TMP}/launch.parent-machine-id"
printf '%s\n' "\${OLC_VM_PARENT_DEPTH:-}" > "${CASE_TMP}/launch.parent-depth"
EOF
  chmod +x "${CASE_TMP}/source/launch-vm"

  cat >"${CASE_TMP}/fakebin/findmnt" <<EOF
#!${TEST_FAKE_BASH}
exit 1
EOF
  chmod +x "${CASE_TMP}/fakebin/findmnt"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  [[ "$expected" == "$actual" ]] || fail "expected [$expected], got [$actual]"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected [$needle] in [$haystack]"
}

trap cleanup_case EXIT

test_launches_with_default_image_and_workspace() {
  local output
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_SOURCE_DIR="${CASE_TMP}/source" \
      OLC_VM_IMAGES_DIR="${CASE_TMP}/images" \
      OLC_VM_WORKSPACE="${CASE_TMP}/workspace" \
      OLC_KVM_DEVICE="${CASE_TMP}/kvm" \
      OLC_DEFAULT_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_DEFAULT_QEMU_BIN="${CASE_TMP}/qemu-store/bin/qemu-system-x86_64" \
      "${OLC_LAUNCH_TEST_VM}" --cpus 1
  )"

  assert_contains "$output" "source: ${CASE_TMP}/source"
  assert_contains "$output" "image: ${CASE_TMP}/images/guest.qcow2"
  assert_contains "$output" "workspace: ${CASE_TMP}/workspace"
  assert_contains "$output" "screen: browser tab"
  assert_eq "${CASE_TMP}/source" "$(cat "${CASE_TMP}/launch.pwd")"
  assert_eq "--cpus 1" "$(cat "${CASE_TMP}/launch.args")"
  assert_eq "${CASE_TMP}/source" "$(cat "${CASE_TMP}/launch.source-dir")"
  assert_eq "${CASE_TMP}/images/guest.qcow2" "$(cat "${CASE_TMP}/launch.vm-image")"
  assert_eq "browser" "$(cat "${CASE_TMP}/launch.frontend")"
  assert_eq "${CASE_TMP}/qemu-store/bin/qemu-system-x86_64" "$(cat "${CASE_TMP}/launch.qemu-bin")"
  assert_eq "${CASE_TMP}/novnc" "$(cat "${CASE_TMP}/launch.novnc-dir")"
  assert_eq "0" "$(cat "${CASE_TMP}/launch.open-browser")"
  assert_eq "10G" "$(cat "${CASE_TMP}/launch.disk-size")"
  assert_eq "1" "$(cat "${CASE_TMP}/launch.fast-boot")"
  assert_eq "none" "$(cat "${CASE_TMP}/launch.network-mode")"
  assert_eq "1" "$(cat "${CASE_TMP}/launch.wait-ready")"
  assert_eq "30" "$(cat "${CASE_TMP}/launch.ready-timeout")"
  assert_eq "15" "$(cat "${CASE_TMP}/launch.ready-warn")"
  assert_eq "0" "$(cat "${CASE_TMP}/launch.share-vm-images")"
  assert_eq "${CASE_TMP}/workspace/tmp" "$(cat "${CASE_TMP}/launch.tmpdir")"
  [[ -d "${CASE_TMP}/workspace/tmp" ]] || fail "expected wrapper to create workspace tmp directory"
  cleanup_case
}

test_uses_cached_qemu_bin_without_nix_build() {
  local output
  setup_case
  mkdir -p "${CASE_TMP}/workspace/cache"
  printf '%s\n' "${CASE_TMP}/qemu-store/bin/qemu-system-x86_64" > "${CASE_TMP}/workspace/cache/qemu-bin"

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_SOURCE_DIR="${CASE_TMP}/source" \
      OLC_VM_IMAGES_DIR="${CASE_TMP}/images" \
      OLC_VM_WORKSPACE="${CASE_TMP}/workspace" \
      OLC_KVM_DEVICE="${CASE_TMP}/kvm" \
      "${OLC_LAUNCH_TEST_VM}"
  )"

  assert_eq "${CASE_TMP}/qemu-store/bin/qemu-system-x86_64" "$(cat "${CASE_TMP}/launch.qemu-bin")"
  [[ ! -f "${CASE_TMP}/nix.args" ]] || fail "expected cached qemu resolution to avoid nix build"
  cleanup_case
}

test_builds_and_caches_qemu_bin_when_needed() {
  local output
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_SOURCE_DIR="${CASE_TMP}/source" \
      OLC_VM_IMAGES_DIR="${CASE_TMP}/images" \
      OLC_VM_WORKSPACE="${CASE_TMP}/workspace" \
      OLC_KVM_DEVICE="${CASE_TMP}/kvm" \
      "${OLC_LAUNCH_TEST_VM}"
  )"

  assert_eq "${CASE_TMP}/qemu-store/bin/qemu-system-x86_64" "$(cat "${CASE_TMP}/launch.qemu-bin")"
  assert_eq "build .#qemu-olc --print-out-paths --no-link" "$(cat "${CASE_TMP}/nix.args")"
  assert_eq "${CASE_TMP}/qemu-store/bin/qemu-system-x86_64" "$(cat "${CASE_TMP}/workspace/cache/qemu-bin")"
  cleanup_case
}

test_requires_nested_kvm_access() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_SOURCE_DIR="${CASE_TMP}/source" \
      OLC_VM_IMAGES_DIR="${CASE_TMP}/images" \
      OLC_VM_WORKSPACE="${CASE_TMP}/workspace" \
      OLC_KVM_DEVICE="${CASE_TMP}/missing-kvm" \
      "${OLC_LAUNCH_TEST_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected wrapper to fail without KVM"
  assert_contains "$output" "${CASE_TMP}/missing-kvm is required for nested VM development"
  assert_contains "$output" "Enable nested KVM on the Ubuntu host"
  cleanup_case
}

test_rejects_missing_explicit_image() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_SOURCE_DIR="${CASE_TMP}/source" \
      OLC_VM_IMAGE="${CASE_TMP}/missing.qcow2" \
      OLC_VM_WORKSPACE="${CASE_TMP}/workspace" \
      OLC_KVM_DEVICE="${CASE_TMP}/kvm" \
      "${OLC_LAUNCH_TEST_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected wrapper to reject a missing explicit image"
  assert_contains "$output" "OLC_VM_IMAGE does not point to a file: ${CASE_TMP}/missing.qcow2"
  cleanup_case
}

test_passes_vm_lineage_to_child_launch() {
  local output lineage_env
  setup_case
  lineage_env="${CASE_TMP}/vm-lineage.env"
  cat > "${lineage_env}" <<'EOF'
OLC_VM_MACHINE_ID=parent-machine
OLC_VM_BOOT_ID=parent-boot
OLC_VM_DEPTH=2
EOF

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_SOURCE_DIR="${CASE_TMP}/source" \
      OLC_VM_IMAGES_DIR="${CASE_TMP}/images" \
      OLC_VM_WORKSPACE="${CASE_TMP}/workspace" \
      OLC_KVM_DEVICE="${CASE_TMP}/kvm" \
      OLC_VM_LINEAGE_ENV="${lineage_env}" \
      "${OLC_LAUNCH_TEST_VM}"
  )"

  assert_contains "$output" "source: ${CASE_TMP}/source"
  assert_eq "parent-machine" "$(cat "${CASE_TMP}/launch.parent-machine-id")"
  assert_eq "2" "$(cat "${CASE_TMP}/launch.parent-depth")"
  cleanup_case
}

test_rejects_non_browser_frontend_override() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_SOURCE_DIR="${CASE_TMP}/source" \
      OLC_VM_IMAGES_DIR="${CASE_TMP}/images" \
      OLC_VM_WORKSPACE="${CASE_TMP}/workspace" \
      OLC_KVM_DEVICE="${CASE_TMP}/kvm" \
      OLC_QEMU_FRONTEND="spice" \
      "${OLC_LAUNCH_TEST_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected wrapper to reject non-browser frontend overrides"
  assert_contains "$output" "embedded VM launches do not allow OLC_QEMU_FRONTEND=spice"
  assert_contains "$output" "browser-tab viewer only"
  cleanup_case
}

test_rejects_direct_display_override() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_SOURCE_DIR="${CASE_TMP}/source" \
      OLC_VM_IMAGES_DIR="${CASE_TMP}/images" \
      OLC_VM_WORKSPACE="${CASE_TMP}/workspace" \
      OLC_KVM_DEVICE="${CASE_TMP}/kvm" \
      OLC_QEMU_DISPLAY="gtk,gl=off,zoom-to-fit=off" \
      "${OLC_LAUNCH_TEST_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected wrapper to reject direct display overrides"
  assert_contains "$output" "embedded VM launches do not allow OLC_QEMU_DISPLAY overrides"
  assert_contains "$output" "browser-tab viewer only"
  cleanup_case
}

test_launches_with_default_image_and_workspace
test_uses_cached_qemu_bin_without_nix_build
test_builds_and_caches_qemu_bin_when_needed
test_requires_nested_kvm_access
test_rejects_missing_explicit_image
test_passes_vm_lineage_to_child_launch
test_rejects_non_browser_frontend_override
test_rejects_direct_display_override

echo "PASS: olc-launch-test-vm"
