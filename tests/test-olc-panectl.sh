#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/tools/olc-panectl"
TEST_TMP_ROOT="${OLC_TEST_TMP_ROOT:-${ROOT_DIR}/.tmp-tests}"
TEST_FAKE_BASH="${OLC_TEST_FAKE_BASH:-$(command -v bash)}"
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
  CASE_TMP="$(mktemp -d "${TEST_TMP_ROOT}/panectl.XXXXXX")"
  mkdir -p "${CASE_TMP}/fakebin" "${CASE_TMP}/runtime"
  : > "${CASE_TMP}/i3.log"
  : > "${CASE_TMP}/events.jsonl"

  cat > "${CASE_TMP}/fakebin/i3-msg" <<EOF
#!${TEST_FAKE_BASH}
set -euo pipefail
printf '%s\n' "\$*" >> "${CASE_TMP}/i3.log"
if [[ "\${1:-}" = "-t" && "\${2:-}" = "get_tree" ]]; then
  cat "${CASE_TMP}/tree.json"
  exit 0
fi
if [[ "\${1:-}" = "-t" && "\${2:-}" = "subscribe" ]]; then
  cat "${CASE_TMP}/events.jsonl"
  exit 0
fi
exit 0
EOF
  chmod +x "${CASE_TMP}/fakebin/i3-msg"
}

write_two_pane_tree() {
  cat > "${CASE_TMP}/tree.json" <<'JSON'
{
  "id": 1,
  "focused": false,
  "rect": {"x": 0, "y": 0, "width": 1600, "height": 900},
  "nodes": [
    {
      "id": 10,
      "focused": false,
      "window": 1001,
      "rect": {"x": 0, "y": 0, "width": 800, "height": 900},
      "window_properties": {"class": "Firefox", "instance": "firefox"}
    },
    {
      "id": 11,
      "focused": true,
      "window": 1002,
      "rect": {"x": 800, "y": 0, "width": 800, "height": 900},
      "window_properties": {"class": "Firefox", "instance": "firefox"}
    }
  ]
}
JSON
}

run_panectl() {
  PATH="${CASE_TMP}/fakebin:$PATH" \
    XDG_RUNTIME_DIR="${CASE_TMP}/runtime" \
    OLC_PANE_PENDING_TTL_MS=10000 \
    "${TEST_FAKE_BASH}" "$SCRIPT_PATH" "$@"
}

pending_file() {
  printf '%s/ol-c-panes/pending-split.json\n' "${CASE_TMP}/runtime"
}

assert_log_contains() {
  local pattern="$1"
  grep -Fxq -- "$pattern" "${CASE_TMP}/i3.log" || {
    sed -n '1,120p' "${CASE_TMP}/i3.log" >&2
    fail "expected i3 log to contain: $pattern"
  }
}

test_prepare_split_at_targets_pane_under_pointer() {
  setup_case
  write_two_pane_tree

  run_panectl prepare-split-at 810 450

  [[ "$(jq -r '.direction' "$(pending_file)")" = left ]] || fail "expected left split"
  [[ "$(jq -r '.targetConId' "$(pending_file)")" = 11 ]] || fail "expected target pane 11"
  assert_log_contains "-t get_tree"
  assert_log_contains "[con_id=11] focus"
  assert_log_contains "split h"
}

test_prepare_split_at_supports_top_edge() {
  setup_case
  write_two_pane_tree

  run_panectl prepare-split-at 1200 5

  [[ "$(jq -r '.direction' "$(pending_file)")" = top ]] || fail "expected top split"
  [[ "$(jq -r '.targetConId' "$(pending_file)")" = 11 ]] || fail "expected target pane 11"
  assert_log_contains "[con_id=11] focus"
  assert_log_contains "split v"
}

test_prepare_split_at_rejects_missing_target() {
  local status
  setup_case
  write_two_pane_tree

  set +e
  run_panectl prepare-split-at 1700 5 >/dev/null 2>&1
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "expected missing target to fail"
  [[ ! -e "$(pending_file)" ]] || fail "expected no pending split after missing target"
  assert_log_contains "-t get_tree"
}

test_prepare_split_at_rejects_too_small_target() {
  local status
  setup_case
  write_two_pane_tree

  set +e
  PATH="${CASE_TMP}/fakebin:$PATH" \
    XDG_RUNTIME_DIR="${CASE_TMP}/runtime" \
    OLC_PANE_MIN_WIDTH_PX=500 \
    "${TEST_FAKE_BASH}" "$SCRIPT_PATH" prepare-split-at 810 450 >/dev/null 2>&1
  status=$?
  set -e

  [[ "$status" -ne 0 ]] || fail "expected too-small target to fail"
  [[ ! -e "$(pending_file)" ]] || fail "expected no pending split after size rejection"
  ! grep -Fxq -- "split h" "${CASE_TMP}/i3.log" || fail "expected rejected target not to split"
}

test_watch_moves_new_left_and_top_panes() {
  local direction move_command
  for direction in left top; do
    setup_case
    mkdir -p "${CASE_TMP}/runtime/ol-c-panes"
    printf '{"direction":"%s","createdMs":%s}\n' "$direction" "$(date +%s%3N)" \
      > "$(pending_file)"
    cat > "${CASE_TMP}/events.jsonl" <<'JSON'
{"change":"new","container":{"id":99,"window_properties":{"class":"Firefox","instance":"firefox"}}}
JSON

    run_panectl watch

    move_command="move $direction"
    if [[ "$direction" = top ]]; then
      move_command="move up"
    fi
    assert_log_contains "[con_id=99] focus"
    assert_log_contains "$move_command"
    [[ ! -e "$(pending_file)" ]] || fail "expected watcher to clear $direction pending split"
  done
}

trap cleanup_case EXIT

test_prepare_split_at_targets_pane_under_pointer
test_prepare_split_at_supports_top_edge
test_prepare_split_at_rejects_missing_target
test_prepare_split_at_rejects_too_small_target
test_watch_moves_new_left_and_top_panes

echo "PASS: olc-panectl"
