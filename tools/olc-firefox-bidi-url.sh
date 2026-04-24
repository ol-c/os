#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: olc-firefox-bidi-url [--base]

Print the active signed-in Firefox WebDriver BiDi URL for the current ol-c GUI
session. By default this prints the full session WebSocket URL. Use `--base`
to print the base WebSocket URL before the `/session` suffix.
EOF
}

fail() {
  echo "error: $*" >&2
  exit 1
}

parse_property() {
  local input="$1"
  local key="$2"

  printf '%s\n' "$input" | sed -n "s/^${key}=//p" | sed -n '1p'
}

output_mode="session"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --base)
      output_mode="base"
      shift
      ;;
    --help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

loginctl_bin="${OLC_LOGINCTL:-loginctl}"
getent_bin="${OLC_GETENT:-getent}"
seat_name="${OLC_FIREFOX_BIDI_SEAT:-seat0}"

active_session="$("$loginctl_bin" show-seat "$seat_name" --property=ActiveSession --value 2>/dev/null || true)"
active_session="$(printf '%s\n' "$active_session" | sed -n '1p')"
[[ -n "$active_session" ]] || fail "no active ${seat_name} session"

session_info="$("$loginctl_bin" show-session "$active_session" \
  --property=Name \
  --property=Class \
  --property=Remote \
  --property=State \
  2>/dev/null || true)"

session_name="$(parse_property "$session_info" Name)"
session_class="$(parse_property "$session_info" Class)"
session_remote="$(parse_property "$session_info" Remote)"
session_state="$(parse_property "$session_info" State)"

[[ -n "$session_name" ]] || fail "active session ${active_session} does not have a user name"
[[ "$session_class" == "user" ]] || fail "active session ${active_session} is not a user session"
[[ "$session_remote" != "yes" ]] || fail "active session ${active_session} is remote"
if [[ -n "$session_state" && "$session_state" != "active" ]]; then
  fail "active session ${active_session} is not active"
fi

passwd_entry="$("$getent_bin" passwd "$session_name" 2>/dev/null || true)"
[[ -n "$passwd_entry" ]] || fail "unable to resolve passwd entry for ${session_name}"

session_uid="$(printf '%s\n' "$passwd_entry" | cut -d: -f3)"
[[ -n "$session_uid" ]] || fail "unable to resolve uid for ${session_name}"

bidi_env_path="${OLC_FIREFOX_BIDI_ENV_PATH:-/run/user/${session_uid}/ol-c-firefox/bidi.env}"
[[ -f "$bidi_env_path" ]] || fail "Firefox BiDi metadata file not found: ${bidi_env_path}"

bidi_session_url="$(sed -n 's/^OLC_FIREFOX_BIDI_WS_URL=//p' "$bidi_env_path" | sed -n '1p')"
bidi_base_url="$(sed -n 's/^OLC_FIREFOX_BIDI_BASE_URL=//p' "$bidi_env_path" | sed -n '1p')"

case "$output_mode" in
  session)
    [[ -n "$bidi_session_url" ]] || fail "Firefox BiDi session URL is not available yet in ${bidi_env_path}"
    printf '%s\n' "$bidi_session_url"
    ;;
  base)
    [[ -n "$bidi_base_url" ]] || fail "Firefox BiDi base URL is not available yet in ${bidi_env_path}"
    printf '%s\n' "$bidi_base_url"
    ;;
esac
