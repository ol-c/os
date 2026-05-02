{ firefoxPatches }:

final: prev:
let
  firefoxUnwrappedName = prev.firefox-unwrapped.name or "firefox-unwrapped";
  firefoxPatchArgs = builtins.concatStringsSep " " (map (patch: "${patch}") firefoxPatches);
in {
  firefox-unwrapped = prev.runCommand "${firefoxUnwrappedName}-ol-c-localhost-fast" {
    nativeBuildInputs = [
      prev.patch
      prev.patchutils
      prev.perl
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
    firefox_patches=(${firefoxPatchArgs})

    if [ "''${#firefox_patches[@]}" -ne 4 ]; then
      echo "error: expected exactly four ol-c Firefox patches" >&2
      exit 1
    fi
    localhost_patch="''${firefox_patches[0]}"
    fxa_sync_ui_patch="''${firefox_patches[1]}"
    power_menu_patch="''${firefox_patches[2]}"
    pane_split_patch="''${firefox_patches[3]}"

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
      local patch_file="$1"
      local source_path="$2"
      local basename="$3"
      local validation_pattern="$4"
      local patch_id
      patch_id="$(basename "$patch_file" .patch)"
      local source_patch="$work_dir/''${patch_id}.''${basename}.source.patch"
      local candidate_patch="$work_dir/''${patch_id}.''${basename}.candidate.patch"
      local applied_path=""
      local applied_omni=""
      local entry
      local omni
      local extract_dir
      local candidate_path

      filterdiff \
        -i "*/$source_path" \
        "$patch_file" \
        > "$source_patch"

      if [ ! -s "$source_patch" ]; then
        echo "error: Firefox patch $patch_file contains no runtime hunks for $source_path" >&2
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
              echo "error: Firefox patch $patch_file matched multiple $basename runtime assets:" >&2
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
        echo "error: Firefox patch $patch_file did not match any extracted $basename runtime asset" >&2
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

    redirector_omni_path=""
    redirector_omni=""
    redirector_extract_dir=""
    for entry in "''${extracted_omnis[@]}"; do
      omni="''${entry%%:*}"
      extract_dir="''${entry#*:}"
      while IFS= read -r candidate_path; do
        if [ -n "$redirector_omni_path" ]; then
          echo "error: found multiple AboutNewTabRedirector.sys.mjs runtime assets:" >&2
          echo "  $redirector_omni:$redirector_omni_path" >&2
          echo "  $omni:$candidate_path" >&2
          exit 1
        fi
        redirector_omni="$omni"
        redirector_omni_path="$candidate_path"
        redirector_extract_dir="$extract_dir"
      done < <(
        find "$extract_dir" -type f -path '*/AboutNewTabRedirector.sys.mjs' \
          | sed "s#^$extract_dir/##" \
          | LC_ALL=C sort
      )
    done
    if [ -z "$redirector_omni_path" ] || [ -z "$redirector_extract_dir" ]; then
      echo "error: failed to locate AboutNewTabRedirector.sys.mjs in extracted Firefox runtime" >&2
      exit 1
    fi

    redirector_runtime="$redirector_extract_dir/$redirector_omni_path"
    cat > "$work_dir/patch-redirector-runtime.pl" <<'PERL'
use strict;
use warnings;

my $path = shift @ARGV or die "missing runtime path\n";
local $/ = undef;
open my $in, '<', $path or die "failed to read $path: $!\n";
my $text = <$in>;
close $in;

my $count = ($text =~ s/const PREF_NEWTAB_SELF_LOADING =\n  "browser\.newtabpage\.activity-stream\.selfLoading\.enabled";\n/const PREF_NEWTAB_SELF_LOADING =\n  "browser.newtabpage.activity-stream.selfLoading.enabled";\n\nconst SECUREOS_LOCALHOST_URL = "https:\/\/localhost\/";\n/s);
die "failed to insert localhost redirect constant into $path\n" unless $count == 1;

$count = ($text =~ s/if \(\n      uri\.spec\.startsWith\("about:home"\) \|\|\n      \(uri\.spec\.startsWith\("about:newtab"\) && lazy\.BUILTIN_NEWTAB_ENABLED\)\n    \) \{\n      chromeURI = Services\.io\.newURI\(this\.defaultURL\);\n    \}/if (uri.spec.startsWith("about:home") || uri.spec.startsWith("about:newtab")) {\n      chromeURI = Services.io.newURI(SECUREOS_LOCALHOST_URL);\n    }/s);
die "failed to replace parent redirect block in $path\n" unless $count == 1;

$count = ($text =~ s/if \(uri\.spec\.startsWith\("about:home"\)\) \{\n      let cacheChannel = AboutHomeStartupCacheChild\.maybeGetCachedPageChannel\(\n        uri,\n        loadInfo\n      \);\n      if \(cacheChannel\) \{\n        return cacheChannel;\n      \}\n      pageURI = Services\.io\.newURI\(this\.defaultURL\);\n    \} else \{\n      \/\/ The only other possibility is about:newtab\.\n      \/\/\n      \/\/ If about:newtab is being requested, then any subsequent request for\n      \/\/ about:home should _never_ request the cache \(which might be woefully\n      \/\/ out of date compared to about:newtab\), so we disqualify the cache if\n      \/\/ it still happens to be around\.\n      AboutHomeStartupCacheChild\.disqualifyCache\(\);\n\n      if \(lazy\.BUILTIN_NEWTAB_ENABLED\) \{\n        pageURI = Services\.io\.newURI\(this\.defaultURL\);\n      \} else \{\n        pageURI = this\.getChromeURI\(uri\);\n      \}\n    \}/if (uri.spec.startsWith("about:home") || uri.spec.startsWith("about:newtab")) {\n      \/\/ Keep explicit about:home\/about:newtab loads on the SecureOS localhost\n      \/\/ shell, and bypass the startup cache so the built-in page is not reused.\n      AboutHomeStartupCacheChild.disqualifyCache();\n      pageURI = Services.io.newURI(SECUREOS_LOCALHOST_URL);\n    } else {\n      pageURI = this.getChromeURI(uri);\n    }/s);
die "failed to replace child redirect block in $path\n" unless $count == 1;

open my $out, '>', $path or die "failed to write $path: $!\n";
print {$out} $text;
close $out;
PERL
    perl "$work_dir/patch-redirector-runtime.pl" "$redirector_runtime"

    if ! grep -Fq 'const SECUREOS_LOCALHOST_URL = "https://localhost/";' "$redirector_runtime"; then
      echo "error: patched Firefox redirector runtime asset is missing the canonical localhost URL: $redirector_omni:$redirector_omni_path" >&2
      exit 1
    fi
    if ! grep -Fq 'pageURI = Services.io.newURI(SECUREOS_LOCALHOST_URL);' "$redirector_runtime"; then
      echo "error: patched Firefox redirector runtime asset is missing the localhost child redirect: $redirector_omni:$redirector_omni_path" >&2
      exit 1
    fi
    if ! grep -Fq 'chromeURI = Services.io.newURI(SECUREOS_LOCALHOST_URL);' "$redirector_runtime"; then
      echo "error: patched Firefox redirector runtime asset is missing the localhost parent redirect: $redirector_omni:$redirector_omni_path" >&2
      exit 1
    fi

    apply_source_patch_to_runtime_asset \
      "$localhost_patch" \
      browser/base/content/utilityOverlay.js \
      utilityOverlay.js \
      'return SECUREOS_LOCALHOST_URL;'

    utility_overlay_path="$(cat "$work_dir/utilityOverlay.js.applied-path")"
    utility_overlay_omni="$(cat "$work_dir/utilityOverlay.js.applied-omni")"
    utility_overlay_extract_dir=""
    for entry in "''${extracted_omnis[@]}"; do
      omni="''${entry%%:*}"
      if [ "$omni" = "$utility_overlay_omni" ]; then
        utility_overlay_extract_dir="''${entry#*:}"
      fi
    done
    if [ -z "$utility_overlay_extract_dir" ]; then
      echo "error: patched Firefox utilityOverlay runtime asset lost its extracted omni directory: $utility_overlay_omni:$utility_overlay_path" >&2
      exit 1
    fi
    if ! grep -Fq 'const SECUREOS_LOCALHOST_URL = "https://localhost/";' "$utility_overlay_extract_dir/$utility_overlay_path"; then
      echo "error: patched Firefox utilityOverlay runtime asset is missing the canonical localhost URL: $utility_overlay_omni:$utility_overlay_path" >&2
      exit 1
    fi
    if ! grep -Fq 'return SECUREOS_LOCALHOST_URL;' "$utility_overlay_extract_dir/$utility_overlay_path"; then
      echo "error: patched Firefox utilityOverlay runtime asset is missing the browser new-tab localhost override: $utility_overlay_omni:$utility_overlay_path" >&2
      exit 1
    fi
    if ! grep -Fq 'aURL == blankPageURL ||' "$utility_overlay_extract_dir/$utility_overlay_path"; then
      echo "error: patched Firefox utilityOverlay runtime asset is missing the blank-page URL handling guard: $utility_overlay_omni:$utility_overlay_path" >&2
      exit 1
    fi

    apply_source_patch_to_runtime_asset \
      "$localhost_patch" \
      browser/components/tabbrowser/NewTabPagePreloading.sys.mjs \
      NewTabPagePreloading.sys.mjs \
      'window.BROWSER_NEW_TAB_URL.startsWith("about:")'

    preloading_path="$(cat "$work_dir/NewTabPagePreloading.sys.mjs.applied-path")"
    preloading_omni="$(cat "$work_dir/NewTabPagePreloading.sys.mjs.applied-omni")"
    preloading_extract_dir=""
    for entry in "''${extracted_omnis[@]}"; do
      omni="''${entry%%:*}"
      if [ "$omni" = "$preloading_omni" ]; then
        preloading_extract_dir="''${entry#*:}"
      fi
    done
    if [ -z "$preloading_extract_dir" ]; then
      echo "error: patched Firefox new-tab preloading runtime asset lost its extracted omni directory: $preloading_omni:$preloading_path" >&2
      exit 1
    fi
    if ! grep -Fq 'canPreloadForWindow(window)' "$preloading_extract_dir/$preloading_path"; then
      echo "error: patched Firefox new-tab preloading runtime asset is missing per-window gating: $preloading_omni:$preloading_path" >&2
      exit 1
    fi
    if ! grep -Fq 'window.BROWSER_NEW_TAB_URL.startsWith("about:")' "$preloading_extract_dir/$preloading_path"; then
      echo "error: patched Firefox new-tab preloading runtime asset is missing the non-about preload guard: $preloading_omni:$preloading_path" >&2
      exit 1
    fi

    tabbrowser_omni_path=""
    tabbrowser_omni=""
    tabbrowser_extract_dir=""
    for entry in "''${extracted_omnis[@]}"; do
      omni="''${entry%%:*}"
      extract_dir="''${entry#*:}"
      while IFS= read -r candidate_path; do
        if [ -n "$tabbrowser_omni_path" ]; then
          echo "error: found multiple tabbrowser.js runtime assets:" >&2
          echo "  $tabbrowser_omni:$tabbrowser_omni_path" >&2
          echo "  $omni:$candidate_path" >&2
          exit 1
        fi
        tabbrowser_omni="$omni"
        tabbrowser_omni_path="$candidate_path"
        tabbrowser_extract_dir="$extract_dir"
      done < <(
        find "$extract_dir" -type f -path '*/tabbrowser.js' \
          | sed "s#^$extract_dir/##" \
          | LC_ALL=C sort
      )
    done
    if [ -z "$tabbrowser_omni_path" ] || [ -z "$tabbrowser_extract_dir" ]; then
      echo "error: failed to locate tabbrowser.js in extracted Firefox runtime" >&2
      exit 1
    fi

    tabbrowser_runtime="$tabbrowser_extract_dir/$tabbrowser_omni_path"
    cat > "$work_dir/patch-tabbrowser-runtime.pl" <<'PERL'
use strict;
use warnings;

my $path = shift @ARGV or die "missing runtime path\n";
local $/ = undef;
open my $in, '<', $path or die "failed to read $path: $!\n";
my $text = <$in>;
close $in;

my $count = ($text =~ s/if \(this\.tabs\.length == 1\) \{\n          \/\/ We already did PermitUnload in the content process\n          \/\/ for this tab \(the only one in the window\)\. So we don't\n          \/\/ need to do it again for any tabs\.\n          window\.skipNextCanClose = true;/if (this.tabs.length == 1) {\n          \/\/ We already did PermitUnload in the content process\n          \/\/ for this tab (the only one in the window). So we don't\n          \/\/ need to do it again for any tabs.\n          if (\n            !Services.prefs.getBoolPref("browser.tabs.closeWindowWithLastTab")\n          ) {\n            let tab = this.getTabForBrowser(browser);\n            if (tab) {\n              this.removeTab(tab, {\n                animate: false,\n                skipPermitUnload: true,\n                closeWindowWithLastTab: false,\n              });\n              event.preventDefault();\n              return;\n            }\n          }\n\n          window.skipNextCanClose = true;/s);
die "failed to replace DOMWindowClose last-tab block in $path\n" unless $count == 1;

open my $out, '>', $path or die "failed to write $path: $!\n";
print {$out} $text;
close $out;
PERL
    perl "$work_dir/patch-tabbrowser-runtime.pl" "$tabbrowser_runtime"

    if ! grep -Fq 'closeWindowWithLastTab: false,' "$tabbrowser_runtime"; then
      echo "error: patched Firefox tabbrowser runtime asset is missing the removeTab last-tab path: $tabbrowser_omni:$tabbrowser_omni_path" >&2
      exit 1
    fi
    if grep -Fq 'this.addTrustedTab(SECUREOS_LOCALHOST_URL' "$tabbrowser_runtime"; then
      echo "error: patched Firefox tabbrowser runtime asset still contains the old localhost trusted-tab replacement path: $tabbrowser_omni:$tabbrowser_omni_path" >&2
      exit 1
    fi

    apply_source_patch_to_runtime_asset \
      "$localhost_patch" \
      browser/components/customizableui/CustomizeMode.sys.mjs \
      CustomizeMode.sys.mjs \
      'this.#window.openTrustedLinkIn(this.#window.BROWSER_NEW_TAB_URL, "window");'

    apply_source_patch_to_runtime_asset \
      "$localhost_patch" \
      browser/components/profiles/ProfilesParent.sys.mjs \
      ProfilesParent.sys.mjs \
      'gBrowser.addTrustedTab(gBrowser.ownerGlobal.BROWSER_NEW_TAB_URL);'

    apply_source_patch_to_runtime_asset \
      "$localhost_patch" \
      browser/components/tabbrowser/content/opentabs-splitview.mjs \
      opentabs-splitview.mjs \
      'this.getWindow().BROWSER_NEW_TAB_URL,'

    apply_source_patch_to_runtime_asset \
      "$localhost_patch" \
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
    if ! sed -n '/window.openDialog(/,/);/p' "$browser_js_extract_dir/$browser_js_path" \
      | grep -Fq 'BROWSER_NEW_TAB_URL'; then
      echo "error: patched Firefox browser.js runtime asset lost Firefox's stock window new-tab entry point unexpectedly: $browser_js_omni:$browser_js_path" >&2
      exit 1
    fi

    apply_source_patch_to_runtime_asset \
      "$fxa_sync_ui_patch" \
      browser/base/content/browser.js \
      browser.js \
      'gSecureOSFxaSyncUi.init()'

    if ! grep -Fq 'olc-fxa-sync-ui-hidden' "$browser_js_extract_dir/$browser_js_path"; then
      echo "error: patched Firefox browser.js runtime asset is missing the ol-c Sync/FxA UI marker: $browser_js_omni:$browser_js_path" >&2
      exit 1
    fi
    if ! grep -Fq '#fxa-toolbar-menu-button' "$browser_js_extract_dir/$browser_js_path"; then
      echo "error: patched Firefox browser.js runtime asset is missing Sync/FxA toolbar hiding: $browser_js_omni:$browser_js_path" >&2
      exit 1
    fi

    apply_source_patch_to_runtime_asset \
      "$power_menu_patch" \
      browser/base/content/browser.js \
      browser.js \
      'gSecureOSPowerMenu.init()'

    if ! grep -Fq 'https://localhost/api/system/power' "$browser_js_extract_dir/$browser_js_path"; then
      echo "error: patched Firefox browser.js runtime asset is missing the ol-c power API endpoint: $browser_js_omni:$browser_js_path" >&2
      exit 1
    fi
    if ! grep -Fq 'document.addEventListener("command", this, true);' "$browser_js_extract_dir/$browser_js_path"; then
      echo "error: patched Firefox browser.js runtime asset is missing the ol-c app-menu command listener: $browser_js_omni:$browser_js_path" >&2
      exit 1
    fi

    power_menu_xhtml_path=""
    power_menu_xhtml_omni=""
    power_menu_xhtml_extract_dir=""
    for entry in "''${extracted_omnis[@]}"; do
      omni="''${entry%%:*}"
      extract_dir="''${entry#*:}"
      while IFS= read -r candidate_path; do
        if ! grep -Fq 'id="appMenu-quit-button2"' "$extract_dir/$candidate_path"; then
          continue
        fi
        if [ -n "$power_menu_xhtml_path" ]; then
          echo "error: found multiple app-menu browser.xhtml runtime assets:" >&2
          echo "  $power_menu_xhtml_omni:$power_menu_xhtml_path" >&2
          echo "  $omni:$candidate_path" >&2
          exit 1
        fi
        power_menu_xhtml_omni="$omni"
        power_menu_xhtml_path="$candidate_path"
        power_menu_xhtml_extract_dir="$extract_dir"
      done < <(
        find "$extract_dir" -type f -name browser.xhtml \
          | sed "s#^$extract_dir/##" \
          | LC_ALL=C sort
      )
    done
    if [ -z "$power_menu_xhtml_path" ] || [ -z "$power_menu_xhtml_extract_dir" ]; then
      echo "error: failed to locate the browser.xhtml runtime asset containing the app menu" >&2
      exit 1
    fi

    power_menu_xhtml_runtime="$power_menu_xhtml_extract_dir/$power_menu_xhtml_path"
    cat > "$work_dir/patch-power-menu-xhtml-runtime.pl" <<'PERL'
use strict;
use warnings;

my $path = shift @ARGV or die "missing runtime path\n";
local $/ = undef;
open my $in, '<', $path or die "failed to read $path: $!\n";
my $text = <$in>;
close $in;

my $old = <<'OLD';
      <toolbarseparator/>
      <toolbarbutton id="appMenu-quit-button2"
                     class="subviewbutton"
OLD

my $new = <<'NEW';
      <toolbarseparator id="appMenu-olc-power-separator"/>
      <toolbarbutton id="appMenu-olc-restart-button"
                     class="subviewbutton"
                     label="Restart"
                     data-olc-power-action="restart"
                     closemenu="none"/>
      <toolbarbutton id="appMenu-olc-shutdown-button"
                     class="subviewbutton"
                     label="Shut down"
                     data-olc-power-action="shutdown"
                     closemenu="none"/>
      <toolbarseparator/>
      <toolbarbutton id="appMenu-quit-button2"
                     class="subviewbutton"
NEW

my $count = ($text =~ s/\Q$old\E/$new/);
die "failed to insert SecureOS power menu items into $path\n" unless $count == 1;

open my $out, '>', $path or die "failed to write $path: $!\n";
print {$out} $text;
close $out;
PERL
    perl "$work_dir/patch-power-menu-xhtml-runtime.pl" "$power_menu_xhtml_runtime"

    if ! grep -Fq 'appMenu-olc-shutdown-button' "$power_menu_xhtml_runtime"; then
      echo "error: patched Firefox browser.xhtml runtime asset is missing the ol-c shutdown menu item: $power_menu_xhtml_omni:$power_menu_xhtml_path" >&2
      exit 1
    fi
    if ! grep -Fq 'data-olc-power-action="shutdown"' "$power_menu_xhtml_runtime"; then
      echo "error: patched Firefox browser.xhtml runtime asset is missing the ol-c shutdown action marker: $power_menu_xhtml_omni:$power_menu_xhtml_path" >&2
      exit 1
    fi

    apply_source_patch_to_runtime_asset \
      "$pane_split_patch" \
      browser/components/tabbrowser/content/drag-and-drop.js \
      drag-and-drop.js \
      'gSecureOSPaneSplitDrag.prepareForEvent(event)'

    apply_source_patch_to_runtime_asset \
      "$pane_split_patch" \
      browser/components/tabbrowser/content/tabbrowser.js \
      tabbrowser.js \
      'gSecureOSPaneSplits?.shouldCloseWindowWithLastTab'

    apply_source_patch_to_runtime_asset \
      "$pane_split_patch" \
      browser/base/content/browser.js \
      browser.js \
      'gSecureOSPaneSplits'

    if ! grep -Fq 'paneSummary()' "$browser_js_extract_dir/$browser_js_path"; then
      echo "error: patched Firefox browser.js runtime asset is missing the ol-c pane split summary hook: $browser_js_omni:$browser_js_path" >&2
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
      echo "OLC_FIREFOX_FXA_SYNC_UI_PATCH_APPLIED=1"
      echo "OLC_FIREFOX_POWER_MENU_PATCH_APPLIED=1"
      echo "OLC_FIREFOX_PANE_SPLIT_PATCH_APPLIED=1"
      printf 'patch_stack=%s\n' "''${firefox_patches[*]}"
      printf 'redirector_omni=%s\n' "$redirector_omni"
      printf 'redirector_path=%s\n' "$redirector_omni_path"
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
