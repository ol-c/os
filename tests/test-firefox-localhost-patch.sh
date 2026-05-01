#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PATCH_FILE="${ROOT_DIR}/patches/firefox/packaged/0001-close-last-tab-to-localhost.patch"
FXA_PATCH_FILE="${ROOT_DIR}/patches/firefox/packaged/0002-hide-sync-fxa-ui.patch"
CURRENT_STATUS="${ROOT_DIR}/docs/current-status.md"
FLAKE="${ROOT_DIR}/flake.nix"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

test_localhost_redirector_contract() {
  local contents
  contents="$(cat "${PATCH_FILE}")"

  [[ "$contents" == *"diff --git a/browser/base/content/utilityOverlay.js b/browser/base/content/utilityOverlay.js"* ]] || fail "expected packaged Firefox patch to modify utilityOverlay"
  [[ "$contents" == *'return SECUREOS_LOCALHOST_URL;'* ]] || fail "expected browser chrome new tabs to resolve directly to localhost"
  [[ "$contents" == *'aURL == blankPageURL ||'* ]] || fail "expected localhost new tabs to keep normal blank-page title handling"

  [[ "$contents" == *"diff --git a/browser/components/newtab/AboutNewTabRedirector.sys.mjs b/browser/components/newtab/AboutNewTabRedirector.sys.mjs"* ]] || fail "expected packaged Firefox patch to modify AboutNewTabRedirector"
  [[ "$contents" == *'const SECUREOS_LOCALHOST_URL = "https://localhost/";'* ]] || fail "expected redirector patch to define the canonical SecureOS localhost URL"
  [[ "$contents" == *'chromeURI = Services.io.newURI(SECUREOS_LOCALHOST_URL);'* ]] || fail "expected parent about:newtab/about:home loads to redirect to localhost"
  [[ "$contents" == *'pageURI = Services.io.newURI(SECUREOS_LOCALHOST_URL);'* ]] || fail "expected child about:newtab/about:home loads to redirect to localhost"
  [[ "$contents" == *"AboutHomeStartupCacheChild.disqualifyCache();"* ]] || fail "expected localhost redirector path to bypass about:home startup cache reuse"
  [[ "$contents" == *"diff --git a/browser/components/tabbrowser/NewTabPagePreloading.sys.mjs b/browser/components/tabbrowser/NewTabPagePreloading.sys.mjs"* ]] || fail "expected packaged Firefox patch to modify new-tab preloading"
  [[ "$contents" == *'canPreloadForWindow(window)'* ]] || fail "expected packaged Firefox patch to gate preloading per window new-tab URL"
  [[ "$contents" == *'window.BROWSER_NEW_TAB_URL.startsWith("about:")'* ]] || fail "expected packaged Firefox patch to disable preloading for non-about new-tab URLs"

  [[ "$contents" != *'url ??= SECUREOS_LOCALHOST_URL;'* ]] || fail "expected BrowserCommands.openTab not to hardcode localhost anymore"
  [[ "$contents" != *'openTrustedLinkIn("https://localhost", "tab"'* ]] || fail "expected browser chrome new-tab entry points not to hardcode localhost anymore"
  [[ "$contents" != *'this.addTrustedTab(SECUREOS_LOCALHOST_URL, {'* ]] || fail "expected tabbrowser replacement tabs not to hardcode localhost anymore"
  [[ "$contents" == *'gBrowser.addTrustedTab(BROWSER_NEW_TAB_URL);'* ]] || fail "expected browser chrome fallback tabs to reuse the shared new-tab URL"
  [[ "$contents" == *'gBrowser.addTrustedTab(gBrowser.ownerGlobal.BROWSER_NEW_TAB_URL);'* ]] || fail "expected profile cleanup tabs to reuse the shared new-tab URL"
  [[ "$contents" == *'this.getWindow().BROWSER_NEW_TAB_URL,'* ]] || fail "expected split-view fallbacks to reuse the shared new-tab URL"
  [[ "$contents" == *'this.#window.openTrustedLinkIn(this.#window.BROWSER_NEW_TAB_URL, "window");'* ]] || fail "expected customize-mode new windows to reuse the shared new-tab URL"

  [[ "$contents" == *'openedURL,'$'\n''+      SECUREOS_LOCALHOST_URL,'* ]] || fail "expected browser mochitest coverage to assert the localhost new-tab target"
  [[ "$contents" == *'replacementURL,'$'\n''+      SECUREOS_LOCALHOST_URL,'* ]] || fail "expected replacement-tab tests to assert the localhost target"
  [[ "$contents" == *'test_new_tab_loads_localhost_url'* ]] || fail "expected browser mochitest coverage for the committed localhost load path"
  [[ "$contents" == *'Services.io.newURI(SECUREOS_LOCALHOST_URL).spec;'* ]] || fail "expected browser mochitest coverage to normalize the committed localhost URI"
  [[ "$contents" == *'test_adjacent_new_tab_uses_localhost_url'* ]] || fail "expected browser mochitest coverage for adjacent new-tab paths"
  [[ "$contents" == *'closeWindowWithLastTab: false,'* ]] || fail "expected DOMWindowClose last-tab handling to re-enter Firefox removeTab logic"
}

