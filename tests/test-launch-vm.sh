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
printf '%s\n' "\${SDL_VIDEO_HIGHDPI_DISABLED:-}" > "${CASE_TMP}/qemu.sdl-hidpi-disabled"
printf '%s\n' "\${GDK_SCALE:-}" > "${CASE_TMP}/qemu.gdk-scale"
printf '%s\n' "\${GDK_DPI_SCALE:-}" > "${CASE_TMP}/qemu.gdk-dpi-scale"
spice_socket=""
for arg in "\$@"; do
  case "\$arg" in
    unix=on,addr=*)
      spice_socket="\${arg#*addr=}"
      spice_socket="\${spice_socket%%,*}"
      ;;
  esac
done
if [[ -n "\$spice_socket" ]]; then
  mkdir -p "\$(dirname "\$spice_socket")"
  : > "\$spice_socket"
  if [[ "\${OLC_FAKE_QEMU_EXIT_EARLY:-0}" = "1" ]]; then
    sleep 0.2
    exit 0
  fi
  trap 'printf "%s\n" terminated > "${CASE_TMP}/qemu.terminated"; exit 0' TERM INT
  while true; do
    sleep 1
  done
fi
exit 0
EOF

  cat >"${CASE_TMP}/fakebin/remote-viewer" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${CASE_TMP}/remote-viewer.args"
if [[ "\${OLC_FAKE_VIEWER_WAIT:-0}" = "1" ]]; then
  trap 'printf "%s\n" terminated > "${CASE_TMP}/remote-viewer.terminated"; exit 0' TERM INT
  while true; do
    sleep 1
  done
fi
exit 0
EOF

  cat >"${CASE_TMP}/fakebin/build-vm" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${CASE_TMP}/build-vm.args"
printf '%s\n' "${CASE_TMP}/artifacts/guest.qcow2"
EOF

  chmod +x "${CASE_TMP}/fakebin/qemu-system-x86_64" "${CASE_TMP}/fakebin/remote-viewer" "${CASE_TMP}/fakebin/build-vm"
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
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to fail without qemu"
  assert_contains "$output" "required command not found: qemu-system-x86_64"
  cleanup_case
}

test_requires_remote_viewer_for_spice() {
  local output status
  setup_case
  rm -f "${CASE_TMP}/fakebin/remote-viewer"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to fail without remote-viewer"
  assert_contains "$output" "required command not found: remote-viewer"
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
  assert_contains "$output" "/dev/kvm is required"
  cleanup_case
}

test_invokes_qemu_with_expected_spice_args() {
  local output qemu_args viewer_args build_args sdl_hidpi_disabled gdk_scale gdk_dpi_scale spice_socket
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      --cpus 3 \
      --memory 3072
  )"

  qemu_args="$(cat "${CASE_TMP}/qemu.args")"
  viewer_args="$(cat "${CASE_TMP}/remote-viewer.args")"
  build_args="$(cat "${CASE_TMP}/build-vm.args")"
  sdl_hidpi_disabled="$(cat "${CASE_TMP}/qemu.sdl-hidpi-disabled")"
  gdk_scale="$(cat "${CASE_TMP}/qemu.gdk-scale")"
  gdk_dpi_scale="$(cat "${CASE_TMP}/qemu.gdk-dpi-scale")"
  assert_contains "$output" "graphical proof: Firefox launches as the in-guest UI shell"
  assert_contains "$output" "serial output: terminal"
  assert_contains "$output" "qemu frontend: spice"
  assert_contains "$output" "spice socket:"
  assert_contains "$output" "viewer: remote-viewer spice+unix://"
  assert_contains "$output" "sdl hidpi disabled: SDL_VIDEO_HIGHDPI_DISABLED=1"
  assert_contains "$output" "gtk scale: GDK_SCALE=1 GDK_DPI_SCALE=1"
  assert_contains "$qemu_args" "-enable-kvm"
  assert_contains "$qemu_args" "-cpu host"
  assert_contains "$qemu_args" "-smp 3"
  assert_contains "$qemu_args" "-m 3072"
  assert_contains "$qemu_args" "if=virtio,format=qcow2,file=${CASE_TMP}/artifacts/guest.qcow2"
  assert_contains "$qemu_args" "-netdev user,id=olc-net"
  assert_contains "$qemu_args" "-device virtio-net-pci,netdev=olc-net"
  assert_contains "$qemu_args" "-device virtio-vga"
  assert_contains "$qemu_args" "-device qemu-xhci,id=ol-c-usb"
  assert_contains "$qemu_args" "-device usb-tablet,bus=ol-c-usb.0"
  assert_contains "$qemu_args" "-audiodev none,id=olc-audio"
  assert_contains "$qemu_args" "-device intel-hda"
  assert_contains "$qemu_args" "-device hda-duplex,audiodev=olc-audio"
  assert_contains "$qemu_args" "-display none"
  assert_contains "$qemu_args" "unix=on,addr="
  assert_contains "$qemu_args" "disable-ticketing=on"
  assert_contains "$qemu_args" "agent-mouse=on"
  assert_contains "$qemu_args" "-device virtio-serial-pci"
  assert_contains "$qemu_args" "-chardev spicevmc,id=ol-c-vdagent,name=vdagent"
  assert_contains "$qemu_args" "-device virtserialport,chardev=ol-c-vdagent,name=com.redhat.spice.0"
  assert_contains "$qemu_args" "-serial mon:stdio"
  [[ "$qemu_args" != *"-nographic"* ]] || fail "milestone2 should use a graphical display"
  assert_contains "$viewer_args" "spice+unix://"
  [[ -z "$build_args" ]] || fail "expected launch-vm to call build-vm without arguments, got [$build_args]"
  [[ "$sdl_hidpi_disabled" == "1" ]] || fail "expected QEMU SDL HiDPI mode to default to disabled, got [$sdl_hidpi_disabled]"
  [[ "$gdk_scale" == "1" ]] || fail "expected QEMU GTK scale to default to 1, got [$gdk_scale]"
  [[ "$gdk_dpi_scale" == "1" ]] || fail "expected QEMU GTK DPI scale to default to 1, got [$gdk_dpi_scale]"
  [[ -f "${CASE_TMP}/qemu.terminated" ]] || fail "expected viewer exit to terminate QEMU"
  spice_socket="${viewer_args#spice+unix://}"
  [[ ! -e "$(dirname "$spice_socket")" ]] || fail "expected SPICE temp directory to be removed"
  cleanup_case
}

