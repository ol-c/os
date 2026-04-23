{ pkgs, ... }:

let
  codexVersion = "0.120.0";
  patchedFirefoxCommand = pkgs.writeShellScriptBin "patched-firefox" ''
    set -euo pipefail

    base_runtime="''${OLC_FIREFOX_BASE_RUNTIME:-/run/current-system/sw/lib/firefox}"
    source_root="''${OLC_SOURCE_ROOT:-/source}"
    packaged_patch_dir="''${OLC_FIREFOX_PACKAGED_PATCH_DIR:-$source_root/patches/firefox/packaged}"
    pending_patch_dir="''${OLC_FIREFOX_PENDING_PATCH_DIR:-$source_root/patches/firefox/pending}"
    workspace="''${OLC_FIREFOX_DEV_WORKSPACE:-/var/lib/ol-c/firefox-dev}"

    if [ -z "''${HOME:-}" ]; then
      HOME="$(${pkgs.getent}/bin/getent passwd "$(id -u)" | ${pkgs.coreutils}/bin/cut -d: -f6)"
      export HOME
    fi

    profile="''${OLC_FIREFOX_DEV_PROFILE:-$HOME/.mozilla/firefox/ol-c.patched-dev}"
    url="''${1:-https://localhost}"

    patch_bin="${pkgs.patch}/bin/patch"
    filterdiff_bin="${pkgs.patchutils}/bin/filterdiff"
    unzip_bin="${pkgs.unzip}/bin/unzip"
    zip_bin="${pkgs.zip}/bin/zip"
    find_bin="${pkgs.findutils}/bin/find"
    sed_bin="${pkgs.gnused}/bin/sed"
    grep_bin="${pkgs.gnugrep}/bin/grep"
    coreutils_bin="${pkgs.coreutils}/bin"

    if [ ! -d "$base_runtime" ]; then
      echo "error: Firefox runtime not found: $base_runtime" >&2
      exit 1
    fi
    if [ ! -d "$packaged_patch_dir" ]; then
      echo "error: Firefox packaged patch directory not found: $packaged_patch_dir" >&2
      exit 1
    fi

    packaged_patches=()
    pending_patches=()
    patches=()

    while IFS= read -r patch_file; do
      packaged_patches+=("$patch_file")
      patches+=("$patch_file")
    done < <("$find_bin" "$packaged_patch_dir" -maxdepth 1 -type f -name '*.patch' | "$coreutils_bin/sort")
    if [ "''${#packaged_patches[@]}" -eq 0 ]; then
      echo "error: no Firefox packaged patches found in $packaged_patch_dir" >&2
      exit 1
    fi

    if [ -d "$pending_patch_dir" ]; then
      while IFS= read -r patch_file; do
        pending_patches+=("$patch_file")
        patches+=("$patch_file")
      done < <("$find_bin" "$pending_patch_dir" -maxdepth 1 -type f -name '*.patch' | "$coreutils_bin/sort")
    fi

    generation="$workspace/runtime"
    work_dir="$workspace/work"
    "$coreutils_bin/rm" -rf "$generation" "$work_dir"
    "$coreutils_bin/mkdir" -p "$generation" "$work_dir" "$profile"

    (
      cd "$base_runtime"
      "$find_bin" . -type d -exec "$coreutils_bin/mkdir" -p "$generation/{}" \;
      while IFS= read -r path; do
        case "$path" in
          ./omni.ja|./browser/omni.ja)
            "$coreutils_bin/cp" -aL "$base_runtime/''${path#./}" "$generation/''${path#./}"
            "$coreutils_bin/chmod" u+w "$generation/''${path#./}"
            ;;
          *)
            "$coreutils_bin/ln" -s "$base_runtime/''${path#./}" "$generation/''${path#./}"
            ;;
        esac
      done < <("$find_bin" . ! -type d | "$coreutils_bin/sort")
    )

    firefox_omnis=(
      "$generation/browser/omni.ja"
      "$generation/omni.ja"
    )
    extracted_omnis=()

    extract_omni() {
      local omni="$1"
      local archive_id
      local extract_dir
      local unzip_status

      if [ ! -f "$omni" ]; then
        echo "error: expected Firefox omni.ja at $omni" >&2
        exit 1
      fi

      archive_id="$(printf '%s' "$omni" | "$sed_bin" "s#^$generation/##; s#[^A-Za-z0-9_.-]#_#g")"
      extract_dir="$work_dir/omnis/$archive_id"
      "$coreutils_bin/mkdir" -p "$extract_dir"

      unzip_status=0
      "$unzip_bin" -q "$omni" -d "$extract_dir" || unzip_status="$?"
      if [ "$unzip_status" -ne 0 ]; then
        echo "warning: unzip reported status $unzip_status while reading optimized Firefox omni.ja at $omni; continuing if required files extracted" >&2
      fi

      extracted_omnis+=("$omni:$extract_dir")
    }

    apply_source_patch_to_runtime_asset() {
      local patch_file="$1"
      local source_path="$2"
      local basename="$3"
      local validation_pattern="$4"
      local patch_id
      local source_patch
      local candidate_patch
      local applied_path=""
      local applied_omni=""
      local entry
      local omni
      local extract_dir
      local candidate_path

      patch_id="$("$coreutils_bin/basename" "$patch_file" .patch)"
      source_patch="$work_dir/$patch_id.$basename.source.patch"
      candidate_patch="$work_dir/$patch_id.$basename.candidate.patch"

      "$filterdiff_bin" -i "*/$source_path" "$patch_file" > "$source_patch"
      if [ ! -s "$source_patch" ]; then
        return 0
      fi

      for entry in "''${extracted_omnis[@]}"; do
        omni="''${entry%%:*}"
        extract_dir="''${entry#*:}"

        while IFS= read -r candidate_path; do
          "$sed_bin" "s#$source_path#$candidate_path#g" "$source_patch" > "$candidate_patch"

          if "$patch_bin" -d "$extract_dir" -p1 --dry-run < "$candidate_patch" >/dev/null 2>&1; then
            if [ -n "$applied_path" ]; then
              echo "error: Firefox patch $patch_file matched multiple $basename runtime assets:" >&2
              echo "  $applied_omni:$applied_path" >&2
              echo "  $omni:$candidate_path" >&2
              exit 1
            fi

            "$patch_bin" -d "$extract_dir" -p1 < "$candidate_patch"
            applied_path="$candidate_path"
            applied_omni="$omni"
          elif "$patch_bin" -R -d "$extract_dir" -p1 --dry-run < "$candidate_patch" >/dev/null 2>&1; then
            if [ -n "$applied_path" ]; then
              echo "error: Firefox patch $patch_file matched multiple $basename runtime assets:" >&2
              echo "  $applied_omni:$applied_path" >&2
              echo "  $omni:$candidate_path" >&2
              exit 1
            fi

            applied_path="$candidate_path"
            applied_omni="$omni"
          fi
        done < <(
          "$find_bin" "$extract_dir" -type f -name "$basename" \
            | "$sed_bin" "s#^$extract_dir/##" \
            | "$coreutils_bin/sort"
        )
      done

      if [ -z "$applied_path" ]; then
        echo "error: Firefox patch $patch_file did not match any extracted $basename runtime asset" >&2
        exit 1
      fi

      extract_dir=""
      for entry in "''${extracted_omnis[@]}"; do
        omni="''${entry%%:*}"
        if [ "$omni" = "$applied_omni" ]; then
          extract_dir="''${entry#*:}"
        fi
      done
      if [ -z "$extract_dir" ]; then
        echo "error: patched Firefox runtime asset lost its extracted omni directory: $applied_omni:$applied_path" >&2
        exit 1
      fi

      if ! "$grep_bin" -Fq "$validation_pattern" "$extract_dir/$applied_path"; then
        echo "error: patched Firefox runtime asset is missing expected code: $applied_omni:$applied_path" >&2
        echo "missing pattern: $validation_pattern" >&2
        exit 1
      fi
    }

    for omni in "''${firefox_omnis[@]}"; do
      extract_omni "$omni"
    done

    for patch_file in "''${patches[@]}"; do
      case "$("$coreutils_bin/basename" "$patch_file")" in
        0001-close-last-tab-to-localhost.patch)
          apply_source_patch_to_runtime_asset "$patch_file" browser/base/content/browser-commands.js browser-commands.js SECUREOS_LOCALHOST_URL
          apply_source_patch_to_runtime_asset "$patch_file" browser/components/tabbrowser/content/tabbrowser.js tabbrowser.js SECUREOS_LOCALHOST_URL
          apply_source_patch_to_runtime_asset "$patch_file" browser/base/content/browser.js browser.js gSecureOSAppearanceBridge.init
          ;;
        0002-hide-sync-fxa-ui.patch)
          apply_source_patch_to_runtime_asset "$patch_file" browser/base/content/browser.js browser.js olc-fxa-sync-ui-hidden
          ;;
        *)
          echo "error: patched-firefox does not know how to fast-apply $patch_file" >&2
          exit 1
          ;;
      esac
    done

    for entry in "''${extracted_omnis[@]}"; do
      omni="''${entry%%:*}"
      extract_dir="''${entry#*:}"
      "$coreutils_bin/rm" "$omni"
      (cd "$extract_dir" && "$zip_bin" -q -r -9 -X "$omni" .)
    done

    "$find_bin" "$generation" \
      \( -type d -name startupCache -o -type f -name 'startupCache*' -o -type f -name 'scriptCache*' \) \
      -prune -exec "$coreutils_bin/rm" -rf {} +
    "$coreutils_bin/rm" -f "$generation/.purgecaches" "$generation/browser/.purgecaches"
    "$coreutils_bin/touch" "$generation/.purgecaches" "$generation/browser/.purgecaches"

    {
      echo "OLC_PATCHED_FIREFOX_RUNTIME=1"
      printf 'base_runtime=%s\n' "$base_runtime"
      printf 'packaged_patch_dir=%s\n' "$packaged_patch_dir"
      printf 'pending_patch_dir=%s\n' "$pending_patch_dir"
      printf 'packaged_patches=%s\n' "''${packaged_patches[*]}"
      printf 'pending_patches=%s\n' "''${pending_patches[*]}"
      printf 'patches=%s\n' "''${patches[*]}"
      printf 'runtime=%s\n' "$generation"
    } > "$generation/ol-c-patched-firefox.txt"

    if [ -z "''${DISPLAY:-}" ] && [ -S /tmp/.X11-unix/X0 ]; then
      export DISPLAY=:0
    fi

    export MOZ_PURGE_CACHES=1
    exec "$generation/firefox" --no-remote --profile "$profile" --new-window "$url"
  '';
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
    patchedFirefoxCommand
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
    "d /var/lib/ol-c/firefox-dev 0775 demo demo -"
    "d /var/lib/ol-c/vms 0775 demo demo -"
    "d /var/lib/ol-c/vms/tmp 0775 demo demo -"
  ];
}
