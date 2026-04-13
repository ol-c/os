#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
REMOTE_BUILD="${ROOT_DIR}/build-firefox-remote"
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
  CASE_TMP="$(mktemp -d "${TEST_TMP_ROOT}/remote.XXXXXX")"
  mkdir -p "${CASE_TMP}/fakebin" "${CASE_TMP}/calls"

  cat >"${CASE_TMP}/fakebin/gcloud" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${CASE_TMP}/calls/gcloud"

if [[ "\$*" == "config get-value project" ]]; then
  if [[ "\${OLC_FAKE_NO_PROJECT:-0}" == "1" ]]; then
    exit 0
  fi
  printf '%s\n' "olc-test-project"
  exit 0
fi

if [[ "\$1" == "config" && "\${2:-}" == "set" && "\${3:-}" == "project" ]]; then
  printf '%s\n' "\${4:-}" > "${CASE_TMP}/selected-project"
  exit 0
fi

if [[ "\$1" == "config" && "\${2:-}" == "configurations" && "\${3:-}" == "list" ]]; then
  printf '%s\n' "NAME IS_ACTIVE ACCOUNT PROJECT"
  printf '%s\n' "default True dev@example.com olc-test-project"
  exit 0
fi

if [[ "\$1" == "auth" && "\${2:-}" == "list" ]]; then
  if [[ "\$*" == *"--filter=status:ACTIVE"* ]]; then
    if [[ "\${OLC_FAKE_NO_ACTIVE_ACCOUNT:-0}" == "1" && ! -f "${CASE_TMP}/logged-in" ]]; then
      exit 0
    fi
    printf '%s\n' "dev@example.com"
  else
    printf '%s\n' "Credentialed Accounts"
    printf '%s\n' "ACTIVE  ACCOUNT"
    printf '%s\n' "*       dev@example.com"
  fi
  exit 0
fi

if [[ "\$1" == "auth" && "\${2:-}" == "login" ]]; then
  if [[ "\${OLC_FAKE_LOGIN_SETS_ACCOUNT:-0}" == "1" ]]; then
    : > "${CASE_TMP}/logged-in"
  fi
  exit 0
fi

if [[ "\$1" == "projects" && "\${2:-}" == "list" ]]; then
  printf '%s\n' "PROJECT_ID NAME PROJECT_NUMBER"
  printf '%s\n' "chosen-project chosen 123"
  exit 0
fi

if [[ "\$1" == "--quiet" && "\${2:-}" == "storage" && "\${3:-}" == "buckets" && "\${4:-}" == "create" ]]; then
  if [[ "\${OLC_FAKE_BUCKET_CREATE_FAIL:-0}" == "1" ]]; then
    exit 1
  fi
  exit 0
fi

if [[ "\$1" == "storage" && "\${2:-}" == "buckets" && "\${3:-}" == "describe" ]]; then
  exit 1
fi

if [[ "\$1" == "--quiet" && "\${2:-}" == "storage" && "\${3:-}" == "cp" ]]; then
  src="\$4"
  dst="\$5"
  case "\$dst" in
    gs://*)
      ;;
    *)
      mkdir -p "\$(dirname "\$dst")"
      case "\$src" in
        */result-path.txt)
          printf '%s\n' "/nix/store/test-firefox" > "\$dst"
          ;;
        */target.txt)
          printf '%s\n' ".#firefox-localhost" > "\$dst"
          ;;
        */build.log)
          printf '%s\n' "remote log" > "\$dst"
          ;;
        */olc-nix-cache.tar.gz)
          tmp="\$(mktemp -d)"
          mkdir -p "\${tmp}/olc-nix-cache"
          tar -C "\$tmp" -czf "\$dst" olc-nix-cache
          rm -rf "\$tmp"
          ;;
      esac
      ;;
  esac
  exit 0
fi

if [[ "\$1" == "--quiet" && "\${2:-}" == "storage" && "\${3:-}" == "rm" ]]; then
  exit 0
fi

if [[ "\$1" == "--quiet" && "\${2:-}" == "batch" && "\${3:-}" == "jobs" && "\${4:-}" == "delete" ]]; then
  exit 0
fi

if [[ "\$1" == "batch" && "\${2:-}" == "jobs" && "\${3:-}" == "describe" ]]; then
  if [[ "\$*" == *"value(status.state)"* ]]; then
    printf '%s\n' "SUCCEEDED"
  elif [[ "\$*" == *"value(uid)"* ]]; then
    printf '%s\n' "fake-job-uid"
  else
    printf '%s\n' "status:"
    printf '%s\n' "  state: SUCCEEDED"
  fi
  exit 0
fi

