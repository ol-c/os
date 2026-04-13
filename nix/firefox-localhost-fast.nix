{ firefoxLocalhostPatch }:

final: prev:
let
  firefoxUnwrappedName = prev.firefox-unwrapped.name or "firefox-unwrapped";
  firefoxSource = (prev.firefox-unwrapped.overrideAttrs (old: {
    passthru = (old.passthru or {}) // {
      olcFirefoxSource = old.src;
    };
  })).olcFirefoxSource;
in {
  firefox-unwrapped = prev.runCommand "${firefoxUnwrappedName}-ol-c-localhost-fast" {
    nativeBuildInputs = [
      prev.gnutar
      prev.patch
      prev.patchutils
      prev.python3
      prev.unzip
      prev.xz
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
    mkdir -p "$work_dir/firefox-source"
    tar -xf ${firefoxSource} -C "$work_dir/firefox-source" --strip-components=1

    mkdir -p "$work_dir/optimized" "$work_dir/deoptimized" "$work_dir/omni"
    cp "$browser_omni" "$work_dir/optimized/omni.ja"
    python "$work_dir/firefox-source/config/optimizejars.py" \
      --deoptimize \
      "$work_dir/optimized" \
      "$work_dir/deoptimized" \
      "$work_dir/optimized"
    unzip -q "$work_dir/deoptimized/omni.ja" -d "$work_dir/omni"

    for path in \
      chrome/browser/content/browser/browser-commands.js \
      chrome/browser/content/browser/tabbrowser.js
    do
      if [ ! -f "$work_dir/omni/$path" ]; then
        echo "error: expected Firefox frontend asset missing from omni.ja: $path" >&2
        exit 1
      fi
    done

    filterdiff \
      -i '*/browser/base/content/browser-commands.js' \
      -i '*/browser/components/tabbrowser/content/tabbrowser.js' \
      ${firefoxLocalhostPatch} \
      > "$work_dir/runtime-source.patch"

    if [ ! -s "$work_dir/runtime-source.patch" ]; then
      echo "error: Firefox localhost patch contains no runtime frontend hunks for the fast repack path" >&2
      exit 1
    fi

    sed \
      -e 's#browser/base/content/browser-commands.js#chrome/browser/content/browser/browser-commands.js#g' \
      -e 's#browser/components/tabbrowser/content/tabbrowser.js#chrome/browser/content/browser/tabbrowser.js#g' \
      "$work_dir/runtime-source.patch" \
      > "$work_dir/runtime-omni.patch"

    patch -d "$work_dir/omni" -p1 < "$work_dir/runtime-omni.patch"

    rm "$browser_omni"
    (cd "$work_dir/omni" && zip -q -r -9 -X "$work_dir/deoptimized/omni.ja" .)
    python "$work_dir/firefox-source/config/optimizejars.py" \
      --optimize \
      "$work_dir/optimized" \
      "$work_dir/deoptimized" \
      "$work_dir/optimized"
    cp "$work_dir/optimized/omni.ja" "$browser_omni"
  '';
}
