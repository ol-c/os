#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
MAKE_INSTALL_USB="${ROOT_DIR}/make-install-usb"
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
  CASE_TMP="$(mktemp -d "${TEST_TMP_ROOT}/make-install-usb.XXXXXX")"
  mkdir -p "${CASE_TMP}/fakebin"
  printf '%s\n' "fake iso" > "${CASE_TMP}/nixos.iso"
  mkdir -p "${CASE_TMP}/iso-out/iso"
  printf '%s\n' "built fake iso" > "${CASE_TMP}/iso-out/iso/ol-c-installer.iso"

  cat >"${CASE_TMP}/fakebin/lsblk" <<EOF
#!${TEST_FAKE_BASH}
if [[ " \$* " == *" -P "* ]]; then
  cat <<'OUT'
PATH="/dev/sda" TYPE="disk" TRAN="sata" RM="0" RO="0" SIZE="512110190592" VENDOR="ATA" MODEL="Internal SSD"
PATH="/dev/sdb" TYPE="disk" TRAN="usb" RM="1" RO="0" SIZE="31004295168" VENDOR="SanDisk" MODEL="Cruzer"
PATH="/dev/sdc" TYPE="disk" TRAN="usb" RM="0" RO="0" SIZE="1000204886016" VENDOR="WD" MODEL="External HDD"
PATH="/dev/sdd" TYPE="disk" TRAN="usb" RM="1" RO="1" SIZE="16000000000" VENDOR="ReadOnly" MODEL="Stick"
PATH="/dev/sdb1" TYPE="part" TRAN="usb" RM="1" RO="0" SIZE="30900000000" VENDOR="" MODEL=""
OUT
  exit 0
fi
if [[ "\${OLC_FAKE_USB_MOUNTED:-0}" = "1" ]]; then
  printf '%s\n' '/run/media/nixos/USB'
fi
EOF

  cat >"${CASE_TMP}/fakebin/dd" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/dd.calls"
EOF

  cat >"${CASE_TMP}/fakebin/run0" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/run0.calls"
export OLC_FAKE_ID_U=0
exec "\$@"
EOF

  cat >"${CASE_TMP}/fakebin/sudo" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/sudo.calls"
export OLC_FAKE_ID_U=0
exec "\$@"
EOF

  cat >"${CASE_TMP}/fakebin/nix" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/nix.calls"
printf '%s\n' "${CASE_TMP}/iso-out"
EOF

  cat >"${CASE_TMP}/fakebin/sync" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' sync > "${CASE_TMP}/sync.calls"
EOF

  cat >"${CASE_TMP}/fakebin/id" <<EOF
#!${TEST_FAKE_BASH}
if [[ "\${1:-}" == "-u" ]]; then
  printf '%s\n' "\${OLC_FAKE_ID_U:-0}"
  exit 0
fi
exec /usr/bin/id "\$@"
EOF

  chmod +x "${CASE_TMP}/fakebin/"*
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected [$needle] in [$haystack]"
}

assert_file_contains() {
  local file="$1"
  local needle="$2"
  [[ -f "$file" ]] || fail "expected file: $file"
  assert_contains "$(cat "$file")" "$needle"
}

run_usb_writer() {
  PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
    OLC_FAKE_USB_MOUNTED="${OLC_FAKE_USB_MOUNTED:-0}" \
    OLC_FAKE_ID_U="${OLC_FAKE_ID_U:-0}" \
    "$MAKE_INSTALL_USB" \
      --iso "${CASE_TMP}/nixos.iso" \
      "$@"
}

run_usb_writer_default_iso() {
  PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
    OLC_FAKE_USB_MOUNTED="${OLC_FAKE_USB_MOUNTED:-0}" \
    OLC_FAKE_ID_U="${OLC_FAKE_ID_U:-0}" \
    "$MAKE_INSTALL_USB" \
      "$@"
}

run_usb_writer_as_user() {
  OLC_FAKE_ID_U=1000 run_usb_writer "$@"
}

run_usb_writer_default_iso_as_user() {
  OLC_FAKE_ID_U=1000 run_usb_writer_default_iso "$@"
}

