#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_VM="${ROOT_DIR}/build-vm"
AGENTS_DOC="${ROOT_DIR}/AGENTS.md"
FLAKE_NIX="${ROOT_DIR}/flake.nix"
INSTALL_OLC="${ROOT_DIR}/install-olc"
MAKE_INSTALL_USB="${ROOT_DIR}/make-install-usb"
OLC_NIX="${ROOT_DIR}/nix/ol-c.nix"
OLC_HARDWARE_NIX="${ROOT_DIR}/nix/ol-c-hardware.nix"
NIX_USERS="${ROOT_DIR}/nix/modules/users.nix"
NIX_BASE="${ROOT_DIR}/nix/modules/base.nix"
NIX_HARDWARE_BASE="${ROOT_DIR}/nix/modules/hardware-base.nix"
NIX_PACKAGES="${ROOT_DIR}/nix/modules/packages.nix"
NIX_LOCALHOST_UI="${ROOT_DIR}/nix/modules/localhost-ui.nix"
NIX_GRAPHICAL_SESSION="${ROOT_DIR}/nix/modules/graphical-session.nix"
NIX_DEVELOPMENT="${ROOT_DIR}/nix/modules/development.nix"
LOCALHOST_APP="${ROOT_DIR}/localhost-ui/app.mjs"
LOCALHOST_SERVER="${ROOT_DIR}/localhost-ui/server.mjs"
LOCALHOST_TERMINAL_APP="${ROOT_DIR}/localhost-ui/terminal-app.mjs"
LOCALHOST_TERMINAL_SERVER="${ROOT_DIR}/localhost-ui/terminal-server.mjs"
LOCALHOST_RUNTIME_STATE="${ROOT_DIR}/localhost-ui/runtime-state.mjs"
LOCALHOST_SETUP_MANAGER="${ROOT_DIR}/localhost-ui/setup-manager.mjs"
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
  CASE_TMP="$(mktemp -d "${TEST_TMP_ROOT}/build.XXXXXX")"
  mkdir -p "${CASE_TMP}/fakebin" "${CASE_TMP}/out"

  cat >"${CASE_TMP}/fakebin/nix" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "\$*" > "${CASE_TMP}/nix.args"
: > "${CASE_TMP}/out/image.qcow2"
printf '%s\n' "${CASE_TMP}/out"
EOF

  cat >"${CASE_TMP}/fakebin/findmnt" <<EOF
#!${TEST_FAKE_BASH}
exit 1
EOF

  cat >"${CASE_TMP}/fakebin/dirname" <<EOF
#!${TEST_FAKE_BASH}
printf '%s\n' "${ROOT_DIR}"
EOF

  chmod +x "${CASE_TMP}/fakebin/nix" "${CASE_TMP}/fakebin/findmnt" "${CASE_TMP}/fakebin/dirname"
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
    PATH="${CASE_TMP}/fakebin" \
      "${TEST_FAKE_BASH}" "${BUILD_VM}" \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected build-vm to fail without nix"
  [[ "$output" == *"required command not found: nix"* ]] || fail "unexpected output: $output"
}

test_prints_resolved_image_path() {
  local output args
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      "${BUILD_VM}"
  )"

  args="$(cat "${CASE_TMP}/nix.args")"
  [[ "$args" == *"build .#ol-c-image --print-out-paths --no-link"* ]] || fail "unexpected nix args: $args"
  assert_eq "${CASE_TMP}/out/image.qcow2" "$output"
}

test_rejects_unknown_argument() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      "${BUILD_VM}" mystery \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected build-vm to reject unknown argument"
  [[ "$output" == *"unknown argument: mystery"* ]] || fail "unexpected output: $output"
}

