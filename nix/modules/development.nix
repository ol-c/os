{ pkgs, ... }:

let
  codexVersion = "0.120.0";
  codexCommand = pkgs.writeShellScriptBin "codex" ''
    set -eu

    if [ -z "''${HOME:-}" ]; then
      HOME="$(${pkgs.getent}/bin/getent passwd "$(id -u)" | ${pkgs.coreutils}/bin/cut -d: -f6)"
      export HOME
    fi

    export CODEX_HOME="''${CODEX_HOME:-''${HOME}/.codex}"
    export CODEX_MODEL="''${CODEX_MODEL:-gpt-5.4}"
    export NO_UPDATE_NOTIFIER="''${NO_UPDATE_NOTIFIER:-1}"

    mkdir -p "$CODEX_HOME"

    exec ${pkgs.nodejs}/bin/npx \
      --yes \
      @openai/codex@${codexVersion} \
      --model "$CODEX_MODEL" \
      --dangerously-bypass-approvals-and-sandbox \
      "$@"
  '';
  olcLaunchTestVm = pkgs.writeShellScriptBin "olc-launch-test-vm" ''
    export OLC_DEFAULT_NOVNC_DIR="''${OLC_DEFAULT_NOVNC_DIR:-${pkgs.novnc}/share/webapps/novnc}"
    exec ${pkgs.bash}/bin/bash ${../../olc-launch-test-vm} "$@"
  '';
in {
  environment.systemPackages = [
    codexCommand
    olcLaunchTestVm
    pkgs.sudo
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "demo" ];
  };

  security.sudo.wheelNeedsPassword = false;

  systemd.tmpfiles.rules = [
    "d /var/lib/ol-c 0755 root root -"
    "d /var/lib/ol-c/vms 0775 demo users -"
    "d /var/lib/ol-c/vms/tmp 0775 demo users -"
  ];
}
