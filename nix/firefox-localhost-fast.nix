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

    browser_omni="$out/lib/firefox/browser/omni.ja"
    if [ ! -f "$browser_omni" ]; then
      echo "error: expected Firefox browser omni.ja at $browser_omni" >&2
      exit 1
    fi

    work_dir="$(mktemp -d)"
    mkdir -p "$work_dir/omni"

    unzip_status=0
    unzip -q "$browser_omni" -d "$work_dir/omni" || unzip_status="$?"
    if [ "$unzip_status" -ne 0 ]; then
      echo "warning: unzip reported status $unzip_status while reading optimized Firefox omni.ja; continuing if required files extracted" >&2
    fi

    apply_source_patch_to_runtime_asset() {
      local source_path="$1"
      local basename="$2"
      local validation_pattern="$3"
      local source_patch="$work_dir/''${basename}.source.patch"
      local candidate_patch="$work_dir/''${basename}.candidate.patch"
      local applied_path=""
      local candidate_path

      filterdiff \
        -i "*/$source_path" \
        ${firefoxLocalhostPatch} \
        > "$source_patch"

      if [ ! -s "$source_patch" ]; then
        echo "error: Firefox localhost patch contains no runtime hunks for $source_path" >&2
        exit 1
      fi

      while IFS= read -r candidate_path; do
        sed "s#$source_path#$candidate_path#g" \
          "$source_patch" \
          > "$candidate_patch"

        if patch -d "$work_dir/omni" -p1 --dry-run < "$candidate_patch" >/dev/null 2>&1; then
          if [ -n "$applied_path" ]; then
            echo "error: Firefox localhost patch matched multiple $basename runtime assets:" >&2
            echo "  $applied_path" >&2
            echo "  $candidate_path" >&2
            exit 1
          fi

          patch -d "$work_dir/omni" -p1 < "$candidate_patch"
          applied_path="$candidate_path"
        fi
      done < <(
        find "$work_dir/omni" -type f -name "$basename" \
          | sed "s#^$work_dir/omni/##" \
          | LC_ALL=C sort
      )

      if [ -z "$applied_path" ]; then
        echo "error: Firefox localhost patch did not match any extracted $basename runtime asset" >&2
        echo "available $basename candidates:" >&2
        find "$work_dir/omni" -type f -name "$basename" \
          | sed "s#^$work_dir/omni/#  #" >&2 || true
        exit 1
      fi

      if ! grep -Fq "$validation_pattern" "$work_dir/omni/$applied_path"; then
        echo "error: patched Firefox runtime asset is missing expected localhost code: $applied_path" >&2
        echo "missing pattern: $validation_pattern" >&2
        exit 1
      fi

      printf '%s\n' "$applied_path" > "$work_dir/''${basename}.applied-path"
    }

    apply_source_patch_to_runtime_asset \
      browser/base/content/browser-commands.js \
      browser-commands.js \
      'url ??= SECUREOS_LOCALHOST_URL'

    apply_source_patch_to_runtime_asset \
      browser/components/tabbrowser/content/tabbrowser.js \
      tabbrowser.js \
      'this.addTrustedTab(SECUREOS_LOCALHOST_URL'

    tabbrowser_omni_path="$(cat "$work_dir/tabbrowser.js.applied-path")"
    if ! grep -Fq 'DOMWindowClose' "$work_dir/omni/$tabbrowser_omni_path"; then
      echo "error: patched Firefox tabbrowser runtime asset does not contain DOMWindowClose handling: $tabbrowser_omni_path" >&2
      exit 1
    fi

    rm "$browser_omni"
    (cd "$work_dir/omni" && zip -q -r -9 -X "$browser_omni" .)
  '';
}
