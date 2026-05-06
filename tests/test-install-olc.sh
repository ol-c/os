#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
INSTALL_OLC="${ROOT_DIR}/install-olc"
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
  CASE_TMP="$(mktemp -d "${TEST_TMP_ROOT}/install-olc.XXXXXX")"
  mkdir -p "${CASE_TMP}/fakebin" "${CASE_TMP}/efi" "${CASE_TMP}/repo/nix"
  : > "${CASE_TMP}/repo/flake.nix"
  : > "${CASE_TMP}/repo/nix/ol-c.nix"
  : > "${CASE_TMP}/repo/nix/ol-c-hardware.nix"

  cat >"${CASE_TMP}/fakebin/parted" <<EOF
#!${TEST_FAKE_BASH}
case " \$* " in
  *" print free "*)
    printf '%s\n' "\${OLC_FAKE_PARTED_OUTPUT}"
    exit 0
    ;;
esac
printf '%s\n' "\$*" >> "${CASE_TMP}/parted.calls"
EOF

  cat >"${CASE_TMP}/fakebin/lsblk" <<EOF
#!${TEST_FAKE_BASH}
if [[ " \$* " == *" -dn "* ]]; then
  printf '%s\n' "\${OLC_FAKE_LSBLK_DISKS:-testdisk disk 200G Fake Disk}"
  exit 0
fi
if [[ "\${OLC_FAKE_LSBLK_MOUNTED:-0}" = "1" ]]; then
  printf '%s\n' '/mnt/existing'
fi
EOF

  cat >"${CASE_TMP}/fakebin/sfdisk" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" >> "${CASE_TMP}/sfdisk.calls"
printf '%s\n' 'label: gpt'
EOF

  cat >"${CASE_TMP}/fakebin/mkfs.vfat" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" >> "${CASE_TMP}/mkfs-vfat.calls"
EOF

  cat >"${CASE_TMP}/fakebin/mkfs.ext4" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" >> "${CASE_TMP}/mkfs-ext4.calls"
EOF

  cat >"${CASE_TMP}/fakebin/mount" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" >> "${CASE_TMP}/mount.calls"
mkdir -p "\${2:-}"
EOF

  cat >"${CASE_TMP}/fakebin/nixos-generate-config" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" >> "${CASE_TMP}/nixos-generate-config.calls"
root=""
while [[ \$# -gt 0 ]]; do
  case "\$1" in
    --root)
      root="\$2"
      shift 2
      ;;
    *)
      shift
      ;;
  esac
done
mkdir -p "\$root/etc/nixos"
printf '%s\n' '{ ... }: {}' > "\$root/etc/nixos/hardware-configuration.nix"
EOF

  cat >"${CASE_TMP}/fakebin/nixos-install" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" >> "${CASE_TMP}/nixos-install.calls"
EOF

  cat >"${CASE_TMP}/fakebin/partprobe" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" >> "${CASE_TMP}/partprobe.calls"
EOF

  cat >"${CASE_TMP}/fakebin/udevadm" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" >> "${CASE_TMP}/udevadm.calls"
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

single_gap_output() {
  cat <<'EOF'
BYT;
/dev/testdisk:214748364800B:scsi:512:512:gpt:Fake Disk:;
1:1048576B:1073741823B:1072693248B:ext4:existing:;
2:1073741824B:161061273599B:159987531776B:free;
EOF
}

multiple_gap_output() {
  cat <<'EOF'
BYT;
/dev/testdisk:322122547200B:scsi:512:512:gpt:Fake Disk:;
1:1048576B:1073741823B:1072693248B:ext4:existing:;
2:1073741824B:118111600639B:117037858816B:free;
3:118111600640B:119185342463B:1073741824B:ext4:other:;
4:119185342464B:236223201279B:117037858816B:free;
EOF
}

run_installer() {
  PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
    OLC_INSTALL_EFI_DIR="${CASE_TMP}/efi" \
    OLC_INSTALL_SKIP_BLOCK_CHECK=1 \
    OLC_FAKE_PARTED_OUTPUT="${OLC_FAKE_PARTED_OUTPUT}" \
    OLC_FAKE_LSBLK_MOUNTED="${OLC_FAKE_LSBLK_MOUNTED:-0}" \
    OLC_INSTALL_WORK_TEMPLATE="${CASE_TMP}/work.XXXXXX" \
    "$INSTALL_OLC" \
      --disk /dev/testdisk \
      --repo "${CASE_TMP}/repo" \
      --target-root "${CASE_TMP}/target" \
      "$@"
}