test_structural_contracts() {
  local flake_nix install_olc make_install_usb olc_nix olc_hardware_nix users ui session development app server terminal_app terminal_server runtime_state setup_manager base hardware_base packages editor_page
  local agents_doc
  flake_nix="$(cat "${FLAKE_NIX}")"
  install_olc="$(cat "${INSTALL_OLC}")"
  make_install_usb="$(cat "${MAKE_INSTALL_USB}")"
  olc_nix="$(cat "${OLC_NIX}")"
  olc_hardware_nix="$(cat "${OLC_HARDWARE_NIX}")"
  base="$(cat "${NIX_BASE}")"
  hardware_base="$(cat "${NIX_HARDWARE_BASE}")"
  packages="$(cat "${NIX_PACKAGES}")"
  agents_doc="$(cat "${AGENTS_DOC}")"
  users="$(cat "${NIX_USERS}")"
  ui="$(cat "${NIX_LOCALHOST_UI}")"
  session="$(cat "${NIX_GRAPHICAL_SESSION}")"
  development="$(cat "${NIX_DEVELOPMENT}")"
  app="$(cat "${LOCALHOST_APP}")"
  editor_page="$(cat "${ROOT_DIR}/localhost-ui/editor-page.mjs")"
  server="$(cat "${LOCALHOST_SERVER}")"
  terminal_app="$(cat "${LOCALHOST_TERMINAL_APP}")"
  terminal_server="$(cat "${LOCALHOST_TERMINAL_SERVER}")"
  runtime_state="$(cat "${LOCALHOST_RUNTIME_STATE}")"
  setup_manager="$(cat "${LOCALHOST_SETUP_MANAGER}")"

  [[ "$flake_nix" == *'nixosModules = {'* && "$flake_nix" == *'hardware = { ... }: {'* && "$flake_nix" == *'./nix/ol-c-hardware.nix'* ]] || fail "expected flake to export an ol-c hardware install module"
  [[ "$flake_nix" == *'nixosConfigurations."ol-c-installer"'* && "$flake_nix" == *'"ol-c-installer-iso"'* && "$flake_nix" == *'installerIsoModule'* ]] || fail "expected flake to export the ol-c installer ISO"
  [[ "$olc_nix" == *"./modules/users.nix"* ]] || fail "expected ol-c module to import users.nix"
  [[ "$olc_nix" == *"./modules/localhost-ui.nix"* ]] || fail "expected ol-c module to import localhost-ui.nix"
  [[ "$olc_hardware_nix" == *"./modules/hardware-base.nix"* ]] || fail "expected hardware profile to import hardware-base.nix"
  [[ "$olc_hardware_nix" != *"./modules/shared-repo.nix"* ]] || fail "expected hardware profile not to import VM virtiofs shared repo mounts"
  [[ "$hardware_base" == *"boot.loader.systemd-boot.enable = true;"* ]] || fail "expected hardware install profile to use systemd-boot"
  [[ "$hardware_base" == *"boot.loader.efi.canTouchEfiVariables = true;"* ]] || fail "expected hardware install profile to manage UEFI boot entries"
  [[ "$hardware_base" == *"networking.networkmanager.enable = true;"* ]] || fail "expected hardware install profile to enable NetworkManager"
  [[ "$hardware_base" == *"hardware.enableRedistributableFirmware = true;"* ]] || fail "expected hardware install profile to include redistributable firmware for Wi-Fi"
  [[ "$hardware_base" == *'"d /etc/ol-c 0755 root root -"'* ]] || fail "expected hardware install profile to create root-owned ol-c system source parent"
  [[ "$hardware_base" != *'"/source"'* && "$hardware_base" != *"olcLocalSourcePermissions"* ]] || fail "expected hardware install profile not to create a developer /source workspace"
  [[ "$flake_nix" == *'installation-cd-minimal.nix'* ]] || fail "expected installer ISO to use the minimal NixOS installer profile"
  [[ "$flake_nix" == *'installerPayload'* && "$flake_nix" == *'export OLC_INSTALL_REPO='* ]] || fail "expected installer ISO to run install-olc against the bundled payload"
  [[ "$flake_nix" == *'networking.networkmanager.enable = true;'* && "$flake_nix" == *'pkgs.networkmanager'* && "$flake_nix" == *'pkgs.iw'* ]] || fail "expected installer ISO to include Wi-Fi-capable NetworkManager tooling"
  [[ "$flake_nix" == *'pkgs.parted'* && "$flake_nix" == *'pkgs.dosfstools'* && "$flake_nix" == *'pkgs.e2fsprogs'* ]] || fail "expected installer ISO to include partition and filesystem tools"
  [[ "$flake_nix" != *'"/source"'* ]] || fail "expected installer ISO not to configure /source"
  [[ "$install_olc" == *"Consumes only already-unallocated space"* ]] || fail "expected installer help to document unallocated-space-only policy"
  [[ "$install_olc" == *"choose_disk_interactive"* && "$install_olc" == *"Candidate install disks:"* ]] || fail "expected installer to offer interactive disk selection"
  [[ "$install_olc" == *"Select free-space gap"* && "$install_olc" == *"Usable unallocated free-space gaps:"* ]] || fail "expected installer to offer interactive free-space gap selection"
  [[ "$install_olc" == *"--non-interactive"* ]] || fail "expected installer to keep a scripted non-interactive mode"
  [[ "$install_olc" == *"check_uefi"* && "$install_olc" == *"UEFI firmware is required"* ]] || fail "expected installer to require UEFI mode"
  [[ "$install_olc" == *"assert_gpt_disk"* && "$install_olc" == *"target disk must use a GPT partition table"* ]] || fail "expected installer to require GPT disks"
  [[ "$install_olc" == *"confirm_execute"* && "$install_olc" == *"INSTALL ol-c to"* ]] || fail "expected installer to require explicit destructive confirmation"
  [[ "$install_olc" == *"nixos-install --root"* && "$install_olc" == *"olc.nixosModules.hardware"* ]] || fail "expected installer to install the hardware flake module"
  [[ "$install_olc" == *'REPO_DIR="${OLC_INSTALL_REPO:-$ROOT_DIR}"'* && "$install_olc" == *'path:/etc/ol-c/source'* ]] || fail "expected installer to use bundled payloads and preserve installed system source under /etc/ol-c/source"
  [[ "$install_olc" == *"NetworkManager/system-connections"* && "$install_olc" == *"ol-c-wifi.nmconnection"* ]] || fail "expected installer to support NetworkManager Wi-Fi provisioning"
  [[ "$make_install_usb" == *'.#ol-c-installer-iso'* && "$make_install_usb" == *"resolve_built_iso_path"* ]] || fail "expected USB writer to build the repo installer ISO by default"
  [[ "$make_install_usb" == *"TYPE=disk, TRAN=usb, RM=1, and RO=0"* ]] || fail "expected USB writer help to document removable USB-only filtering"
  [[ "$make_install_usb" == *'[[ "$type" == "disk" ]]'* && "$make_install_usb" == *'[[ "$tran" == "usb" ]]'* && "$make_install_usb" == *'[[ "$rm" == "1" ]]'* && "$make_install_usb" == *'[[ "$ro" == "0" ]]'* ]] || fail "expected USB writer to filter to writable removable USB disks"
  [[ "$make_install_usb" == *"device_has_mounts"* && "$make_install_usb" == *"selected USB stick or one of its partitions is mounted"* ]] || fail "expected USB writer to reject mounted targets"
  [[ "$make_install_usb" == *"WRITE ISO to"* && "$make_install_usb" == *'of="$TARGET_DEVICE"'* ]] || fail "expected USB writer to require confirmation and write to the whole selected device"
  [[ "$base" == *"ids.uids.nixbld = lib.mkForce 700;"* ]] || fail "expected nix build users to be force-allocated below 1000 for homed setup detection"
  [[ "$base" == *"Storage=persistent"* ]] || fail "expected journald to persist logs locally"
  [[ "$base" == *'systemd.generators.olc-nested-fast-boot'* ]] || fail "expected a nested fast-boot systemd generator"
  [[ "$base" == *"olc-fast-boot=1"* ]] || fail "expected the fast-boot generator to detect the nested fast-boot SMBIOS flag"
  [[ "$base" == *"mask_unit systemd-journal-flush.service"* ]] || fail "expected nested fast boot to skip journal flush"
  [[ "$base" == *"mask_unit systemd-random-seed.service"* ]] || fail "expected nested fast boot to skip random seed loading"
  [[ "$base" != *"mask_unit growpart.service"* && "$base" != *"mask_unit systemd-growfs-root.service"* ]] || fail "expected nested fast boot to keep root growth enabled"
  [[ "$base" == *"mask_unit dhcpcd.service"* ]] || fail "expected nested net=none to skip dhcpcd"
  [[ "$base" == *'systemd.services.olc-journal-mirror'* ]] || fail "expected a shared journal mirror service"
  [[ "$base" == *'RequiresMountsFor = "/source";'* ]] || fail "expected the shared journal mirror to require /source"
  [[ "$base" == *"''\${machine_id}-''\${current_boot_id}.journal"* ]] || fail "expected the shared journal mirror to write one native journal file per VM boot"
  [[ "$base" == *'systemd-journal-remote'* ]] || fail "expected the shared journal mirror to use systemd-journal-remote"
  [[ "$base" == *'--output=export'* ]] || fail "expected the shared journal mirror to export the local journal in export format before import"
  [[ "$base" == *'OLC_VM_PARENT_MACHINE_ID'* && "$base" == *'OLC_VM_DEPTH'* ]] || fail "expected the shared journal mirror to record VM lineage fields"
  [[ "$base" == *'olc-lifecycle-id='* && "$base" == *'OLC_VM_LIFECYCLE_ID'* ]] || fail "expected VM lineage to record lifecycle IDs from SMBIOS serial fields"
  [[ "$base" != *'case "$serial" in'* ]] || fail "expected VM lineage parsing to accept parent fields anywhere in the SMBIOS serial"
  [[ "$agents_doc" == *'/source/.olc-debug/journal'* ]] || fail "expected AGENTS to document the shared journal mirror directory"
  [[ "$agents_doc" == *'journalctl --directory=/source/.olc-debug/journal'* ]] || fail "expected AGENTS to document standard journalctl usage for the shared mirror"
  [[ "$base" == *'sleep 0.2'* ]] || fail "expected the shared journal mirror to export new entries at subsecond cadence"
  [[ "$packages" == *'fonts.enableDefaultPackages = false;'* ]] || fail "expected non-Noto default font packages to be disabled"
  [[ "$packages" == *'noto-fonts'* && "$packages" == *'noto-fonts-cjk-sans'* && "$packages" == *'noto-fonts-cjk-serif'* && "$packages" == *'noto-fonts-color-emoji'* ]] || fail "expected the OS image to include the bundled Noto font set"
  [[ "$packages" == *'fonts.fontconfig.defaultFonts'* ]] || fail "expected explicit fontconfig defaults"
  [[ "$packages" == *'"Noto Sans"'* && "$packages" == *'"Noto Serif"'* && "$packages" == *'"Noto Sans Mono"'* && "$packages" == *'"Noto Color Emoji"'* ]] || fail "expected Noto fontconfig defaults for sans, serif, monospace, and emoji"
  [[ "$packages" == *'xorg.xrandr'* ]] || fail "expected the OS image to include xrandr for guest-side display mode changes"
  [[ "$users" == *'greeterUser = "olc-greeter"'* ]] || fail "expected a dedicated browser greeter user"
  [[ "$users" == *'isSystemUser = true;'* && "$users" == *'home = "/var/lib/ol-c/greeter";'* ]] || fail "expected the browser greeter to use a writable dedicated home"
  [[ "$users" == *'setupUser = "olc-setup"'* ]] || fail "expected a dedicated setup user"
  [[ "$users" == *'users.groups.olc-admin = {};'* ]] || fail "expected an explicit olc-admin group"
  [[ "$users" == *'isNormalUser = true;'* ]] || fail "expected setup user to be a normal user for greetd initial sessions"
  [[ "$users" == *'uid = 1100;'* ]] || fail "expected setup user to use a non-conflicting uid above 1000"
  [[ "$session" == *'services.greetd = {'* ]] || fail "expected greetd to manage setup and login flow"
  [[ "$session" == *'terminal.vt = 1;'* ]] || fail "expected greetd to own vt1"
  [[ "$session" == *'default_session = {'* && "$session" == *'user = "olc-greeter";'* ]] || fail "expected configured boots to use the dedicated browser greeter account on vt1"
  [[ "$session" == *'initial_session = {'* && "$session" == *'olc-setup'* ]] || fail "expected fresh boots to use a setup initial session"
  [[ "$session" == *'getent group olc-admin'* ]] || fail "expected initial setup session to switch on admin existence"
  [[ "$session" == *'writeShellScript "olc-greetd-user-session"'* ]] || fail "expected a dedicated greetd wrapper for configured user sessions"
  [[ "$session" == *'writeShellScript "olc-greetd-setup-session"'* ]] || fail "expected a dedicated greetd wrapper for setup sessions"
  [[ "$session" == *'writeShellScript "olc-greetd-browser-greeter"'* ]] || fail "expected a dedicated greetd wrapper for the browser greeter session"
  [[ "$session" == *'writeShellScript "olc-greeter-xsession"'* ]] || fail "expected a dedicated X session script for the browser greeter"
  [[ "$session" == *'runCommand "olc-login-greeter-ui"'* ]] || fail "expected the browser greeter modules to be packaged through an explicit checked Nix output"
  [[ "$session" == *'../../localhost-ui/login-accounts.mjs'* && "$session" == *'../../localhost-ui/greetd-client.mjs'* && "$session" == *'../../localhost-ui/login-greeter-app.mjs'* && "$session" == *'../../localhost-ui/login-greeter-page.mjs'* && "$session" == *'../../localhost-ui/login-greeter.mjs'* ]] || fail "expected the greeter package to directly reference every browser greeter module"
  [[ "$session" == *'OLC_GETENT='* && "$session" == *'${pkgs.getent}/bin/getent'* && "$session" == *'OLC_HOMECTL='* && "$session" == *'${pkgs.systemd}/bin/homectl'* && "$session" == *"OLC_GREETER_EXCLUDE_USERS='root,nobody,olc-setup,olc-greeter'"* && "$session" == *"OLC_GREETER_MIN_UID='1000'"* && "$session" == *"OLC_GREETER_MAX_UID='60000'"* ]] || fail "expected the greeter account list to use getent and homectl with explicit human-user filters"
  [[ "$session" == *'${loginGreeterUi}/login-greeter.mjs'* && "$session" == *'OLC_GREETD_LOGIN_CMD'* ]] || fail "expected the greeter session to launch the packaged local greetd bridge with the configured login command"
  [[ "$session" == *'greeterUrl = "https://localhost:${toString greeterPort}/login";'* && "$session" == *'--kiosk --new-window ${greeterUrl}'* ]] || fail "expected the greeter session to open the browser login page in kiosk mode"
  [[ "$session" == *'identifier=olc-greetd-session'* ]] || fail "expected greetd session wrappers to log before startx"
  [[ "$session" == *'startxWithRetry = sessionScript:'* ]] || fail "expected graphical sessions to wrap startx in a retry helper"
  [[ "$session" == *'${startxWithRetry userSessionScript}'* ]] || fail "expected configured greetd logins to launch the explicit user session script through the startx retry helper"
  [[ "$session" == *'exec ${greetdSetupSessionCommand}'* ]] || fail "expected setup boots to launch the explicit setup wrapper"
  [[ "$session" == *'security.pam.services.greetd.text'* && "$session" == *'auth      substack      login'* && "$session" == *'session   include       login'* ]] || fail "expected greetd PAM to delegate to the login stack for homed authentication"

  [[ "$ui" == *"services.homed.enable = true;"* ]] || fail "expected systemd-homed to be enabled"
  [[ "$ui" == *"options.olc.setup.prefillFirstUser"* ]] || fail "expected a test-only first-user prefill option"
  [[ "$ui" == *"systemd.services.ol-c-prefill-first-user"* ]] || fail "expected a first-user prefill service"
  [[ "$ui" == *"OLC_HOMECTL"* ]] || fail "expected localhost UI service to provide homectl"
  [[ "$ui" == *"OLC_LOGINCTL"* ]] || fail "expected localhost services to provide loginctl"
  [[ "$ui" == *"OLC_SCRIPT"* ]] || fail "expected localhost UI service to provide script for homectl PTY automation"
  [[ "$ui" == *"OLC_SYSTEMD_RUN"* ]] || fail "expected localhost UI service to provide systemd-run for editor worker fallback"
  [[ "$ui" == *"OLC_SYSTEMCTL"* && "$ui" == *'${pkgs.systemd}/bin/systemctl'* ]] || fail "expected localhost UI service to provide systemctl for power actions"
  [[ "$ui" != *"User = \"demo\";"* ]] || fail "expected localhost UI service not to run as demo"
  [[ "$ui" == *'systemd.services.olc-vm-ready'* ]] || fail "expected a guest ready-marker service for embedded VM discovery"
  [[ "$ui" == *'systemd.services.olc-vm-operator'* ]] || fail "expected a guest operator service for embedded VM BiDi control"
  [[ "$ui" == *'OLC_VM_OPERATOR_ROOT = "/source/.olc-debug/operator/current"'* ]] || fail "expected the operator service to use the shared operator directory"
  [[ "$ui" == *'OLC_VM_READY=embedded-control-ready'* ]] || fail "expected the guest ready marker to record a stable readiness field"
  [[ "$ui" == *'OLC_VM_READY_CONTROL=bidi'* ]] || fail "expected the guest ready marker to record the BiDi control surface"
  [[ "$ui" == *'SYSLOG_IDENTIFIER=olc-vm-ready'* ]] || fail "expected the guest ready marker to log under a stable identifier"
  [[ "$ui" == *'OLC_FIREFOX_BIDI_ENV_PATH'* && "$ui" == *'ActiveSession'* ]] || fail "expected the guest ready marker to wait for active-session Firefox BiDi metadata"
  [[ "$ui" == *'sleep 0.1'* ]] || fail "expected the guest ready marker to poll localhost at subsecond granularity"
  [[ "$ui" == *'date +%s%3N'* ]] || fail "expected the guest ready marker to enforce a millisecond timeout budget"
  [[ "$ui" == *'RequiresMountsFor = "/source";'* ]] || fail "expected the embedded VM operator to require the shared source mount"

  [[ "$session" == *'writeShellScript "olc-user-xsession"'* ]] || fail "expected a dedicated user X session script"
  [[ "$session" == *'writeShellScript "olc-setup-xsession"'* ]] || fail "expected a dedicated setup X session script"
  [[ "$session" == *"https://localhost/setup"* ]] || fail "expected setup kiosk to open the setup route"
  [[ "$session" == *'kiosk = false;'* ]] || fail "expected the normal signed-in session not to force kiosk mode"
  [[ "$session" == *'kiosk = true;'* ]] || fail "expected the setup session to force kiosk mode"
  [[ "$session" == *'++ lib.optional kiosk "--kiosk"'* ]] || fail "expected Firefox launch args to include an opt-in kiosk flag"
  [[ "$session" == *'printf '\''kiosk=%s\n'\'' "${if kiosk then "1" else "0"}"'* ]] || fail "expected Firefox launch diagnostics to record kiosk mode"
  [[ "$session" == *'$HOME/.mozilla/firefox/ol-c.default'* ]] || fail "expected Firefox profile diagnostics to be home-relative"
  [[ "$session" == *'systemd-cat --identifier=olc-xsession'* ]] || fail "expected graphical sessions to log directly into journald"
  [[ "$session" == *'sleep 0.1'* ]] || fail "expected graphical session startup waits to use subsecond polling"
  [[ "$session" == *'olc_fast_boot=1'* ]] || fail "expected graphical sessions to detect nested fast-boot launches"
  [[ "$session" == *'MOZ_PURGE_CACHES=1'* ]] || fail "expected normal boots to preserve explicit cold-start Firefox coverage"
  [[ "$session" == *'--remote-debugging-port 0'* ]] || fail "expected the graphical Firefox session to enable local BiDi"
  [[ "$session" == *'bidi.env'* && "$session" == *'WebDriver BiDi listening on'* ]] || fail "expected the graphical Firefox session to publish a BiDi endpoint record"
  [[ "$session" == *'writeShellScript "olc-screen-resize-watcher"'* ]] || fail "expected a guest-side screen resize watcher"
  [[ "$session" == *'${pkgs.xorg.xrandr}/bin/xrandr --verbose --prop'* ]] || fail "expected the resize watcher to read RandR and EDID state in the guest"
  [[ "$session" == *'edid_preferred = edid_size(edid_hex)'* ]] || fail "expected the resize watcher to parse the EDID preferred size"
  [[ "$session" == *'elif [ -z "$edid_preferred" ]'* ]] || fail "expected stale RandR preferred markers to be ignored when EDID preferred size is available"
  [[ "$session" == *'--output "$output" --mode "$target_mode"'* ]] || fail "expected the resize watcher to apply target RandR modes"
  [[ "$session" == *'${screenResizeWatcher} "$$" &'* ]] || fail "expected graphical sessions to start the resize watcher"

  [[ "$development" == *"trusted-users = [ \"root\" \"@wheel\" ];"* ]] || fail "expected development nix trust to follow wheel users"
  [[ "$development" != *"d /var/lib/ol-c/firefox-dev 0775 root olc-admin -"* ]] || fail "expected the retired Firefox runtime workspace to be removed from the development profile"
  [[ "$development" == *"d /var/lib/ol-c/vms 0775 root olc-admin -"* ]] || fail "expected nested VM workspace to belong to olc-admin"
  [[ "$development" == *'OLC_DEFAULT_NOVNC_DIR'* ]] || fail "expected nested VM launches to inherit a default noVNC path"
  [[ "$development" == *'OLC_DEFAULT_QEMU_BIN'* ]] || fail "expected nested VM launches to inherit a default patched QEMU path"
  [[ "$development" == *'writeShellScriptBin "olc-firefox-bidi-url"'* ]] || fail "expected development profile to expose the Firefox BiDi URL helper"
  [[ "$development" == *'writeShellScriptBin "olc-firefox-bidi"'* ]] || fail "expected development profile to expose the Firefox BiDi client helper"
  [[ "$development" == *'writeShellScriptBin "olc-vm-bidi"'* ]] || fail "expected development profile to expose the embedded VM BiDi helper"
  [[ "$development" == *'writeShellScriptBin "olc-vmctl"'* ]] || fail "expected development profile to install olc-vmctl"
  [[ "$development" == *'tools}/olc-vmctl.mjs'* ]] || fail "expected olc-vmctl to run the repo QMP controller"

  [[ "$runtime_state" == *"show-seat"* ]] || fail "expected runtime state to resolve the active seat session"
  [[ "$runtime_state" == *"getent"* ]] || fail "expected runtime state to resolve user entries through getent"
  [[ "$setup_manager" == *"OLC_FIRST_USER_STORAGE ?? 'luks'"* ]] || fail "expected first user creation to default to LUKS-backed homed storage"
  [[ "$setup_manager" == *"OLC_FIRST_USER_DISK_SIZE ?? '8G'"* ]] || fail "expected first homed admin to default to an 8G disk image"
  [[ "$setup_manager" == *"OLC_FIRST_USER_UID ?? '1000'"* ]] || fail "expected the first homed admin to prefer UID 1000"
  [[ "$setup_manager" == *"OLC_FIRST_USER_GROUPS ?? 'olc-admin,wheel,kvm'"* ]] || fail "expected the first user to receive admin and dev groups"
  [[ "$setup_manager" == *"scriptBin"* && "$setup_manager" == *"stdinPath"* ]] || fail "expected first-user provisioning to drive homectl create through a PTY-backed script session"
  [[ "$setup_manager" == *"\${password}\\n\${password}\\n"* ]] || fail "expected first-user provisioning to feed the password twice to homectl create"
  [[ "$setup_manager" == *"createCommand"* && "$setup_manager" == *"homectlBin"* && "$setup_manager" == *"--storage=\${storage}"* && "$setup_manager" == *"--disk-size=\${diskSize}"* ]] || fail "expected first-user provisioning to use homectl create with direct flags"
  [[ "$setup_manager" == *"'inspect'"* && "$setup_manager" == *"'--json=short'"* ]] || fail "expected first-user provisioning to verify the created homed user exists"
  [[ "$setup_manager" == *"first-user provisioning timed out"* ]] || fail "expected first-user provisioning to fail cleanly on timeout"
  [[ "$setup_manager" == *"password must be at least 12 characters"* ]] || fail "expected first-user password validation"

  [[ "$app" == *"state.setupMode ? setupHtml() : rootHtml()"* ]] || fail "expected root route to switch between setup and system UI"
  [[ "$app" == *"reqUrl.pathname === '/api/setup/status'"* ]] || fail "expected setup status endpoint"
  [[ "$app" == *"reqUrl.pathname === '/api/setup/first-user'"* ]] || fail "expected first-user setup endpoint"
  [[ "$app" == *"editor is unavailable during first setup"* ]] || fail "expected editor to be blocked during setup"
  [[ "$app" == *"Terminal is unavailable during first setup."* ]] || fail "expected terminal to be blocked during setup"
  [[ "$app" == *"getEditorUser"* ]] || fail "expected editor API to resolve the active signed-in user dynamically"
  [[ "$app" == *"readEditorClientJs()"* ]] || fail "expected editor asset route to read the current bundle at request time"

  [[ "$server" == *"createFirstUser"* ]] || fail "expected server to wire first-user provisioning"
  [[ "$server" == *"getRuntimeState"* ]] || fail "expected server to wire runtime state resolution"
  [[ "$server" == *"terminate-user', setupUser"* ]] || fail "expected server to terminate the setup user session after setup completion"
  [[ "$terminal_app" == *"getTerminalUser"* ]] || fail "expected terminal app to resolve the active user dynamically"
  [[ "$terminal_app" == *"terminal is unavailable until a signed-in user session exists"* ]] || fail "expected terminal app to fail clearly when nobody is signed in"
  [[ "$terminal_server" == *"getActiveConsoleUser"* ]] || fail "expected terminal server to use active console user resolution"
  [[ "$editor_page" == *"systemd-run"* ]] || fail "expected editor worker to support a systemd-run fallback for live source-server execution"
}

test_requires_nix
test_prints_resolved_image_path
test_rejects_unknown_argument
test_structural_contracts

echo "PASS: build-vm"
