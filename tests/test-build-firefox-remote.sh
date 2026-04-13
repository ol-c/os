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
  printf '%s\n' "ol-c-test-project"
  exit 0
fi

if [[ "\$1" == "config" && "\${2:-}" == "set" && "\${3:-}" == "project" ]]; then
  printf '%s\n' "\${4:-}" > "${CASE_TMP}/selected-project"
  exit 0
fi

if [[ "\$1" == "config" && "\${2:-}" == "set" && "\${3:-}" == "account" ]]; then
  printf '%s\n' "\${4:-}" > "${CASE_TMP}/selected-account"
  exit 0
fi

if [[ "\$1" == "config" && "\${2:-}" == "configurations" && "\${3:-}" == "activate" ]]; then
  printf '%s\n' "\${4:-}" > "${CASE_TMP}/selected-config"
  exit 0
fi

if [[ "\$1" == "config" && "\${2:-}" == "configurations" && "\${3:-}" == "list" ]]; then
  printf '%s\n' "NAME IS_ACTIVE ACCOUNT PROJECT"
  printf '%s\n' "default True dev@example.com ol-c-test-project"
  printf '%s\n' "other False other@example.com other-project"
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
    printf '%s\n' "        other@example.com"
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

if [[ "\$1" == "compute" && "\${2:-}" == "instances" && "\${3:-}" == "create" ]]; then
  if [[ "\${OLC_FAKE_VM_CREATE_FAIL:-0}" == "1" ]]; then
    exit 1
  fi
  exit 0
fi

if [[ "\$1" == "compute" && "\${2:-}" == "instances" && "\${3:-}" == "delete" ]]; then
  exit 0
fi

if [[ "\$1" == "compute" && "\${2:-}" == "instances" && "\${3:-}" == "describe" ]]; then
  if [[ "\$*" == *"value(status)"* ]]; then
    printf '%s\n' "RUNNING"
  else
    printf '%s\n' "name: \${4:-}"
    printf '%s\n' "status: RUNNING"
  fi
  exit 0
fi

if [[ "\$1" == "compute" && "\${2:-}" == "instances" && "\${3:-}" == "get-serial-port-output" ]]; then
  printf '%s\n' "serial progress"
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
        */status.txt)
          printf '%s\n' "0" > "\$dst"
          ;;
        */ol-c-nix-cache.tar.gz)
          tmp="\$(mktemp -d)"
          mkdir -p "\${tmp}/ol-c-nix-cache"
          tar -C "\$tmp" -czf "\$dst" ol-c-nix-cache
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
  assert_contains "$output" "bucket:       gs://ol-c-test-project-ol-c-remote-builds"
  assert_contains "$output" "target:       .#firefox-localhost"
  assert_contains "$output" "machine:      h4d-standard-192"
  assert_contains "$output" "timeout:      1h"
  assert_contains "$output" "Would create Compute Engine VM:"
  assert_contains "$output" "gcloud compute instances create ol-c-firefox-"
  assert_contains "$output" "--machine-type=h4d-standard-192"
  assert_contains "$output" "--boot-disk-type=hyperdisk-balanced"
  assert_contains "$output" "--boot-disk-size=300GB"
  assert_contains "$output" "--image-family=ubuntu-2404-lts-amd64"
  assert_contains "$output" "--image-project=ubuntu-os-cloud"
  assert_contains "$output" "--scopes=https://www.googleapis.com/auth/cloud-platform"
  assert_contains "$output" "--maintenance-policy=TERMINATE"
  assert_contains "$output" "--max-run-duration=1h"
  assert_contains "$output" "--instance-termination-action=DELETE"
  assert_contains "$output" "--labels=ol-c-purpose=firefox-remote-build,ol-c-job=ol-c-firefox-"
  assert_contains "$output" '.#firefox-localhost'
  assert_contains "$output" "/tmp/ol-c-build.log"
  assert_contains "$output" "ol-c-nix-cache.tar.gz"
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

test_bucket_override_still_wins() {
  local output
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      OLC_GCP_BUCKET=custom-ol-c-builds \
      "${REMOTE_BUILD}" --dry-run
  )"

  assert_contains "$output" "bucket:       gs://custom-ol-c-builds"
  cleanup_case
}

test_interactive_identity_confirmation_can_continue() {
  local output
  setup_case

  output="$(
    printf '\n' | PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      OLC_GCP_CONFIRM_IDENTITY=1 \
      "${REMOTE_BUILD}" --dry-run
  )"

  assert_contains "$output" "Google Cloud launch identity:"
  assert_contains "$output" "account:       dev@example.com"
  assert_contains "$output" "project:       ol-c-test-project"
  assert_contains "$output" "Dry run only"
  cleanup_case
}

test_interactive_identity_confirmation_can_login() {
  local output calls
  setup_case

  output="$(
    printf '%s\n%s\n' "login" "yes" | PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      OLC_GCP_CONFIRM_IDENTITY=1 \
      OLC_FAKE_NO_ACTIVE_ACCOUNT=1 \
      OLC_FAKE_LOGIN_SETS_ACCOUNT=1 \
      "${REMOTE_BUILD}" --dry-run
  )"
  calls="$(cat "${CASE_TMP}/calls/gcloud")"

  assert_contains "$output" "Google Cloud launch identity:"
  assert_contains "$calls" "auth login --launch-browser"
  assert_contains "$output" "Dry run only"
  cleanup_case
}

