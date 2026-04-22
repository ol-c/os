#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
REMOTE_BUILD="${ROOT_DIR}/build-firefox-remote"
SOURCE_REMOTE_BUILD="${ROOT_DIR}/build-firefox-source-remote"
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
  unset OLC_GCP_LOCAL_BUILDS_DIR
  unset OLC_GCP_RESULT_LINK
  unset OLC_GCP_TIMEOUT
}

setup_case() {
  cleanup_case
  mkdir -p "$TEST_TMP_ROOT"
  CASE_TMP="$(mktemp -d "${TEST_TMP_ROOT}/remote.XXXXXX")"
  export OLC_GCP_LOCAL_BUILDS_DIR="${CASE_TMP}/gcp-builds"
  export OLC_GCP_RESULT_LINK="${CASE_TMP}/result-gcp-firefox-localhost"
  mkdir -p "${CASE_TMP}/fakebin" "${CASE_TMP}/calls"

  cat >"${CASE_TMP}/fakebin/gcloud" <<EOF
#!${TEST_FAKE_BASH}
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
          if [[ "\${OLC_FAKE_NO_STATUS:-0}" == "1" ]]; then
            exit 1
          fi
          if [[ "\${OLC_FAKE_STATUS_AFTER_PROGRESS:-0}" == "1" && ! -f "${CASE_TMP}/status-polled" ]]; then
            : > "${CASE_TMP}/status-polled"
            exit 1
          fi
          printf '%s\n' "0" > "\$dst"
          ;;
        */progress.json)
          if [[ "\${OLC_FAKE_NO_PROGRESS:-0}" == "1" ]]; then
            exit 1
          fi
          printf '%s\n' '{"status":"running","phase":"nix-build","percent":63,"message":"building Firefox","started_at":"2026-04-20T01:00:00Z","updated_at":"2026-04-20T01:02:00Z","elapsed_seconds":120,"eta_seconds":300,"exit_status":null,"target":".#firefox-localhost","machine_type":"c2-standard-30","boot_disk_type":"pd-ssd","boot_disk_size":"300GB","zone":"us-central1-a"}' > "\$dst"
          ;;
        */timings.json)
          printf '%s\n' '{"status":"succeeded","target":".#firefox-localhost","machine_type":"c2-standard-30","boot_disk_type":"pd-ssd","boot_disk_size":"300GB","zone":"us-central1-a","started_at":"2026-04-20T01:00:00Z","finished_at":"2026-04-20T01:10:00Z","total_seconds":600,"phases":{"host-tools":10,"google-cloud-cli":20,"nix-install":30,"source-download":5,"nix-build":500,"closure-export":20,"result-upload":15}}' > "\$dst"
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
#!${TEST_FAKE_BASH}
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      "${REMOTE_BUILD}" --dry-run
  )"

  assert_contains "$output" "Google Cloud configurations:"
  assert_contains "$output" "Google Cloud auth accounts:"
  assert_contains "$output" "bucket:       gs://ol-c-test-project-ol-c-remote-builds"
  assert_contains "$output" "target:       .#firefox-localhost"
  assert_contains "$output" "machine:      c2-standard-30"
  assert_contains "$output" "boot disk:    pd-ssd, 300GB"
  assert_contains "$output" "timeout:      1h"
  assert_contains "$output" "Would create Compute Engine VM:"
  assert_contains "$output" "gcloud compute instances create ol-c-firefox-"
  assert_contains "$output" "--machine-type=c2-standard-30"
  assert_contains "$output" "--boot-disk-type=pd-ssd"
  assert_contains "$output" "--boot-disk-size=300GB"
  assert_contains "$output" "--image-family=ubuntu-2404-lts-amd64"
  assert_contains "$output" "--image-project=ubuntu-os-cloud"
  assert_contains "$output" "--scopes=https://www.googleapis.com/auth/cloud-platform"
  assert_contains "$output" "--maintenance-policy=TERMINATE"
  assert_contains "$output" "--max-run-duration=1h"
  assert_contains "$output" "--instance-termination-action=DELETE"
  assert_contains "$output" "--labels=ol-c-purpose=firefox-remote-build,ol-c-job=ol-c-firefox-"
  assert_contains "$output" '.#firefox-localhost'
  assert_contains "$output" "export HOME=/root"
  assert_contains "$output" "trap 'status=\$?; set +e; finish_with_status \"\$status\"; self_delete_or_shutdown; exit \"\$status\"' ERR"
  assert_contains "$output" "export NIX_CONFIG='experimental-features = nix-command flakes'"
  assert_contains "$output" "write_progress()"
  assert_contains "$output" "write_timings()"
  assert_contains "$output" "progress.json"
  assert_contains "$output" "timings.json"
  assert_contains "$output" "phase_begin nix-build 50"
  assert_contains "$output" "/tmp/ol-c-build.log"
  assert_contains "$output" "ol-c-nix-cache.tar.gz"
  cleanup_case
}

