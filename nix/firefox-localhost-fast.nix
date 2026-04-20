{ firefoxLocalhostPatch }:

final: prev:
let
  firefoxUnwrappedName = prev.firefox-unwrapped.name or "firefox-unwrapped";
in {
  firefox-unwrapped = prev.runCommand "${firefoxUnwrappedName}-ol-c-localhost-fast" {
    nativeBuildInputs = [
      prev.patch
      prev.patchutils
      prev.unzip
      prev.zip
    ];
    meta = prev.firefox-unwrapped.meta;
    passthru = (prev.firefox-unwrapped.passthru or {}) // {
      inherit (prev.firefox-unwrapped) gtk3;
    };
  } ''
    set -euo pipefail

    cp -a ${prev.firefox-unwrapped} "$out"
    chmod -R u+w "$out"

    work_dir="$(mktemp -d)"

    firefox_omnis=(
      "$out/lib/firefox/browser/omni.ja"
      "$out/lib/firefox/omni.ja"
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

      archive_id="$(printf '%s' "$omni" | sed "s#^$out/lib/firefox/##; s#[^A-Za-z0-9_.-]#_#g")"
      extract_dir="$work_dir/omnis/$archive_id"
      mkdir -p "$extract_dir"

      unzip_status=0
      unzip -q "$omni" -d "$extract_dir" || unzip_status="$?"
      if [ "$unzip_status" -ne 0 ]; then
        echo "warning: unzip reported status $unzip_status while reading optimized Firefox omni.ja at $omni; continuing if required files extracted" >&2
      fi

      extracted_omnis+=("$omni:$extract_dir")
    }

    for omni in "''${firefox_omnis[@]}"; do
      extract_omni "$omni"
    done

    apply_source_patch_to_runtime_asset() {
      local source_path="$1"
      local basename="$2"
      local validation_pattern="$3"
      local source_patch="$work_dir/''${basename}.source.patch"
      local candidate_patch="$work_dir/''${basename}.candidate.patch"
      local applied_path=""
      local applied_omni=""
      local entry
      local omni
      local extract_dir
      local candidate_path

      filterdiff \
        -i "*/$source_path" \
        ${firefoxLocalhostPatch} \
        > "$source_patch"

      if [ ! -s "$source_patch" ]; then
        echo "error: Firefox localhost patch contains no runtime hunks for $source_path" >&2
        exit 1
      fi

      for entry in "''${extracted_omnis[@]}"; do
        omni="''${entry%%:*}"
        extract_dir="''${entry#*:}"

        while IFS= read -r candidate_path; do
          sed "s#$source_path#$candidate_path#g" \
            "$source_patch" \
            > "$candidate_patch"

          if patch -d "$extract_dir" -p1 --dry-run < "$candidate_patch" >/dev/null 2>&1; then
            if [ -n "$applied_path" ]; then
              echo "error: Firefox localhost patch matched multiple $basename runtime assets:" >&2
              echo "  $applied_omni:$applied_path" >&2
              echo "  $omni:$candidate_path" >&2
              exit 1
            fi

            patch -d "$extract_dir" -p1 < "$candidate_patch"
            applied_path="$candidate_path"
            applied_omni="$omni"
          fi
        done < <(
          find "$extract_dir" -type f -name "$basename" \
            | sed "s#^$extract_dir/##" \
            | LC_ALL=C sort
        )
      done

      if [ -z "$applied_path" ]; then
        echo "error: Firefox localhost patch did not match any extracted $basename runtime asset" >&2
        echo "available $basename candidates:" >&2
        for entry in "''${extracted_omnis[@]}"; do
          omni="''${entry%%:*}"
          extract_dir="''${entry#*:}"
          find "$extract_dir" -type f -name "$basename" \
            | sed "s#^$extract_dir/#  $omni:#" >&2 || true
        done
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

      if ! grep -Fq "$validation_pattern" "$extract_dir/$applied_path"; then
        echo "error: patched Firefox runtime asset is missing expected localhost code: $applied_omni:$applied_path" >&2
        echo "missing pattern: $validation_pattern" >&2
        exit 1
      fi

      printf '%s\n' "$applied_path" > "$work_dir/''${basename}.applied-path"
      printf '%s\n' "$applied_omni" > "$work_dir/''${basename}.applied-omni"
    }

    apply_source_patch_to_runtime_asset \
      browser/base/content/browser-commands.js \
      browser-commands.js \
      'url ??= SECUREOS_LOCALHOST_URL'

    browser_commands_omni_path="$(cat "$work_dir/browser-commands.js.applied-path")"
    browser_commands_omni="$(cat "$work_dir/browser-commands.js.applied-omni")"
    browser_commands_extract_dir=""
    for entry in "''${extracted_omnis[@]}"; do
      omni="''${entry%%:*}"
      if [ "$omni" = "$browser_commands_omni" ]; then
        browser_commands_extract_dir="''${entry#*:}"
      fi
    done
    if [ -z "$browser_commands_extract_dir" ]; then
      echo "error: patched Firefox browser-commands runtime asset lost its extracted omni directory: $browser_commands_omni:$browser_commands_omni_path" >&2
      exit 1
    fi
    if grep -Fq 'url ??= BROWSER_NEW_TAB_URL;' "$browser_commands_extract_dir/$browser_commands_omni_path"; then
      echo "error: patched Firefox browser commands runtime asset can still default new tabs to Firefox's stock new-tab URL: $browser_commands_omni:$browser_commands_omni_path" >&2
      exit 1
    fi

    apply_source_patch_to_runtime_asset \
      browser/components/tabbrowser/content/tabbrowser.js \
      tabbrowser.js \
      'this.addTrustedTab(SECUREOS_LOCALHOST_URL'

    tabbrowser_omni_path="$(cat "$work_dir/tabbrowser.js.applied-path")"
    tabbrowser_omni="$(cat "$work_dir/tabbrowser.js.applied-omni")"
    tabbrowser_extract_dir=""
    for entry in "''${extracted_omnis[@]}"; do
      omni="''${entry%%:*}"
      if [ "$omni" = "$tabbrowser_omni" ]; then
        tabbrowser_extract_dir="''${entry#*:}"
      fi
    done
    if [ -z "$tabbrowser_extract_dir" ]; then
      echo "error: patched Firefox tabbrowser runtime asset lost its extracted omni directory: $tabbrowser_omni:$tabbrowser_omni_path" >&2
      exit 1
    fi
    if ! grep -Fq 'DOMWindowClose' "$tabbrowser_extract_dir/$tabbrowser_omni_path"; then
      echo "error: patched Firefox tabbrowser runtime asset does not contain DOMWindowClose handling: $tabbrowser_omni:$tabbrowser_omni_path" >&2
      exit 1
    fi
    sed -i \
      's#this\.addTrustedTab(BROWSER_NEW_TAB_URL,#this.addTrustedTab(SECUREOS_LOCALHOST_URL,#g' \
      "$tabbrowser_extract_dir/$tabbrowser_omni_path"
    if grep -Fq 'this.addTrustedTab(BROWSER_NEW_TAB_URL,' "$tabbrowser_extract_dir/$tabbrowser_omni_path"; then
      echo "error: patched Firefox tabbrowser runtime asset still contains stock trusted new-tab replacement calls: $tabbrowser_omni:$tabbrowser_omni_path" >&2
      exit 1
    fi

    apply_source_patch_to_runtime_asset \
      browser/base/content/browser.js \
      browser.js \
      'gSecureOSAppearanceBridge.init()'

    browser_js_path="$(cat "$work_dir/browser.js.applied-path")"
    browser_js_omni="$(cat "$work_dir/browser.js.applied-omni")"
    browser_js_extract_dir=""
    for entry in "''${extracted_omnis[@]}"; do
      omni="''${entry%%:*}"
      if [ "$omni" = "$browser_js_omni" ]; then
        browser_js_extract_dir="''${entry#*:}"
      fi
    done
    if [ -z "$browser_js_extract_dir" ]; then
      echo "error: patched Firefox browser.js runtime asset lost its extracted omni directory: $browser_js_omni:$browser_js_path" >&2
      exit 1
    fi
    if ! grep -Fq 'new WebChannel(' "$browser_js_extract_dir/$browser_js_path"; then
      echo "error: patched Firefox browser.js runtime asset is missing the localhost WebChannel bridge: $browser_js_omni:$browser_js_path" >&2
      exit 1
    fi
    if ! grep -Fq 'firefox-compact-dark@mozilla.org' "$browser_js_extract_dir/$browser_js_path"; then
      echo "error: patched Firefox browser.js runtime asset is missing built-in dark theme activation: $browser_js_omni:$browser_js_path" >&2
      exit 1
    fi
    sed -i \
      's#openTrustedLinkIn(BROWSER_NEW_TAB_URL,#openTrustedLinkIn("https://localhost",#g' \
      "$browser_js_extract_dir/$browser_js_path"
    sed -i \
      '/window.openDialog(/,/);/ s#BROWSER_NEW_TAB_URL#"https://localhost"#g' \
      "$browser_js_extract_dir/$browser_js_path"
    if grep -Fq 'openTrustedLinkIn(BROWSER_NEW_TAB_URL,' "$browser_js_extract_dir/$browser_js_path"; then
      echo "error: patched Firefox browser.js runtime asset can still open trusted tabs with Firefox's stock new-tab URL: $browser_js_omni:$browser_js_path" >&2
      exit 1
    fi
    if sed -n '/window.openDialog(/,/);/p' "$browser_js_extract_dir/$browser_js_path" \
      | grep -Fq 'BROWSER_NEW_TAB_URL'; then
      echo "error: patched Firefox browser.js runtime asset can still open windows with Firefox's stock new-tab URL: $browser_js_omni:$browser_js_path" >&2
      exit 1
    fi

    for entry in "''${extracted_omnis[@]}"; do
      omni="''${entry%%:*}"
      extract_dir="''${entry#*:}"
      rm "$omni"
      (cd "$extract_dir" && zip -q -r -9 -X "$omni" .)
    done

    {
      echo "OLC_FIREFOX_LOCALHOST_PATCH_APPLIED=1"
      printf 'browser_commands_omni=%s\n' "$browser_commands_omni"
      printf 'browser_commands_path=%s\n' "$browser_commands_omni_path"
      printf 'browser_js_omni=%s\n' "$browser_js_omni"
      printf 'browser_js_path=%s\n' "$browser_js_path"
      printf 'tabbrowser_omni=%s\n' "$tabbrowser_omni"
      printf 'tabbrowser_path=%s\n' "$tabbrowser_omni_path"
    } > "$out/lib/firefox/ol-c-localhost-patch.txt"

    find "$out/lib/firefox" \
      \( -type d -name startupCache -o -type f -name 'startupCache*' -o -type f -name 'scriptCache*' \) \
      -prune -exec rm -rf {} +
    touch "$out/lib/firefox/.purgecaches"
    touch "$out/lib/firefox/browser/.purgecaches"
  '';

  firefox = final.wrapFirefox final.firefox-unwrapped { };
}
