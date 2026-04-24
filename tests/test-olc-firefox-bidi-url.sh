#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/tools/olc-firefox-bidi-url.sh"
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
  CASE_TMP="$(mktemp -d "${TEST_TMP_ROOT}/firefox-bidi-url.XXXXXX")"
  mkdir -p "${CASE_TMP}/fakebin"

  cat >"${CASE_TMP}/fakebin/loginctl" <<EOF
#!${TEST_FAKE_BASH}
case "\$*" in
  "show-seat seat0 --property=ActiveSession --value")
    if [[ "\${OLC_TEST_ACTIVE_SESSION+x}" == "x" ]]; then
      printf '%s\n' "\$OLC_TEST_ACTIVE_SESSION"
    else
      printf '%s\n' 'c1'
    fi
    ;;
  "show-session c1 --property=Name --property=Class --property=Remote --property=State")
    cat <<OLC_SESSION
Name=\${OLC_TEST_SESSION_NAME:-vieweruser}
Class=\${OLC_TEST_SESSION_CLASS:-user}
Remote=\${OLC_TEST_SESSION_REMOTE:-no}
State=\${OLC_TEST_SESSION_STATE:-active}
OLC_SESSION
    ;;
  *)
    exit 1
    ;;
esac
EOF

  cat >"${CASE_TMP}/fakebin/getent" <<EOF
#!${TEST_FAKE_BASH}
if [[ "\$1" == "passwd" && "\$2" == "\${OLC_TEST_SESSION_NAME:-vieweruser}" ]]; then
  printf '%s\n' "\${OLC_TEST_PASSWD_ENTRY:-vieweruser:x:1000:1000::/home/vieweruser:/run/current-system/sw/bin/bash}"
  exit 0
fi
exit 1
EOF

  chmod +x "${CASE_TMP}/fakebin/loginctl" "${CASE_TMP}/fakebin/getent"
}

assert_eq() {
  local expected="$1"
  local actual="$2"
  [[ "$expected" == "$actual" ]] || fail "expected [$expected], got [$actual]"
}

trap cleanup_case EXIT

test_prints_session_url() {
  local bidi_env_path output
  setup_case
  bidi_env_path="${CASE_TMP}/bidi.env"
  cat >"${bidi_env_path}" <<'EOF'
OLC_FIREFOX_BIDI_ENABLED=1
OLC_FIREFOX_BIDI_PORT=0
OLC_FIREFOX_BIDI_BASE_URL=ws://127.0.0.1:47777
OLC_FIREFOX_BIDI_WS_URL=ws://127.0.0.1:47777/session
EOF

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_LOGINCTL="${CASE_TMP}/fakebin/loginctl" \
      OLC_GETENT="${CASE_TMP}/fakebin/getent" \
      OLC_FIREFOX_BIDI_ENV_PATH="${bidi_env_path}" \
      "${TEST_FAKE_BASH}" "${SCRIPT_PATH}"
  )"

  assert_eq "ws://127.0.0.1:47777/session" "$output"
}

test_prints_base_url() {
  local bidi_env_path output
  setup_case
  bidi_env_path="${CASE_TMP}/bidi.env"
  cat >"${bidi_env_path}" <<'EOF'
OLC_FIREFOX_BIDI_ENABLED=1
OLC_FIREFOX_BIDI_PORT=0
OLC_FIREFOX_BIDI_BASE_URL=ws://127.0.0.1:48888
OLC_FIREFOX_BIDI_WS_URL=ws://127.0.0.1:48888/session
EOF

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_LOGINCTL="${CASE_TMP}/fakebin/loginctl" \
      OLC_GETENT="${CASE_TMP}/fakebin/getent" \
      OLC_FIREFOX_BIDI_ENV_PATH="${bidi_env_path}" \
      "${TEST_FAKE_BASH}" "${SCRIPT_PATH}" --base
  )"

  assert_eq "ws://127.0.0.1:48888" "$output"
}

test_fails_when_session_url_missing() {
  local bidi_env_path output status
  setup_case
  bidi_env_path="${CASE_TMP}/bidi.env"
  cat >"${bidi_env_path}" <<'EOF'
OLC_FIREFOX_BIDI_ENABLED=1
OLC_FIREFOX_BIDI_PORT=0
EOF

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_LOGINCTL="${CASE_TMP}/fakebin/loginctl" \
      OLC_GETENT="${CASE_TMP}/fakebin/getent" \
      OLC_FIREFOX_BIDI_ENV_PATH="${bidi_env_path}" \
      "${TEST_FAKE_BASH}" "${SCRIPT_PATH}" 2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected missing session URL to fail"
  [[ "$output" == *"Firefox BiDi session URL is not available yet"* ]] || fail "unexpected output: $output"
}

test_fails_without_active_session() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_LOGINCTL="${CASE_TMP}/fakebin/loginctl" \
      OLC_GETENT="${CASE_TMP}/fakebin/getent" \
      OLC_TEST_ACTIVE_SESSION="" \
      "${TEST_FAKE_BASH}" "${SCRIPT_PATH}" 2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected missing active session to fail"
  [[ "$output" == *"no active seat0 session"* ]] || fail "unexpected output: $output"
}

test_prints_session_url
test_prints_base_url
test_fails_when_session_url_missing
test_fails_without_active_session

echo "PASS: olc-firefox-bidi-url"
