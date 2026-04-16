#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
BUILD_VM="${ROOT_DIR}/build-vm"
FLAKE_NIX="${ROOT_DIR}/flake.nix"
OLC_NIX="${ROOT_DIR}/nix/ol-c.nix"
NIX_BASE="${ROOT_DIR}/nix/modules/base.nix"
NIX_DEVELOPMENT="${ROOT_DIR}/nix/modules/development.nix"
NIX_GRAPHICAL_SESSION="${ROOT_DIR}/nix/modules/graphical-session.nix"
NIX_LOCALHOST_UI="${ROOT_DIR}/nix/modules/localhost-ui.nix"
NIX_PACKAGES="${ROOT_DIR}/nix/modules/packages.nix"
NIX_SHARED_REPO="${ROOT_DIR}/nix/modules/shared-repo.nix"
NIX_USERS="${ROOT_DIR}/nix/modules/users.nix"
NIX_FIREFOX_FAST="${ROOT_DIR}/nix/firefox-localhost-fast.nix"
LOCALHOST_UI_SERVER="${ROOT_DIR}/localhost-ui/server.mjs"
LOCALHOST_UI_DEV_SUPERVISOR="${ROOT_DIR}/localhost-ui/dev-supervisor.mjs"
LOCALHOST_UI_TERMINAL_APP="${ROOT_DIR}/localhost-ui/terminal-app.mjs"
LOCALHOST_UI_TERMINAL_SERVER="${ROOT_DIR}/localhost-ui/terminal-server.mjs"
LOCALHOST_UI_APP="${ROOT_DIR}/localhost-ui/app.mjs"
LOCALHOST_UI_SYSTEM_CONTROLS="${ROOT_DIR}/localhost-ui/system-controls.mjs"
LOCALHOST_UI_SYSTEM_PAGE="${ROOT_DIR}/localhost-ui/system-page.mjs"
TERMINAL_CLIENT_SOURCE="${ROOT_DIR}/terminal-client/src/index.js"
TERMINAL_CLIENT_THEMES="${ROOT_DIR}/terminal-client/src/terminal-themes.mjs"
TERMINAL_CLIENT_LIFECYCLE="${ROOT_DIR}/terminal-client/src/session-lifecycle.mjs"
TERMINAL_CLIENT_DIST_CSS="${ROOT_DIR}/terminal-client/dist/terminal.css"
TERMINAL_CLIENT_BUILD="${ROOT_DIR}/terminal-client/build.mjs"
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
  local contents olc_nix terminal_client terminal_themes terminal_css terminal_build
  contents="$(
    cat \
      "${NIX_BASE}" \
      "${NIX_DEVELOPMENT}" \
      "${NIX_GRAPHICAL_SESSION}" \
      "${NIX_LOCALHOST_UI}" \
      "${NIX_PACKAGES}" \
      "${NIX_SHARED_REPO}" \
      "${NIX_USERS}" \
      "${LOCALHOST_UI_DEV_SUPERVISOR}" \
      "${LOCALHOST_UI_TERMINAL_APP}" \
      "${LOCALHOST_UI_TERMINAL_SERVER}" \
      "${LOCALHOST_UI_SERVER}" \
      "${LOCALHOST_UI_APP}" \
      "${LOCALHOST_UI_SYSTEM_CONTROLS}" \
      "${LOCALHOST_UI_SYSTEM_PAGE}"
  )"
  olc_nix="$(cat "${OLC_NIX}")"
  terminal_client="$(cat "${TERMINAL_CLIENT_SOURCE}" "${TERMINAL_CLIENT_LIFECYCLE}")"
  terminal_themes="$(cat "${TERMINAL_CLIENT_THEMES}")"
  terminal_css="$(cat "${TERMINAL_CLIENT_DIST_CSS}")"
  terminal_build="$(cat "${TERMINAL_CLIENT_BUILD}")"

  [[ "$olc_nix" == *"./modules/base.nix"* ]] || fail "expected OL-C module to import base module"
  [[ "$olc_nix" == *"./modules/users.nix"* ]] || fail "expected OL-C module to import users module"
  [[ "$olc_nix" == *"./modules/packages.nix"* ]] || fail "expected OL-C module to import packages module"
  [[ "$olc_nix" == *"./modules/localhost-ui.nix"* ]] || fail "expected OL-C module to import localhost UI module"
  [[ "$olc_nix" == *"./modules/graphical-session.nix"* ]] || fail "expected OL-C module to import graphical session module"
  [[ "$olc_nix" == *"./modules/shared-repo.nix"* ]] || fail "expected OL-C module to import shared repo module"
  [[ "$olc_nix" == *"./modules/development.nix"* ]] || fail "expected OL-C module to import development module"
  [[ "$olc_nix" != *"system.activationScripts.olcDemoSession"* ]] || fail "expected OL-C module to delegate graphical session setup"
  [[ "$olc_nix" != *"systemd.services.ol-c-ui"* ]] || fail "expected OL-C module to delegate localhost UI setup"

  [[ "$contents" == *"fileSystems.\"/source\""* ]] || fail "expected VM to mount the shared repo at /source"
  [[ "$contents" == *"device = \"ol-c-source\";"* ]] || fail "expected VM shared repo mount to use the QEMU virtiofs tag"
  [[ "$contents" == *"fsType = \"virtiofs\";"* ]] || fail "expected VM shared repo mount to use virtiofs"
  [[ "$contents" == *"\"x-systemd.automount\""* ]] || fail "expected VM shared repo mount to be automount-friendly"
  [[ "$contents" == *"uid = 1000;"* ]] || fail "expected demo user UID to be fixed for host shared repo writes"
  [[ "$contents" == *"git"* ]] || fail "expected VM to include git for in-guest development"
  [[ "$contents" == *"ripgrep"* ]] || fail "expected VM to include ripgrep for in-guest development"
  [[ "$contents" == *"openssh"* ]] || fail "expected VM to include OpenSSH tools for in-guest development"
  [[ "$contents" == *"writeShellScriptBin \"codex\""* ]] || fail "expected VM to include a codex command wrapper"
  [[ "$contents" == *"codexVersion = \"0.120.0\";"* ]] || fail "expected VM codex wrapper to pin the Codex CLI version"
  [[ "$contents" == *"@openai/codex@\${codexVersion}"* ]] || fail "expected VM codex wrapper to use the pinned Codex CLI version"
  [[ "$contents" == *"--dangerously-bypass-approvals-and-sandbox"* ]] || fail "expected VM codex wrapper to run with full development permissions"
  [[ "$contents" == *"CODEX_MODEL:-gpt-5.4"* ]] || fail "expected VM codex wrapper to default to GPT-5.4"
  [[ "$contents" == *"getent passwd"* ]] || fail "expected VM codex wrapper to recover HOME when terminal sessions omit it"
  [[ "$contents" == *"CODEX_HOME:-''\${HOME}/.codex"* ]] || fail "expected VM codex wrapper to derive CODEX_HOME from a safe HOME value"
  [[ "$contents" == *"mkdir -p \"\$CODEX_HOME\""* ]] || fail "expected VM codex wrapper to create CODEX_HOME before launching Codex"
  [[ "$contents" == *"NO_UPDATE_NOTIFIER"* ]] || fail "expected VM codex wrapper to suppress npm update notices"
  [[ "$contents" == *"security.sudo.wheelNeedsPassword = false;"* ]] || fail "expected VM demo user to have passwordless sudo for development"
  [[ "$contents" == *"OLC_LOCALHOST_UI_OK"* ]] || fail "expected VM to define an OL-C localhost UI success marker"
  [[ "$contents" == *"dev-supervisor.mjs"* ]] || fail "expected VM localhost UI service to run through the source preview supervisor"
  [[ "$contents" == *"systemd.services.ol-c-terminal"* ]] || fail "expected VM to run a stable terminal service"
  [[ "$contents" == *"terminal-server.mjs"* ]] || fail "expected VM stable terminal service to use the terminal server entrypoint"
  [[ "$contents" == *"OLC_TERMINAL_SERVER_OK"* ]] || fail "expected VM stable terminal service to expose a readiness marker"
  [[ "$contents" == *"OLC_TERMINAL_UPSTREAM = \"https://127.0.0.1:9443\";"* ]] || fail "expected VM localhost UI to proxy initial terminal pages to the stable terminal service"
  [[ "$contents" == *"wants = [ \"ol-c-terminal.service\" ];"* ]] || fail "expected VM localhost UI to start with the stable terminal service"
  [[ "$contents" == *"OLC_SOURCE_PREVIEW_MODE"* ]] || fail "expected VM source preview supervisor to log selected preview mode"
  [[ "$contents" == *"const defaultSourceRoot = '/source';"* ]] || fail "expected VM source preview supervisor to default to /source"
  [[ "$contents" == *"serverPath: sourceServer"* ]] || fail "expected VM source preview supervisor to prefer /source localhost UI server"
  [[ "$contents" == *"storeRoot}/server.mjs"* ]] || fail "expected VM source preview supervisor to fall back to the packaged server"
  [[ "$contents" != *"sourcePath(sourceRoot, '/terminal-client/dist')"* ]] || fail "expected VM source preview supervisor not to restart terminals for terminal asset edits"
  [[ "$contents" == *"scheduleRestart()"* ]] || fail "expected VM source preview supervisor to restart after watched edits"
  [[ "$contents" == *"const fallbackTerminalTitle = 'ol-c terminal';"* ]] || fail "expected VM terminal fallback title to use product branding"
  [[ "$contents" == *"<title>System</title>"* ]] || fail "expected VM home tab title to use the system status document title"
  [[ "$contents" == *"<h1>System</h1>"* ]] || fail "expected VM home heading to use the system status document title"
  [[ "$contents" == *"server.listen(443, '127.0.0.1'"* ]] || fail "expected VM to serve the UI on localhost:443"
  [[ "$contents" == *"new EventSource('/api/system/events')"* ]] || fail "expected VM localhost UI to subscribe to live system status events"
  [[ "$contents" == *"POST /api/system"* || "$contents" == *"postCommand('/api/system/volume'"* ]] || fail "expected VM localhost UI to send system control commands"
  [[ "$contents" == *"createSelectedSystemControls"* ]] || fail "expected VM localhost UI to select real or fake system controls"
  [[ "$contents" == *"OLC_SYSTEM_CONTROLS_BACKEND"* ]] || fail "expected VM localhost UI to support deterministic fake controls"
  [[ "$contents" == *"OLC_HARDWARE_TEST"* ]] || fail "expected VM localhost UI to support composable fake hardware capabilities"
  [[ "$contents" == *"wifi"* && "$contents" == *"bluetooth"* && "$contents" == *"battery"* ]] || fail "expected VM localhost UI to define hardware test capability tokens"
  [[ "$contents" == *"'/api/system/events'"* ]] || fail "expected VM localhost UI to expose an SSE system status endpoint"
  [[ "$contents" == *"'/api/system/volume'"* ]] || fail "expected VM localhost UI to expose the volume command endpoint"
  [[ "$contents" == *"'/api/system/appearance'"* ]] || fail "expected VM localhost UI to expose the appearance command endpoint"
  [[ "$contents" == *"input id=\"volume-control\" type=\"range\""* ]] || fail "expected VM localhost UI to render an inline volume slider"
  [[ "$contents" == *"select id=\"appearance-control\""* ]] || fail "expected VM localhost UI to render an inline appearance picker"
  [[ "$contents" == *"WebChannelMessageToChrome"* ]] || fail "expected VM localhost UI to send Firefox chrome appearance messages"
  [[ "$contents" == *"olc-appearance"* ]] || fail "expected VM localhost UI to use the OL-C appearance bridge channel"
  [[ "$contents" == *"setAppearance"* ]] || fail "expected VM localhost UI to request browser-wide appearance changes"
  [[ "$contents" == *"network-implementation"* ]] || fail "expected VM localhost UI to show network implementation status"
  [[ "$contents" == *"volume-implementation"* ]] || fail "expected VM localhost UI to show volume implementation status"
  [[ "$contents" == *"bluetooth-implementation"* ]] || fail "expected VM localhost UI to show bluetooth implementation status"
  [[ "$contents" == *"Implementation: "* ]] || fail "expected VM localhost UI to label facility implementation status"
  [[ "$contents" == *"Open terminal</a>"* ]] || fail "expected VM localhost UI to link to the terminal proof surface"
  [[ "$contents" == *"window.open('/terminal', '_blank')"* ]] || fail "expected VM localhost UI to open terminal sessions in closable tabs"
  [[ "$contents" == *"reqUrl.pathname.startsWith('/terminal')"* ]] || fail "expected VM localhost UI to proxy initial /terminal page requests"
  [[ "$contents" == *"proxyTerminalRequest(req, res)"* ]] || fail "expected VM localhost UI to delegate terminal requests to the stable service"
  [[ "$contents" != *"connection: 'upgrade'"* ]] || fail "expected VM localhost UI not to proxy terminal websocket upgrades"
  [[ "$contents" == *"if (reqUrl.pathname === '/terminal')"* ]] || fail "expected VM stable terminal service to handle /terminal"
  [[ "$contents" == *"const backendBasePath = pathForBackend(token)"* ]] || fail "expected VM /terminal page to mint a fresh backend path for each terminal page"
  [[ "$contents" == *"return \`/session/\${token}\`;"* ]] || fail "expected VM terminal backend paths to stay short on the dedicated backend origin"
  [[ "$contents" == *"\${publicPrefix}/assets/terminal.css"* ]] || fail "expected VM /terminal page to load terminal styles from the stable terminal origin"
  [[ "$contents" == *"\${publicPrefix}/assets/terminal.js"* ]] || fail "expected VM /terminal page to load terminal client from the stable terminal origin"
  [[ "$contents" == *"OLC_TERMINAL_PUBLIC_URL = \"https://localhost:9443\";"* ]] || fail "expected VM stable terminal service to advertise its direct terminal origin"
  [[ "$contents" == *"OLC_TERMINAL_PORT = \"9443\";"* ]] || fail "expected VM stable terminal service to listen on the dedicated terminal backend port"
  [[ "$contents" == *"createServer({"* && "$contents" == *"readFileSync(requireEnv('OLC_TLS_KEY'))"* ]] || fail "expected VM stable terminal service to serve HTTPS directly"
  [[ "$contents" == *"allowedTerminalOrigins"* ]] || fail "expected VM stable terminal backend to restrict CORS origins"
  [[ "$contents" == *"access-control-allow-origin"* ]] || fail "expected VM stable terminal backend to allow browser calls from the UI origin"
  [[ "$contents" == *"window.OLC_TERMINAL_CONFIG"* ]] || fail "expected VM /terminal page to configure a first-party terminal client"
  [[ "$contents" == *"OLC_TERMINAL_CLIENT_JS"* ]] || fail "expected VM stable terminal service to receive the terminal client asset path"
  [[ "$contents" == *"OLC_TERMINAL_CLIENT_CSS"* ]] || fail "expected VM stable terminal service to receive the terminal stylesheet asset path"
  [[ "$contents" == *"terminalClientJs: readFileSync(requireEnv('OLC_TERMINAL_CLIENT_JS'), 'utf8')"* ]] || fail "expected VM stable terminal service to read the terminal client asset"
  [[ "$contents" == *"terminalClientCss: readFileSync(requireEnv('OLC_TERMINAL_CLIENT_CSS'), 'utf8')"* ]] || fail "expected VM stable terminal service to read the terminal stylesheet asset"
  [[ "$contents" == *"OLC_TTYD = \"\${pkgs.ttyd}/bin/ttyd\";"* ]] || fail "expected VM stable terminal service to provide ttyd for the terminal backend"
  [[ "$contents" == *"OLC_PACTL = \"\${pkgs.pulseaudio}/bin/pactl\";"* ]] || fail "expected VM localhost UI service to provide pactl for volume controls"
  [[ "$contents" == *"OLC_PULSE_SERVER = \"unix:/run/user/1000/pulse/native\";"* ]] || fail "expected VM localhost UI service to target the demo user's Pulse-compatible socket"
  [[ "$contents" == *"ttydBin: requireEnv('OLC_TTYD')"* ]] || fail "expected VM stable terminal service to use configured ttyd for the terminal backend"
  [[ "$contents" == *"commandEnv.PULSE_SERVER = pulseServer;"* ]] || fail "expected VM volume adapter to pass the configured Pulse server to pactl"
  [[ "$contents" == *"services.pipewire = {"* ]] || fail "expected VM to enable PipeWire for guest audio"
  [[ "$contents" == *"pulse.enable = true;"* ]] || fail "expected VM to enable PulseAudio compatibility for pactl"
  [[ "$contents" == *"security.rtkit.enable = true;"* ]] || fail "expected VM to enable realtime support for PipeWire"
  [[ "$contents" == *"'--uid', demoUser.uid"* ]] || fail "expected VM ttyd backend to run as the demo user"
  [[ "$contents" == *"'--base-path', basePath"* ]] || fail "expected VM ttyd backend to stay behind the localhost reverse proxy"
  [[ "$contents" == *"recordSocketOpen(token);"* ]] || fail "expected VM terminal sessions to track active websocket clients"
  [[ "$contents" == *"recordSocketClose(token);"* ]] || fail "expected VM terminal sessions to tolerate disconnects before cleanup"
  [[ "$contents" == *"const reconnectGraceTimeoutMs = 60_000;"* ]] || fail "expected VM terminal sessions to use a reconnect grace timeout after websocket disconnect"
  [[ "$contents" == *"scheduleReconnectGraceTimeout(token)"* ]] || fail "expected VM terminal sessions to schedule cleanup only after websocket disconnect"
  [[ "$contents" == *"backend.reconnectGraceTimer = cancelTimer(backend.reconnectGraceTimer);"* ]] || fail "expected VM terminal sessions to cancel reconnect cleanup when active"
  [[ "$contents" == *"closeTerminalBackend(req, res, getBackendToken(req.url))"* ]] || fail "expected VM terminal sessions to expose explicit close cleanup"
  [[ "$contents" == *"closeUrl:"* ]] || fail "expected VM /terminal page to keep an explicit backend close URL available"
  [[ "$terminal_client" == *"appConfig.wsUrl"* ]] || fail "expected VM terminal client to use the direct stable websocket URL when provided"
  [[ "$terminal_client" != *"window.addEventListener('pagehide'"* ]] || fail "expected VM terminal client to avoid killing sessions on pagehide"
  [[ "$terminal_client" != *"navigator.sendBeacon"* ]] || fail "expected VM terminal client to avoid beacon-based pagehide cleanup"
  [[ "$terminal_client" != *"keepalive: true"* ]] || fail "expected VM terminal client to avoid keepalive pagehide cleanup"
  [[ "$terminal_client" == *"const reconnectFailureWindowMs = 10_000;"* ]] || fail "expected VM terminal client to retry transient token failures"
  [[ "$terminal_client" == *"firstReconnectFailureAt ??= now;"* ]] || fail "expected VM terminal client to track reconnect failure windows"
  [[ "$terminal_client" == *"const fallbackTitle = 'ol-c terminal';"* ]] || fail "expected VM terminal client fallback title to use product branding"
  [[ "$terminal_client" == *"import { terminalThemes } from './terminal-themes.mjs';"* ]] || fail "expected VM terminal client to import vendored terminal themes"
  [[ "$terminal_client" == *"window.matchMedia('(prefers-color-scheme: dark)')"* ]] || fail "expected VM terminal client to follow browser light and dark modes"
  [[ "$terminal_client" == *"return darkModeQuery.matches ? terminalThemes.dark : terminalThemes.light;"* ]] || fail "expected VM terminal client to choose between vendored light and dark themes"
  [[ "$terminal_client" == *"theme: selectedTerminalTheme()"* ]] || fail "expected VM terminal client to initialize xterm with the selected vendored theme"
  [[ "$terminal_client" == *"terminal.options.theme = selectedTerminalTheme();"* ]] || fail "expected VM terminal client to update xterm theme when the color scheme changes"
  [[ "$terminal_themes" == *"export const terminalThemes"* ]] || fail "expected VM terminal themes to be exported from a dedicated module"
  [[ "$terminal_themes" == *"base03: '#002b36'"* && "$terminal_themes" == *"base3: '#fdf6e3'"* ]] || fail "expected VM terminal themes to vendor canonical Solarized base colors"
  [[ "$terminal_themes" == *"light: Object.freeze"* && "$terminal_themes" == *"dark: Object.freeze"* ]] || fail "expected VM terminal themes to define light and dark variants"
  [[ "$terminal_themes" == *"selectionBackground: solarized.base2"* && "$terminal_themes" == *"selectionBackground: solarized.base02"* ]] || fail "expected VM terminal themes to define curated Solarized selection colors"
  [[ "$terminal_themes" == *"brightMagenta: solarized.violet"* ]] || fail "expected VM terminal themes to include the full Solarized ANSI palette"
  [[ "$terminal_client" != *"background: '#050814'"* ]] || fail "expected VM terminal client to avoid the old custom dark background"
  [[ "$terminal_client" != *"foreground: '#dbe4f0'"* ]] || fail "expected VM terminal client to avoid the old custom foreground"
  [[ "$terminal_css" == *"body {"* && "$terminal_css" == *"margin: 0;"* && "$terminal_css" == *"padding: 0;"* ]] || fail "expected VM terminal page to remove browser body spacing"
  [[ "$terminal_css" == *"@media (prefers-color-scheme: dark)"* ]] || fail "expected VM terminal CSS to define dark-mode colors with a media query"
  [[ "$terminal_css" == *"--terminal-bg: #fdf6e3;"* && "$terminal_css" == *"--terminal-fg: #657b83;"* ]] || fail "expected VM terminal CSS to define Solarized Light page colors"
  [[ "$terminal_css" == *"--terminal-bg: #002b36;"* && "$terminal_css" == *"--terminal-fg: #839496;"* ]] || fail "expected VM terminal CSS to define Solarized Dark page colors"
  [[ "$terminal_css" == *"background: var(--terminal-bg);"* ]] || fail "expected VM terminal page background to match the terminal background"
  [[ "$terminal_css" != *"radial-gradient"* ]] || fail "expected VM terminal page to avoid styled gradient backgrounds"
  [[ "$terminal_css" != *"linear-gradient"* ]] || fail "expected VM terminal page to avoid styled gradient backgrounds"
  [[ "$terminal_css" != *"padding: 12px;"* ]] || fail "expected VM terminal surface to avoid inner terminal padding"
  [[ "$terminal_build" == *"const xtermCss = readFileSync(join(xtermCssPath, 'css/xterm.css'), 'utf8');"* ]] || fail "expected terminal build to include the upstream xterm.css stylesheet"
  [[ "$terminal_client" == *"closeRootSessionTab"* ]] || fail "expected VM terminal client to close the tab when the root terminal session exits"
  [[ "$terminal_client" == *"This browser blocked closing the tab"* ]] || fail "expected VM terminal client to keep root-exit fallback behavior explicit"
  [[ "$terminal_client" == *"if (event.code === 1000 || event.code === 1001)"* ]] || fail "expected VM terminal client to treat normal websocket closure as root-session exit"
  [[ "$contents" != *"'--once'"* ]] || fail "expected VM ttyd backend to survive transient reconnects"
  [[ "$contents" != *"'--exit-no-conn'"* ]] || fail "expected VM ttyd backend to avoid immediate exit on disconnect"
  [[ "$contents" == *"programs.bash.promptInit = ''"* ]] || fail "expected VM to override the default bash prompt init"
  [[ "$contents" == *"olc_terminal_title()"* ]] || fail "expected VM shell to define a terminal title helper"
  [[ "$contents" == *"olc_prompt_title()"* ]] || fail "expected VM shell to define a prompt title helper"
  [[ "$contents" == *"olc_command_title()"* ]] || fail "expected VM shell to define a command title helper"
  [[ "$contents" == *"PROMPT_COMMAND='olc_prompt_title'"* ]] || fail "expected VM shell prompt to report the current directory as the terminal title"
  [[ "$contents" == *"trap 'olc_command_title' DEBUG"* ]] || fail "expected VM shell to report the executing command as the terminal title"
  [[ "$contents" == *"printf '\\033]0;%s\\007' \"\$title\""* ]] || fail "expected VM shell to emit standard OSC title sequences"
  [[ "$contents" == *"local dir=\"''\${PWD/#\$HOME/~}\""* ]] || fail "expected VM shell title to shorten the home directory to tilde"
  [[ "$contents" == *"PS1='[\\u@\\h:\\w]\\$ '"* ]] || fail "expected VM to use a single-line bash prompt without the extra blank line"
  [[ "$contents" == *"user_pref(\"browser.tabs.inTitlebar\", 1);"* ]] || fail "expected VM to keep Firefox tabs in the title bar"
  [[ "$contents" == *"user_pref(\"browser.tabs.drawInTitlebar\", true);"* ]] || fail "expected VM to force Firefox titlebar drawing"
  [[ "$contents" == *"user_pref(\"browser.tabs.closeWindowWithLastTab\", false);"* ]] || fail "expected VM to keep Firefox open when the last tab closes"
  [[ "$contents" == *"user_pref(\"browser.aboutwelcome.enabled\", false);"* ]] || fail "expected VM to disable Firefox welcome and onboarding pages"
  [[ "$contents" == *"user_pref(\"browser.shell.checkDefaultBrowser\", false);"* ]] || fail "expected VM to disable Firefox default-browser startup checks"
  [[ "$contents" == *"user_pref(\"browser.startup.homepage\", \"https://localhost\");"* ]] || fail "expected VM to pin the Firefox home page to the in-guest HTTPS UI"
  [[ "$contents" == *"user_pref(\"browser.startup.homepage_override.mstone\", \"ignore\");"* ]] || fail "expected VM to disable Firefox homepage override tabs"
  [[ "$contents" == *"user_pref(\"security.enterprise_roots.enabled\", true);"* ]] || fail "expected VM to trust the guest localhost certificate through system roots"
  [[ "$contents" == *"user_pref(\"datareporting.policy.dataSubmissionEnabled\", false);"* ]] || fail "expected VM to disable Firefox data reporting submission"
  [[ "$contents" == *"user_pref(\"datareporting.policy.firstRunURL\", \"\");"* ]] || fail "expected VM to disable Firefox data-reporting first-run URL"
  [[ "$contents" == *"user_pref(\"startup.homepage_override_url\", \"\");"* ]] || fail "expected VM to clear Firefox startup override URL"
  [[ "$contents" == *"user_pref(\"startup.homepage_welcome_url\", \"\");"* ]] || fail "expected VM to clear Firefox welcome URL"
  [[ "$contents" == *"user_pref(\"startup.homepage_welcome_url.additional\", \"\");"* ]] || fail "expected VM to clear Firefox additional welcome URL"
  [[ "$contents" == *"user_pref(\"toolkit.telemetry.reportingpolicy.firstRun\", false);"* ]] || fail "expected VM to mark Firefox telemetry reporting policy as already handled"
  [[ "$contents" == *"matchbox-window-manager -use_titlebar no -use_cursor yes &"* ]] || fail "expected VM to launch matchbox without a title bar"
  [[ "$contents" == *"services.spice-vdagentd.enable = true;"* ]] || fail "expected VM to enable the SPICE guest agent daemon"
  [[ "$contents" == *"spice-vdagent"* ]] || fail "expected VM to include the SPICE guest agent"
  [[ "$contents" == *"\${pkgs.spice-vdagent}/bin/spice-vdagent &"* ]] || fail "expected VM xsession to start the SPICE session agent"
  [[ "$contents" == *"curl --silent --fail --cacert"* ]] || fail "expected VM to wait for the localhost HTTPS UI before launching Firefox"
  [[ "$contents" == *"xdotool windowsize \"\$window_id\" 100% 100%"* ]] || fail "expected VM to force Firefox to fill the screen"
  [[ "$contents" == *"expected_unwrapped=%s\\n' '\${pkgs.firefox-unwrapped}/lib/firefox/firefox'"* ]] || fail "expected VM to record the patched unwrapped Firefox executable expected at runtime"
  [[ "$contents" == *"firefox_launcher=%s\\n' '\${pkgs.firefox-unwrapped}/lib/firefox/firefox'"* ]] || fail "expected VM to record that it launches the patched unwrapped Firefox directly"
  [[ "$contents" == *"firefox_pid=\"\$!\""* ]] || fail "expected VM to record the launched Firefox process id"
  [[ "$contents" == *"running_firefox_exe=%s\\n' \"\$running_firefox\""* ]] || fail "expected VM to record the actual running Firefox executable"
  [[ "$contents" == *"unexpected_firefox_exe=1"* ]] || fail "expected VM diagnostics to flag a wrapper that launches the wrong unwrapped Firefox"
  [[ "$contents" == *"> /home/demo/ol-c-firefox-launch.txt"* ]] || fail "expected VM to write Firefox launch diagnostics"
  [[ "$contents" == *"MOZ_PURGE_CACHES=1 \${pkgs.firefox-unwrapped}/lib/firefox/firefox --no-remote --profile /home/demo/.mozilla/firefox/ol-c.default --new-window https://localhost &"* ]] || fail "expected VM to launch the patched unwrapped Firefox directly with cache purge enabled"
  [[ "$contents" == *"rm -rf /home/demo/.cache/mozilla/firefox/ol-c.default/startupCache"* ]] || fail "expected VM activation to clear the demo Firefox profile startup cache"
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
  [[ "$flake_contents" == *"firefox = final.wrapFirefox final.firefox-unwrapped { };"* ]] || fail "expected source overlay to rebuild the Firefox wrapper against the patched firefox-unwrapped"
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
  [[ "$patch_contents" == *"WebChannel: \"resource://gre/modules/WebChannel.sys.mjs\""* ]] || fail "expected Firefox patch to import WebChannel for the localhost appearance bridge"
  [[ "$patch_contents" == *"const SECUREOS_APPEARANCE_CHANNEL_ID = \"olc-appearance\";"* ]] || fail "expected Firefox patch to define the appearance bridge channel"
  [[ "$patch_contents" == *"const SECUREOS_APPEARANCE_ORIGIN = \"https://localhost\";"* ]] || fail "expected Firefox patch to restrict the appearance bridge to localhost"
  [[ "$patch_contents" == *"firefox-compact-dark@mozilla.org"* ]] || fail "expected Firefox patch to activate Firefox's built-in dark theme"
  [[ "$patch_contents" == *"firefox-compact-light@mozilla.org"* ]] || fail "expected Firefox patch to activate Firefox's built-in light theme"
  [[ "$patch_contents" == *"gSecureOSAppearanceBridge.init();"* ]] || fail "expected Firefox patch to initialize the appearance WebChannel bridge"
  [[ "$patch_contents" == *"+    url ??= SECUREOS_LOCALHOST_URL;"* ]] || fail "expected Firefox patch to point user-created new tabs at localhost"
  [[ "$patch_contents" != *"+    return SECUREOS_LOCALHOST_URL;"* ]] || fail "expected Firefox patch to avoid overriding the internal new-tab URL"
  [[ "$patch_contents" == *"+              this.addTrustedTab(SECUREOS_LOCALHOST_URL, {"* ]] || fail "expected Firefox patch to replace self-closing final tabs with localhost"
  [[ "$patch_contents" == *"browser_localhost_shell.js"* ]] || fail "expected Firefox patch to add browser regression tests"
  [[ "$patch_contents" == *"test_new_tab_uses_localhost_url"* ]] || fail "expected Firefox patch to test new-tab localhost behavior"
  [[ "$patch_contents" == *"test_dom_window_close_last_tab_uses_localhost"* ]] || fail "expected Firefox patch to test terminal-style final-tab closure"
  [[ "$patch_contents" == *"The SecureOS localhost surface should keep normal page title handling"* ]] || fail "expected Firefox patch to test normal title handling for localhost"
  [[ "$fast_contents" == *"firefox_omnis=("* ]] || fail "expected fast Firefox package to inspect all runtime omni archives"
  [[ "$fast_contents" == *"\"\$out/lib/firefox/browser/omni.ja\""* ]] || fail "expected fast Firefox package to patch browser omni.ja"
  [[ "$fast_contents" == *"\"\$out/lib/firefox/omni.ja\""* ]] || fail "expected fast Firefox package to patch top-level omni.ja"
  [[ "$fast_contents" == *"extracted_omnis=()"* ]] || fail "expected fast Firefox package to track extracted omni archives"
  [[ "$fast_contents" == *"for entry in \"''\${extracted_omnis[@]}\""* ]] || fail "expected fast Firefox package to match runtime assets across all extracted omni archives"
  [[ "$fast_contents" == *"filterdiff"* ]] || fail "expected fast Firefox package to extract runtime hunks from the repo patch"
  [[ "$fast_contents" != *"prev.nodejs"* ]] || fail "expected fast Firefox package to avoid Node.js after keeping Firefox's global new-tab URL getter intact"
  [[ "$fast_contents" == *"unzip_status=0"* ]] || fail "expected fast Firefox package to tolerate optimized omni.ja unzip warnings"
  [[ "$fast_contents" == *"continuing if required files extracted"* ]] || fail "expected fast Firefox package to validate extracted files after unzip warnings"
  [[ "$fast_contents" == *"browser/base/content/browser-commands.js"* ]] || fail "expected fast Firefox package to consume browser command hunks"
  [[ "$fast_contents" == *"browser/base/content/browser.js"* ]] || fail "expected fast Firefox package to consume browser chrome bridge hunks"
  [[ "$fast_contents" == *"browser/components/tabbrowser/content/tabbrowser.js"* ]] || fail "expected fast Firefox package to consume tabbrowser hunks"
  [[ "$fast_contents" == *"apply_source_patch_to_runtime_asset()"* ]] || fail "expected fast Firefox package to match runtime assets by patch context"
  [[ "$fast_contents" == *"patch -d \"\$extract_dir\" -p1 --dry-run"* ]] || fail "expected fast Firefox package to dry-run candidate patches against each extracted omni"
  [[ "$fast_contents" == *"Firefox localhost patch matched multiple"* ]] || fail "expected fast Firefox package to fail on ambiguous runtime asset matches"
  [[ "$fast_contents" == *"Firefox localhost patch did not match any extracted"* ]] || fail "expected fast Firefox package to fail on missing runtime asset matches"
  [[ "$fast_contents" == *"url ??= SECUREOS_LOCALHOST_URL"* ]] || fail "expected fast Firefox package to validate new-tab localhost code"
  [[ "$fast_contents" != *"Object.defineProperty(this, \"BROWSER_NEW_TAB_URL\""* ]] || fail "expected fast Firefox package to keep Firefox's global new-tab URL getter intact for normal title handling"
  [[ "$fast_contents" == *"url ??= BROWSER_NEW_TAB_URL;"* ]] || fail "expected fast Firefox package to fail if browser commands can still default to Firefox's stock new-tab URL"
  [[ "$fast_contents" == *"can still default new tabs to Firefox's stock new-tab URL"* ]] || fail "expected fast Firefox package to validate browser command defaults"
  [[ "$fast_contents" == *"this.addTrustedTab(SECUREOS_LOCALHOST_URL"* ]] || fail "expected fast Firefox package to validate last-tab localhost code"
  [[ "$fast_contents" == *"DOMWindowClose"* ]] || fail "expected fast Firefox package to validate terminal-style close handling"
  [[ "$fast_contents" == *"s#this\\.addTrustedTab(BROWSER_NEW_TAB_URL,#this.addTrustedTab(SECUREOS_LOCALHOST_URL,#g"* ]] || fail "expected fast Firefox package to normalize all tabbrowser trusted new-tab replacement calls"
  [[ "$fast_contents" == *"still contains stock trusted new-tab replacement calls"* ]] || fail "expected fast Firefox package to fail if tabbrowser replacement calls still use Firefox's stock new-tab URL"
  [[ "$fast_contents" == *"gSecureOSAppearanceBridge.init()"* ]] || fail "expected fast Firefox package to validate the appearance bridge in browser.js"
  [[ "$fast_contents" == *"new WebChannel("* ]] || fail "expected fast Firefox package to validate WebChannel bridge installation"
  [[ "$fast_contents" == *"firefox-compact-dark@mozilla.org"* ]] || fail "expected fast Firefox package to validate built-in dark theme activation"
  [[ "$fast_contents" == *"openTrustedLinkIn(BROWSER_NEW_TAB_URL"* ]] || fail "expected fast Firefox package to find browser.js direct new-tab paths"
  [[ "$fast_contents" == *"openTrustedLinkIn(\"https://localhost\""* ]] || fail "expected fast Firefox package to rewrite browser.js trusted tab opens to localhost"
  [[ "$fast_contents" == *"window.openDialog(/,/);/ s#BROWSER_NEW_TAB_URL#\"https://localhost\"#g"* ]] || fail "expected fast Firefox package to rewrite browser.js new-window fallback to localhost"
  [[ "$fast_contents" == *"sed -n '/window.openDialog(/,/);/p'"* ]] || fail "expected fast Firefox package to validate only the browser.js new-window fallback block"
  [[ "$fast_contents" == *"can still open trusted tabs with Firefox's stock new-tab URL"* ]] || fail "expected fast Firefox package to fail if browser.js trusted tab opens can still use Firefox's stock new-tab URL"
  [[ "$fast_contents" == *"OLC_FIREFOX_LOCALHOST_PATCH_APPLIED=1"* ]] || fail "expected fast Firefox package to leave an in-VM patch marker"
  [[ "$fast_contents" == *"browser_js_path="* ]] || fail "expected fast Firefox package to identify the patched browser.js runtime asset"
  [[ "$fast_contents" == *"ol-c-localhost-patch.txt"* ]] || fail "expected fast Firefox package to identify patched runtime assets"
  [[ "$fast_contents" == *"-name startupCache"* ]] || fail "expected fast Firefox package to remove packaged startup caches after rewriting chrome JS"
  [[ "$fast_contents" == *"-name 'scriptCache*'"* ]] || fail "expected fast Firefox package to remove packaged script caches after rewriting chrome JS"
  [[ "$fast_contents" == *"touch \"\$out/lib/firefox/.purgecaches\""* ]] || fail "expected fast Firefox package to force Firefox to purge stale app startup bytecode caches"
  [[ "$fast_contents" == *"touch \"\$out/lib/firefox/browser/.purgecaches\""* ]] || fail "expected fast Firefox package to force Firefox to purge stale browser startup bytecode caches"
  [[ "$fast_contents" == *"firefox = final.wrapFirefox final.firefox-unwrapped { };"* ]] || fail "expected fast Firefox package to rebuild the Firefox wrapper against the patched firefox-unwrapped"
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
