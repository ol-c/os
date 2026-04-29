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
printf '%s\n' "\${PULSE_SERVER:-}" > "${CASE_TMP}/qemu.pulse-server"
printf '%s\n' "\${PULSE_SINK:-}" > "${CASE_TMP}/qemu.pulse-sink"
qmp_socket=""
vnc_enabled=0
for arg in "\$@"; do
  case "\$arg" in
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
if [[ "\$vnc_enabled" = "1" ]]; then
  qemu_exit_status="\${OLC_FAKE_QEMU_EXIT_STATUS:-0}"
  if [[ "\${OLC_FAKE_QEMU_EXIT_EARLY:-0}" = "1" ]]; then
    sleep 0.2
    exit "\$qemu_exit_status"
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

  cat >"${CASE_TMP}/fakebin/node" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/node.args"
printf '%s\n' "\${OLC_NOVNC_DIR:-}" > "${CASE_TMP}/node.novnc-dir"
printf '%s\n' "\${OLC_VM_SCREEN_VNC_WS_PORT:-}" > "${CASE_TMP}/node.vnc-ws-port"
printf '%s\n' "\${OLC_VM_SCREEN_AUDIO_ENABLED:-}" > "${CASE_TMP}/node.audio-enabled"
printf '%s\n' "\${OLC_VM_SCREEN_AUDIO_BIN:-}" > "${CASE_TMP}/node.audio-bin"
printf '%s\n' "\${OLC_VM_SCREEN_AUDIO_ARGS_JSON:-}" > "${CASE_TMP}/node.audio-args-json"
printf '%s\n' "\${OLC_VM_SCREEN_AUDIO_SAMPLE_RATE:-}" > "${CASE_TMP}/node.audio-sample-rate"
printf '%s\n' "\${OLC_VM_SCREEN_AUDIO_CHANNELS:-}" > "${CASE_TMP}/node.audio-channels"
printf '%s\n' "\${PULSE_SERVER:-}" > "${CASE_TMP}/node.pulse-server"
printf '%s\n' 'OLC_VM_SCREEN_URL http://127.0.0.1:6080/'
if [[ "\${OLC_FAKE_VM_SCREEN_WAIT:-0}" != "1" ]]; then
  exit "\${OLC_FAKE_VM_SCREEN_EXIT_STATUS:-0}"
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

  cat >"${CASE_TMP}/fakebin/journalctl" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" >> "${CASE_TMP}/journalctl.args.all"
count_file="${CASE_TMP}/journalctl.ready-count"
count=0
if [[ -f "\$count_file" ]]; then
  count="\$(cat "\$count_file")"
fi
count="\$((count + 1))"
printf '%s\n' "\$count" > "\$count_file"

if [[ " \$* " == *" SYSLOG_IDENTIFIER=olc-vm-ready "* ]]; then
  ready_after="\${OLC_FAKE_READY_AFTER_CALLS:-1}"
  if [[ "\$count" -ge "\$ready_after" && "\${OLC_FAKE_READY_FAIL:-0}" != "1" ]]; then
    cat <<'OUT'
__REALTIME_TIMESTAMP=1714090000000000
SYSLOG_IDENTIFIER=olc-vm-ready
MESSAGE=ol-c vm ready for embedded control
OLC_VM_READY=embedded-control-ready
OLC_VM_MACHINE_ID=child-machine
OLC_VM_BOOT_ID=child-boot
OLC_VM_DEPTH=1
OLC_VM_PARENT_MACHINE_ID=parent-machine

OUT
  fi
  exit 0
fi

cat <<'OUT'
Sat 2026-04-26 12:00:00 UTC ol-c-browser systemd[1]: still booting
OUT
EOF

  cat >"${CASE_TMP}/fakebin/pactl" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" >> "${CASE_TMP}/pactl.args.all"
printf '%s\n' "\${PULSE_SERVER:-}" > "${CASE_TMP}/pactl.pulse-server"
case "\${1:-}" in
  info)
    exit 0
    ;;
  load-module)
    printf '%s\n' "\$*" > "${CASE_TMP}/pactl.load-module.args"
    printf '%s\n' 42
    exit 0
    ;;
  unload-module)
    printf '%s\n' "\$*" > "${CASE_TMP}/pactl.unload-module.args"
    exit 0
    ;;