run_interactive_installer() {
  PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
    OLC_INSTALL_INTERACTIVE=1 \
    OLC_INSTALL_EFI_DIR="${CASE_TMP}/efi" \
    OLC_INSTALL_SKIP_BLOCK_CHECK=1 \
    OLC_FAKE_PARTED_OUTPUT="${OLC_FAKE_PARTED_OUTPUT}" \
    OLC_FAKE_LSBLK_DISKS="${OLC_FAKE_LSBLK_DISKS:-testdisk disk 200G Fake Disk}" \
    OLC_FAKE_LSBLK_MOUNTED="${OLC_FAKE_LSBLK_MOUNTED:-0}" \
    OLC_INSTALL_WORK_TEMPLATE="${CASE_TMP}/work.XXXXXX" \
    "$INSTALL_OLC" \
      --repo "${CASE_TMP}/repo" \
      "$@"
}

test_dry_run_plans_without_mutation() {
  local output
  setup_case
  OLC_FAKE_PARTED_OUTPUT="$(single_gap_output)"

  output="$(run_installer)"

  assert_contains "$output" "mode:        dry-run"
  assert_contains "$output" "ESP:   /dev/testdisk2"
  assert_contains "$output" "root:  /dev/testdisk3"
  assert_contains "$output" "dry-run only: no disk changes were made"
  [[ ! -f "${CASE_TMP}/parted.calls" ]] || fail "dry-run should not mutate partitions"
  [[ ! -f "${CASE_TMP}/mkfs-ext4.calls" ]] || fail "dry-run should not format"
  [[ ! -f "${CASE_TMP}/nixos-install.calls" ]] || fail "dry-run should not install"
  cleanup_case
}

test_interactive_selects_disk_and_defaults_options() {
  local output
  setup_case
  OLC_FAKE_PARTED_OUTPUT="$(single_gap_output)"

  output="$(run_interactive_installer --target-root "${CASE_TMP}/target" 2>"${CASE_TMP}/interactive.stderr" <<< $'1\n\nnone\n\n')"

  assert_contains "$output" "mode:        dry-run"
  assert_contains "$output" "disk:        /dev/testdisk"
  assert_contains "$output" "wifi:        none"
  assert_contains "$output" "range: 1073741824-161061273599"
  assert_file_contains "${CASE_TMP}/interactive.stderr" "Candidate install disks:"
  [[ ! -f "${CASE_TMP}/parted.calls" ]] || fail "interactive dry-run should not mutate partitions"
  cleanup_case
}

test_interactive_selects_free_space_gap() {
  local output
  setup_case
  OLC_FAKE_PARTED_OUTPUT="$(multiple_gap_output)"

  output="$(run_interactive_installer --target-root "${CASE_TMP}/target" 2>"${CASE_TMP}/interactive.stderr" <<< $'1\n\nnone\n2\n\n')"

  assert_contains "$output" "disk:        /dev/testdisk"
  assert_contains "$output" "range: 119185342464-236223201279"
  assert_file_contains "${CASE_TMP}/interactive.stderr" "Select free-space gap"
  cleanup_case
}

test_execute_requires_exact_confirmation() {
  local output status
  setup_case
  OLC_FAKE_PARTED_OUTPUT="$(single_gap_output)"

  set +e
  output="$(run_installer --execute <<<"no" 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected confirmation failure"
  assert_contains "$output" "confirmation did not match"
  [[ ! -f "${CASE_TMP}/parted.calls" ]] || fail "failed confirmation should not mutate partitions"
  cleanup_case
}

test_execute_creates_only_planned_partitions_and_installs() {
  local output connection_mode
  setup_case
  OLC_FAKE_PARTED_OUTPUT="$(single_gap_output)"

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_INSTALL_EFI_DIR="${CASE_TMP}/efi" \
      OLC_INSTALL_SKIP_BLOCK_CHECK=1 \
      OLC_FAKE_PARTED_OUTPUT="${OLC_FAKE_PARTED_OUTPUT}" \
      OLC_INSTALL_WORK_TEMPLATE="${CASE_TMP}/work.XXXXXX" \
      OLC_INSTALL_CONFIRM="INSTALL ol-c to /dev/testdisk" \
      OLC_INSTALL_WIFI_SSID="olc-test" \
      OLC_INSTALL_WIFI_PASSPHRASE="correct horse" \
      "$INSTALL_OLC" \
        --disk /dev/testdisk \
        --repo "${CASE_TMP}/repo" \
        --target-root "${CASE_TMP}/target" \
        --execute
  )"

  assert_contains "$output" "mode:        execute"
  assert_contains "$output" "ol-c install complete"
  assert_file_contains "${CASE_TMP}/parted.calls" "unit B mkpart OLC-EFI fat32 1073741824B 2147483647B"
  assert_file_contains "${CASE_TMP}/parted.calls" "set 2 esp on"
  assert_file_contains "${CASE_TMP}/parted.calls" "unit B mkpart OLC-ROOT ext4 2147483648B 161061273599B"
  assert_file_contains "${CASE_TMP}/mkfs-vfat.calls" "-F 32 -n OLC-EFI /dev/testdisk2"
  assert_file_contains "${CASE_TMP}/mkfs-ext4.calls" "-F -L OLC-ROOT /dev/testdisk3"
  assert_file_contains "${CASE_TMP}/mount.calls" "/dev/testdisk3 ${CASE_TMP}/target"
  assert_file_contains "${CASE_TMP}/mount.calls" "/dev/testdisk2 ${CASE_TMP}/target/boot"
  assert_file_contains "${CASE_TMP}/nixos-install.calls" "--root ${CASE_TMP}/target --flake ${CASE_TMP}/work."
  [[ -f "${CASE_TMP}/target/etc/ol-c/source/flake.nix" ]] || fail "expected ol-c system source copied to target /etc/ol-c/source"
  [[ -f "${CASE_TMP}/target/etc/nixos/flake.nix" ]] || fail "expected installed rebuild flake"
  assert_file_contains "${CASE_TMP}/target/etc/nixos/flake.nix" 'olc.url = "path:/etc/ol-c/source";'
  assert_file_contains "${CASE_TMP}/target/etc/NetworkManager/system-connections/ol-c-wifi.nmconnection" "ssid=olc-test"
  connection_mode="$(stat -c '%a' "${CASE_TMP}/target/etc/NetworkManager/system-connections/ol-c-wifi.nmconnection")"
  [[ "$connection_mode" == "600" ]] || fail "expected Wi-Fi connection mode 600, got $connection_mode"
  assert_file_contains "${CASE_TMP}/target/var/lib/ol-c/install/manifest.env" "disk=/dev/testdisk"
  assert_file_contains "${CASE_TMP}/target/var/lib/ol-c/install/manifest.env" "installed_source=/etc/ol-c/source"
  cleanup_case
}