test_current_status_records_localhost_patch_gate() {
  local contents
  contents="$(cat "${CURRENT_STATUS}")"

  [[ "$contents" == *"bash tests/test-firefox-localhost-patch.sh"* ]] || fail "expected docs/current-status.md to record the localhost patch contract test"
}

test_packaged_build_stays_blind_to_pending_patches() {
  local contents
  contents="$(cat "${FLAKE}")"

  [[ "$contents" == *'firefoxPackagedPatchDir = ./patches/firefox/packaged;'* ]] || fail "expected packaged Firefox builds to read only the packaged patch directory"
  [[ "$contents" != *'./patches/firefox/pending'* ]] || fail "expected packaged Firefox build paths to stay blind to pending patches"
}

test_fast_runtime_overlay_covers_localhost_new_tab_assets() {
  local contents
  contents="$(cat "${ROOT_DIR}/nix/firefox-localhost-fast.nix")"

  [[ "$contents" == *'browser/base/content/utilityOverlay.js'* ]] || fail "expected fast Firefox overlay to apply the utilityOverlay runtime asset"
  [[ "$contents" == *'return SECUREOS_LOCALHOST_URL;'* ]] || fail "expected fast Firefox overlay to validate the browser new-tab localhost override"
  [[ "$contents" == *'browser/components/tabbrowser/NewTabPagePreloading.sys.mjs'* ]] || fail "expected fast Firefox overlay to apply the new-tab preloading runtime asset"
  [[ "$contents" == *'window.BROWSER_NEW_TAB_URL.startsWith("about:")'* ]] || fail "expected fast Firefox overlay to validate the non-about preload guard"
  [[ "$contents" == *'browser/components/customizableui/CustomizeMode.sys.mjs'* ]] || fail "expected fast Firefox overlay to apply customize-mode new-window runtime hooks"
  [[ "$contents" == *'browser/components/profiles/ProfilesParent.sys.mjs'* ]] || fail "expected fast Firefox overlay to apply profile cleanup replacement-tab runtime hooks"
  [[ "$contents" == *'browser/components/tabbrowser/content/opentabs-splitview.mjs'* ]] || fail "expected fast Firefox overlay to apply split-view fallback runtime hooks"
}

test_packaged_patch_ownership_split() {
  local localhost_contents fxa_contents
  localhost_contents="$(cat "${PATCH_FILE}")"
  fxa_contents="$(cat "${FXA_PATCH_FILE}")"

  [[ "$localhost_contents" != *'gSecureOSFxaSyncUi.init();'* ]] || fail "expected localhost packaged patch not to duplicate the FxA/Sync browser.js runtime hunk"
  [[ "$localhost_contents" != *'olc-fxa-sync-ui-hidden'* ]] || fail "expected localhost packaged patch not to own the FxA/Sync browser.js marker"
  [[ "$fxa_contents" == *'gSecureOSFxaSyncUi.init();'* ]] || fail "expected FxA/Sync packaged patch to own the FxA/Sync browser.js runtime hunk"
  [[ "$fxa_contents" == *'olc-fxa-sync-ui-hidden'* ]] || fail "expected FxA/Sync packaged patch to own the FxA/Sync browser.js marker"
}

test_localhost_redirector_contract
test_current_status_records_localhost_patch_gate
test_packaged_build_stays_blind_to_pending_patches
test_fast_runtime_overlay_covers_localhost_new_tab_assets
test_packaged_patch_ownership_split

echo "PASS: firefox-localhost-patch"
