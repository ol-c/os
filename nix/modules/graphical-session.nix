{ config, pkgs, ... }:

let
  localhostTls = config.olc.localhost.tlsPackage;
in {
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "modesetting" ];
  services.xserver.displayManager.startx.enable = true;
  services.xserver.desktopManager.xterm.enable = false;
  services.spice-vdagentd.enable = true;

  environment.loginShellInit = ''
    if [ -z "''${DISPLAY:-}" ] && [ "''${XDG_VTNR:-}" = "1" ]; then
      exec startx
    fi
  '';

  system.activationScripts.olcDemoSession = ''
    mkdir -p /home/demo
    mkdir -p /home/demo/.mozilla/firefox/ol-c.default
    cat > /home/demo/.mozilla/firefox/profiles.ini <<'EOF'
    [Profile0]
    Name=default
    IsRelative=1
    Path=ol-c.default
    Default=1

    [General]
    StartWithLastProfile=1
    Version=2
    EOF
    cat > /home/demo/.mozilla/firefox/ol-c.default/user.js <<'EOF'
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
    EOF
    rm -rf /home/demo/.cache/mozilla/firefox/ol-c.default/startupCache
    cat > /home/demo/.xinitrc <<'EOF'
    xsetroot -solid "#0f172a"
    ${pkgs.spice-vdagent}/bin/spice-vdagent &
    matchbox-window-manager -use_titlebar no -use_cursor yes &
    for _ in $(seq 1 40); do
      if curl --silent --fail --cacert ${localhostTls}/ca.crt https://localhost/ >/dev/null; then
        break
      fi
      sleep 0.25
    done
    {
      printf 'expected_unwrapped=%s\n' '${pkgs.firefox-unwrapped}/lib/firefox/firefox'
      printf 'firefox_launcher=%s\n' '${pkgs.firefox-unwrapped}/lib/firefox/firefox'
      printf 'moz_purge_caches=%s\n' '1'
      printf 'profile=%s\n' '/home/demo/.mozilla/firefox/ol-c.default'
    } > /home/demo/ol-c-firefox-launch.txt
    MOZ_PURGE_CACHES=1 ${pkgs.firefox-unwrapped}/lib/firefox/firefox --no-remote --profile /home/demo/.mozilla/firefox/ol-c.default --new-window https://localhost &
    firefox_pid="$!"
    for _ in $(seq 1 40); do
      running_firefox="$(${pkgs.coreutils}/bin/readlink -f "/proc/$firefox_pid/exe" 2>/dev/null || true)"
      if [ -n "$running_firefox" ]; then
        printf 'running_firefox_exe=%s\n' "$running_firefox" >> /home/demo/ol-c-firefox-launch.txt
        if [ "$running_firefox" != '${pkgs.firefox-unwrapped}/lib/firefox/firefox' ]; then
          printf 'unexpected_firefox_exe=1\n' >> /home/demo/ol-c-firefox-launch.txt
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
    EOF
    chown -R demo:demo /home/demo/.mozilla
    chown demo:demo /home/demo/.xinitrc
    chmod 0755 /home/demo/.mozilla /home/demo/.mozilla/firefox /home/demo/.mozilla/firefox/ol-c.default
    chmod 0644 /home/demo/.mozilla/firefox/profiles.ini
    chmod 0644 /home/demo/.mozilla/firefox/ol-c.default/user.js
    chmod 0644 /home/demo/.xinitrc
  '';
}
