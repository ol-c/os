#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/tools/olc-vm-bidi.mjs"
TEST_TMP_ROOT="${OLC_TEST_TMP_ROOT:-${ROOT_DIR}/.tmp-tests}"
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
  CASE_TMP="$(mktemp -d "${TEST_TMP_ROOT}/olc-vm-bidi.XXXXXX")"
  mkdir -p "${CASE_TMP}/operator/current/requests" "${CASE_TMP}/operator/current/results" "${CASE_TMP}/fakebin" "${CASE_TMP}/journal"
  cat > "${CASE_TMP}/fakebin/journalctl" <<'EOF'
#!/usr/bin/env bash
cat <<'OUT'
__REALTIME_TIMESTAMP=1714090000000000
SYSLOG_IDENTIFIER=olc-vm-ready
OLC_VM_READY=embedded-control-ready
OLC_VM_MACHINE_ID=child-machine-id
OLC_VM_PARENT_MACHINE_ID=parent-machine-id

OUT
EOF
  chmod +x "${CASE_TMP}/fakebin/journalctl"
}

trap cleanup_case EXIT

test_creates_targeted_request_and_prints_result() {
  local output
  setup_case

  (
    while true; do
      request_file="$(find "${CASE_TMP}/operator/current/requests" -maxdepth 1 -name '*.json' | sed -n '1p')"
      if [[ -n "$request_file" ]]; then
        request_id="$(basename "$request_file")"
        [[ "$(cat "$request_file")" == *'"targetMachineId": "child-machine-id"'* ]] || fail "expected request to target the child machine id"
        cat > "${CASE_TMP}/operator/current/results/${request_id}" <<'EOF'
{
  "ok": true,
  "stdout": "System"
}
EOF
        break
      fi
      sleep 0.1
    done
  ) &

  output="$(
    PATH="${CASE_TMP}/fakebin:${PATH}" \
    OLC_JOURNALCTL=journalctl \
    OLC_VM_PARENT_MACHINE_ID=parent-machine-id \
    OLC_VM_OPERATOR_ROOT="${CASE_TMP}/operator/current" \
      node "${SCRIPT_PATH}" --journal-dir "${CASE_TMP}/journal" eval 'document.title'
  )"

  [[ "$output" == "System" ]] || fail "unexpected output: $output"
}

test_creates_targeted_request_and_prints_result

echo "PASS: olc-vm-bidi"