if [[ "\$1" == "batch" && "\${2:-}" == "jobs" && "\${3:-}" == "submit" ]]; then
  exit 0
fi

if [[ "\$1" == "beta" && "\${2:-}" == "logging" && "\${3:-}" == "tail" ]]; then
  exit 0
fi

if [[ "\$1" == "logging" && "\${2:-}" == "read" ]]; then
  printf '%s\n' "remote progress"
  exit 0
fi

exit 0
EOF

  cat >"${CASE_TMP}/fakebin/nix" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >> "${CASE_TMP}/calls/nix"
EOF

  chmod +x "${CASE_TMP}/fakebin/gcloud" "${CASE_TMP}/fakebin/nix"
}

assert_contains() {
  local haystack="$1" needle="$2"
  [[ "$haystack" == *"$needle"* ]] || fail "expected [$needle] in [$haystack]"
}

trap cleanup_case EXIT

test_requires_gcloud() {
  local output status
  setup_case
  rm -f "${CASE_TMP}/fakebin/gcloud"

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${REMOTE_BUILD}" --dry-run \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected missing gcloud to fail"
  assert_contains "$output" "required command not found: gcloud"
  cleanup_case
}

test_dry_run_uses_safe_defaults() {
  local output
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${REMOTE_BUILD}" --dry-run
  )"

  assert_contains "$output" "Google Cloud configurations:"
  assert_contains "$output" "Google Cloud auth accounts:"
  assert_contains "$output" "bucket:       gs://ol-c-os-dev-builds"
  assert_contains "$output" "target:       .#firefox-localhost"
  assert_contains "$output" "machine:      h4d-standard-192"
  assert_contains "$output" '"maxRunDuration": "10800s"'
  assert_contains "$output" '"machineType": "h4d-standard-192"'
  assert_contains "$output" '"type": "hyperdisk-balanced"'
  assert_contains "$output" '"sizeGb": "300"'
  assert_contains "$output" '"destination": "CLOUD_LOGGING"'
  assert_contains "$output" 'zones/us-central1-a'
  assert_contains "$output" '.#firefox-localhost'
  cleanup_case
}

test_dry_run_allows_target_override() {
  local output
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${REMOTE_BUILD}" --dry-run .#ol-c-image
  )"

  assert_contains "$output" "target:       .#ol-c-image"
  assert_contains "$output" '.#ol-c-image'
  cleanup_case
}

test_bucket_create_and_batch_submit_contract() {
  local output calls
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${REMOTE_BUILD}" .#firefox-localhost
  )"
  calls="$(cat "${CASE_TMP}/calls/gcloud")"

  assert_contains "$output" "Creating staging bucket gs://ol-c-os-dev-builds"
  assert_contains "$output" "Submitting Batch job"
  assert_contains "$output" "Batch job "
  assert_contains "$calls" "storage buckets describe gs://ol-c-os-dev-builds"
  assert_contains "$calls" "--quiet storage buckets create gs://ol-c-os-dev-builds --location=us-central1 --uniform-bucket-level-access --public-access-prevention"
  assert_contains "$calls" "batch jobs submit olc-firefox-"
  assert_contains "$calls" "--config="
  cleanup_case
}

test_kill_deletes_batch_job() {
  local output calls
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${REMOTE_BUILD}" --kill olc-firefox-test
  )"
  calls="$(cat "${CASE_TMP}/calls/gcloud")"

  assert_contains "$output" "Deleting Batch job olc-firefox-test"
  assert_contains "$calls" "--quiet batch jobs delete olc-firefox-test --project=olc-test-project --location=us-central1"
  cleanup_case
}

test_fetch_imports_downloaded_cache() {
  local output nix_calls
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${REMOTE_BUILD}" --fetch olc-firefox-test
  )"
  nix_calls="$(cat "${CASE_TMP}/calls/nix")"

  assert_contains "$output" "Downloading artifacts for olc-firefox-test"
  assert_contains "$output" "Remote result: /nix/store/test-firefox"
  assert_contains "$nix_calls" "copy --no-check-sigs --from file://${ROOT_DIR}/.gcp-builds/olc-firefox-test/olc-nix-cache /nix/store/test-firefox"
  [[ -L "${ROOT_DIR}/result-gcp-firefox-localhost" ]] || fail "expected fetch to update result symlink"
  rm -f "${ROOT_DIR}/result-gcp-firefox-localhost"
  rm -rf "${ROOT_DIR}/.gcp-builds/olc-firefox-test"
  cleanup_case
}

