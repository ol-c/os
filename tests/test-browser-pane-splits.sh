#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
PATCH_FILE="${ROOT_DIR}/patches/firefox/packaged/0004-add-browser-pane-splits.patch"
SESSION_NIX="${ROOT_DIR}/nix/modules/graphical-session.nix"
PACKAGES_NIX="${ROOT_DIR}/nix/modules/packages.nix"
PANECTL="${ROOT_DIR}/tools/olc-panectl"
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
  [[ "$contents" == *'Services.env.get("OLC_PANECTL")'* ]] || fail "expected Firefox to use the configured olc-panectl path"
  [[ "$contents" == *'prepare-split-at'* ]] || fail "expected Firefox drag handling to prepare a point-targeted i3 split"
  [[ "$contents" == *'sourcePointForWindow()'* ]] || fail "expected Firefox pane split prep to pass source-pane context"
  [[ "$contents" == *'sourceWillCloseAfterDrag()'* ]] || fail "expected Firefox pane split prep to identify closing source panes"
  [[ "$contents" == *'gSecureOSPaneSplitDrag.prepareForEvent(event)'* ]] || fail "expected dragend to consult the pane split target"
  [[ "$contents" == *'dt.dropEffect != "none"'* ]] || fail "expected native Firefox tab-bar drops to bypass pane splitting"
  [[ "$contents" == *'allowAdoptingAllTabs: 1'* ]] || fail "expected pane splits to allow moving the last source tab into a new pane"
  [[ "$contents" != *'gBrowser.addTrustedTab(BROWSER_NEW_TAB_URL,'* ]] || fail "expected pane splits not to keep source panes alive with dummy tabs"
  [[ "$contents" == *"diff --git a/browser/components/tabbrowser/content/tabbrowser.js b/browser/components/tabbrowser/content/tabbrowser.js"* ]] || fail "expected pane split patch to modify last-tab close behavior"
  [[ "$contents" == *'...windowFeatures'* ]] || fail "expected internal pane-split options not to leak into Firefox window features"
  [[ "$contents" == *'gSecureOSPaneSplits?.shouldCloseWindowWithLastTab'* ]] || fail "expected last-tab closes to remove non-final browser panes"
  [[ "$contents" == *"diff --git a/browser/base/content/browser.js b/browser/base/content/browser.js"* ]] || fail "expected pane split patch to expose browser pane counting in browser chrome"
  [[ "$contents" == *'BrowserWindowTracker.getOrderedWindows'* ]] || fail "expected pane counting to use Firefox browser-window tracking"
  [[ "$contents" == *'paneSummary()'* ]] || fail "expected a pane summary hook for browser-chrome and live validation"
}

