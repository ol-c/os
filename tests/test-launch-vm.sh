#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LAUNCH_VM="${ROOT_DIR}/launch-vm"
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
  CASE_TMP="$(mktemp -d "${TEST_TMP_ROOT}/launch.XXXXXX")"
  mkdir -p "${CASE_TMP}/fakebin" "${CASE_TMP}/artifacts"
  : > "${CASE_TMP}/artifacts/guest.qcow2"

  cat >"${CASE_TMP}/fakebin/qemu-system-x86_64" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${CASE_TMP}/qemu.args"
exit 0
EOF

  cat >"${CASE_TMP}/fakebin/build-vm" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" > "${CASE_TMP}/build-vm.profile"
printf '%s\n' "${CASE_TMP}/artifacts/guest.qcow2"
EOF

  chmod +x "${CASE_TMP}/fakebin/qemu-system-x86_64" "${CASE_TMP}/fakebin/build-vm"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected [$needle] in [$haystack]"
}

trap cleanup_case EXIT

test_requires_qemu() {
  local output status
  setup_case
  rm -f "${CASE_TMP}/fakebin/qemu-system-x86_64"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      SECUREOS_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to fail without qemu"
  assert_contains "$output" "required command not found: qemu-system-x86_64"
  cleanup_case
}

test_requires_kvm_by_default() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to fail without kvm"
  assert_contains "$output" "/dev/kvm is required for milestone1"
  cleanup_case
}

test_invokes_qemu_with_expected_milestone1_args() {
  local output qemu_args build_profile
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      SECUREOS_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      --milestone milestone1 \
      --cpus 4 \
      --memory 4096
  )"

  qemu_args="$(cat "${CASE_TMP}/qemu.args")"
  build_profile="$(cat "${CASE_TMP}/build-vm.profile")"
  assert_contains "$output" "success marker: MILESTONE1_BOOT_OK"
  assert_contains "$qemu_args" "-enable-kvm"
  assert_contains "$qemu_args" "-cpu host"
  assert_contains "$qemu_args" "-smp 4"
  assert_contains "$qemu_args" "-m 4096"
  assert_contains "$qemu_args" "if=virtio,format=qcow2,file=${CASE_TMP}/artifacts/guest.qcow2"
  assert_contains "$qemu_args" "-nographic"
  assert_contains "$qemu_args" "-serial mon:stdio"
  assert_contains "$qemu_args" "-snapshot"
  assert_contains "$build_profile" "milestone1"
  cleanup_case
}

test_invokes_qemu_with_expected_milestone2_args() {
  local output qemu_args build_profile
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      SECUREOS_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      --milestone milestone2 \
      --cpus 3 \
      --memory 3072
  )"

  qemu_args="$(cat "${CASE_TMP}/qemu.args")"
  build_profile="$(cat "${CASE_TMP}/build-vm.profile")"
  assert_contains "$output" "page marker: MILESTONE2_BROWSER_OK"
  assert_contains "$output" "serial output: terminal"
  assert_contains "$qemu_args" "-enable-kvm"
  assert_contains "$qemu_args" "-cpu host"
  assert_contains "$qemu_args" "-smp 3"
  assert_contains "$qemu_args" "-m 3072"
  assert_contains "$qemu_args" "if=virtio,format=qcow2,file=${CASE_TMP}/artifacts/guest.qcow2"
  assert_contains "$qemu_args" "-device virtio-vga"
  assert_contains "$qemu_args" "-serial mon:stdio"
  [[ "$qemu_args" != *"-nographic"* ]] || fail "milestone2 should use a graphical display"
  assert_contains "$build_profile" "milestone2"
  cleanup_case
}

test_rejects_unknown_profile() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      SECUREOS_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      --milestone nope \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected unknown milestone to fail"
  assert_contains "$output" "unsupported milestone: nope"
  cleanup_case
}

test_fails_if_build_output_is_missing() {
  local output status
  setup_case

  cat >"${CASE_TMP}/fakebin/build-vm" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$1" > "${CASE_TMP}/build-vm.profile"
printf '%s\n' "${CASE_TMP}/artifacts/missing.qcow2"
EOF
  chmod +x "${CASE_TMP}/fakebin/build-vm"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      SECUREOS_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      --milestone milestone2 \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to fail if the built image is missing"
  assert_contains "$output" "built image not found"
  cleanup_case
}

test_requires_qemu
test_requires_kvm_by_default
test_invokes_qemu_with_expected_milestone1_args
test_invokes_qemu_with_expected_milestone2_args
test_rejects_unknown_profile
test_fails_if_build_output_is_missing

echo "PASS: launch-vm"
