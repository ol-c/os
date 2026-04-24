{ config, pkgs, ... }:

let
  localhostTls = config.olc.localhost.tlsPackage;
  firefoxBin = "${pkgs.firefox-unwrapped}/lib/firefox/firefox";
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
  userXinitRc = startUrl: ''
    xsetroot -solid "#0f172a"
    ${pkgs.spice-vdagent}/bin/spice-vdagent &
    matchbox-window-manager -use_titlebar no -use_cursor yes &
    ${userProfileScript}
    rm -rf "$HOME/.cache/mozilla/firefox/ol-c.default/startupCache"
    for _ in $(seq 1 40); do
      if curl --silent --fail --cacert ${localhostTls}/ca.crt https://localhost/ >/dev/null; then
        break
      fi
      sleep 0.25
    done
    {
      printf 'expected_unwrapped=%s\n' '${firefoxBin}'
      printf 'firefox_launcher=%s\n' '${firefoxBin}'
      printf 'moz_purge_caches=%s\n' '1'
      printf 'profile=%s\n' "$HOME/.mozilla/firefox/ol-c.default"
    } > "$HOME/ol-c-firefox-launch.txt"
    MOZ_PURGE_CACHES=1 ${firefoxBin} --no-remote --profile "$HOME/.mozilla/firefox/ol-c.default" --new-window ${startUrl} &
    firefox_pid="$!"
    for _ in $(seq 1 40); do
      running_firefox="$(${pkgs.coreutils}/bin/readlink -f "/proc/$firefox_pid/exe" 2>/dev/null || true)"
      if [ -n "$running_firefox" ]; then
        printf 'running_firefox_exe=%s\n' "$running_firefox" >> "$HOME/ol-c-firefox-launch.txt"
        if [ "$running_firefox" != '${firefoxBin}' ]; then
          printf 'unexpected_firefox_exe=1\n' >> "$HOME/ol-c-firefox-launch.txt"
        fi
        break
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
      sleep 0.25
    done
    wait
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
        user = "greeter";
        command = "${pkgs.tuigreet}/bin/tuigreet --time --cmd ${pkgs.xorg.xinit}/bin/startx";
      };
      initial_session = {
        user = "olc-setup";
        command = pkgs.writeShellScript "olc-setup-initial-session" ''
          set -euo pipefail

          if ${pkgs.getent}/bin/getent group olc-admin | ${pkgs.gnugrep}/bin/grep -Eq '^[^:]*:[^:]*:[^:]*:[^[:space:]]'; then
            exit 0
          fi

          exec ${pkgs.xorg.xinit}/bin/startx
        '';
      };
    };
  };

  system.activationScripts.olcGraphicalSession = ''
    mkdir -p /etc/skel/.mozilla/firefox/ol-c.default
    cat > /etc/skel/.xinitrc <<'OLC_SKEL_XINIT'
    ${userXinitRc "https://localhost"}
    OLC_SKEL_XINIT
    chmod 0755 /etc/skel/.xinitrc

    mkdir -p /var/lib/ol-c/setup/.mozilla/firefox/ol-c.default
    cat > /var/lib/ol-c/setup/.xinitrc <<'OLC_SETUP_XINIT'
    ${userXinitRc "https://localhost/setup"}
    OLC_SETUP_XINIT
    chown -R olc-setup:olc-setup /var/lib/ol-c/setup
    chmod 0755 /var/lib/ol-c/setup/.xinitrc
  '';
}