test_i3_session_contract() {
  local session packages panectl
  session="$(cat "${SESSION_NIX}")"
  packages="$(cat "${PACKAGES_NIX}")"
  panectl="$(cat "${PANECTL}")"

  [[ "$session" == *'name = "olc-panectl";'* ]] || fail "expected graphical session to package olc-panectl"
  [[ "$session" == *'text = builtins.readFile ../../tools/olc-panectl;'* ]] || fail "expected graphical session to package the repo-owned olc-panectl script"
  [[ "$panectl" == *'prepare-split-at'* ]] || fail "expected olc-panectl to support point-targeted pane splits"
  [[ "$panectl" == *'target_pane_at()'* ]] || fail "expected olc-panectl to find the Firefox pane under the drop point"
  [[ "$panectl" == *'adjacent_pane_in_direction()'* ]] || fail "expected olc-panectl to retarget closing source pane moves through adjacent panes"
  [[ "$panectl" == *'nearest_direction()'* ]] || fail "expected olc-panectl to choose splits by nearest pane edge"
  [[ "$panectl" == *'left|right|top|bottom'* ]] || fail "expected olc-panectl to support all four split directions"
  [[ "$panectl" == *'i3-msg split h'* ]] || fail "expected olc-panectl to prepare horizontal i3 splits"
  [[ "$panectl" == *'i3-msg split v'* ]] || fail "expected olc-panectl to prepare vertical i3 splits"
  [[ "$panectl" == *'i3-msg -t subscribe -m'* ]] || fail "expected olc-panectl to subscribe to i3 window events"
  [[ "$panectl" == *'i3-msg move left'* ]] || fail "expected left-edge splits to move the new Firefox pane to the left"
  [[ "$panectl" == *'i3-msg move up'* ]] || fail "expected top-edge splits to move the new Firefox pane above the target"
  [[ "$panectl" != *'OLC_PANE_MIN_WIDTH_PX'* ]] || fail "expected pane splits not to reject narrow targets"
  [[ "$panectl" != *'OLC_PANE_MIN_HEIGHT_PX'* ]] || fail "expected pane splits not to reject short targets"
  [[ "$panectl" != *'too-narrow'* ]] || fail "expected pane splits not to log too-narrow rejections"
  [[ "$panectl" != *'too-short'* ]] || fail "expected pane splits not to log too-short rejections"
  [[ "$session" == *'OLC_PANE_RESIZE_BORDER_PX'* ]] || fail "expected resize border size to be configurable"
  [[ "$session" != *'OLC_PANE_SPLIT_TARGET_PX'* ]] || fail "expected pane split targeting not to depend on global edge-band thickness"
  [[ "$session" == *'OLC_PANE_BORDER_COLOR'* ]] || fail "expected pane border color to be configurable"
  [[ "$session" == *'default_border pixel $OLC_PANE_RESIZE_BORDER_PX'* ]] || fail "expected i3 pixel borders to provide the mouse resize hit region"
  [[ "$session" == *'for_window [class="^[Ff]irefox$"] border pixel $OLC_PANE_RESIZE_BORDER_PX'* ]] || fail "expected Firefox panes to use the configured resize border"
  [[ "$session" == *'i3 -c "$i3_config" &'* ]] || fail "expected user browser sessions to start i3"
  [[ "$session" == *'${olcPanectl}/bin/olc-panectl watch &'* ]] || fail "expected user browser sessions to start the pane watcher"
  [[ "$session" != *'xdotool key --window "$window_id" alt+F10'* ]] || fail "expected user browser sessions not to force Firefox fullscreen under i3"
  [[ "$session" != *'browser.olc.panes.splitTargetThicknessPx'* ]] || fail "expected user.js not to configure obsolete screen-edge split bands"
  [[ "$packages" == *'i3'* ]] || fail "expected i3 to be available in the OS image"
  [[ "$packages" == *'jq'* ]] || fail "expected jq to be available for pane event helpers"
}

test_fast_firefox_overlay_contract() {
  local contents
  contents="$(cat "${FAST_OVERLAY}")"

  [[ "$contents" == *'expected exactly four ol-c Firefox patches'* ]] || fail "expected fast Firefox overlay to account for the pane split patch"
  [[ "$contents" == *'pane_split_patch'* ]] || fail "expected fast Firefox overlay to name the pane split patch"
  [[ "$contents" == *'browser/components/tabbrowser/content/drag-and-drop.js'* ]] || fail "expected fast Firefox overlay to patch drag-and-drop runtime assets"
  [[ "$contents" == *'prepare-split-at'* ]] || fail "expected fast Firefox overlay to validate point-targeted pane split drag runtime code"
  [[ "$contents" == *'gSecureOSPaneSplits?.shouldCloseWindowWithLastTab'* ]] || fail "expected fast Firefox overlay to validate pane-aware last-tab closing"
  [[ "$contents" == *'OLC_FIREFOX_PANE_SPLIT_PATCH_APPLIED=1'* ]] || fail "expected fast Firefox output to record pane split patch application"
}

test_status_records_validation_gate() {
  local contents
  contents="$(cat "${CURRENT_STATUS}")"

  [[ "$contents" == *'bash tests/test-browser-pane-splits.sh'* ]] || fail "expected docs/current-status.md to record the pane split contract test"
  [[ "$contents" == *'bash tests/test-olc-panectl.sh'* ]] || fail "expected docs/current-status.md to record the pane controller helper test"
}

test_firefox_pane_split_patch_contract
test_i3_session_contract
test_fast_firefox_overlay_contract
test_status_records_validation_gate

echo "PASS: browser-pane-splits"
