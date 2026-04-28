#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PATCH_FILE="${ROOT_DIR}/patches/firefox/packaged/0001-close-last-tab-to-localhost.patch"
AGENTS="${ROOT_DIR}/AGENTS.md"
FLAKE="${ROOT_DIR}/flake.nix"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

test_localhost_redirector_contract() {
  local contents
  contents="$(cat "${PATCH_FILE}")"

  [[ "$contents" == *"diff --git a/browser/components/newtab/AboutNewTabRedirector.sys.mjs b/browser/components/newtab/AboutNewTabRedirector.sys.mjs"* ]] || fail "expected packaged Firefox patch to modify AboutNewTabRedirector"
  [[ "$contents" == *'const SECUREOS_LOCALHOST_URL = "https://localhost";'* ]] || fail "expected redirector patch to define the SecureOS localhost URL"
  [[ "$contents" == *'chromeURI = Services.io.newURI(SECUREOS_LOCALHOST_URL);'* ]] || fail "expected parent about:newtab/about:home loads to redirect to localhost"
  [[ "$contents" == *'pageURI = Services.io.newURI(SECUREOS_LOCALHOST_URL);'* ]] || fail "expected child about:newtab/about:home loads to redirect to localhost"
  [[ "$contents" == *"AboutHomeStartupCacheChild.disqualifyCache();"* ]] || fail "expected localhost redirector path to bypass about:home startup cache reuse"
  [[ "$contents" == *"default behaviors like urlbar focus still trigger"* ]] || fail "expected redirector patch to document why the deeper redirect exists"

  [[ "$contents" != *'url ??= SECUREOS_LOCALHOST_URL;'* ]] || fail "expected BrowserCommands.openTab not to hardcode localhost anymore"
  [[ "$contents" != *'openTrustedLinkIn("https://localhost", "tab"'* ]] || fail "expected browser chrome new-tab entry points not to hardcode localhost anymore"
  [[ "$contents" != *'this.addTrustedTab(SECUREOS_LOCALHOST_URL, {'* ]] || fail "expected tabbrowser replacement tabs not to hardcode localhost anymore"

  [[ "$contents" == *'openedURL,'$'\n''+      win.BROWSER_NEW_TAB_URL,'* ]] || fail "expected browser mochitest coverage to assert the Firefox new-tab URL path"
  [[ "$contents" == *'replacementURL,'$'\n''+      win.BROWSER_NEW_TAB_URL,'* ]] || fail "expected replacement-tab tests to assert the Firefox new-tab URL path"
  [[ "$contents" == *'closeWindowWithLastTab: false,'* ]] || fail "expected DOMWindowClose last-tab handling to re-enter Firefox removeTab logic"
}

test_agents_records_localhost_patch_gate() {
  local contents
  contents="$(cat "${AGENTS}")"

  [[ "$contents" == *"bash tests/test-firefox-localhost-patch.sh"* ]] || fail "expected AGENTS.md to record the localhost patch contract test"
}

test_packaged_build_stays_blind_to_pending_patches() {
  local contents
  contents="$(cat "${FLAKE}")"

  [[ "$contents" == *'firefoxPackagedPatchDir = ./patches/firefox/packaged;'* ]] || fail "expected packaged Firefox builds to read only the packaged patch directory"
  [[ "$contents" != *'./patches/firefox/pending'* ]] || fail "expected packaged Firefox build paths to stay blind to pending patches"
}

test_localhost_redirector_contract
test_agents_records_localhost_patch_gate
test_packaged_build_stays_blind_to_pending_patches

echo "PASS: firefox-localhost-patch"
