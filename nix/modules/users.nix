{ lib, ... }:

{
  users.users.root.initialPassword = "root";

  users.users.demo = {
    isNormalUser = true;
    uid = 1000;
    initialPassword = "demo";
    extraGroups = [ "wheel" ];
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

    PROMPT_COMMAND='olc_prompt_title'
    trap 'olc_command_title' DEBUG
    PS1='[\u@\h:\w]\$ '
  '';
}