test_exits_when_qemu_exits_first() {
  local output qemu_args viewer_args
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_VIEWER_WAIT=1 \
      "${LAUNCH_VM}"
  )"

  qemu_args="$(cat "${CASE_TMP}/qemu.args")"
  viewer_args="$(cat "${CASE_TMP}/remote-viewer.args")"
  assert_contains "$output" "qemu frontend: spice"
  assert_contains "$qemu_args" "-display none"
  assert_contains "$viewer_args" "spice+unix://"
  [[ -f "${CASE_TMP}/remote-viewer.terminated" ]] || fail "expected QEMU exit to terminate remote-viewer"
  cleanup_case
}

test_allows_direct_display_backend_override() {
  local output qemu_args sdl_hidpi_disabled gdk_scale gdk_dpi_scale
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_QEMU_DISPLAY="gtk,gl=off,zoom-to-fit=off" \
      OLC_QEMU_SDL_VIDEO_HIGHDPI_DISABLED="0" \
      OLC_QEMU_GDK_SCALE="2" \
      OLC_QEMU_GDK_DPI_SCALE="0.5" \
      "${LAUNCH_VM}"
  )"

  qemu_args="$(cat "${CASE_TMP}/qemu.args")"
  sdl_hidpi_disabled="$(cat "${CASE_TMP}/qemu.sdl-hidpi-disabled")"
  gdk_scale="$(cat "${CASE_TMP}/qemu.gdk-scale")"
  gdk_dpi_scale="$(cat "${CASE_TMP}/qemu.gdk-dpi-scale")"
  assert_contains "$output" "qemu frontend: direct"
  assert_contains "$output" "display backend: gtk,gl=off,zoom-to-fit=off"
  assert_contains "$output" "sdl hidpi disabled: SDL_VIDEO_HIGHDPI_DISABLED=0"
  assert_contains "$output" "gtk scale: GDK_SCALE=2 GDK_DPI_SCALE=0.5"
  assert_contains "$qemu_args" "-display gtk,gl=off,zoom-to-fit=off"
  [[ ! -f "${CASE_TMP}/remote-viewer.args" ]] || fail "direct display override should not launch remote-viewer"
  [[ "$sdl_hidpi_disabled" == "0" ]] || fail "expected overridden QEMU SDL HiDPI mode, got [$sdl_hidpi_disabled]"
  [[ "$gdk_scale" == "2" ]] || fail "expected overridden QEMU GTK scale, got [$gdk_scale]"
  [[ "$gdk_dpi_scale" == "0.5" ]] || fail "expected overridden QEMU GTK DPI scale, got [$gdk_dpi_scale]"
  cleanup_case
}

test_allows_sdl_frontend_override() {
  local output qemu_args
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_QEMU_FRONTEND=sdl \
      "${LAUNCH_VM}"
  )"

  qemu_args="$(cat "${CASE_TMP}/qemu.args")"
  assert_contains "$output" "qemu frontend: sdl"
  assert_contains "$output" "display backend: sdl,gl=off"
  assert_contains "$qemu_args" "-display sdl,gl=off"
  [[ ! -f "${CASE_TMP}/remote-viewer.args" ]] || fail "SDL frontend should not launch remote-viewer"
  cleanup_case
}

test_rejects_milestone_argument() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      --milestone milestone1 \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected --milestone to fail"
  assert_contains "$output" "unknown argument: --milestone"
  cleanup_case
}

test_requires_option_values() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      --cpus \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected --cpus without a value to fail"
  assert_contains "$output" "--cpus requires a value"
  cleanup_case
}

test_fails_if_build_output_is_missing() {
  local output status
  setup_case

  cat >"${CASE_TMP}/fakebin/build-vm" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" > "${CASE_TMP}/build-vm.args"
printf '%s\n' "${CASE_TMP}/artifacts/missing.qcow2"
EOF
  chmod +x "${CASE_TMP}/fakebin/build-vm"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to fail if the built image is missing"
  assert_contains "$output" "built image not found"
  cleanup_case
}

test_requires_qemu
test_requires_remote_viewer_for_spice
test_requires_kvm_by_default
test_invokes_qemu_with_expected_spice_args
test_exits_when_qemu_exits_first
test_allows_direct_display_backend_override
test_allows_sdl_frontend_override
test_rejects_milestone_argument
test_requires_option_values
test_fails_if_build_output_is_missing

echo "PASS: launch-vm"
