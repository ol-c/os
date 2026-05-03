{ config, lib, pkgs, ... }:

let
  localhostTls = config.olc.localhost.tlsPackage;
  firefoxBin = "${pkgs.firefox-unwrapped}/lib/firefox/firefox";
  greeterPort = 9444;
  greeterUrl = "https://localhost:${toString greeterPort}/login";
  loginGreeterUi = pkgs.runCommand "olc-login-greeter-ui" {} ''
    mkdir -p "$out"
    install -m 0444 ${../../localhost-ui/login-accounts.mjs} "$out/login-accounts.mjs"
    install -m 0444 ${../../localhost-ui/greetd-client.mjs} "$out/greetd-client.mjs"
    install -m 0444 ${../../localhost-ui/login-greeter-app.mjs} "$out/login-greeter-app.mjs"
    install -m 0444 ${../../localhost-ui/login-greeter-page.mjs} "$out/login-greeter-page.mjs"
    install -m 0444 ${../../localhost-ui/login-greeter.mjs} "$out/login-greeter.mjs"
  '';
  bidiRecorder = pkgs.writeShellScript "olc-firefox-bidi-recorder" ''
    set -euo pipefail

    bidi_env_path="$1"
    bidi_log_path="$2"
    launcher_pid="$3"

    mkdir -p "$(dirname "$bidi_env_path")"
    : > "$bidi_env_path"

    for _ in $(seq 1 600); do
      bidi_base_url="$(${pkgs.gnused}/bin/sed -n 's/^WebDriver BiDi listening on \(ws:\/\/127\.0\.0\.1:[0-9][0-9]*\)$/\1/p' "$bidi_log_path" | tail -n 1)"
      if [ -n "$bidi_base_url" ]; then
        {
          printf 'OLC_FIREFOX_BIDI_ENABLED=1\n'
          printf 'OLC_FIREFOX_BIDI_PORT=0\n'
          printf 'OLC_FIREFOX_BIDI_BASE_URL=%s\n' "$bidi_base_url"
          printf 'OLC_FIREFOX_BIDI_WS_URL=%s/session\n' "$bidi_base_url"
        } > "$bidi_env_path"
        exit 0
      fi

      if ! kill -0 "$launcher_pid" 2>/dev/null; then
        exit 0
      fi

      sleep 0.1
    done

    exit 0
  '';
  olcPanectl = pkgs.writeShellApplication {
    name = "olc-panectl";
    runtimeInputs = [
      pkgs.coreutils
      pkgs.gnugrep
      pkgs.i3
      pkgs.jq
    ];
    text = builtins.readFile ../../tools/olc-panectl;
  };
  sessionPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.curl
    pkgs.findutils
    pkgs.i3
    pkgs.jq
    pkgs.matchbox
    olcPanectl
    pkgs.spice-vdagent
    pkgs.systemd
    pkgs.util-linux
    pkgs.xdotool
    pkgs.xorg.xauth
    pkgs.xorg.xinit
    pkgs.xorg.xrandr
    pkgs.xorg.xsetroot
  ];
  screenResizeWatcher = pkgs.writeShellScript "olc-screen-resize-watcher" ''
    set -u

    session_pid="''${1:-}"
    min_width=320
    min_height=240
    max_width=4096
    max_height=2160
    last_rejected_target=""

    log() {
      printf 'olc-screen-resize-watcher %s\n' "$*"
    }

    while true; do
      if [ -n "$session_pid" ] && ! kill -0 "$session_pid" 2>/dev/null; then
        exit 0
      fi

      if ! query="$(${pkgs.xorg.xrandr}/bin/xrandr --verbose --prop 2>/dev/null)"; then
        sleep 0.2
        continue
      fi

      state="$(
        printf '%s\n' "$query" | ${pkgs.gawk}/bin/awk '
          function byte(hex, offset) {
            return strtonum("0x" substr(hex, (offset * 2) + 1, 2))
          }
          function edid_size(hex, hactive_lo, hhigh, vactive_lo, vhigh, width, height) {
            gsub(/[[:space:]]/, "", hex)
            if (length(hex) < 144) {
              return ""
            }
            if (byte(hex, 54) == 0 && byte(hex, 55) == 0) {
              return ""
            }
            hactive_lo = byte(hex, 56)
            hhigh = byte(hex, 58)
            vactive_lo = byte(hex, 59)
            vhigh = byte(hex, 61)
            width = hactive_lo + (and(hhigh, 0xf0) * 16)
            height = vactive_lo + (and(vhigh, 0xf0) * 16)
            if (width > 0 && height > 0) {
              return width "x" height
            }
            return ""
          }
          function finish_edid() {
            if (reading_edid) {
              edid_preferred = edid_size(edid_hex)
              reading_edid = 0
              edid_hex = ""
            }
          }
          $2 == "connected" && output == "" {
            output = $1
            in_output = 1
            next
          }
          /^[^[:space:]]/ {
            finish_edid()
            in_output = 0
          }
          in_output && /^[[:space:]]+EDID:/ {
            reading_edid = 1
            edid_hex = ""
            next
          }
          reading_edid {
            if ($1 ~ /^[0-9a-fA-F]+$/) {
              edid_hex = edid_hex $1
              next
            }
            finish_edid()
          }
          in_output && $1 ~ /^[0-9]+x[0-9]+$/ {
            mode_by_size[$1] = $1
            if ($0 ~ /\*/) {
              current = $1
              current_size = $1
            }
            if ($0 ~ /\+/) {
              preferred = $1
            }
          }
          END {
            finish_edid()
            if (output != "") {
              edid_mode = mode_by_size[edid_preferred]
              printf "%s\t%s\t%s\t%s\t%s\t%s\n", output, current, current_size, preferred, edid_preferred, edid_mode
            }
          }
        '
      )"

      if [ -z "$state" ]; then
        sleep 0.2
        continue
      fi

      IFS=$'\t' read -r output current_mode current_size preferred_mode edid_preferred edid_mode <<< "$state"

      target_mode=""
      target_size=""
      target_source=""
      if [ -n "$edid_mode" ] && [ "$edid_preferred" != "$current_size" ]; then
        target_mode="$edid_mode"
        target_size="$edid_preferred"
        target_source="edid-preferred"
      elif [ -z "$edid_preferred" ] && [ -n "$preferred_mode" ] && [ "$preferred_mode" != "$current_mode" ]; then
        target_mode="$preferred_mode"
        target_size="$preferred_mode"
        target_source="randr-marker"
      fi

      if [ -z "$target_mode" ]; then
        sleep 0.2
        continue
      fi

      if [[ ! "$target_size" =~ ^([0-9]+)x([0-9]+)$ ]]; then
        rejected_target="$output:$target_mode"
        if [ "$rejected_target" != "$last_rejected_target" ]; then
          log "rejecting output=$output target=$target_mode source=$target_source reason=invalid-mode-name"
          last_rejected_target="$rejected_target"
        fi
        sleep 0.2
        continue
      fi

      width="''${BASH_REMATCH[1]}"
      height="''${BASH_REMATCH[2]}"
      if (( width < min_width || width > max_width || height < min_height || height > max_height )); then
        rejected_target="$output:$target_mode"
        if [ "$rejected_target" != "$last_rejected_target" ]; then
          log "rejecting output=$output target=$target_mode source=$target_source reason=outside-bounds"
          last_rejected_target="$rejected_target"
        fi
        sleep 0.2
        continue
      fi

      last_rejected_target=""
      log "applying output=$output current=''${current_mode:-unknown} target=$target_mode source=$target_source"
      if ! ${pkgs.xorg.xrandr}/bin/xrandr --output "$output" --mode "$target_mode"; then
        log "apply_failed output=$output target=$target_mode source=$target_source"
      fi
      sleep 0.2
    done
  '';
  userSessionScript = pkgs.writeShellScript "olc-user-xsession" ''
    ${userXinitRc {
      startUrl = "https://localhost";
      kiosk = false;
    }}
  '';
  setupSessionScript = pkgs.writeShellScript "olc-setup-xsession" ''
    ${userXinitRc {
      startUrl = "https://localhost/setup";
      kiosk = true;
    }}
  '';
  fastBootCheck = ''
    olc_fast_boot=0
    if [ -r /sys/class/dmi/id/product_serial ] \
      && ${pkgs.coreutils}/bin/tr -d '\n' < /sys/class/dmi/id/product_serial | ${pkgs.gnugrep}/bin/grep -Fq 'olc-fast-boot=1'; then
      olc_fast_boot=1
    fi
  '';
  waitForDisplayZeroRelease = ''
    display_zero_busy() {
      if ${pkgs.procps}/bin/pgrep -x Xorg >/dev/null 2>&1; then
        return 0
      fi
      if ${pkgs.procps}/bin/pgrep -x X >/dev/null 2>&1; then
        return 0
      fi
      if ${pkgs.procps}/bin/pgrep -x Xorg.wrap >/dev/null 2>&1; then
        return 0
      fi
      if [ -e /tmp/.X0-lock ] || [ -e /tmp/.tX0-lock ] || [ -S /tmp/.X11-unix/X0 ]; then
        return 0
      fi
      return 1
    }

    log_display_zero_state() {
      printf 'display_zero_state=%s\n' "$1"
      ls -ld /tmp /tmp/.X11-unix 2>/dev/null || true
      ls -l /tmp/.X0-lock /tmp/.tX0-lock /tmp/.X11-unix/X0 2>/dev/null || true
    }

    log_display_zero_state before-wait
    for _ in $(seq 1 150); do
      if ! display_zero_busy; then
        break
      fi
      if ! ${pkgs.procps}/bin/pgrep -x Xorg >/dev/null 2>&1 \
        && ! ${pkgs.procps}/bin/pgrep -x X >/dev/null 2>&1 \
        && ! ${pkgs.procps}/bin/pgrep -x Xorg.wrap >/dev/null 2>&1; then
        rm -f /tmp/.X0-lock /tmp/.tX0-lock /tmp/.X11-unix/X0
      fi
      if ! display_zero_busy; then
        break
      fi
      sleep 0.1
    done
    log_display_zero_state after-wait
  '';
  startxWithRetry = sessionScript: ''
    startx_status=1
    for attempt in $(seq 1 3); do
      ${waitForDisplayZeroRelease}
      if ${pkgs.xorg.xinit}/bin/startx ${sessionScript}; then
        exit 0
      fi
      startx_status=$?
      printf 'startx attempt %s failed with status=%s\n' "$attempt" "$startx_status"
      if ! ${pkgs.procps}/bin/pgrep -x Xorg >/dev/null 2>&1 \
        && ! ${pkgs.procps}/bin/pgrep -x X >/dev/null 2>&1 \
        && ! ${pkgs.procps}/bin/pgrep -x Xorg.wrap >/dev/null 2>&1; then
        rm -f /tmp/.X0-lock /tmp/.tX0-lock /tmp/.X11-unix/X0
      fi
      sleep 0.2
    done
    exit "$startx_status"
  '';
  greetdUserSessionCommand = pkgs.writeShellScript "olc-greetd-user-session" ''
    export PATH='${sessionPath}:$PATH'
    exec > >(${pkgs.systemd}/bin/systemd-cat --identifier=olc-greetd-session) 2>&1
    set -x
    printf 'mode=user uid=%s user=%s home=%s shell=%s pwd=%s xdg_runtime_dir=%s command=%s\n' \
      "$(id -u)" "$(id -un)" "$HOME" "$SHELL" "$PWD" "''${XDG_RUNTIME_DIR-}" \
      "${pkgs.xorg.xinit}/bin/startx ${userSessionScript}"
    ${pkgs.getent}/bin/getent passwd "$(id -un)" || true
    ${pkgs.systemd}/bin/loginctl show-user "$(id -un)" || true
    ${startxWithRetry userSessionScript}
  '';
  greetdSetupSessionCommand = pkgs.writeShellScript "olc-greetd-setup-session" ''
    export PATH='${sessionPath}:$PATH'
    exec > >(${pkgs.systemd}/bin/systemd-cat --identifier=olc-greetd-session) 2>&1
    set -x
    printf 'mode=setup uid=%s user=%s home=%s shell=%s pwd=%s xdg_runtime_dir=%s command=%s\n' \
      "$(id -u)" "$(id -un)" "$HOME" "$SHELL" "$PWD" "''${XDG_RUNTIME_DIR-}" \
      "${pkgs.xorg.xinit}/bin/startx ${setupSessionScript}"
    ${pkgs.getent}/bin/getent passwd "$(id -un)" || true
    ${pkgs.systemd}/bin/loginctl show-user "$(id -un)" || true
    ${startxWithRetry setupSessionScript}
  '';
  greetdBrowserGreeterCommand = pkgs.writeShellScript "olc-greetd-browser-greeter" ''
    export PATH='${sessionPath}:$PATH'
    exec > >(${pkgs.systemd}/bin/systemd-cat --identifier=olc-greetd-session) 2>&1
    set -x
    printf 'mode=greeter uid=%s user=%s home=%s shell=%s pwd=%s xdg_runtime_dir=%s command=%s\n' \
      "$(id -u)" "$(id -un)" "$HOME" "$SHELL" "$PWD" "''${XDG_RUNTIME_DIR-}" \
      "${pkgs.xorg.xinit}/bin/startx ${greeterSessionScript}"
    ${pkgs.getent}/bin/getent passwd "$(id -un)" || true
    ${pkgs.systemd}/bin/loginctl show-user "$(id -un)" || true
    ${startxWithRetry greeterSessionScript}
  '';
  userProfileScript = ''
    mkdir -p "$HOME/.mozilla/firefox/ol-c.default"
    cat > "$HOME/.mozilla/firefox/profiles.ini" <<'OLC_PROFILES'
    [Profile0]
    Name=default
    IsRelative=1
    Path=ol-c.default
    Default=1

    [General]
    StartWithLastProfile=1
    Version=2
    OLC_PROFILES
    cat > "$HOME/.mozilla/firefox/ol-c.default/user.js" <<'OLC_USERJS'
    user_pref("browser.tabs.inTitlebar", 1);
    user_pref("browser.tabs.drawInTitlebar", true);
    user_pref("browser.tabs.closeWindowWithLastTab", false);
    user_pref("browser.aboutwelcome.enabled", false);
    user_pref("browser.shell.checkDefaultBrowser", false);
    user_pref("browser.startup.homepage", "https://localhost");
    user_pref("browser.startup.homepage_override.mstone", "ignore");
    user_pref("browser.startup.page", 1);
    user_pref("browser.toolbars.bookmarks.visibility", "never");
    user_pref("datareporting.policy.dataSubmissionEnabled", false);
    user_pref("datareporting.policy.firstRunURL", "");
    user_pref("security.enterprise_roots.enabled", true);
    user_pref("startup.homepage_override_url", "");
    user_pref("startup.homepage_welcome_url", "");
    user_pref("startup.homepage_welcome_url.additional", "");
    user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
    OLC_USERJS
  '';
  greeterProfileScript = ''
    mkdir -p "$HOME/.mozilla/firefox/ol-c.greeter"
    cat > "$HOME/.mozilla/firefox/profiles.ini" <<'OLC_GREETER_PROFILES'
    [Profile0]
    Name=greeter
    IsRelative=1
    Path=ol-c.greeter
    Default=1

    [General]
    StartWithLastProfile=1
    Version=2
    OLC_GREETER_PROFILES
    cat > "$HOME/.mozilla/firefox/ol-c.greeter/user.js" <<'OLC_GREETER_USERJS'
    user_pref("browser.aboutwelcome.enabled", false);
    user_pref("browser.sessionstore.resume_from_crash", false);
    user_pref("browser.shell.checkDefaultBrowser", false);
    user_pref("browser.startup.homepage", "${greeterUrl}");
    user_pref("browser.startup.homepage_override.mstone", "ignore");
    user_pref("browser.startup.page", 1);
    user_pref("dom.disable_beforeunload", true);
    user_pref("extensions.getAddons.showPane", false);
    user_pref("security.enterprise_roots.enabled", true);
    user_pref("signon.rememberSignons", false);
    user_pref("startup.homepage_override_url", "");
    user_pref("startup.homepage_welcome_url", "");
    user_pref("startup.homepage_welcome_url.additional", "");
    user_pref("toolkit.telemetry.reportingpolicy.firstRun", false);
    OLC_GREETER_USERJS
  '';
  firefoxLaunchArgs = { startUrl, kiosk ? false }:
    lib.concatStringsSep " " (
      [
        firefoxBin
        "--no-remote"
        ''--profile "$HOME/.mozilla/firefox/ol-c.default"''
        "--remote-debugging-port 0"
        "--remote-allow-hosts localhost,127.0.0.1"
      ]
      ++ lib.optional kiosk "--kiosk"
      ++ [ "--new-window ${startUrl}" ]
    );
  greeterSessionScript = pkgs.writeShellScript "olc-greeter-xsession" ''
    export PATH='${sessionPath}:$PATH'
    exec > >(${pkgs.systemd}/bin/systemd-cat --identifier=olc-greeter-xsession) 2>&1
    export PS4='+greeter-xsession:''${LINENO}: '
    set -x
    xsetroot -solid "#0f172a"
    ${screenResizeWatcher} "$$" &
    ${pkgs.spice-vdagent}/bin/spice-vdagent &
    matchbox-window-manager -use_titlebar no -use_cursor yes &
    ${greeterProfileScript}
    greeter_runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ol-c-greeter"
    mkdir -p "$greeter_runtime_dir"
    OLC_GREETD_LOGIN_CMD='${greetdUserSessionCommand}' \
      OLC_GETENT='${pkgs.getent}/bin/getent' \
      OLC_HOMECTL='${pkgs.systemd}/bin/homectl' \
      OLC_GREETER_PORT='${toString greeterPort}' \
      OLC_GREETER_EXCLUDE_USERS='root,nobody,olc-setup,olc-greeter' \
      OLC_GREETER_MIN_UID='1000' \
      OLC_GREETER_MAX_UID='60000' \
      OLC_TLS_CERT='${localhostTls}/server.crt' \
      OLC_TLS_KEY='${localhostTls}/server.key' \
      ${pkgs.nodejs}/bin/node ${loginGreeterUi}/login-greeter.mjs &
    greeter_server_pid="$!"
    for _ in $(seq 1 50); do
      if curl --silent --fail --cacert ${localhostTls}/ca.crt ${greeterUrl} >/dev/null; then
        break
      fi
      if ! kill -0 "$greeter_server_pid" 2>/dev/null; then
        wait "$greeter_server_pid"
        exit $?
      fi
      sleep 0.1
    done
    ${firefoxBin} --no-remote --profile "$HOME/.mozilla/firefox/ol-c.greeter" --kiosk --new-window ${greeterUrl} >/dev/null 2>&1 &
    greeter_firefox_pid="$!"
    while kill -0 "$greeter_server_pid" 2>/dev/null; do
      if ! kill -0 "$greeter_firefox_pid" 2>/dev/null; then
        kill "$greeter_server_pid" 2>/dev/null || true
        wait "$greeter_server_pid" || true
        exit 1
      fi
      sleep 0.2
    done
    wait "$greeter_server_pid"
    greeter_status="$?"
    kill "$greeter_firefox_pid" 2>/dev/null || true
    wait "$greeter_firefox_pid" 2>/dev/null || true
    exit "$greeter_status"
  '';
  userXinitRc = { startUrl, kiosk ? false }: ''
    export PATH='${sessionPath}:$PATH'
    exec > >(${pkgs.systemd}/bin/systemd-cat --identifier=olc-xsession) 2>&1
    export PS4='+xsession:''${LINENO}: '
    set -x
    printf 'uid=%s user=%s home=%s pwd=%s start_url=%s kiosk=%s\n' \
      "$(id -u)" "$(id -un)" "$HOME" "$PWD" "${startUrl}" "${if kiosk then "1" else "0"}"
    ${fastBootCheck}
    printf 'olc_fast_boot=%s\n' "$olc_fast_boot"
    olc_uint() {
      local value="$1"
      local fallback="$2"
      local min="$3"
      local max="$4"
      if ! [[ "$value" =~ ^[0-9]+$ ]]; then
        value="$fallback"
      fi
      if (( value < min )); then
        value="$min"
      fi
      if (( value > max )); then
        value="$max"
      fi
      printf '%s\n' "$value"
    }
    olc_color() {
      local value="$1"
      local fallback="$2"
      if [[ "$value" =~ ^#[0-9A-Fa-f]{6}$ ]]; then
        printf '%s\n' "$value"
      else
        printf '%s\n' "$fallback"
      fi
    }

    OLC_PANE_RESIZE_BORDER_PX="$(olc_uint "''${OLC_PANE_RESIZE_BORDER_PX:-8}" 8 0 32)"
    OLC_PANE_MIN_WIDTH_PX="$(olc_uint "''${OLC_PANE_MIN_WIDTH_PX:-320}" 320 160 4096)"
    OLC_PANE_MIN_HEIGHT_PX="$(olc_uint "''${OLC_PANE_MIN_HEIGHT_PX:-240}" 240 120 2160)"
    OLC_PANE_PENDING_TTL_MS="$(olc_uint "''${OLC_PANE_PENDING_TTL_MS:-3000}" 3000 250 10000)"
    OLC_PANE_BORDER_COLOR="$(olc_color "''${OLC_PANE_BORDER_COLOR:-#0f172a}" "#0f172a")"
    OLC_PANE_ACTIVE_BORDER_COLOR="$(olc_color "''${OLC_PANE_ACTIVE_BORDER_COLOR:-$OLC_PANE_BORDER_COLOR}" "$OLC_PANE_BORDER_COLOR")"
    OLC_PANE_INACTIVE_BORDER_COLOR="$(olc_color "''${OLC_PANE_INACTIVE_BORDER_COLOR:-$OLC_PANE_BORDER_COLOR}" "$OLC_PANE_BORDER_COLOR")"
    export OLC_PANECTL='${olcPanectl}/bin/olc-panectl'
    export OLC_PANE_RESIZE_BORDER_PX OLC_PANE_MIN_WIDTH_PX OLC_PANE_MIN_HEIGHT_PX OLC_PANE_PENDING_TTL_MS

    xsetroot -solid "$OLC_PANE_BORDER_COLOR"
    ${screenResizeWatcher} "$$" &
    ${pkgs.spice-vdagent}/bin/spice-vdagent &
    i3_runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ol-c-i3"
    i3_config="$i3_runtime_dir/config"
    mkdir -p "$i3_runtime_dir"
    cat > "$i3_config" <<OLC_I3_CONFIG
set \$mod Mod4
font pango:Noto Sans 10
focus_follows_mouse yes
mouse_warping none
floating_modifier \$mod
workspace_layout default
default_border pixel $OLC_PANE_RESIZE_BORDER_PX
default_floating_border pixel $OLC_PANE_RESIZE_BORDER_PX
hide_edge_borders none
client.focused $OLC_PANE_ACTIVE_BORDER_COLOR $OLC_PANE_ACTIVE_BORDER_COLOR #ffffff $OLC_PANE_ACTIVE_BORDER_COLOR $OLC_PANE_ACTIVE_BORDER_COLOR
client.focused_inactive $OLC_PANE_INACTIVE_BORDER_COLOR $OLC_PANE_INACTIVE_BORDER_COLOR #ffffff $OLC_PANE_INACTIVE_BORDER_COLOR $OLC_PANE_INACTIVE_BORDER_COLOR
client.unfocused $OLC_PANE_INACTIVE_BORDER_COLOR $OLC_PANE_INACTIVE_BORDER_COLOR #ffffff $OLC_PANE_INACTIVE_BORDER_COLOR $OLC_PANE_INACTIVE_BORDER_COLOR
client.urgent #7f1d1d #7f1d1d #ffffff #7f1d1d #7f1d1d
for_window [class="^[Ff]irefox$"] border pixel $OLC_PANE_RESIZE_BORDER_PX
for_window [class="^[Ff]irefox$"] focus
OLC_I3_CONFIG
    i3 -c "$i3_config" &
    i3_pid="$!"
    for _ in $(seq 1 50); do
      if i3-msg -t get_version >/dev/null 2>&1; then
        break
      fi
      if ! kill -0 "$i3_pid" 2>/dev/null; then
        wait "$i3_pid"
        exit $?
      fi
      sleep 0.1
    done
    if ! i3-msg -t get_version >/dev/null 2>&1; then
      printf 'i3_not_ready=1\n'
      wait "$i3_pid"
      exit $?
    fi
    ${olcPanectl}/bin/olc-panectl clear-pending || true
    ${olcPanectl}/bin/olc-panectl watch &
    ${userProfileScript}
    firefox_runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/ol-c-firefox"
    firefox_bidi_env="''${firefox_runtime_dir}/bidi.env"
    firefox_bidi_log="''${firefox_runtime_dir}/firefox.log"
    mkdir -p "$firefox_runtime_dir"
    rm -f "$firefox_bidi_env" "$firefox_bidi_log"
    if [ "$olc_fast_boot" != "1" ]; then
      rm -rf "$HOME/.cache/mozilla/firefox/ol-c.default/startupCache"
    fi
    for _ in $(seq 1 40); do
      if curl --silent --fail --cacert ${localhostTls}/ca.crt https://localhost/ >/dev/null; then
        break
      fi
      sleep 0.1
    done
    {
      printf 'expected_unwrapped=%s\n' '${firefoxBin}'
      printf 'firefox_launcher=%s\n' '${firefoxBin}'
      printf 'moz_purge_caches=%s\n' "$([ "$olc_fast_boot" = "1" ] && printf 0 || printf 1)"
      printf 'kiosk=%s\n' "${if kiosk then "1" else "0"}"
      printf 'profile=%s\n' "$HOME/.mozilla/firefox/ol-c.default"
      printf 'bidi_env=%s\n' "$firefox_bidi_env"
      printf 'bidi_log=%s\n' "$firefox_bidi_log"
    } > "$HOME/ol-c-firefox-launch.txt"
    cat "$HOME/ol-c-firefox-launch.txt"
    (
      firefox_pid=""
      for _ in $(seq 1 40); do
        firefox_pid="$(${pkgs.procps}/bin/pgrep -n -u "$(id -u)" firefox 2>/dev/null || true)"
        if [ -n "$firefox_pid" ]; then
          running_firefox="$(${pkgs.coreutils}/bin/readlink -f "/proc/$firefox_pid/exe" 2>/dev/null || true)"
          if [ -n "$running_firefox" ]; then
            printf 'running_firefox_exe=%s\n' "$running_firefox" >> "$HOME/ol-c-firefox-launch.txt"
            if [ "$running_firefox" != '${firefoxBin}' ]; then
              printf 'unexpected_firefox_exe=1\n' >> "$HOME/ol-c-firefox-launch.txt"
            fi
            cat "$HOME/ol-c-firefox-launch.txt"
            break
          fi
        fi
        sleep 0.1
      done
    ) &
    if [ "$olc_fast_boot" = "1" ]; then
      ${firefoxLaunchArgs { inherit startUrl kiosk; }} >>"$firefox_bidi_log" 2>&1 &
    else
      env MOZ_PURGE_CACHES=1 \
        ${firefoxLaunchArgs { inherit startUrl kiosk; }} >>"$firefox_bidi_log" 2>&1 &
    fi
    launcher_pid="$!"
    printf 'launcher_pid=%s\n' "$launcher_pid" >> "$HOME/ol-c-firefox-launch.txt"
    ${bidiRecorder} "$firefox_bidi_env" "$firefox_bidi_log" "$launcher_pid" &
    firefox_pid=""
    for _ in $(seq 1 80); do
      firefox_pid="$(${pkgs.procps}/bin/pgrep -n -u "$(id -u)" firefox 2>/dev/null || true)"
      if [ -n "$firefox_pid" ]; then
        printf 'session_firefox_pid=%s\n' "$firefox_pid" >> "$HOME/ol-c-firefox-launch.txt"
        break
      fi
      if ! kill -0 "$launcher_pid" 2>/dev/null; then
        break
      fi
      sleep 0.1
    done
    if [ -z "$firefox_pid" ]; then
      printf 'session_firefox_pid_not_found=1\n' >> "$HOME/ol-c-firefox-launch.txt"
      cat "$HOME/ol-c-firefox-launch.txt"
      wait "$launcher_pid"
      exit $?
    fi
    cat "$HOME/ol-c-firefox-launch.txt"
    while ${pkgs.procps}/bin/pgrep -u "$(id -u)" firefox >/dev/null 2>&1; do
      sleep 1
    done
  '';
in {
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "modesetting" ];
  services.xserver.displayManager.startx = {
    enable = true;
    generateScript = true;
  };
  services.xserver.desktopManager.xterm.enable = false;
  services.spice-vdagentd.enable = true;
  security.pam.services.greetd.text = ''
    auth      substack      login
    account   include       login
    password  substack      login
    session   include       login
  '';
  services.greetd = {
    enable = true;
    settings = {
      terminal.vt = 1;
      default_session = {
        user = "olc-greeter";
        command = "${greetdBrowserGreeterCommand}";
      };
      initial_session = {
        user = "olc-setup";
        command = pkgs.writeShellScript "olc-setup-initial-session" ''
          set -euo pipefail

          if ${pkgs.getent}/bin/getent group olc-admin | ${pkgs.gnugrep}/bin/grep -Eq '^[^:]*:[^:]*:[^:]*:[^[:space:]]'; then
            exit 0
          fi

          exec ${greetdSetupSessionCommand}
        '';
      };
    };
  };

  system.activationScripts.olcGraphicalSession = ''
    mkdir -p /etc/skel/.mozilla/firefox/ol-c.default
    mkdir -p /var/lib/ol-c/greeter/.mozilla/firefox/ol-c.greeter
    mkdir -p /var/lib/ol-c/setup/.mozilla/firefox/ol-c.default
    chown -R olc-greeter:olc-greeter /var/lib/ol-c/greeter
    chown -R olc-setup:olc-setup /var/lib/ol-c/setup
  '';
}
