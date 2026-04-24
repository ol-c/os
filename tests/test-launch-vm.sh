#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
LAUNCH_VM="${ROOT_DIR}/launch-vm"
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
  CASE_TMP="$(mktemp -d "${TEST_TMP_ROOT}/launch.XXXXXX")"
  mkdir -p "${CASE_TMP}/fakebin" "${CASE_TMP}/artifacts" "${CASE_TMP}/novnc/core" "${CASE_TMP}/qemu-store/bin"
  : > "${CASE_TMP}/artifacts/guest.qcow2"
  : > "${CASE_TMP}/novnc/core/rfb.js"

  cat >"${CASE_TMP}/fakebin/qemu-system-x86_64" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/qemu.args"
printf '%s\n' "\${SDL_VIDEO_HIGHDPI_DISABLED:-}" > "${CASE_TMP}/qemu.sdl-hidpi-disabled"
printf '%s\n' "\${GDK_SCALE:-}" > "${CASE_TMP}/qemu.gdk-scale"
printf '%s\n' "\${GDK_DPI_SCALE:-}" > "${CASE_TMP}/qemu.gdk-dpi-scale"
spice_socket=""
qmp_socket=""
vnc_enabled=0
for arg in "\$@"; do
  case "\$arg" in
    unix=on,addr=*)
      spice_socket="\${arg#*addr=}"
      spice_socket="\${spice_socket%%,*}"
      ;;
    unix:*,server=on,wait=off)
      qmp_socket="\${arg#unix:}"
      qmp_socket="\${qmp_socket%%,*}"
      ;;
    127.0.0.1:*,websocket=127.0.0.1:*)
      vnc_enabled=1
      ;;
  esac
done
if [[ -n "\$qmp_socket" ]]; then
  mkdir -p "\$(dirname "\$qmp_socket")"
  : > "\$qmp_socket"
  printf '%s\n' "\$qmp_socket" > "${CASE_TMP}/qmp.socket-path"
fi
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
if [[ "\$vnc_enabled" = "1" ]]; then
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

  cat >"${CASE_TMP}/fakebin/virtiofsd" <<EOF
#!${TEST_FAKE_BASH}
if [[ "\${1:-}" == "--help" ]]; then
  printf '%s\n' 'Usage: virtiofsd --translate-uid --translate-gid'
  exit 0
fi
printf '%s\n' "\$*" >> "${CASE_TMP}/virtiofsd.args.all"
socket_path=""
shared_dir=""
for arg in "\$@"; do
  case "\$arg" in
    --socket-path=*)
      socket_path="\${arg#--socket-path=}"
      ;;
    --shared-dir=*)
      shared_dir="\${arg#--shared-dir=}"
      ;;
  esac
done
if [[ "\$shared_dir" == "${ROOT_DIR}" ]]; then
  printf '%s\n' "\$*" > "${CASE_TMP}/virtiofsd.args"
  printf '%s\n' "\$socket_path" > "${CASE_TMP}/virtiofsd.socket-path"
  printf '%s\n' "\$shared_dir" > "${CASE_TMP}/virtiofsd.shared-dir"
else
  printf '%s\n' "\$*" > "${CASE_TMP}/vm-images-virtiofsd.args"
  printf '%s\n' "\$socket_path" > "${CASE_TMP}/vm-images-virtiofsd.socket-path"
  printf '%s\n' "\$shared_dir" > "${CASE_TMP}/vm-images-virtiofsd.shared-dir"
fi
if [[ -n "\$socket_path" ]]; then
  mkdir -p "\$(dirname "\$socket_path")"
  : > "\$socket_path"
fi
trap 'printf "%s\n" terminated >> "${CASE_TMP}/virtiofsd.terminated"; exit 0' TERM INT
while true; do
  sleep 1
done
EOF

  cat >"${CASE_TMP}/fakebin/remote-viewer" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/remote-viewer.args"
if [[ "\${OLC_FAKE_VIEWER_WAIT:-0}" = "1" ]]; then
  trap 'printf "%s\n" terminated > "${CASE_TMP}/remote-viewer.terminated"; exit 0' TERM INT
  while true; do
    sleep 1
  done