test_submit_launches_browser_login_when_account_missing() {
  local output calls
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      OLC_FAKE_NO_ACTIVE_ACCOUNT=1 \
      OLC_FAKE_LOGIN_SETS_ACCOUNT=1 \
      "${REMOTE_BUILD}" --dry-run
  )"
  calls="$(cat "${CASE_TMP}/calls/gcloud")"

  assert_contains "$output" "No active Google Cloud account found. Launching browser login"
  assert_contains "$calls" "auth login --launch-browser"
  assert_contains "$output" "Dry run only"
  cleanup_case
}

test_submit_fails_if_browser_login_does_not_select_account() {
  local output status calls
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      OLC_FAKE_NO_ACTIVE_ACCOUNT=1 \
      "${REMOTE_BUILD}" --dry-run \
      2>&1
  )"
  status=$?
  set -e
  calls="$(cat "${CASE_TMP}/calls/gcloud")"

  [[ $status -ne 0 ]] || fail "expected missing account after login to fail"
  assert_contains "$output" "gcloud auth login --launch-browser"
  assert_contains "$calls" "auth login --launch-browser"
  [[ "$calls" != *"storage buckets create"* ]] || fail "expected missing account to stop before bucket creation"
  cleanup_case
}

test_submit_helps_select_project_interactively() {
  local output calls selected
  setup_case

  output="$(
    printf '%s\n' "chosen-project" | PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      OLC_FAKE_NO_PROJECT=1 \
      OLC_GCP_ASSUME_INTERACTIVE=1 \
      "${REMOTE_BUILD}" --dry-run
  )"
  calls="$(cat "${CASE_TMP}/calls/gcloud")"
  selected="$(cat "${CASE_TMP}/selected-project")"

  assert_contains "$output" "No Google Cloud project is selected."
  assert_contains "$output" "Available projects:"
  assert_contains "$calls" "projects list"
  assert_contains "$calls" "config set project chosen-project"
  [[ "$selected" == "chosen-project" ]] || fail "expected selected project to be recorded"
  assert_contains "$output" "project:      chosen-project"
  cleanup_case
}

test_submit_fails_without_project_when_noninteractive() {
  local output status calls
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      OLC_FAKE_NO_PROJECT=1 \
      "${REMOTE_BUILD}" --dry-run \
      2>&1
  )"
  status=$?
  set -e
  calls="$(cat "${CASE_TMP}/calls/gcloud")"

  [[ $status -ne 0 ]] || fail "expected noninteractive missing project to fail"
  assert_contains "$output" "gcloud config set project PROJECT_ID"
  assert_contains "$calls" "projects list"
  cleanup_case
}

test_management_mode_does_not_launch_login() {
  local output status calls
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      OLC_FAKE_NO_ACTIVE_ACCOUNT=1 \
      OLC_FAKE_LOGIN_SETS_ACCOUNT=1 \
      "${REMOTE_BUILD}" --kill olc-firefox-test \
      2>&1
  )"
  status=$?
  set -e
  calls="$(cat "${CASE_TMP}/calls/gcloud")"

  [[ $status -ne 0 ]] || fail "expected management mode without account to fail"
  assert_contains "$output" "gcloud auth login --launch-browser"
  [[ "$calls" != *"auth login --launch-browser"* ]] || fail "management mode should not launch browser login"
  cleanup_case
}

test_bucket_create_failure_recommends_unique_bucket() {
  local output status
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      OLC_FAKE_BUCKET_CREATE_FAIL=1 \
      "${REMOTE_BUILD}" .#firefox-localhost \
      2>&1
  )"
  status=$?
  set -e

  [[ $status -ne 0 ]] || fail "expected bucket creation failure to fail"
  assert_contains "$output" "bucket names are global"
  assert_contains "$output" "OLC_GCP_BUCKET=<unique-name>"
  cleanup_case
}

test_script_documents_archive_excludes() {
  local contents
  contents="$(cat "${REMOTE_BUILD}")"

  assert_contains "$contents" "--exclude='./.git'"
  assert_contains "$contents" "--exclude='./terminal-client/node_modules'"
  assert_contains "$contents" "--exclude='./result'"
  assert_contains "$contents" "--exclude='./result-*'"
  assert_contains "$contents" "--exclude='./.gcp-builds'"
}

test_requires_gcloud
test_submit_launches_browser_login_when_account_missing
test_submit_fails_if_browser_login_does_not_select_account
test_submit_helps_select_project_interactively
test_submit_fails_without_project_when_noninteractive
test_management_mode_does_not_launch_login
test_dry_run_uses_safe_defaults
test_dry_run_allows_target_override
test_bucket_create_and_batch_submit_contract
test_bucket_create_failure_recommends_unique_bucket
test_kill_deletes_batch_job
test_fetch_imports_downloaded_cache
test_script_documents_archive_excludes

echo "PASS: build-firefox-remote"