test_execute_uses_bundled_payload_env_by_default() {
  setup_case
  OLC_FAKE_PARTED_OUTPUT="$(single_gap_output)"

  PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
    OLC_INSTALL_REPO="${CASE_TMP}/repo" \
    OLC_INSTALL_EFI_DIR="${CASE_TMP}/efi" \
    OLC_INSTALL_SKIP_BLOCK_CHECK=1 \
    OLC_FAKE_PARTED_OUTPUT="${OLC_FAKE_PARTED_OUTPUT}" \
    OLC_INSTALL_WORK_TEMPLATE="${CASE_TMP}/work.XXXXXX" \
    OLC_INSTALL_CONFIRM="INSTALL ol-c to /dev/testdisk" \
    "$INSTALL_OLC" \
      --disk /dev/testdisk \
      --target-root "${CASE_TMP}/target" \
      --wifi none \
      --execute >/dev/null

  [[ -f "${CASE_TMP}/target/etc/ol-c/source/flake.nix" ]] || fail "expected bundled payload source to be installed"
  assert_file_contains "${CASE_TMP}/target/var/lib/ol-c/install/manifest.env" "repo_source=${CASE_TMP}/repo"
  cleanup_case
}

test_multiple_gaps_require_explicit_selection() {
  local output status
  setup_case
  OLC_FAKE_PARTED_OUTPUT="$(multiple_gap_output)"

  set +e
  output="$(run_installer 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected multiple gap failure"
  assert_contains "$output" "multiple usable unallocated gaps found"
  assert_contains "$output" "--gap 1073741824-118111600639"
  assert_contains "$output" "--gap 119185342464-236223201279"
  cleanup_case
}

test_explicit_gap_selects_matching_range() {
  local output
  setup_case
  OLC_FAKE_PARTED_OUTPUT="$(multiple_gap_output)"

  output="$(run_installer --gap 119185342464-236223201279)"

  assert_contains "$output" "range: 119185342464-236223201279"
  assert_contains "$output" "ESP:   /dev/testdisk2"
  cleanup_case
}

test_rejects_non_gpt_disk() {
  local output status
  setup_case
  OLC_FAKE_PARTED_OUTPUT="$(cat <<'EOF'
BYT;
/dev/testdisk:214748364800B:scsi:512:512:msdos:Fake Disk:;
1:1048576B:161061273599B:161060225024B:free;
EOF
)"

  set +e
  output="$(run_installer 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected non-GPT failure"
  assert_contains "$output" "target disk must use a GPT partition table"
  cleanup_case
}

test_rejects_mounted_target_disk() {
  local output status
  setup_case
  OLC_FAKE_PARTED_OUTPUT="$(single_gap_output)"
  OLC_FAKE_LSBLK_MOUNTED=1

  set +e
  output="$(run_installer 2>&1)"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected mounted disk failure"
  assert_contains "$output" "target disk or one of its partitions is mounted"
  cleanup_case
}

trap cleanup_case EXIT

test_dry_run_plans_without_mutation
test_interactive_selects_disk_and_defaults_options
test_interactive_selects_free_space_gap
test_execute_requires_exact_confirmation
test_execute_creates_only_planned_partitions_and_installs
test_execute_uses_bundled_payload_env_by_default
test_multiple_gaps_require_explicit_selection
test_explicit_gap_selects_matching_range
test_rejects_non_gpt_disk
test_rejects_mounted_target_disk

echo "PASS: install-olc"
