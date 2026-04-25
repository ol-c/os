#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_VM="${ROOT_DIR}/build-vm"
AGENTS_DOC="${ROOT_DIR}/AGENTS.md"
FLAKE_NIX="${ROOT_DIR}/flake.nix"
OLC_NIX="${ROOT_DIR}/nix/ol-c.nix"
NIX_USERS="${ROOT_DIR}/nix/modules/users.nix"
NIX_BASE="${ROOT_DIR}/nix/modules/base.nix"
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
  local olc_nix users ui session development app server terminal_app terminal_server runtime_state setup_manager base editor_page
  local agents_doc
  olc_nix="$(cat "${OLC_NIX}")"
  base="$(cat "${NIX_BASE}")"
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

  [[ "$olc_nix" == *"./modules/users.nix"* ]] || fail "expected ol-c module to import users.nix"
  [[ "$olc_nix" == *"./modules/localhost-ui.nix"* ]] || fail "expected ol-c module to import localhost-ui.nix"
  [[ "$base" == *"ids.uids.nixbld = lib.mkForce 700;"* ]] || fail "expected nix build users to be force-allocated below 1000 for homed setup detection"
  [[ "$base" == *"Storage=persistent"* ]] || fail "expected journald to persist logs locally"
  [[ "$base" == *'systemd.services.olc-journal-mirror'* ]] || fail "expected a shared journal mirror service"
  [[ "$base" == *'RequiresMountsFor = "/source";'* ]] || fail "expected the shared journal mirror to require /source"
  [[ "$base" == *'current.journal'* ]] || fail "expected the shared journal mirror to write a native current.journal file"
  [[ "$base" == *'systemd-journal-remote'* ]] || fail "expected the shared journal mirror to use systemd-journal-remote"
  [[ "$base" == *'--output=export'* ]] || fail "expected the shared journal mirror to export the local journal in export format before import"
  [[ "$base" == *'OLC_VM_PARENT_MACHINE_ID'* && "$base" == *'OLC_VM_DEPTH'* ]] || fail "expected the shared journal mirror to record VM lineage fields"
  [[ "$agents_doc" == *'/source/.olc-debug/journal/current.journal'* ]] || fail "expected AGENTS to document the shared journal mirror path"
  [[ "$agents_doc" == *'journalctl --file=/source/.olc-debug/journal/current.journal'* ]] || fail "expected AGENTS to document standard journalctl usage for the shared mirror"
  [[ "$users" == *'setupUser = "olc-setup"'* ]] || fail "expected a dedicated setup user"
  [[ "$users" == *'users.groups.olc-admin = {};'* ]] || fail "expected an explicit olc-admin group"
  [[ "$users" == *'isNormalUser = true;'* ]] || fail "expected setup user to be a normal user for greetd initial sessions"
  [[ "$users" == *'uid = 1100;'* ]] || fail "expected setup user to use a non-conflicting uid above 1000"
  [[ "$session" == *'services.greetd = {'* ]] || fail "expected greetd to manage setup and login flow"
  [[ "$session" == *'terminal.vt = 1;'* ]] || fail "expected greetd to own vt1"
  [[ "$session" == *'default_session = {'* && "$session" == *'tuigreet'* ]] || fail "expected configured boots to use tuigreet for login"
  [[ "$session" == *'initial_session = {'* && "$session" == *'olc-setup'* ]] || fail "expected fresh boots to use a setup initial session"
  [[ "$session" == *'getent group olc-admin'* ]] || fail "expected initial setup session to switch on admin existence"
  [[ "$session" == *'writeShellScript "olc-greetd-user-session"'* ]] || fail "expected a dedicated greetd wrapper for configured user sessions"
  [[ "$session" == *'writeShellScript "olc-greetd-setup-session"'* ]] || fail "expected a dedicated greetd wrapper for setup sessions"
  [[ "$session" == *'identifier=olc-greetd-session'* ]] || fail "expected greetd session wrappers to log before startx"
  [[ "$session" == *'exec ${pkgs.xorg.xinit}/bin/startx ${userSessionScript}'* ]] || fail "expected configured greetd logins to launch the explicit user session script"
  [[ "$session" == *'exec ${greetdSetupSessionCommand}'* ]] || fail "expected setup boots to launch the explicit setup wrapper"
  [[ "$session" == *'security.pam.services.greetd.text'* && "$session" == *'auth      substack      login'* && "$session" == *'session   include       login'* ]] || fail "expected greetd PAM to delegate to the login stack for homed authentication"

  [[ "$ui" == *"services.homed.enable = true;"* ]] || fail "expected systemd-homed to be enabled"
  [[ "$ui" == *"options.olc.setup.prefillFirstUser"* ]] || fail "expected a test-only first-user prefill option"
  [[ "$ui" == *"systemd.services.ol-c-prefill-first-user"* ]] || fail "expected a first-user prefill service"
  [[ "$ui" == *"OLC_HOMECTL"* ]] || fail "expected localhost UI service to provide homectl"
  [[ "$ui" == *"OLC_LOGINCTL"* ]] || fail "expected localhost services to provide loginctl"
  [[ "$ui" == *"OLC_SCRIPT"* ]] || fail "expected localhost UI service to provide script for homectl PTY automation"
  [[ "$ui" == *"OLC_SYSTEMD_RUN"* ]] || fail "expected localhost UI service to provide systemd-run for editor worker fallback"
  [[ "$ui" != *"User = \"demo\";"* ]] || fail "expected localhost UI service not to run as demo"

  [[ "$session" == *'writeShellScript "olc-user-xsession"'* ]] || fail "expected a dedicated user X session script"
  [[ "$session" == *'writeShellScript "olc-setup-xsession"'* ]] || fail "expected a dedicated setup X session script"
  [[ "$session" == *"https://localhost/setup"* ]] || fail "expected setup kiosk to open the setup route"
  [[ "$session" == *'$HOME/.mozilla/firefox/ol-c.default'* ]] || fail "expected Firefox profile diagnostics to be home-relative"
  [[ "$session" == *'systemd-cat --identifier=olc-xsession'* ]] || fail "expected graphical sessions to log directly into journald"

  [[ "$development" == *"trusted-users = [ \"root\" \"@wheel\" ];"* ]] || fail "expected development nix trust to follow wheel users"
  [[ "$development" == *"d /var/lib/ol-c/firefox-dev 0775 root olc-admin -"* ]] || fail "expected Firefox dev workspace to belong to olc-admin"
  [[ "$development" == *"d /var/lib/ol-c/vms 0775 root olc-admin -"* ]] || fail "expected nested VM workspace to belong to olc-admin"
  [[ "$development" == *'writeShellScriptBin "olc-vmctl"'* ]] || fail "expected development profile to install olc-vmctl"
  [[ "$development" == *'tools}/olc-vmctl.mjs'* ]] || fail "expected olc-vmctl to run the repo QMP controller"

  [[ "$runtime_state" == *"show-seat"* ]] || fail "expected runtime state to resolve the active seat session"
  [[ "$runtime_state" == *"getent"* ]] || fail "expected runtime state to resolve user entries through getent"
  [[ "$setup_manager" == *"OLC_FIRST_USER_STORAGE ?? 'luks'"* ]] || fail "expected first user creation to default to LUKS-backed homed storage"
  [[ "$setup_manager" == *"OLC_FIRST_USER_UID ?? '1000'"* ]] || fail "expected the first homed admin to prefer UID 1000"
  [[ "$setup_manager" == *"OLC_FIRST_USER_GROUPS ?? 'olc-admin,wheel,kvm'"* ]] || fail "expected the first user to receive admin and dev groups"
  [[ "$setup_manager" == *"scriptBin"* && "$setup_manager" == *"stdinPath"* ]] || fail "expected first-user provisioning to drive homectl create through a PTY-backed script session"
  [[ "$setup_manager" == *"\${password}\\n\${password}\\n"* ]] || fail "expected first-user provisioning to feed the password twice to homectl create"
  [[ "$setup_manager" == *"createCommand"* && "$setup_manager" == *"homectlBin"* && "$setup_manager" == *"--storage=\${storage}"* ]] || fail "expected first-user provisioning to use homectl create with direct flags"
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