esac
exit 0
EOF

  cat >"${CASE_TMP}/fakebin/parec" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/parec.args"
while true; do
  sleep 1
done
EOF

  chmod +x "${CASE_TMP}/fakebin/qemu-system-x86_64" "${CASE_TMP}/fakebin/qemu-img" "${CASE_TMP}/fakebin/virtiofsd" "${CASE_TMP}/fakebin/node" "${CASE_TMP}/fakebin/build-vm" "${CASE_TMP}/fakebin/nix" "${CASE_TMP}/fakebin/journalctl" "${CASE_TMP}/fakebin/pactl" "${CASE_TMP}/fakebin/parec"
  cp "${CASE_TMP}/fakebin/qemu-system-x86_64" "${CASE_TMP}/qemu-store/bin/qemu-system-x86_64"
}

assert_contains() {
  local haystack="$1"
  local needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected [$needle] in [$haystack]"
}

safe_cat() {
  cat "$1" 2>/dev/null || true
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
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
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
  local output qemu_args build_args qemu_img_args virtiofsd_args virtiofsd_shared_dir vm_images_virtiofsd_args vm_images_shared_dir virtiofs_socket vm_images_socket node_args node_novnc_dir node_vnc_ws_port node_audio_enabled node_audio_bin node_audio_args_json node_audio_sample_rate node_audio_channels node_pulse_server nix_args qmp_socket qemu_pulse_server qemu_pulse_sink pactl_load_args pactl_unload_args pactl_pulse_server
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_VM_SCREEN_WAIT=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      --cpus 3 \
      --memory 3072
  )"
  set -e

  qemu_args="$(safe_cat "${CASE_TMP}/qemu.args")"
  build_args="$(safe_cat "${CASE_TMP}/build-vm.args")"
  qemu_img_args="$(safe_cat "${CASE_TMP}/qemu-img.args")"
  virtiofsd_args="$(safe_cat "${CASE_TMP}/virtiofsd.args")"
  virtiofsd_shared_dir="$(safe_cat "${CASE_TMP}/virtiofsd.shared-dir")"
  vm_images_virtiofsd_args="$(safe_cat "${CASE_TMP}/vm-images-virtiofsd.args")"
  vm_images_shared_dir="$(safe_cat "${CASE_TMP}/vm-images-virtiofsd.shared-dir")"
  node_args="$(safe_cat "${CASE_TMP}/node.args")"
  node_novnc_dir="$(safe_cat "${CASE_TMP}/node.novnc-dir")"
  node_vnc_ws_port="$(safe_cat "${CASE_TMP}/node.vnc-ws-port")"
  node_audio_enabled="$(safe_cat "${CASE_TMP}/node.audio-enabled")"
  node_audio_bin="$(safe_cat "${CASE_TMP}/node.audio-bin")"
  node_audio_args_json="$(safe_cat "${CASE_TMP}/node.audio-args-json")"
  node_audio_sample_rate="$(safe_cat "${CASE_TMP}/node.audio-sample-rate")"
  node_audio_channels="$(safe_cat "${CASE_TMP}/node.audio-channels")"
  node_pulse_server="$(safe_cat "${CASE_TMP}/node.pulse-server")"
  nix_args="$(safe_cat "${CASE_TMP}/nix.args.all")"
  qmp_socket="$(safe_cat "${CASE_TMP}/qmp.socket-path")"
  qemu_pulse_server="$(safe_cat "${CASE_TMP}/qemu.pulse-server")"
  qemu_pulse_sink="$(safe_cat "${CASE_TMP}/qemu.pulse-sink")"
  pactl_load_args="$(safe_cat "${CASE_TMP}/pactl.load-module.args")"
  pactl_unload_args="$(safe_cat "${CASE_TMP}/pactl.unload-module.args")"
  pactl_pulse_server="$(safe_cat "${CASE_TMP}/pactl.pulse-server")"
  assert_contains "$output" "graphical proof: Firefox launches as the in-guest UI shell"
  assert_contains "$output" "serial output: terminal"
  assert_contains "$output" "qemu frontend: browser"
  assert_contains "$output" "qemu binary: ${CASE_TMP}/qemu-store/bin/qemu-system-x86_64"
  assert_contains "$output" "qmp socket: "
  assert_contains "$output" "runtime disk overlay: "
  assert_contains "$output" "runtime disk size: 64G"
  assert_contains "$output" "fast boot: 0"
  assert_contains "$output" "network mode: user"
  assert_contains "$output" "source mount: ${ROOT_DIR} -> /source"
  assert_contains "$output" "image mount: ${CASE_TMP}/artifacts -> /vm-images"
  assert_contains "$output" "in-guest image: /vm-images/guest.qcow2"
  assert_contains "$output" "virtiofsd sandbox: none"
  assert_contains "$output" "virtiofsd id mapping: guest 1000:1000 -> host "
  assert_contains "$output" "viewer: browser tab"
  assert_contains "$output" "audio: browser bridge via olc_vm_"
  assert_contains "$output" "novnc assets: ${CASE_TMP}/novnc"
  assert_contains "$output" "vnc display: 127.0.0.1:"
  assert_contains "$output" "vnc websocket: 127.0.0.1:"
  assert_contains "$output" "browser url: http://127.0.0.1:6080/"
  assert_contains "$output" "reconnect url: http://localhost:6080/"
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
  assert_contains "$qemu_args" "-audiodev pa,id=olc-audio,server=unix:/run/user/1000/pulse/native"
  assert_contains "$qemu_args" "out.latency=20000"
  assert_contains "$qemu_args" "-device intel-hda"
  assert_contains "$qemu_args" "-device hda-duplex,audiodev=olc-audio"
  assert_contains "$qemu_args" "-qmp unix:"
  assert_contains "$qemu_args" "-display none"
  assert_contains "$qemu_args" "-vnc 127.0.0.1:"
  assert_contains "$qemu_args" "websocket=127.0.0.1:"
  assert_contains "$qemu_args" "-chardev qemu-vdagent,id=ol-c-vdagent,name=vdagent,clipboard=on,mouse=off"
  assert_contains "$qemu_args" "-device virtio-serial-pci"
  assert_contains "$qemu_args" "-device virtserialport,chardev=ol-c-vdagent,name=com.redhat.spice.0"
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
  assert_contains "$node_args" "vm-screen/server.mjs"
  [[ "$node_novnc_dir" == "${CASE_TMP}/novnc" ]] || fail "expected screen server to use fake noVNC assets, got [$node_novnc_dir]"
  [[ "$node_vnc_ws_port" =~ ^[0-9]+$ ]] || fail "expected screen server to receive a websocket port, got [$node_vnc_ws_port]"
  [[ "$node_audio_enabled" == "1" ]] || fail "expected browser audio bridge to be enabled for the viewer, got [$node_audio_enabled]"
  [[ "$node_audio_bin" == "${CASE_TMP}/fakebin/parec" ]] || fail "expected viewer audio capture bin to use fake parec, got [$node_audio_bin]"
  assert_contains "$node_audio_args_json" "\"--device=olc_vm_"
  assert_contains "$node_audio_args_json" "\"--rate=48000\""
  assert_contains "$node_audio_args_json" "\"--channels=2\""
  assert_contains "$node_audio_args_json" "\"--format=s16le\""
  [[ "$node_audio_sample_rate" == "48000" ]] || fail "expected viewer audio sample rate 48000, got [$node_audio_sample_rate]"
  [[ "$node_audio_channels" == "2" ]] || fail "expected viewer audio channels 2, got [$node_audio_channels]"
  [[ "$node_pulse_server" == "unix:/run/user/1000/pulse/native" ]] || fail "expected viewer server pulse env, got [$node_pulse_server]"
  [[ "$qemu_pulse_server" == "unix:/run/user/1000/pulse/native" ]] || fail "expected QEMU pulse server env, got [$qemu_pulse_server]"
  [[ "$qemu_pulse_sink" == olc_vm_* ]] || fail "expected QEMU pulse sink env, got [$qemu_pulse_sink]"
  assert_contains "$pactl_load_args" "load-module module-null-sink sink_name=olc_vm_"
  assert_contains "$pactl_load_args" "rate=48000"
  assert_contains "$pactl_load_args" "channels=2"
  assert_contains "$pactl_load_args" "format=s16le"
  [[ "$pactl_pulse_server" == "unix:/run/user/1000/pulse/native" ]] || fail "expected pactl to target the pulse server socket, got [$pactl_pulse_server]"
  [[ "$pactl_unload_args" == "unload-module 42" ]] || fail "expected launcher cleanup to unload the temporary VM audio sink, got [$pactl_unload_args]"
  [[ -f "${CASE_TMP}/virtiofsd.terminated" ]] || fail "expected launcher cleanup to terminate virtiofsd"
  [[ "$qmp_socket" == /tmp/ol-c-qmp.*/* ]] || fail "expected QMP socket to use a disposable temp directory, got [$qmp_socket]"
  virtiofs_socket="$(safe_cat "${CASE_TMP}/virtiofsd.socket-path")"
  vm_images_socket="$(safe_cat "${CASE_TMP}/vm-images-virtiofsd.socket-path")"
  [[ ! -e "$(dirname "$virtiofs_socket")" ]] || fail "expected virtiofs temp directory to be removed"
  [[ ! -e "$(dirname "$vm_images_socket")" ]] || fail "expected VM images virtiofs temp directory to be removed"
  [[ ! -e "$(dirname "$qmp_socket")" ]] || fail "expected QMP temp directory to be removed"
  cleanup_case
}

test_disables_browser_audio_bridge_when_requested() {
  local output qemu_args node_audio_enabled
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_AUDIO_MODE=none \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_VM_SCREEN_WAIT=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      --cpus 1 \
      --memory 1024
  )"
  set -e

  qemu_args="$(safe_cat "${CASE_TMP}/qemu.args")"
  node_audio_enabled="$(safe_cat "${CASE_TMP}/node.audio-enabled")"
  assert_contains "$output" "audio: disabled"
  assert_contains "$qemu_args" "-audiodev none,id=olc-audio"
  [[ -z "$node_audio_enabled" ]] || fail "expected viewer audio bridge env to stay unset when audio is disabled, got [$node_audio_enabled]"
  [[ ! -f "${CASE_TMP}/pactl.load-module.args" ]] || fail "expected no Pulse sink setup when browser audio is disabled"
  cleanup_case
}

test_uses_build_friendly_default_resources() {
  local output qemu_args
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_VM_SCREEN_WAIT=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}"
  )"
  set -e

  qemu_args="$(safe_cat "${CASE_TMP}/qemu.args")"
  assert_contains "$qemu_args" "-smp 8"
  assert_contains "$qemu_args" "-m 16384"
  assert_contains "$qemu_args" "-object memory-backend-memfd,id=olc-mem,size=16384M,share=on"
  assert_contains "$output" "runtime disk size: 64G"
  cleanup_case
}

test_does_not_write_runtime_metadata() {
  local runtime_dir launch_log launcher_pid
  setup_case
  runtime_dir="${CASE_TMP}/runtime"
  launch_log="${CASE_TMP}/launch.log"
  launcher_pid=""

  PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
    BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
    OLC_SKIP_SOURCE_WRITE_CHECK=1 \
    OLC_SKIP_KVM_CHECK=1 \
    "${LAUNCH_VM}" >"${launch_log}" 2>&1 &
  launcher_pid="$!"

  for _ in $(seq 1 50); do
    if [[ -f "${CASE_TMP}/qmp.socket-path" ]]; then
      break
    fi
    sleep 0.1
  done

  [[ ! -f "${runtime_dir}/vm.json" ]] || fail "did not expect launch-vm to write an ad-hoc control file"

  kill "$launcher_pid" >/dev/null 2>&1 || true
  wait "$launcher_pid" >/dev/null 2>&1 || true
  launcher_pid=""
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

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_VM_SCREEN_WAIT=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}"
  )"
  set -e

  qemu_args="$(safe_cat "${CASE_TMP}/qemu.args")"
  node_novnc_dir="$(safe_cat "${CASE_TMP}/node.novnc-dir")"
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

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/does-not-exist" \
      OLC_VM_IMAGE="${CASE_TMP}/explicit/reused.qcow2" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_VM_SCREEN_WAIT=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}"
  )"
  set -e

  qemu_args="$(safe_cat "${CASE_TMP}/qemu.args")"
  vm_images_shared_dir="$(safe_cat "${CASE_TMP}/vm-images-virtiofsd.shared-dir")"
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

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_VM_SCREEN_WAIT=1 \
      OLC_VM_PARENT_MACHINE_ID=parent-machine \
      OLC_VM_PARENT_DEPTH=3 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}"
  )"
  set -e

  qemu_args="$(safe_cat "${CASE_TMP}/qemu.args")"
  assert_contains "$output" "parent machine id: parent-machine"
  assert_contains "$output" "parent vm depth: 3"
  assert_contains "$qemu_args" "-smbios type=1,serial=olc-parent-machine-id=parent-machine;olc-parent-depth=3"
  cleanup_case
}

test_supports_fast_boot_without_guest_network() {
  local output qemu_args
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_VM_SCREEN_WAIT=1 \
      OLC_VM_FAST_BOOT=1 \
      OLC_VM_NETWORK_MODE=none \
      OLC_SHARE_VM_IMAGES=0 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}"
  )"
  set -e

  qemu_args="$(safe_cat "${CASE_TMP}/qemu.args")"
  assert_contains "$output" "fast boot: 1"
  assert_contains "$output" "network mode: none"
  [[ "$output" != *"image mount:"* ]] || fail "expected vm image sharing to be disabled"
  [[ "$qemu_args" != *"-netdev user,id=olc-net"* ]] || fail "expected network mode none to omit the QEMU user netdev"
  [[ "$qemu_args" != *"-device virtio-net-pci,netdev=olc-net"* ]] || fail "expected network mode none to omit the virtio NIC"
  [[ "$qemu_args" != *"ol-c-vm-images"* ]] || fail "expected vm image sharing to be disabled"
  assert_contains "$qemu_args" "-smbios type=1,serial=olc-fast-boot=1;olc-net=none"
  cleanup_case
}

test_waits_for_ready_marker_when_requested() {
  local output
  setup_case
  : > "${CASE_TMP}/current.journal"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_VM_SCREEN_WAIT=1 \
      OLC_VM_WAIT_READY=1 \
      OLC_VM_READY_JOURNAL="${CASE_TMP}/current.journal" \
      OLC_VM_READY_WARN_SECONDS=999 \
      OLC_VM_PARENT_MACHINE_ID=parent-machine \
      OLC_VM_PARENT_DEPTH=0 \
      OLC_FAKE_READY_AFTER_CALLS=2 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}"
  )"
  set -e

  assert_contains "$output" "waiting for ready marker: timeout=30s warn=999s journal=${CASE_TMP}/current.journal"
  assert_contains "$output" "ready marker arrived after "
  [[ -f "${CASE_TMP}/journalctl.ready-count" ]] || fail "expected journalctl polling for a ready marker"
  cleanup_case
}

test_ready_marker_timeout_surfaces_journal_tail() {
  local output status
  setup_case
  : > "${CASE_TMP}/current.journal"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_WAIT_READY=1 \
      OLC_VM_READY_JOURNAL="${CASE_TMP}/current.journal" \
      OLC_VM_READY_TIMEOUT_SECONDS=1 \
      OLC_VM_PARENT_MACHINE_ID=parent-machine \
      OLC_VM_PARENT_DEPTH=0 \
      OLC_FAKE_READY_FAIL=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_SKIP_KVM_CHECK=1 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to fail when the ready marker does not arrive"
  assert_contains "$output" "timed out waiting 1s for embedded VM ready marker"
  assert_contains "$output" "still booting"
  [[ -f "${CASE_TMP}/qemu.terminated" ]] || fail "expected ready-marker timeout to terminate QEMU"
  cleanup_case
}

test_exits_when_qemu_exits_first() {
  local output qemu_args
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_VM_SCREEN_WAIT=1 \
      "${LAUNCH_VM}"
  )"
  set -e

  qemu_args="$(safe_cat "${CASE_TMP}/qemu.args")"
  assert_contains "$output" "qemu frontend: browser"
  assert_contains "$qemu_args" "-display none"
  assert_contains "$qemu_args" "-chardev qemu-vdagent,id=ol-c-vdagent,name=vdagent,clipboard=on,mouse=off"
  cleanup_case
}

test_surfaces_qemu_exit_status() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_QEMU_EXIT_STATUS=23 \
      OLC_FAKE_VM_SCREEN_WAIT=1 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -eq 23 ]] || fail "expected launch-vm to return the QEMU exit status, got [$status]"
  assert_contains "$output" "browser url: http://127.0.0.1:6080/"
  cleanup_case
}

test_surfaces_vm_screen_exit_status_and_log() {
  local output status
  setup_case

  cat >"${CASE_TMP}/fakebin/node" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/node.args"
printf '%s\n' "\${OLC_NOVNC_DIR:-}" > "${CASE_TMP}/node.novnc-dir"
printf '%s\n' "\${OLC_VM_SCREEN_VNC_WS_PORT:-}" > "${CASE_TMP}/node.vnc-ws-port"
printf '%s\n' 'OLC_VM_SCREEN_URL http://127.0.0.1:6080/'
printf '%s\n' 'vm screen crashed after startup' >&2
exit 17
EOF
  chmod +x "${CASE_TMP}/fakebin/node"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_VM_SCREEN_OPEN_BROWSER=0 \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_FAKE_QEMU_EXIT_EARLY=1 \
      OLC_FAKE_QEMU_EXIT_STATUS=0 \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -eq 17 ]] || fail "expected launch-vm to return the VM screen exit status, got [$status]"
  assert_contains "$output" "vm screen crashed after startup"
  cleanup_case
}

test_rejects_direct_display_override() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_QEMU_DISPLAY="gtk,gl=off,zoom-to-fit=off" \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to reject direct display overrides"
  assert_contains "$output" "OLC_QEMU_DISPLAY is not supported"
  assert_contains "$output" "browser only"
  cleanup_case
}

test_rejects_non_browser_frontend_override() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      BUILD_VM_BIN="${CASE_TMP}/fakebin/build-vm" \
      OLC_NOVNC_DIR="${CASE_TMP}/novnc" \
      OLC_SKIP_KVM_CHECK=1 \
      OLC_SKIP_SOURCE_WRITE_CHECK=1 \
      OLC_QEMU_FRONTEND=sdl \
      "${LAUNCH_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected launch-vm to reject non-browser frontends"
  assert_contains "$output" "OLC_QEMU_FRONTEND=sdl is not supported"
  assert_contains "$output" "browser only"
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
test_requires_virtiofsd
test_requires_kvm_by_default
test_requires_source_directory_create_permissions
test_invokes_qemu_with_expected_browser_args_by_default
test_disables_browser_audio_bridge_when_requested
test_uses_build_friendly_default_resources
test_resolves_nixpkgs_novnc_webapp_layout
test_explicit_vm_image_skips_build
test_missing_explicit_vm_image_fails
test_passes_parent_vm_lineage_to_guest_firmware
test_supports_fast_boot_without_guest_network
test_does_not_write_runtime_metadata
test_waits_for_ready_marker_when_requested
test_ready_marker_timeout_surfaces_journal_tail
test_exits_when_qemu_exits_first
test_surfaces_qemu_exit_status
test_surfaces_vm_screen_exit_status_and_log
test_rejects_direct_display_override
test_rejects_non_browser_frontend_override
test_rejects_milestone_argument
test_requires_option_values
test_fails_if_build_output_is_missing

echo "PASS: launch-vm"
