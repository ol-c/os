#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PATCH_FILE="${ROOT_DIR}/patches/firefox/packaged/0004-add-browser-pane-splits.patch"
SESSION_NIX="${ROOT_DIR}/nix/modules/graphical-session.nix"
PACKAGES_NIX="${ROOT_DIR}/nix/modules/packages.nix"
FAST_OVERLAY="${ROOT_DIR}/nix/firefox-localhost-fast.nix"
CURRENT_STATUS="${ROOT_DIR}/docs/current-status.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

test_firefox_pane_split_patch_contract() {
  local contents
  contents="$(cat "${PATCH_FILE}")"

  [[ "$contents" == *"diff --git a/browser/components/tabbrowser/content/drag-and-drop.js b/browser/components/tabbrowser/content/drag-and-drop.js"* ]] || fail "expected pane split patch to modify tab drag handling"
  [[ "$contents" == *"browser.olc.panes.splitTargetThicknessPx"* ]] || fail "expected pane split target thickness to be Firefox-pref configurable"
  [[ "$contents" == *'Services.env.get("OLC_PANECTL")'* ]] || fail "expected Firefox to use the configured olc-panectl path"
  [[ "$contents" == *'prepare-split'* ]] || fail "expected Firefox drag handling to prepare an i3 split before opening a new pane window"
  [[ "$contents" == *'gSecureOSPaneSplitDrag.prepareForEvent(event)'* ]] || fail "expected dragend to consult the pane split target"
  [[ "$contents" == *'gBrowser.addTrustedTab(BROWSER_NEW_TAB_URL,'* ]] || fail "expected one-tab source panes to be refilled with the system page before adoption"
  [[ "$contents" == *"diff --git a/browser/components/tabbrowser/content/tabbrowser.js b/browser/components/tabbrowser/content/tabbrowser.js"* ]] || fail "expected pane split patch to modify last-tab close behavior"
  [[ "$contents" == *'gSecureOSPaneSplits?.shouldCloseWindowWithLastTab'* ]] || fail "expected last-tab closes to remove non-final browser panes"
  [[ "$contents" == *"diff --git a/browser/base/content/browser.js b/browser/base/content/browser.js"* ]] || fail "expected pane split patch to expose browser pane counting in browser chrome"
  [[ "$contents" == *'BrowserWindowTracker.getOrderedWindows'* ]] || fail "expected pane counting to use Firefox browser-window tracking"
  [[ "$contents" == *'paneSummary()'* ]] || fail "expected a pane summary hook for browser-chrome and live validation"
}

test_i3_session_contract() {
  local session packages
  session="$(cat "${SESSION_NIX}")"
  packages="$(cat "${PACKAGES_NIX}")"

  [[ "$session" == *'name = "olc-panectl";'* ]] || fail "expected graphical session to package olc-panectl"
  [[ "$session" == *'i3-msg split h'* ]] || fail "expected olc-panectl to prepare horizontal i3 splits"
  [[ "$session" == *'i3-msg split v'* ]] || fail "expected olc-panectl to prepare vertical i3 splits"
  [[ "$session" == *'i3-msg -t subscribe -m'* ]] || fail "expected olc-panectl to subscribe to i3 window events"
  [[ "$session" == *'i3-msg move left'* ]] || fail "expected left-edge splits to move the new Firefox pane to the left"
  [[ "$session" == *'OLC_PANE_RESIZE_BORDER_PX'* ]] || fail "expected resize border size to be configurable"
  [[ "$session" == *'OLC_PANE_SPLIT_TARGET_PX'* ]] || fail "expected tab-drag split target thickness to be configurable"
  [[ "$session" == *'OLC_PANE_BORDER_COLOR'* ]] || fail "expected pane border color to be configurable"
  [[ "$session" == *'default_border pixel $OLC_PANE_RESIZE_BORDER_PX'* ]] || fail "expected i3 pixel borders to provide the mouse resize hit region"
  [[ "$session" == *'for_window [class="^[Ff]irefox$"] border pixel $OLC_PANE_RESIZE_BORDER_PX'* ]] || fail "expected Firefox panes to use the configured resize border"
  [[ "$session" == *'i3 -c "$i3_config" &'* ]] || fail "expected user browser sessions to start i3"
  [[ "$session" == *'${olcPanectl}/bin/olc-panectl watch &'* ]] || fail "expected user browser sessions to start the pane watcher"
  [[ "$session" != *'xdotool key --window "$window_id" alt+F10'* ]] || fail "expected user browser sessions not to force Firefox fullscreen under i3"
  [[ "$session" == *'browser.olc.panes.splitTargetThicknessPx'* ]] || fail "expected user.js to pass the configured split target thickness into Firefox"
  [[ "$packages" == *'i3'* ]] || fail "expected i3 to be available in the OS image"
  [[ "$packages" == *'jq'* ]] || fail "expected jq to be available for pane event helpers"
}

test_fast_firefox_overlay_contract() {
  local contents
  contents="$(cat "${FAST_OVERLAY}")"

  [[ "$contents" == *'expected exactly four ol-c Firefox patches'* ]] || fail "expected fast Firefox overlay to account for the pane split patch"
  [[ "$contents" == *'pane_split_patch'* ]] || fail "expected fast Firefox overlay to name the pane split patch"
  [[ "$contents" == *'browser/components/tabbrowser/content/drag-and-drop.js'* ]] || fail "expected fast Firefox overlay to patch drag-and-drop runtime assets"
  [[ "$contents" == *'gSecureOSPaneSplitDrag.prepareForEvent(event)'* ]] || fail "expected fast Firefox overlay to validate pane split drag runtime code"
  [[ "$contents" == *'gSecureOSPaneSplits?.shouldCloseWindowWithLastTab'* ]] || fail "expected fast Firefox overlay to validate pane-aware last-tab closing"
  [[ "$contents" == *'OLC_FIREFOX_PANE_SPLIT_PATCH_APPLIED=1'* ]] || fail "expected fast Firefox output to record pane split patch application"
}

test_status_records_validation_gate() {
  local contents
  contents="$(cat "${CURRENT_STATUS}")"

  [[ "$contents" == *'bash tests/test-browser-pane-splits.sh'* ]] || fail "expected docs/current-status.md to record the pane split contract test"
}

test_firefox_pane_split_patch_contract
test_i3_session_contract
test_fast_firefox_overlay_contract
test_status_records_validation_gate

echo "PASS: browser-pane-splits"