test_dry_run_lists_only_removable_usb_sticks() {
  local output stderr
  setup_case

  output="$(run_usb_writer --dry-run 2>"${CASE_TMP}/stderr" <<< "1")"
  stderr="$(cat "${CASE_TMP}/stderr")"

  assert_contains "$stderr" "/dev/sdb"
  [[ "$stderr" != *"/dev/sda"* ]] || fail "internal SATA disk should not be listed"
  [[ "$stderr" != *"/dev/sdc"* ]] || fail "non-removable USB HDD should not be listed"
  [[ "$stderr" != *"/dev/sdd"* ]] || fail "read-only USB disk should not be listed"
  assert_contains "$output" "mode:      dry-run"
  assert_contains "$output" "target:    /dev/sdb"
  [[ ! -f "${CASE_TMP}/dd.calls" ]] || fail "dry-run should not call dd"
  [[ ! -f "${CASE_TMP}/nix.calls" ]] || fail "explicit --iso should not build the repo installer ISO"
  cleanup_case
}

test_default_iso_builds_repo_installer_iso() {
  local output
  setup_case

  output="$(run_usb_writer_default_iso --dry-run 2>"${CASE_TMP}/stderr" <<< "1")"

  assert_file_contains "${CASE_TMP}/nix.calls" "build .#ol-c-installer-iso --print-out-paths --no-link"
  assert_contains "$output" "iso:       ${CASE_TMP}/iso-out/iso/ol-c-installer.iso"
  assert_contains "$output" "mode:      dry-run"
  [[ ! -f "${CASE_TMP}/dd.calls" ]] || fail "dry-run should not call dd"
  cleanup_case
}

test_default_iso_fails_when_build_output_has_no_iso() {
  local output status
  setup_case
  rm -f "${CASE_TMP}/iso-out/iso/ol-c-installer.iso"

  set +e
  output="$(run_usb_writer_default_iso --dry-run <<< "1" 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected missing built ISO failure"
  assert_contains "$output" "built installer output does not contain an ISO"
  cleanup_case
}

test_write_requires_exact_confirmation() {
  local output status
  setup_case

  set +e
  output="$(run_usb_writer <<< $'1\nwrong\n' 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected confirmation failure"
  assert_contains "$output" "confirmation did not match"
  [[ ! -f "${CASE_TMP}/dd.calls" ]] || fail "failed confirmation should not call dd"
  cleanup_case
}

test_write_uses_whole_selected_device() {
  local output
  setup_case

  output="$(OLC_USB_CONFIRM="WRITE ISO to /dev/sdb" run_usb_writer 2>"${CASE_TMP}/stderr" <<< "1")"

  assert_contains "$output" "USB installer written to /dev/sdb"
  assert_file_contains "${CASE_TMP}/dd.calls" "if=${CASE_TMP}/nixos.iso of=/dev/sdb bs=4M status=progress conv=fsync"
  assert_file_contains "${CASE_TMP}/sync.calls" "sync"
  cleanup_case
}

test_non_root_write_builds_as_user_then_reexecs_privileged_write() {
  local output
  setup_case

  output="$(OLC_USB_CONFIRM="WRITE ISO to /dev/sdb" run_usb_writer_default_iso_as_user 2>"${CASE_TMP}/stderr" <<< "1")"

  assert_contains "$output" "USB installer written to /dev/sdb"
  assert_file_contains "${CASE_TMP}/nix.calls" "build .#ol-c-installer-iso --print-out-paths --no-link"
  assert_file_contains "${CASE_TMP}/run0.calls" "--write-iso ${CASE_TMP}/iso-out/iso/ol-c-installer.iso --write-device /dev/sdb --confirmed"
  assert_file_contains "${CASE_TMP}/dd.calls" "if=${CASE_TMP}/iso-out/iso/ol-c-installer.iso of=/dev/sdb bs=4M status=progress conv=fsync"
  cleanup_case
}

test_refuses_mounted_usb_stick_before_write() {
  local output status
  setup_case
  OLC_FAKE_USB_MOUNTED=1

  set +e
  output="$(OLC_USB_CONFIRM="WRITE ISO to /dev/sdb" run_usb_writer <<< "1" 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected mounted USB failure"
  assert_contains "$output" "selected USB stick or one of its partitions is mounted"
  [[ ! -f "${CASE_TMP}/dd.calls" ]] || fail "mounted USB should not call dd"
  cleanup_case
}

trap cleanup_case EXIT

test_dry_run_lists_only_removable_usb_sticks
test_default_iso_builds_repo_installer_iso
test_default_iso_fails_when_build_output_has_no_iso
test_write_requires_exact_confirmation
test_write_uses_whole_selected_device
test_non_root_write_builds_as_user_then_reexecs_privileged_write
test_refuses_mounted_usb_stick_before_write

echo "PASS: make-install-usb"