test_interactive_identity_confirmation_can_switch_account() {
  local output calls selected
  setup_case

  output="$(
    printf '%s\n%s\n%s\n' "account" "other@example.com" "yes" | PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      OLC_GCP_CONFIRM_IDENTITY=1 \
      "${REMOTE_BUILD}" --dry-run
  )"
  calls="$(cat "${CASE_TMP}/calls/gcloud")"
  selected="$(cat "${CASE_TMP}/selected-account")"

  assert_contains "$output" "Credentialed Google Cloud accounts:"
  assert_contains "$calls" "config set account other@example.com"
  [[ "$selected" == "other@example.com" ]] || fail "expected selected account to be recorded"
  assert_contains "$output" "Dry run only"
  cleanup_case
}

test_interactive_identity_confirmation_can_switch_config() {
  local output calls selected
  setup_case

  output="$(
    printf '%s\n%s\n%s\n' "config" "other" "yes" | PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      OLC_GCP_CONFIRM_IDENTITY=1 \
      "${REMOTE_BUILD}" --dry-run
  )"
  calls="$(cat "${CASE_TMP}/calls/gcloud")"
  selected="$(cat "${CASE_TMP}/selected-config")"

  assert_contains "$output" "Available Google Cloud configurations:"
  assert_contains "$calls" "config configurations activate other"
  [[ "$selected" == "other" ]] || fail "expected selected config to be recorded"
  assert_contains "$output" "Dry run only"
  cleanup_case
}

test_bucket_create_and_vm_submit_contract() {
  local output calls
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${REMOTE_BUILD}" .#firefox-localhost
  )"
  calls="$(cat "${CASE_TMP}/calls/gcloud")"

  assert_contains "$output" "Creating staging bucket gs://ol-c-test-project-ol-c-remote-builds"
  assert_contains "$output" "Creating Compute Engine VM"
  assert_contains "$output" "VM submitted: ol-c-firefox-"
  assert_contains "$output" "Compute Engine will delete it after 1h"
  assert_contains "$calls" "storage buckets describe gs://ol-c-test-project-ol-c-remote-builds"
  assert_contains "$calls" "--quiet storage buckets create gs://ol-c-test-project-ol-c-remote-builds --location=us-central1 --uniform-bucket-level-access --public-access-prevention"
  assert_contains "$calls" "compute instances create ol-c-firefox-"
  assert_contains "$calls" "--maintenance-policy=TERMINATE"
  assert_contains "$calls" "--max-run-duration=1h"
  assert_contains "$calls" "--instance-termination-action=DELETE"
  assert_contains "$calls" "--labels=ol-c-purpose=firefox-remote-build,ol-c-job=ol-c-firefox-"
  [[ "$calls" != *"batch jobs"* ]] || fail "expected direct VM flow not Batch"
  cleanup_case
}

test_kill_deletes_compute_instance() {
  local output calls
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${REMOTE_BUILD}" --kill ol-c-firefox-test
  )"
  calls="$(cat "${CASE_TMP}/calls/gcloud")"

  assert_contains "$output" "Deleting Compute Engine VM ol-c-firefox-test"
  assert_contains "$calls" "--quiet compute instances delete ol-c-firefox-test --project=ol-c-test-project --zone=us-central1-a"
  cleanup_case
}

test_fetch_imports_downloaded_cache() {
  local output nix_calls
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      "${REMOTE_BUILD}" --fetch ol-c-firefox-test
  )"
  nix_calls="$(cat "${CASE_TMP}/calls/nix")"

  assert_contains "$output" "Downloading artifacts for ol-c-firefox-test"
  assert_contains "$output" "Remote result: /nix/store/test-firefox"
  assert_contains "$nix_calls" "copy --no-check-sigs --from file://${ROOT_DIR}/.gcp-builds/ol-c-firefox-test/ol-c-nix-cache /nix/store/test-firefox"
  [[ -L "${ROOT_DIR}/result-gcp-firefox-localhost" ]] || fail "expected fetch to update result symlink"
  rm -f "${ROOT_DIR}/result-gcp-firefox-localhost"
  rm -rf "${ROOT_DIR}/.gcp-builds/ol-c-firefox-test"
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
      "${REMOTE_BUILD}" --kill ol-c-firefox-test \
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

test_vm_create_failure_cleans_uploaded_source() {
  local output status calls
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:/usr/bin:/bin" \
      OLC_FAKE_VM_CREATE_FAIL=1 \
      "${REMOTE_BUILD}" .#firefox-localhost \
      2>&1
  )"
  status=$?
  set -e
  calls="$(cat "${CASE_TMP}/calls/gcloud")"

  [[ $status -ne 0 ]] || fail "expected VM creation failure to fail"
  assert_contains "$output" "VM creation failed"
  assert_contains "$output" "Cleaning up uploaded source artifacts at gs://ol-c-test-project-ol-c-remote-builds/runs/ol-c-firefox-"
  assert_contains "$calls" "--quiet storage rm --recursive gs://ol-c-test-project-ol-c-remote-builds/runs/ol-c-firefox-"
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
test_bucket_override_still_wins
test_interactive_identity_confirmation_can_continue
test_interactive_identity_confirmation_can_login
test_interactive_identity_confirmation_can_switch_account
test_interactive_identity_confirmation_can_switch_config
test_bucket_create_and_vm_submit_contract
test_bucket_create_failure_recommends_unique_bucket
test_vm_create_failure_cleans_uploaded_source
test_kill_deletes_compute_instance
test_fetch_imports_downloaded_cache
test_script_documents_archive_excludes

echo "PASS: build-firefox-remote"
