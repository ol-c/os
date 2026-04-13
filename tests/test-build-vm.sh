#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_VM="${ROOT_DIR}/build-vm"
FLAKE_NIX="${ROOT_DIR}/flake.nix"
OLC_NIX="${ROOT_DIR}/nix/ol-c.nix"
NIX_BASE="${ROOT_DIR}/nix/modules/base.nix"
NIX_GRAPHICAL_SESSION="${ROOT_DIR}/nix/modules/graphical-session.nix"
NIX_LOCALHOST_UI="${ROOT_DIR}/nix/modules/localhost-ui.nix"
NIX_PACKAGES="${ROOT_DIR}/nix/modules/packages.nix"
NIX_USERS="${ROOT_DIR}/nix/modules/users.nix"
NIX_FIREFOX_FAST="${ROOT_DIR}/nix/firefox-localhost-fast.nix"
LOCALHOST_UI_SERVER="${ROOT_DIR}/localhost-ui/server.mjs"
TERMINAL_CLIENT_SOURCE="${ROOT_DIR}/terminal-client/src/index.js"
TERMINAL_CLIENT_LIFECYCLE="${ROOT_DIR}/terminal-client/src/session-lifecycle.mjs"
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
  local contents olc_nix terminal_client
  contents="$(
    cat \
      "${NIX_BASE}" \
      "${NIX_GRAPHICAL_SESSION}" \
      "${NIX_LOCALHOST_UI}" \
      "${NIX_PACKAGES}" \
      "${NIX_USERS}" \
      "${LOCALHOST_UI_SERVER}"
  )"
  olc_nix="$(cat "${OLC_NIX}")"
  terminal_client="$(cat "${TERMINAL_CLIENT_SOURCE}" "${TERMINAL_CLIENT_LIFECYCLE}")"

  [[ "$olc_nix" == *"./modules/base.nix"* ]] || fail "expected OL-C module to import base module"
  [[ "$olc_nix" == *"./modules/users.nix"* ]] || fail "expected OL-C module to import users module"
  [[ "$olc_nix" == *"./modules/packages.nix"* ]] || fail "expected OL-C module to import packages module"
  [[ "$olc_nix" == *"./modules/localhost-ui.nix"* ]] || fail "expected OL-C module to import localhost UI module"
  [[ "$olc_nix" == *"./modules/graphical-session.nix"* ]] || fail "expected OL-C module to import graphical session module"
  [[ "$olc_nix" != *"system.activationScripts.olcDemoSession"* ]] || fail "expected OL-C module to delegate graphical session setup"
  [[ "$olc_nix" != *"systemd.services.ol-c-ui"* ]] || fail "expected OL-C module to delegate localhost UI setup"

  [[ "$contents" == *"OLC_LOCALHOST_UI_OK"* ]] || fail "expected VM to define an OL-C localhost UI success marker"
  [[ "$contents" == *"server.listen(443, '127.0.0.1'"* ]] || fail "expected VM to serve the UI on localhost:443"
  [[ "$contents" == *"The next proof surface is <a href=\"/terminal\" onclick=\"window.open('/terminal', '_blank'); return false;\"><code>/terminal</code></a>"* ]] || fail "expected VM localhost UI to link to the terminal proof surface"
  [[ "$contents" == *"window.open('/terminal', '_blank')"* ]] || fail "expected VM localhost UI to open terminal sessions in closable tabs"
  [[ "$contents" == *"if (reqUrl.pathname === '/terminal')"* ]] || fail "expected VM localhost UI to handle /terminal"
  [[ "$contents" == *"const backendBasePath = \`/terminal/backend/"* ]] || fail "expected VM /terminal page to mint a fresh backend path for each terminal page"
  [[ "$contents" == *"/terminal/assets/terminal.css"* ]] || fail "expected VM /terminal page to load first-party terminal styles"
  [[ "$contents" == *"/terminal/assets/terminal.js"* ]] || fail "expected VM /terminal page to load the first-party terminal client"
  [[ "$contents" == *"window.OLC_TERMINAL_CONFIG"* ]] || fail "expected VM /terminal page to configure a first-party terminal client"
  [[ "$contents" == *"OLC_TERMINAL_CLIENT_JS"* ]] || fail "expected VM localhost UI to receive the terminal client asset path"
  [[ "$contents" == *"OLC_TERMINAL_CLIENT_CSS"* ]] || fail "expected VM localhost UI to receive the terminal stylesheet asset path"
  [[ "$contents" == *"const terminalClientJs = readFileSync"* ]] || fail "expected VM localhost UI to read the terminal client asset"
  [[ "$contents" == *"const terminalClientCss = readFileSync"* ]] || fail "expected VM localhost UI to read the terminal stylesheet asset"
  [[ "$contents" == *"OLC_TTYD = \"\${pkgs.ttyd}/bin/ttyd\";"* ]] || fail "expected VM localhost UI service to provide ttyd for the terminal backend"
  [[ "$contents" == *"const ttydBin = requireEnv('OLC_TTYD');"* ]] || fail "expected VM localhost UI to use configured ttyd for the terminal backend"
  [[ "$contents" == *"'--uid', demoUser.uid"* ]] || fail "expected VM ttyd backend to run as the demo user"
  [[ "$contents" == *"'--base-path', basePath"* ]] || fail "expected VM ttyd backend to stay behind the localhost reverse proxy"
  [[ "$contents" == *"recordSocketOpen(token);"* ]] || fail "expected VM terminal sessions to track active websocket clients"
  [[ "$contents" == *"recordSocketClose(token);"* ]] || fail "expected VM terminal sessions to tolerate disconnects before cleanup"
  [[ "$contents" == *"const backendIdleTimeoutMs = 300_000;"* ]] || fail "expected VM terminal sessions to use an idle timeout instead of immediate exit"
  [[ "$terminal_client" == *"closeRootSessionTab"* ]] || fail "expected VM terminal client to close the tab when the root terminal session exits"
  [[ "$terminal_client" == *"This browser blocked closing the tab"* ]] || fail "expected VM terminal client to keep root-exit fallback behavior explicit"
  [[ "$terminal_client" == *"if (event.code === 1000 || event.code === 1001)"* ]] || fail "expected VM terminal client to treat normal websocket closure as root-session exit"
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
  local flake_contents fast_contents patch_contents
  flake_contents="$(cat "${FLAKE_NIX}")"
  fast_contents="$(cat "${NIX_FIREFOX_FAST}")"
  patch_contents="$(cat "${FIREFOX_PATCH}")"

  [[ "$flake_contents" == *"firefoxLocalhostPatch = ./patches/firefox/0001-close-last-tab-to-localhost.patch;"* ]] || fail "expected flake to define the repo-local Firefox patch"
  [[ "$flake_contents" == *"inputs.nixpkgs.follows = \"nixpkgs\";"* ]] || fail "expected nixos-generators to follow the repo nixpkgs input"
  [[ "$flake_contents" == *"firefoxFastOverlay = import ./nix/firefox-localhost-fast.nix"* ]] || fail "expected flake to define the fast Firefox repack overlay"
  [[ "$flake_contents" == *"firefoxSourceOverlay = final: prev: {"* ]] || fail "expected flake to keep the full source Firefox overlay"
  [[ "$flake_contents" == *"firefoxPkgs = import nixpkgs {"* ]] || fail "expected flake to define the fast Firefox package set"
  [[ "$flake_contents" == *"firefoxSourcePkgs = import nixpkgs {"* ]] || fail "expected flake to define the source-build Firefox package set"
  [[ "$flake_contents" == *"overlays = [ firefoxFastOverlay ];"* ]] || fail "expected fast Firefox package set to use the repack overlay"
  [[ "$flake_contents" == *"overlays = [ firefoxSourceOverlay ];"* ]] || fail "expected source Firefox package set to use the source overlay"
  [[ "$flake_contents" == *"\"firefox-unwrapped\" = prev.\"firefox-unwrapped\".overrideAttrs"* ]] || fail "expected source overlay to override nixpkgs firefox-unwrapped"
  [[ "$flake_contents" == *"patches = (old.patches or []) ++ [ firefoxLocalhostPatch ];"* ]] || fail "expected flake to append the localhost patch to firefox-unwrapped"
  [[ "$flake_contents" == *"firefox-localhost = firefoxPkgs.firefox;"* ]] || fail "expected flake to expose the fast patched Firefox package"
  [[ "$flake_contents" == *"firefox-localhost-source = firefoxSourcePkgs.firefox;"* ]] || fail "expected flake to expose the full source patched Firefox package"
  [[ "$flake_contents" == *"pkgs = firefoxPkgs;"* ]] || fail "expected generated images to use the fast patched nixpkgs import"
  [[ "$flake_contents" == *"nixosConfigurations.\"ol-c\""* ]] || fail "expected flake to expose one current OL-C NixOS configuration"
  [[ "$flake_contents" == *"\"ol-c-image\" = nixos-generators.nixosGenerate"* ]] || fail "expected flake to expose one current OL-C image"
  [[ "$flake_contents" == *"modules = [ olcModule ];"* ]] || fail "expected OL-C image generation to avoid reapplying the overlay module"
  [[ "$flake_contents" != *"vmModule"* ]] || fail "expected flake to remove generic VM module wiring"
  [[ "$flake_contents" != *"vm-image"* ]] || fail "expected flake to remove generic VM image target"
  [[ "$flake_contents" != *"milestone1Module"* ]] || fail "expected flake to remove milestone1 module wiring"
  [[ "$flake_contents" != *"milestone2Module"* ]] || fail "expected flake to remove milestone2 module wiring"
  [[ "$flake_contents" != *"milestone1-image"* ]] || fail "expected flake to remove milestone1 image target"
  [[ "$flake_contents" != *"milestone2-image"* ]] || fail "expected flake to remove milestone2 image target"
  [[ "$patch_contents" == *"const SECUREOS_LOCALHOST_URL = \"https://localhost\";"* ]] || fail "expected Firefox patch to define the localhost shell URL"
  [[ "$patch_contents" == *"+    url ??= SECUREOS_LOCALHOST_URL;"* ]] || fail "expected Firefox patch to point user-created new tabs at localhost"
  [[ "$patch_contents" != *"+    return SECUREOS_LOCALHOST_URL;"* ]] || fail "expected Firefox patch to avoid overriding the internal new-tab URL"
  [[ "$patch_contents" == *"+              this.addTrustedTab(SECUREOS_LOCALHOST_URL, {"* ]] || fail "expected Firefox patch to replace self-closing final tabs with localhost"
  [[ "$patch_contents" == *"browser_localhost_shell.js"* ]] || fail "expected Firefox patch to add browser regression tests"
  [[ "$patch_contents" == *"test_new_tab_uses_localhost_url"* ]] || fail "expected Firefox patch to test new-tab localhost behavior"
  [[ "$patch_contents" == *"test_dom_window_close_last_tab_uses_localhost"* ]] || fail "expected Firefox patch to test terminal-style final-tab closure"
  [[ "$patch_contents" == *"The SecureOS localhost surface should keep normal page title handling"* ]] || fail "expected Firefox patch to test normal title handling for localhost"
  [[ "$fast_contents" == *"browser_omni=\"\$out/lib/firefox/browser/omni.ja\""* ]] || fail "expected fast Firefox package to patch browser omni.ja"
  [[ "$fast_contents" == *"filterdiff"* ]] || fail "expected fast Firefox package to extract runtime hunks from the repo patch"
  [[ "$fast_contents" == *"olcFirefoxSource = old.src;"* ]] || fail "expected fast Firefox package to reuse the pinned Firefox source for jar tooling"
  [[ "$fast_contents" == *"tar -xf \${firefoxSource}"* ]] || fail "expected fast Firefox package to unpack the pinned Firefox source tarball"
  [[ "$fast_contents" == *"config/optimizejars.py"* ]] || fail "expected fast Firefox package to use Firefox's own optimized jar tooling"
  [[ "$fast_contents" == *"--deoptimize"* ]] || fail "expected fast Firefox package to deoptimize omni.ja before patching"
  [[ "$fast_contents" == *"--optimize"* ]] || fail "expected fast Firefox package to reoptimize omni.ja after patching"
  [[ "$fast_contents" == *"browser/base/content/browser-commands.js"* ]] || fail "expected fast Firefox package to consume browser command hunks"
  [[ "$fast_contents" == *"browser/components/tabbrowser/content/tabbrowser.js"* ]] || fail "expected fast Firefox package to consume tabbrowser hunks"
  [[ "$fast_contents" == *"chrome/browser/content/browser/browser-commands.js"* ]] || fail "expected fast Firefox package to map browser commands into omni.ja"
  [[ "$fast_contents" == *"chrome/browser/content/browser/tabbrowser.js"* ]] || fail "expected fast Firefox package to map tabbrowser into omni.ja"
  [[ "$fast_contents" == *"expected Firefox frontend asset missing from omni.ja"* ]] || fail "expected fast Firefox package to fail on missing frontend assets"
  [[ "$fast_contents" == *"meta = prev.firefox-unwrapped.meta;"* ]] || fail "expected fast Firefox package to preserve firefox-unwrapped metadata for the wrapper"
  [[ "$fast_contents" == *"passthru = (prev.firefox-unwrapped.passthru or {})"* ]] || fail "expected fast Firefox package to preserve firefox-unwrapped passthru attributes for the wrapper"
  [[ "$fast_contents" == *"inherit (prev.firefox-unwrapped) gtk3;"* ]] || fail "expected fast Firefox package to preserve the gtk3 wrapper input"
}

test_requires_nix
test_prints_resolved_image_path
test_rejects_milestone_arguments
test_rejects_unknown_argument
test_requires_bootable_image_in_output
test_vm_runs_firefox_borderless_and_maximized
test_packages_firefox_with_localhost_patch

echo "PASS: build-vm"