test_dry_run_allows_target_override() {
  local output
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      "${REMOTE_BUILD}" --dry-run .#ol-c-image
  )"

  assert_contains "$output" "target:       .#ol-c-image"
  assert_contains "$output" '.#ol-c-image'
  cleanup_case
}

test_source_remote_dry_run_uses_source_target() {
  local output
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      "${SOURCE_REMOTE_BUILD}" --dry-run
  )"

  assert_contains "$output" "target:       .#firefox-localhost-source"
  assert_contains "$output" "timeout:      1h"
  assert_contains "$output" '.#firefox-localhost-source'
  assert_contains "$output" 'nix build "$BUILD_TARGET" --print-build-logs'
  cleanup_case
}

test_source_remote_respects_timeout_override() {
  local output
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_GCP_TIMEOUT=45m \
      "${SOURCE_REMOTE_BUILD}" --dry-run
  )"

  assert_contains "$output" "target:       .#firefox-localhost-source"
  assert_contains "$output" "timeout:      45m"
  assert_contains "$output" "--max-run-duration=45m"
  cleanup_case
}

test_source_remote_management_does_not_append_target() {
  local output calls
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      "${SOURCE_REMOTE_BUILD}" --status ol-c-firefox-test
  )"
  calls="$(cat "${CASE_TMP}/calls/gcloud" 2>/dev/null || true)"

  assert_contains "$output" "Job: ol-c-firefox-test"
  assert_contains "$output" "Progress: 63% nix-build: building Firefox"
  [[ "$output" != *"TARGET can only be used"* ]] || fail "source remote should not append target in management mode"
  [[ "$calls" != *"compute instances create"* ]] || fail "source remote status mode should not create a VM"
  cleanup_case
}

test_bucket_override_still_wins() {
  local output
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_GCP_BUCKET=custom-ol-c-builds \
      "${REMOTE_BUILD}" --dry-run
  )"

  assert_contains "$output" "bucket:       gs://custom-ol-c-builds"
  cleanup_case
}

test_no_wait_submits_without_fetching_result() {
  local output calls
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      "${REMOTE_BUILD}" --no-wait .#firefox-localhost
  )"
  calls="$(cat "${CASE_TMP}/calls/gcloud" 2>/dev/null || true)"

  assert_contains "$output" "VM submitted: ol-c-firefox-"
  assert_contains "$output" "Not waiting for ol-c-firefox-"
  assert_contains "$output" "--status ol-c-firefox-"
  assert_contains "$output" "--logs ol-c-firefox-"
  assert_contains "$output" "--fetch ol-c-firefox-"
  assert_contains "$calls" "compute instances create ol-c-firefox-"
  [[ ! -s "${CASE_TMP}/calls/nix" ]] || fail "no-wait should not fetch and import the result"
  [[ "$output" != *"Downloading artifacts"* ]] || fail "no-wait should not fetch artifacts"
  cleanup_case
}

test_invalid_timeout_fails_before_bucket_creation() {
  local output status calls
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_GCP_TIMEOUT=soon \
      "${REMOTE_BUILD}" --dry-run \
      2>&1
  )"
  status=$?
  set -e
  calls="$(cat "${CASE_TMP}/calls/gcloud" 2>/dev/null || true)"

  [[ $status -ne 0 ]] || fail "expected invalid timeout to fail"
  assert_contains "$output" "invalid OLC_GCP_TIMEOUT: soon"
  [[ "$calls" != *"storage buckets create"* ]] || fail "invalid timeout should stop before bucket creation"
  [[ "$calls" != *"compute instances create"* ]] || fail "invalid timeout should stop before VM creation"
  cleanup_case
}

test_invalid_disk_size_fails_before_bucket_creation() {
  local output status calls
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_GCP_BOOT_DISK_SIZE=large \
      "${REMOTE_BUILD}" --dry-run \
      2>&1
  )"
  status=$?
  set -e
  calls="$(cat "${CASE_TMP}/calls/gcloud" 2>/dev/null || true)"

  [[ $status -ne 0 ]] || fail "expected invalid disk size to fail"
  assert_contains "$output" "invalid OLC_GCP_BOOT_DISK_SIZE: large"
  [[ "$calls" != *"storage buckets create"* ]] || fail "invalid disk size should stop before bucket creation"
  [[ "$calls" != *"compute instances create"* ]] || fail "invalid disk size should stop before VM creation"
  cleanup_case
}