fi
exit 0
EOF

  cat >"${CASE_TMP}/fakebin/node" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/node.args"
printf '%s\n' "\${OLC_NOVNC_DIR:-}" > "${CASE_TMP}/node.novnc-dir"
printf '%s\n' "\${OLC_VM_SCREEN_VNC_WS_PORT:-}" > "${CASE_TMP}/node.vnc-ws-port"
printf '%s\n' 'OLC_VM_SCREEN_URL http://127.0.0.1:6080/'
if [[ "\${OLC_FAKE_VM_SCREEN_WAIT:-0}" != "1" ]]; then
  exit 0
fi
trap 'printf "%s\n" terminated > "${CASE_TMP}/node.terminated"; exit 0' TERM INT
while true; do
  sleep 1
done
EOF

  cat >"${CASE_TMP}/fakebin/build-vm" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/build-vm.args"
printf '%s\n' "${CASE_TMP}/artifacts/guest.qcow2"
EOF

  cat >"${CASE_TMP}/fakebin/qemu-img" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/qemu-img.args"
overlay=""
for arg in "\$@"; do
  case "\$arg" in
    *.qcow2)
      overlay="\$arg"
      ;;
  esac
done
if [[ -n "\$overlay" ]]; then
  mkdir -p "\$(dirname "\$overlay")"
  : > "\$overlay"
fi
EOF

  cat >"${CASE_TMP}/fakebin/nix" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" >> "${CASE_TMP}/nix.args.all"
case " \$* " in
  *" .#qemu-olc "*)
    printf '%s\n' "${CASE_TMP}/qemu-store"
    ;;
  *" .#novnc "*)
    printf '%s\n' "${CASE_TMP}/novnc-store"
    ;;
  *)
    printf '%s\n' "${CASE_TMP}/unknown-store"
    ;;
esac
EOF

  chmod +x "${CASE_TMP}/fakebin/qemu-system-x86_64" "${CASE_TMP}/fakebin/qemu-img" "${CASE_TMP}/fakebin/virtiofsd" "${CASE_TMP}/fakebin/remote-viewer" "${CASE_TMP}/fakebin/node" "${CASE_TMP}/fakebin/build-vm" "${CASE_TMP}/fakebin/nix"
  cp "${CASE_TMP}/fakebin/qemu-system-x86_64" "${CASE_TMP}/qemu-store/bin/qemu-system-x86_64"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected [$needle] in [$haystack]"
}

trap cleanup_case EXIT

test_requires_patched_qemu_build_for_browser() {
  local output status
  setup_case
  rm -f "${CASE_TMP}/qemu-store/bin/qemu-system-x86_64"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to fail without patched qemu"
  assert_contains "$output" "unable to locate qemu-system-x86_64 in patched QEMU build output: ${CASE_TMP}/qemu-store"
  cleanup_case
}

test_rejects_bad_qemu_bin_override() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_QEMU_FRONTEND=sdl \
      OLC_QEMU_BIN="${CASE_TMP}/missing-qemu" \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to fail for a bad QEMU override"
  assert_contains "$output" "OLC_QEMU_BIN is not executable: ${CASE_TMP}/missing-qemu"
  cleanup_case
}

test_requires_remote_viewer_for_spice() {
  local output status
  setup_case
  rm -f "${CASE_TMP}/fakebin/remote-viewer"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_QEMU_FRONTEND=spice \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
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


test_requires_virtiofsd() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_VIRTIOFSD="${CASE_TMP}/missing-virtiofsd" \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to fail without virtiofsd"
  assert_contains "$output" "OLC_VIRTIOFSD is not executable: ${CASE_TMP}/missing-virtiofsd"
  cleanup_case
}

test_requires_kvm_by_default() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_KVM_DEVICE="${CASE_TMP}/missing-kvm" \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to fail without kvm"
  assert_contains "$output" "${CASE_TMP}/missing-kvm is required"
  cleanup_case
}

