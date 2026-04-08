#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_VM="${ROOT_DIR}/build-vm"
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

test_requires_nix
test_prints_resolved_image_path_for_milestone1
test_prints_resolved_image_path_for_milestone2
test_rejects_unknown_profile
test_requires_bootable_image_in_output

echo "PASS: build-vm"
