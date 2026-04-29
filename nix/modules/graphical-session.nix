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
  sessionPath = lib.makeBinPath [
    pkgs.coreutils
    pkgs.curl
    pkgs.findutils
    pkgs.matchbox
    pkgs.spice-vdagent
    pkgs.systemd
    pkgs.util-linux
    pkgs.xdotool
    pkgs.xorg.xauth
    pkgs.xorg.xinit
    pkgs.xorg.xsetroot
  ];
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
    xsetroot -solid "#0f172a"
    ${pkgs.spice-vdagent}/bin/spice-vdagent &
    matchbox-window-manager -use_titlebar no -use_cursor yes &
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
      for _ in $(seq 1 40); do
        window_id="$(xdotool search --onlyvisible --class firefox 2>/dev/null | head -n 1 || true)"
        if [ -n "$window_id" ]; then
          xdotool windowmove "$window_id" 0 0
          xdotool windowsize "$window_id" 100% 100%
          xdotool key --window "$window_id" alt+F10
          break
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
