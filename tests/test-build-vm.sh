#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_VM="${ROOT_DIR}/build-vm"
FLAKE_NIX="${ROOT_DIR}/flake.nix"
OLC_NIX="${ROOT_DIR}/nix/ol-c.nix"
FIREFOX_PATCH="${ROOT_DIR}/patches/firefox/0001-close-last-tab-to-localhost.patch"
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

test_prints_resolved_image_path() {
  local output args
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${BUILD_VM}"
  )"

  args="$(cat "${CASE_TMP}/nix.args")"
  [[ "$args" == *"build .#ol-c-image --print-out-paths --no-link"* ]] || fail "unexpected nix args: $args"
  assert_eq "${CASE_TMP}/out/image.qcow2" "$output"
  cleanup_case
}

test_rejects_milestone_arguments() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${BUILD_VM}" milestone1 \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected build-vm to reject milestone arguments"
  [[ "$output" == *"build-vm no longer accepts milestone arguments; use ./build-vm"* ]] || fail "unexpected output: $output"
  cleanup_case
}

test_rejects_unknown_argument() {
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

  [[ $status -ne 0 ]] || fail "expected build-vm to reject unknown argument"
  [[ "$output" == *"unknown argument: mystery"* ]] || fail "unexpected output: $output"
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

test_vm_runs_firefox_borderless_and_maximized() {
  local contents
  contents="$(cat "${OLC_NIX}")"

  [[ "$contents" == *"OLC_LOCALHOST_UI_OK"* ]] || fail "expected VM to define an OL-C localhost UI success marker"
  [[ "$contents" == *"server.listen(443, '127.0.0.1'"* ]] || fail "expected VM to serve the UI on localhost:443"
  [[ "$contents" == *"The next proof surface is <a href=\"/terminal\"><code>/terminal</code></a>"* ]] || fail "expected VM localhost UI to link to the terminal proof surface"
  [[ "$contents" == *"if (reqUrl.pathname === '/terminal')"* ]] || fail "expected VM localhost UI to handle /terminal"
  [[ "$contents" == *"const backendBasePath = \`/terminal/backend/"* ]] || fail "expected VM /terminal page to mint a fresh backend path for each terminal page"
  [[ "$contents" == *"/terminal/assets/terminal.css"* ]] || fail "expected VM /terminal page to load first-party terminal styles"
  [[ "$contents" == *"/terminal/assets/terminal.js"* ]] || fail "expected VM /terminal page to load the first-party terminal client"
  [[ "$contents" == *"window.OLC_TERMINAL_CONFIG"* ]] || fail "expected VM /terminal page to configure a first-party terminal client"
  [[ "$contents" == *"const terminalClientJs = "* ]] || fail "expected VM localhost UI to embed the terminal client asset"
  [[ "$contents" == *"const terminalClientCss = "* ]] || fail "expected VM localhost UI to embed the terminal stylesheet asset"
  [[ "$contents" == *"const ttydBin = '"* ]] || fail "expected VM localhost UI to use ttyd for the terminal backend"
  [[ "$contents" == *"'--uid', demoUser.uid"* ]] || fail "expected VM ttyd backend to run as the demo user"
  [[ "$contents" == *"'--base-path', basePath"* ]] || fail "expected VM ttyd backend to stay behind the localhost reverse proxy"
  [[ "$contents" == *"recordSocketOpen(token);"* ]] || fail "expected VM terminal sessions to track active websocket clients"
  [[ "$contents" == *"recordSocketClose(token);"* ]] || fail "expected VM terminal sessions to tolerate disconnects before cleanup"
  [[ "$contents" == *"const backendIdleTimeoutMs = 300_000;"* ]] || fail "expected VM terminal sessions to use an idle timeout instead of immediate exit"
  [[ "$contents" != *"'--once'"* ]] || fail "expected VM ttyd backend to survive transient reconnects"
  [[ "$contents" != *"'--exit-no-conn'"* ]] || fail "expected VM ttyd backend to avoid immediate exit on disconnect"
  [[ "$contents" == *"programs.bash.promptInit = ''"* ]] || fail "expected VM to override the default bash prompt init"
  [[ "$contents" == *"PS1='[\\u@\\h:\\w]\\$ '"* ]] || fail "expected VM to use a single-line bash prompt without the extra blank line"
  [[ "$contents" != *"PROMPT_COMMAND='olc_precmd'"* ]] || fail "expected VM terminal proof to avoid custom bash title hooks while input handling is stabilized"
  [[ "$contents" == *"user_pref(\"browser.tabs.inTitlebar\", 1);"* ]] || fail "expected VM to keep Firefox tabs in the title bar"
  [[ "$contents" == *"user_pref(\"browser.tabs.drawInTitlebar\", true);"* ]] || fail "expected VM to force Firefox titlebar drawing"
  [[ "$contents" == *"user_pref(\"browser.tabs.closeWindowWithLastTab\", false);"* ]] || fail "expected VM to keep Firefox open when the last tab closes"
  [[ "$contents" == *"user_pref(\"browser.startup.homepage\", \"https://localhost\");"* ]] || fail "expected VM to pin the Firefox home page to the in-guest HTTPS UI"
  [[ "$contents" == *"user_pref(\"security.enterprise_roots.enabled\", true);"* ]] || fail "expected VM to trust the guest localhost certificate through system roots"
  [[ "$contents" == *"matchbox-window-manager -use_titlebar no -use_cursor yes &"* ]] || fail "expected VM to launch matchbox without a title bar"
  [[ "$contents" == *"services.spice-vdagentd.enable = true;"* ]] || fail "expected VM to enable the SPICE guest agent daemon"
  [[ "$contents" == *"spice-vdagent"* ]] || fail "expected VM to include the SPICE guest agent"
  [[ "$contents" == *"\${pkgs.spice-vdagent}/bin/spice-vdagent &"* ]] || fail "expected VM xsession to start the SPICE session agent"
  [[ "$contents" == *"curl --silent --fail --cacert"* ]] || fail "expected VM to wait for the localhost HTTPS UI before launching Firefox"
  [[ "$contents" == *"xdotool windowsize \"\$window_id\" 100% 100%"* ]] || fail "expected VM to force Firefox to fill the screen"
  [[ "$contents" == *"firefox --no-remote --profile /home/demo/.mozilla/firefox/ol-c.default --new-window https://localhost &"* ]] || fail "expected VM to launch Firefox against the localhost UI"
  [[ "$contents" != *"tmux"* ]] || fail "expected VM terminal proof to avoid tmux session wrapping"
  [[ "$contents" != *"openbox"* ]] || fail "expected VM to avoid Openbox"
}

test_packages_firefox_with_localhost_patch() {
  local flake_contents patch_contents
  flake_contents="$(cat "${FLAKE_NIX}")"
  patch_contents="$(cat "${FIREFOX_PATCH}")"

  [[ "$flake_contents" == *"firefoxLocalhostPatch = ./patches/firefox/0001-close-last-tab-to-localhost.patch;"* ]] || fail "expected flake to define the repo-local Firefox patch"
  [[ "$flake_contents" == *"inputs.nixpkgs.follows = \"nixpkgs\";"* ]] || fail "expected nixos-generators to follow the repo nixpkgs input"
  [[ "$flake_contents" == *"firefoxPkgs = import nixpkgs {"* ]] || fail "expected flake to share one nixpkgs import for Firefox packaging and images"
  [[ "$flake_contents" == *"\"firefox-unwrapped\" = prev.\"firefox-unwrapped\".overrideAttrs"* ]] || fail "expected flake to override nixpkgs firefox-unwrapped"
  [[ "$flake_contents" == *"patches = (old.patches or []) ++ [ firefoxLocalhostPatch ];"* ]] || fail "expected flake to append the localhost patch to firefox-unwrapped"
  [[ "$flake_contents" == *"firefox-localhost = firefoxPkgs.firefox;"* ]] || fail "expected flake to expose the shared patched Firefox package"
  [[ "$flake_contents" == *"pkgs = firefoxPkgs;"* ]] || fail "expected generated images to use the same patched nixpkgs import"
  [[ "$flake_contents" == *"nixosConfigurations.\"ol-c\""* ]] || fail "expected flake to expose one current OL-C NixOS configuration"
  [[ "$flake_contents" == *"\"ol-c-image\" = nixos-generators.nixosGenerate"* ]] || fail "expected flake to expose one current OL-C image"
  [[ "$flake_contents" == *"modules = [ olcModule ];"* ]] || fail "expected OL-C image generation to avoid reapplying the overlay module"
  [[ "$flake_contents" != *"vmModule"* ]] || fail "expected flake to remove generic VM module wiring"
  [[ "$flake_contents" != *"vm-image"* ]] || fail "expected flake to remove generic VM image target"
  [[ "$flake_contents" != *"milestone1Module"* ]] || fail "expected flake to remove milestone1 module wiring"
  [[ "$flake_contents" != *"milestone2Module"* ]] || fail "expected flake to remove milestone2 module wiring"
  [[ "$flake_contents" != *"milestone1-image"* ]] || fail "expected flake to remove milestone1 image target"
  [[ "$flake_contents" != *"milestone2-image"* ]] || fail "expected flake to remove milestone2 image target"
  [[ "$patch_contents" == *"+        this.addTrustedTab(\"https://localhost\", {"* ]] || fail "expected Firefox patch to replace the last closed tab with localhost"
  [[ "$patch_contents" == *"browser_closeLastTab_loads_localhost.js"* ]] || fail "expected Firefox patch to add a browser regression test"
}

test_requires_nix
test_prints_resolved_image_path
test_rejects_milestone_arguments
test_rejects_unknown_argument
test_requires_bootable_image_in_output
test_vm_runs_firefox_borderless_and_maximized
test_packages_firefox_with_localhost_patch

echo "PASS: build-vm"