test_requires_source_directory_create_permissions() {
  local output status source_dir
  setup_case
  source_dir="${CASE_TMP}/readonly-source"
  mkdir -p "$source_dir"
  chmod 0555 "$source_dir"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SOURCE_DIR="$source_dir" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to fail for a non-creatable source directory"
  assert_contains "$output" "source directory does not allow creating files: $source_dir"
  [[ ! -f "${CASE_TMP}/build-vm.args" ]] || fail "expected source write check to fail before building the VM"
  cleanup_case
}

test_invokes_qemu_with_expected_browser_args_by_default() {
  local output qemu_args build_args qemu_img_args virtiofsd_args virtiofsd_shared_dir vm_images_virtiofsd_args vm_images_shared_dir sdl_hidpi_disabled gdk_scale gdk_dpi_scale virtiofs_socket vm_images_socket node_args node_novnc_dir node_vnc_ws_port nix_args qmp_socket
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      --cpus 3 \
      --memory 3072
  )"

  qemu_args="$(cat "${CASE_TMP}/qemu.args")"
  build_args="$(cat "${CASE_TMP}/build-vm.args")"
  qemu_img_args="$(cat "${CASE_TMP}/qemu-img.args")"
  virtiofsd_args="$(cat "${CASE_TMP}/virtiofsd.args")"
  virtiofsd_shared_dir="$(cat "${CASE_TMP}/virtiofsd.shared-dir")"
  vm_images_virtiofsd_args="$(cat "${CASE_TMP}/vm-images-virtiofsd.args")"
  vm_images_shared_dir="$(cat "${CASE_TMP}/vm-images-virtiofsd.shared-dir")"
  sdl_hidpi_disabled="$(cat "${CASE_TMP}/qemu.sdl-hidpi-disabled")"
  gdk_scale="$(cat "${CASE_TMP}/qemu.gdk-scale")"
  gdk_dpi_scale="$(cat "${CASE_TMP}/qemu.gdk-dpi-scale")"
  node_args="$(cat "${CASE_TMP}/node.args")"
  node_novnc_dir="$(cat "${CASE_TMP}/node.novnc-dir")"
  node_vnc_ws_port="$(cat "${CASE_TMP}/node.vnc-ws-port")"
  nix_args="$(cat "${CASE_TMP}/nix.args.all")"
  qmp_socket="$(cat "${CASE_TMP}/qmp.socket-path")"
  assert_contains "$output" "graphical proof: Firefox launches as the in-guest UI shell"
  assert_contains "$output" "serial output: terminal"
  assert_contains "$output" "qemu frontend: browser"
  assert_contains "$output" "qemu binary: ${CASE_TMP}/qemu-store/bin/qemu-system-x86_64"
  assert_contains "$output" "qmp socket: "
  assert_contains "$output" "runtime disk overlay: "
  assert_contains "$output" "runtime disk size: 64G"
  assert_contains "$output" "source mount: ${ROOT_DIR} -> /source"
  assert_contains "$output" "image mount: ${CASE_TMP}/artifacts -> /vm-images"
  assert_contains "$output" "in-guest image: /vm-images/guest.qcow2"
  assert_contains "$output" "virtiofsd sandbox: none"
  assert_contains "$output" "virtiofsd id mapping: guest 1000:1000 -> host "
  assert_contains "$output" "viewer: browser tab"
  assert_contains "$output" "novnc assets: ${CASE_TMP}/novnc"
  assert_contains "$output" "vnc display: 127.0.0.1:"
  assert_contains "$output" "vnc websocket: 127.0.0.1:"
  assert_contains "$output" "browser url: http://127.0.0.1:6080/"
  assert_contains "$output" "reconnect url: http://localhost:6080/"
  assert_contains "$output" "sdl hidpi disabled: SDL_VIDEO_HIGHDPI_DISABLED=1"
  assert_contains "$output" "gtk scale: GDK_SCALE=1 GDK_DPI_SCALE=1"
  assert_contains "$qemu_args" "-enable-kvm"
  assert_contains "$qemu_args" "-cpu host"
  assert_contains "$qemu_args" "-smp 3"
  assert_contains "$qemu_args" "-m 3072"
  assert_contains "$qemu_args" "-object memory-backend-memfd,id=olc-mem,size=3072M,share=on"
  assert_contains "$qemu_args" "-numa node,memdev=olc-mem"
  assert_contains "$qemu_args" "-machine pc,vmport=off,i8042=off"
  assert_contains "$qemu_args" "if=virtio,format=qcow2,file=/tmp/ol-c-disk."
  [[ "$qemu_args" != *" -snapshot"* ]] || fail "expected launch-vm to use an explicit disposable overlay instead of QEMU -snapshot"
  assert_contains "$qemu_img_args" "create -q -f qcow2 -F qcow2 -b ${CASE_TMP}/artifacts/guest.qcow2"
  assert_contains "$qemu_img_args" "64G"
  assert_contains "$qemu_args" "-netdev user,id=olc-net"
  assert_contains "$qemu_args" "-device virtio-net-pci,netdev=olc-net"
  assert_contains "$qemu_args" "-chardev socket,id=ol-c-source,path="
  assert_contains "$qemu_args" "-device vhost-user-fs-pci,chardev=ol-c-source,tag=ol-c-source"
  assert_contains "$qemu_args" "-chardev socket,id=ol-c-vm-images,path="
  assert_contains "$qemu_args" "-device vhost-user-fs-pci,chardev=ol-c-vm-images,tag=ol-c-vm-images"
  assert_contains "$qemu_args" "-device virtio-vga"
  assert_contains "$qemu_args" "-device qemu-xhci,id=ol-c-usb"
  assert_contains "$qemu_args" "-device usb-kbd,bus=ol-c-usb.0"
  assert_contains "$qemu_args" "-device usb-tablet,bus=ol-c-usb.0"
  assert_contains "$qemu_args" "-audiodev none,id=olc-audio"
  assert_contains "$qemu_args" "-device intel-hda"
  assert_contains "$qemu_args" "-device hda-duplex,audiodev=olc-audio"
  assert_contains "$qemu_args" "-qmp unix:"
  assert_contains "$qemu_args" "-display none"
  assert_contains "$qemu_args" "-vnc 127.0.0.1:"
  assert_contains "$qemu_args" "websocket=127.0.0.1:"
  assert_contains "$qemu_args" "-chardev qemu-vdagent,id=ol-c-vdagent,name=vdagent,clipboard=on,mouse=off"
  assert_contains "$qemu_args" "-device virtio-serial-pci"
  assert_contains "$qemu_args" "-device virtserialport,chardev=ol-c-vdagent,name=com.redhat.spice.0"
  [[ "$qemu_args" != *"-spice"* ]] || fail "browser frontend should not launch a SPICE server"
  [[ "$qemu_args" != *"spicevmc"* ]] || fail "browser frontend should not add the SPICE guest channel"
  assert_contains "$qemu_args" "-serial mon:stdio"
  assert_contains "$nix_args" "build .#qemu-olc --print-out-paths --no-link"
  assert_contains "$virtiofsd_args" "--socket-path="
  assert_contains "$virtiofsd_args" "--shared-dir=${ROOT_DIR}"
  assert_contains "$virtiofsd_args" "--sandbox=none"
  assert_contains "$virtiofsd_args" "--translate-uid=map:1000:"
  assert_contains "$virtiofsd_args" "--translate-gid=map:1000:"
  assert_contains "$virtiofsd_args" "--cache=auto"
  assert_contains "$vm_images_virtiofsd_args" "--shared-dir=${CASE_TMP}/artifacts"
  assert_contains "$vm_images_virtiofsd_args" "--sandbox=none"
  assert_contains "$vm_images_virtiofsd_args" "--translate-uid=map:1000:"
  assert_contains "$vm_images_virtiofsd_args" "--translate-gid=map:1000:"
  assert_contains "$vm_images_virtiofsd_args" "--cache=auto"
  [[ "$virtiofsd_shared_dir" == "$ROOT_DIR" ]] || fail "expected virtiofsd to share repo root, got [$virtiofsd_shared_dir]"
  [[ "$vm_images_shared_dir" == "${CASE_TMP}/artifacts" ]] || fail "expected VM image virtiofsd to share image directory, got [$vm_images_shared_dir]"
  [[ "$qemu_args" != *"-nographic"* ]] || fail "milestone2 should use a graphical display"
  [[ -z "$build_args" ]] || fail "expected launch-vm to call build-vm without arguments, got [$build_args]"
  [[ "$sdl_hidpi_disabled" == "1" ]] || fail "expected QEMU SDL HiDPI mode to default to disabled, got [$sdl_hidpi_disabled]"
  [[ "$gdk_scale" == "1" ]] || fail "expected QEMU GTK scale to default to 1, got [$gdk_scale]"
  [[ "$gdk_dpi_scale" == "1" ]] || fail "expected QEMU GTK DPI scale to default to 1, got [$gdk_dpi_scale]"
  assert_contains "$node_args" "vm-screen/server.mjs"
  [[ "$node_novnc_dir" == "${CASE_TMP}/novnc" ]] || fail "expected screen server to use fake noVNC assets, got [$node_novnc_dir]"
  [[ "$node_vnc_ws_port" =~ ^[0-9]+$ ]] || fail "expected screen server to receive a websocket port, got [$node_vnc_ws_port]"
  [[ -f "${CASE_TMP}/qemu.terminated" ]] || fail "expected screen server exit to terminate QEMU"
  [[ -f "${CASE_TMP}/virtiofsd.terminated" ]] || fail "expected launcher cleanup to terminate virtiofsd"
  [[ ! -f "${CASE_TMP}/remote-viewer.args" ]] || fail "browser frontend should not launch remote-viewer"
  [[ "$qmp_socket" == /tmp/ol-c-qmp.*/* ]] || fail "expected QMP socket to use a disposable temp directory, got [$qmp_socket]"
  virtiofs_socket="$(cat "${CASE_TMP}/virtiofsd.socket-path")"
  vm_images_socket="$(cat "${CASE_TMP}/vm-images-virtiofsd.socket-path")"
  [[ ! -e "$(dirname "$virtiofs_socket")" ]] || fail "expected virtiofs temp directory to be removed"
  [[ ! -e "$(dirname "$vm_images_socket")" ]] || fail "expected VM images virtiofs temp directory to be removed"
  [[ ! -e "$(dirname "$qmp_socket")" ]] || fail "expected QMP temp directory to be removed"
  cleanup_case
}

test_resolves_nixpkgs_novnc_webapp_layout() {
  local output qemu_args node_novnc_dir
  setup_case
  rm -rf "${CASE_TMP}/novnc"
  mkdir -p "${CASE_TMP}/novnc-store/share/webapps/novnc/core"
  : > "${CASE_TMP}/novnc-store/share/webapps/novnc/core/rfb.js"

  cat >"${CASE_TMP}/fakebin/nix" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" >> "${CASE_TMP}/nix.args.all"
case " \$* " in
  *" .#qemu-olc "*)
    printf '%s\n' "${CASE_TMP}/qemu-store"
    ;;
  *" .#novnc "*)
    printf '%s\n' "${CASE_TMP}/novnc-store"
    ;;
  *)
    printf '%s\n' "${CASE_TMP}/unknown-store"
    ;;
esac
EOF
  chmod +x "${CASE_TMP}/fakebin/nix"

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}"
  )"

  qemu_args="$(cat "${CASE_TMP}/qemu.args")"
  node_novnc_dir="$(cat "${CASE_TMP}/node.novnc-dir")"
  assert_contains "$output" "novnc assets: ${CASE_TMP}/novnc-store/share/webapps/novnc"
  assert_contains "$qemu_args" "-vnc 127.0.0.1:"
  [[ "$node_novnc_dir" == "${CASE_TMP}/novnc-store/share/webapps/novnc" ]] || fail "expected nixpkgs noVNC webapp layout, got [$node_novnc_dir]"
  cleanup_case
}

test_explicit_vm_image_skips_build() {
  local output qemu_args vm_images_shared_dir
  setup_case
  mkdir -p "${CASE_TMP}/explicit"
  : > "${CASE_TMP}/explicit/reused.qcow2"

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/does-not-exist" \
      OLC_VM_IMAGE="${CASE_TMP}/explicit/reused.qcow2" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}"
  )"

  qemu_args="$(cat "${CASE_TMP}/qemu.args")"
  vm_images_shared_dir="$(cat "${CASE_TMP}/vm-images-virtiofsd.shared-dir")"
  assert_contains "$output" "booting image: ${CASE_TMP}/explicit/reused.qcow2"
  assert_contains "$output" "image mount: ${CASE_TMP}/explicit -> /vm-images"
  assert_contains "$output" "in-guest image: /vm-images/reused.qcow2"
  assert_contains "$qemu_args" "if=virtio,format=qcow2,file=/tmp/ol-c-disk."
  [[ ! -f "${CASE_TMP}/build-vm.args" ]] || fail "expected explicit OLC_VM_IMAGE to skip build-vm"
  [[ "$vm_images_shared_dir" == "${CASE_TMP}/explicit" ]] || fail "expected explicit image directory to be shared, got [$vm_images_shared_dir]"
  cleanup_case
}

test_missing_explicit_vm_image_fails() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_VM_IMAGE="${CASE_TMP}/missing.qcow2" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected missing OLC_VM_IMAGE to fail"
  assert_contains "$output" "OLC_VM_IMAGE does not point to a file: ${CASE_TMP}/missing.qcow2"
  [[ ! -f "${CASE_TMP}/build-vm.args" ]] || fail "expected missing OLC_VM_IMAGE to fail before build-vm"
  cleanup_case
}

test_passes_parent_vm_lineage_to_guest_firmware() {
  local output qemu_args
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_VM_PARENT_MACHINE_ID=parent-machine \
      OLC_VM_PARENT_DEPTH=3 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}"
  )"

  qemu_args="$(cat "${CASE_TMP}/qemu.args")"
  assert_contains "$output" "parent machine id: parent-machine"
  assert_contains "$output" "parent vm depth: 3"
  assert_contains "$qemu_args" "-smbios type=1,serial=olc-parent-machine-id=parent-machine;olc-parent-depth=3"
  cleanup_case
}

test_exits_when_qemu_exits_first() {
  local output qemu_args viewer_args
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_QEMU_FRONTEND=spice \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_VIEWER_WAIT=1 \
      "${LAUNCH_VM}"
  )"

  qemu_args="$(cat "${CASE_TMP}/qemu.args")"
  viewer_args="$(cat "${CASE_TMP}/remote-viewer.args")"
  assert_contains "$output" "qemu frontend: spice"
  assert_contains "$qemu_args" "-display none"
  assert_contains "$qemu_args" "-chardev spicevmc,id=ol-c-vdagent,name=vdagent"
  [[ "$qemu_args" != *"qemu-vdagent"* ]] || fail "SPICE frontend should not use the browser VNC clipboard chardev"
  assert_contains "$viewer_args" "spice+unix://"
  [[ -f "${CASE_TMP}/remote-viewer.terminated" ]] || fail "expected QEMU exit to terminate remote-viewer"
  cleanup_case
}

test_allows_direct_display_backend_override() {
  local output qemu_args sdl_hidpi_disabled gdk_scale gdk_dpi_scale
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
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
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/build-vm.args"
printf '%s\n' "${CASE_TMP}/artifacts/missing.qcow2"
EOF
  chmod +x "${CASE_TMP}/fakebin/build-vm"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
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

test_requires_patched_qemu_build_for_browser
test_rejects_bad_qemu_bin_override
test_requires_remote_viewer_for_spice
test_requires_virtiofsd
test_requires_kvm_by_default
test_requires_source_directory_create_permissions
test_invokes_qemu_with_expected_browser_args_by_default
test_resolves_nixpkgs_novnc_webapp_layout
test_explicit_vm_image_skips_build
test_missing_explicit_vm_image_fails
test_passes_parent_vm_lineage_to_guest_firmware
test_exits_when_qemu_exits_first
test_allows_direct_display_backend_override
test_allows_sdl_frontend_override
test_rejects_milestone_argument
test_requires_option_values
test_fails_if_build_output_is_missing

echo "PASS: launch-vm"