test_management_mode_rejects_extra_target() {
  local output status calls
  setup_case

  set +e
  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      "${REMOTE_BUILD}" --status ol-c-firefox-test .#firefox-localhost \
      2>&1
  )"
  status=$?
  set -e
  calls="$(cat "${CASE_TMP}/calls/gcloud" 2>/dev/null || true)"

  [[ $status -ne 0 ]] || fail "expected management mode extra target to fail"
  assert_contains "$output" "TARGET can only be used when submitting a build"
  [[ "$calls" != *"compute instances create"* ]] || fail "status mode should not create a VM"
  cleanup_case
}

test_interactive_identity_confirmation_can_continue() {
  local output
  setup_case

  output="$(
    printf '\n' | PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    printf '%s\n%s\n' "login" "yes" | PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    printf '%s\n%s\n%s\n' "account" "other@example.com" "yes" | PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    printf '%s\n%s\n%s\n' "config" "other" "yes" | PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      "${REMOTE_BUILD}" --fetch ol-c-firefox-test
  )"
  nix_calls="$(cat "${CASE_TMP}/calls/nix")"

  assert_contains "$output" "Downloading artifacts for ol-c-firefox-test"
  assert_contains "$output" "Remote result: /nix/store/test-firefox"
  assert_contains "$nix_calls" "copy --no-check-sigs --from file://${OLC_GCP_LOCAL_BUILDS_DIR}/ol-c-firefox-test/ol-c-nix-cache /nix/store/test-firefox"
  [[ -s "${OLC_GCP_LOCAL_BUILDS_DIR}/timing-history.tsv" ]] || fail "expected fetch to save timing history"
  [[ -L "${OLC_GCP_RESULT_LINK}" ]] || fail "expected fetch to update result symlink"
  cleanup_case
}

test_status_prints_progress_artifact() {
  local output
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      "${REMOTE_BUILD}" --status ol-c-firefox-test
  )"

  assert_contains "$output" "Job: ol-c-firefox-test"
  assert_contains "$output" "Progress: 63% nix-build: building Firefox"
  assert_contains "$output" "elapsed 2m00s"
  assert_contains "$output" "eta 5m00s"
  cleanup_case
}

test_status_handles_missing_progress_artifact() {
  local output
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_FAKE_NO_PROGRESS=1 \
      OLC_FAKE_NO_STATUS=1 \
      "${REMOTE_BUILD}" --status ol-c-firefox-test
  )"

  assert_contains "$output" "Remote status: not uploaded"
  assert_contains "$output" "Progress: not uploaded"
  cleanup_case
}

test_wait_loop_prints_progress_and_saves_timings() {
  local output
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
      OLC_FAKE_STATUS_AFTER_PROGRESS=1 \
      OLC_GCP_POLL_INTERVAL=1 \
      "${REMOTE_BUILD}" .#firefox-localhost
  )"

  assert_contains "$output" "Remote progress ol-c-firefox-"
  assert_contains "$output" "63% nix-build: building Firefox"
  assert_contains "$output" "Remote build ol-c-firefox-"
  [[ -s "${OLC_GCP_LOCAL_BUILDS_DIR}/timing-history.tsv" ]] || fail "expected wait loop to save timing history"
  cleanup_case
}

test_submit_launches_browser_login_when_account_missing() {
  local output calls
  setup_case

  output="$(
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    printf '%s\n' "chosen-project" | PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
    PATH="${CASE_TMP}/fakebin:${TEST_SYSTEM_PATH}" \
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
test_source_remote_dry_run_uses_source_target
test_source_remote_respects_timeout_override
test_source_remote_management_does_not_append_target
test_bucket_override_still_wins
test_no_wait_submits_without_fetching_result
test_invalid_timeout_fails_before_bucket_creation
test_invalid_disk_size_fails_before_bucket_creation
test_management_mode_rejects_extra_target
test_interactive_identity_confirmation_can_continue
test_interactive_identity_confirmation_can_login
test_interactive_identity_confirmation_can_switch_account
test_interactive_identity_confirmation_can_switch_config
test_bucket_create_and_vm_submit_contract
test_bucket_create_failure_recommends_unique_bucket
test_vm_create_failure_cleans_uploaded_source
test_kill_deletes_compute_instance
test_fetch_imports_downloaded_cache
test_status_prints_progress_artifact
test_status_handles_missing_progress_artifact
test_wait_loop_prints_progress_and_saves_timings
test_script_documents_archive_excludes

echo "PASS: build-firefox-remote"
