{ lib, ... }:

{
  users.users.root.initialPassword = "root";

  users.users.demo = {
    isNormalUser = true;
    uid = 1000;
    initialPassword = "demo";
    extraGroups = [ "kvm" "wheel" ];
    home = "/home/demo";
  };

  services.getty.autologinUser = lib.mkForce "demo";

  programs.bash.promptInit = ''
    olc_terminal_title() {
      local title="$1"
      title="''${title//$'\n'/ }"
      title="''${title//$'\r'/ }"
      title="''${title//$'\t'/ }"
      printf '\033]0;%s\007' "$title"
    }

    olc_prompt_title() {
      local dir="''${PWD/#$HOME/~}"
      olc_terminal_title "$dir"
    }

    olc_command_title() {
      local command="$BASH_COMMAND"
      case "$command" in
        olc_*|PROMPT_COMMAND=*|trap\ *)
          return
          ;;
      esac

      if [[ -n "$command" ]]; then
        olc_terminal_title "$command"
      fi
    }

    edit() {
      local target="''${1-}"
      local url
      url="$(node -e 'const path = require("node:path"); const root = process.argv[1]; const target = process.argv[2] || ""; const url = new URL("https://localhost/edit"); url.searchParams.set("root", root); if (target) url.searchParams.set("path", path.resolve(root, target)); console.log(url.href);' "$PWD" "$target")" || return
      firefox --new-tab "$url" >/dev/null 2>&1 &
      disown %% 2>/dev/null || true
    }

    PROMPT_COMMAND='olc_prompt_title'
    trap 'olc_command_title' DEBUG
    PS1='[\u@\h:\w]\$ '
  '';
}
