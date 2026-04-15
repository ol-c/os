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
in {
  environment.systemPackages = [
    codexCommand
    pkgs.sudo
  ];

  security.sudo.wheelNeedsPassword = false;
}
