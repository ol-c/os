#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
SCRIPT_PATH="${ROOT_DIR}/olc-firefox-source"
INIT_SCRIPT_PATH="${ROOT_DIR}/olc-init"
FLAKE="${ROOT_DIR}/flake.nix"
GITIGNORE="${ROOT_DIR}/.gitignore"
NIX_DEVELOPMENT="${ROOT_DIR}/nix/modules/development.nix"
AGENTS="${ROOT_DIR}/AGENTS.md"
README="${ROOT_DIR}/README.md"
WORKFLOW_DOC="${ROOT_DIR}/docs/firefox-source-workflow-plan.md"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

test_shared_source_script_contract() {
  local contents
  contents="$(cat "${SCRIPT_PATH}")"

  [[ "$contents" == *'WORKSPACE_ROOT="${OLC_FIREFOX_SOURCE_WORKSPACE_ROOT:-${SOURCE_ROOT}/.olc-firefox}"'* ]] || fail "expected shared Firefox source workspace under a gitignored repo path"
  [[ "$contents" == *'CACHE_ROOT="${WORKSPACE_ROOT}/cache"'* ]] || fail "expected the source helper to separate reusable cache state from working instances"
  [[ "$contents" == *'INSTANCE_ID="firefox-${firefox_version}-${SOURCE_STORE_HASH}-${nixpkgs_short_rev}"'* ]] || fail "expected source instances to be namespaced by Firefox identity"
  [[ "$contents" == *'CACHED_SOURCE_ARCHIVE_PATH="${CACHE_INSTANCE_ROOT}/${source_archive_basename}"'* ]] || fail "expected the source helper to keep a repo-local cached copy of the pinned source archive"
  [[ "$contents" == *'need_cmd patch'* ]] || fail "expected the source helper to require the standard patch tool"
  [[ "$contents" == *'need_cmd nix'* ]] || fail "expected the source helper to require nix for the pinned Firefox dev shell"
  [[ "$contents" == *'patch -p1 --no-backup-if-mismatch < "$patch_file"'* ]] || fail "expected the source helper to apply clean repo patch artifacts onto the source tree"
  [[ "$contents" == *'prepare_pristine_source_cache() {'* ]] || fail "expected the source helper to support a reusable pristine source cache"
  [[ "$contents" == *'ensure_cached_source_archive() {'* ]] || fail "expected the source helper to cache the pinned source archive under the shared repo workspace"
  [[ "$contents" == *'cp -f "$SOURCE_ARCHIVE_STORE_REALIZED" "$CACHED_SOURCE_ARCHIVE_PATH"'* ]] || fail "expected the source helper to copy the realized store tarball into the repo-local cache"
  [[ "$contents" == *'tar -xJf "$CACHED_SOURCE_ARCHIVE_PATH" --strip-components=1 -C "$extract_root"'* ]] || fail "expected pristine extraction to read from the repo-local cached archive"
  [[ "$contents" == *'cp -a --reflink=auto "$PRISTINE_SOURCE_DIR/." "$copy_root/"'* ]] || fail "expected source instances to be copied from the pristine cache"
  [[ "$contents" != *'git add -A'* ]] || fail "expected the default shared source bootstrap not to index the full Firefox tree"
  [[ "$contents" == *"printf 'mk_add_options MOZ_OBJDIR=%s\\n' \"\${OBJDIR}\""* ]] || fail "expected the source helper to generate a shared objdir mozconfig"
  [[ "$contents" == *'ac_add_options --enable-project=browser'* ]] || fail "expected the source helper to generate a standard Firefox project mozconfig"
  [[ "$contents" == *'ac_add_options --with-libclang-path=${LIBCLANG_PATH:-}'* ]] || fail "expected the source helper to thread the dev-shell libclang path into mozconfig"
  [[ "$contents" == *'ac_add_options --with-wasi-sysroot=${OLC_FIREFOX_WASI_SYSROOT:-}'* ]] || fail "expected the source helper to thread the dev-shell wasi sysroot into mozconfig"
  [[ "$contents" == *'exec ./mach "$@"'* ]] || fail "expected the source helper to run the standard mach workflow from the shared tree"
  [[ "$contents" == *'exec nix develop "${ROOT_DIR}#firefox-source"'* ]] || fail "expected the source helper to re-enter a pinned Firefox dev shell"
  [[ "$contents" == *'OLC_FIREFOX_SOURCE_DEVENV=1'* ]] || fail "expected the source helper to mark re-entry into the Firefox dev shell"
  [[ "$contents" == *'__mach-direct'* ]] || fail "expected the source helper to support an internal mach re-entry path"
  [[ "$contents" == *'__shell-direct'* ]] || fail "expected the source helper to support an internal shell re-entry path"
  [[ "$contents" == *'validate_dev_shell_env() {'* ]] || fail "expected the source helper to validate the dev-shell-only Firefox build prerequisites"
  [[ "$contents" == *'export MOZBUILD_STATE_PATH="${STATE_DIR}/mozbuild"'* ]] || fail "expected the source helper to isolate mozbuild state per shared instance"
  [[ "$contents" == *'MACH_BUILD_PYTHON_NATIVE_PACKAGE_SOURCE'* ]] || fail "expected the source helper to force mach to use the dev-shell Python"
  [[ "$contents" == *'export HOST_CC="${HOST_CC:-$CC}"'* ]] || fail "expected the source helper to default HOST_CC to the selected compiler"
  [[ "$contents" == *'export HOST_CXX="${HOST_CXX:-${CXX:-}}"'* ]] || fail "expected the source helper to default HOST_CXX to the selected compiler"
  [[ "$contents" == *'export AS="${CC}"'* ]] || fail "expected the source helper to normalize the assembler to the compiler driver for mach builds"
  [[ "$contents" == *'export HOST_AS="${HOST_CC}"'* ]] || fail "expected the source helper to normalize the host assembler to the host compiler driver"
  [[ "$contents" == *'warning: existing Firefox source instance uses a different patch fingerprint.'* ]] || fail "expected the source helper to detect stale patch stacks"
  [[ "$contents" == *'resolve_instance_only() {'* ]] || fail "expected the source helper to support cheap identity-only status checks"
  [[ "$contents" == *'prepare-cache      Bootstrap or reuse the pristine pinned Firefox source cache.'* ]] || fail "expected the source helper to expose a dedicated pristine cache command"
  [[ "$contents" == *'archive_ready:   $(if [ -f "$CACHED_SOURCE_ARCHIVE_PATH" ]; then printf true; else printf false; fi)'* ]] || fail "expected status to report whether the repo-local cached archive already exists"
  [[ "$contents" == *'cache_ready:     $(if [ -d "$PRISTINE_SOURCE_DIR" ]; then printf true; else printf false; fi)'* ]] || fail "expected status to report whether the pristine cache already exists"
  [[ "$contents" == *'instance_ready:  $(if [ -d "$SOURCE_DIR" ]; then printf true; else printf false; fi)'* ]] || fail "expected status to report whether the shared source tree already exists"
  [[ "$contents" == *'recreate           Recreate the shared source tree'* ]] || fail "expected the source helper to support rebuilding the shared tree from the pinned source archive"
}

test_gitignore_documents_shared_source_workspace() {
  local contents
  contents="$(cat "${GITIGNORE}")"

  [[ "$contents" == *'.olc-firefox/'* ]] || fail "expected .gitignore to document the shared Firefox source workspace"
}

test_flake_exports_firefox_dev_shell() {
  local contents
  contents="$(cat "${FLAKE}")"

  [[ "$contents" == *'devShells.${system}.firefox-source'* ]] || fail "expected the flake to export a Firefox source dev shell"
  [[ "$contents" == *'inputsFrom = [ firefoxSourcePkgs.firefox-unwrapped ];'* ]] || fail "expected the Firefox dev shell to inherit Firefox build inputs"
  [[ "$contents" == *'python3'* ]] || fail "expected the Firefox dev shell to include python3"
  [[ "$contents" == *'llvm'* ]] || fail "expected the Firefox dev shell to include llvm tools"
  [[ "$contents" == *'clang'* ]] || fail "expected the Firefox dev shell to include clang for bindgen"
  [[ "$contents" == *'llvmPackages.libclang'* ]] || fail "expected the Firefox dev shell to include libclang for bindgen"
  [[ "$contents" == *'LIBCLANG_PATH = "${firefoxSourcePkgs.llvmPackages.libclang.lib}/lib";'* ]] || fail "expected the Firefox dev shell to export LIBCLANG_PATH for bindgen"
  [[ "$contents" == *'firefoxWasmCc = firefoxSourcePkgs.writeShellScriptBin "olc-firefox-source-wasm-cc"'* ]] || fail "expected the Firefox dev shell to define a sanitized wasi C compiler wrapper"
  [[ "$contents" == *'firefoxWasmCxx = firefoxSourcePkgs.writeShellScriptBin "olc-firefox-source-wasm-cxx"'* ]] || fail "expected the Firefox dev shell to define a sanitized wasi C++ compiler wrapper"
  [[ "$contents" == *'unset NIX_LDFLAGS'* ]] || fail "expected the Firefox dev shell wasi compiler wrappers to drop host linker flags"
  [[ "$contents" == *'WASM_CC = "${firefoxWasmCc}/bin/olc-firefox-source-wasm-cc";'* ]] || fail "expected the Firefox dev shell to export the sanitized wasi C compiler wrapper"
  [[ "$contents" == *'WASM_CXX = "${firefoxWasmCxx}/bin/olc-firefox-source-wasm-cxx";'* ]] || fail "expected the Firefox dev shell to export the sanitized wasi C++ compiler wrapper"
  [[ "$contents" == *'OLC_FIREFOX_WASI_SYSROOT = "${firefoxWasiSysRoot}";'* ]] || fail "expected the Firefox dev shell to export the nixpkgs-style wasi sysroot"
  [[ "$contents" == *'export CC="${firefoxSourcePkgs.clang}/bin/clang"'* ]] || fail "expected the Firefox dev shell to default CC to clang for standard Firefox source builds"
  [[ "$contents" == *'export CXX="${firefoxSourcePkgs.clang}/bin/clang++"'* ]] || fail "expected the Firefox dev shell to default CXX to clang++ for standard Firefox source builds"
  [[ "$contents" == *"export HOST_CC=\"''\${HOST_CC:-\$CC}\""* ]] || fail "expected the Firefox dev shell to default HOST_CC to the selected compiler"
  [[ "$contents" == *"export HOST_CXX=\"''\${HOST_CXX:-\$CXX}\""* ]] || fail "expected the Firefox dev shell to default HOST_CXX to the selected compiler"
  [[ "$contents" == *'export AS="$CC"'* ]] || fail "expected the Firefox dev shell to normalize AS onto the compiler driver"
  [[ "$contents" == *'export HOST_AS="$HOST_CC"'* ]] || fail "expected the Firefox dev shell to normalize HOST_AS onto the host compiler driver"
  [[ "$contents" == *'pkg-config'* ]] || fail "expected the Firefox dev shell to include pkg-config"
  [[ "$contents" == *'alsa-lib'* ]] || fail "expected the Firefox dev shell to include alsa development metadata"
}

test_firefox_dev_shell_defaults_to_clang() {
  local env_output
  env_output="$(
    nix develop "${ROOT_DIR}#firefox-source" \
      --command bash -lc 'printf "CC=%s\nCXX=%s\nHOST_CC=%s\nHOST_CXX=%s\nAS=%s\nHOST_AS=%s\n" "$CC" "$CXX" "$HOST_CC" "$HOST_CXX" "$AS" "$HOST_AS"'
  )"

  [[ "$env_output" == *$'\nCC='*'/bin/clang'* || "$env_output" == CC=*'/bin/clang'* ]] || fail "expected the Firefox dev shell to default CC to clang"
  [[ "$env_output" == *$'\nCXX='*'/bin/clang++'* || "$env_output" == CXX=*'/bin/clang++'* ]] || fail "expected the Firefox dev shell to default CXX to clang++"
  [[ "$env_output" == *$'\nHOST_CC='*'/bin/clang'* || "$env_output" == HOST_CC=*'/bin/clang'* ]] || fail "expected the Firefox dev shell to default HOST_CC to clang"
  [[ "$env_output" == *$'\nHOST_CXX='*'/bin/clang++'* || "$env_output" == HOST_CXX=*'/bin/clang++'* ]] || fail "expected the Firefox dev shell to default HOST_CXX to clang++"
  [[ "$env_output" == *$'\nAS='*'/bin/clang'* || "$env_output" == AS=*'/bin/clang'* ]] || fail "expected the Firefox dev shell to normalize AS onto clang"
  [[ "$env_output" == *$'\nHOST_AS='*'/bin/clang'* || "$env_output" == HOST_AS=*'/bin/clang'* ]] || fail "expected the Firefox dev shell to normalize HOST_AS onto clang"
}

test_wasi_toolchain_does_not_poison_native_link_flags() {
  local env_output
  env_output="$(
    nix develop "${ROOT_DIR}#firefox-source" \
      --command bash -lc 'printf "%s\n" "${NIX_LDFLAGS:-}"'
  )"

  [[ "$env_output" != *'wasm32-unknown-wasi'* ]] || fail "expected native linker flags in the Firefox dev shell to stay free of wasi search paths"
  [[ "$env_output" != *'compiler-rt-static-wasm32-unknown-wasi'* ]] || fail "expected the Firefox dev shell not to leak compiler-rt wasi libraries into native links"
  [[ "$env_output" != *'libcxx-static-wasm32-unknown-wasi'* ]] || fail "expected the Firefox dev shell not to leak libcxx wasi libraries into native links"
}

test_guest_wrapper_contract() {
  local contents
  contents="$(cat "${NIX_DEVELOPMENT}")"

  [[ "$contents" == *'writeShellScriptBin "olc-firefox-source"'* ]] || fail "expected the guest development profile to expose olc-firefox-source"
  [[ "$contents" != *'writeShellScriptBin "patched-firefox"'* ]] || fail "expected the guest development profile not to keep the retired patched-firefox path"
  [[ "$contents" == *'if [ -x "$source_root/olc-firefox-source" ]; then'* ]] || fail "expected the guest wrapper to prefer the live shared repo script"
  [[ "$contents" == *'exec ${pkgs.bash}/bin/bash ${../../olc-firefox-source} "$@"'* ]] || fail "expected the guest wrapper to fall back to the repo-owned helper"
}

test_repo_init_contract() {
  local contents
  contents="$(cat "${INIT_SCRIPT_PATH}")"

  [[ "$contents" == *'usage: olc-init <command>'* ]] || fail "expected a generic repo init entrypoint"
  [[ "$contents" == *'"$FIREFOX_SOURCE_HELPER" prepare-cache'* ]] || fail "expected repo init prepare to build the pristine Firefox source cache"
  [[ "$contents" == *'"$FIREFOX_SOURCE_HELPER" status'* ]] || fail "expected repo init status to surface Firefox source cache status"
  [[ "$contents" == *'Prepare reusable shared assets for this repo. Safe to run repeatedly.'* ]] || fail "expected repo init to document safe repeated use"
}

test_agents_records_shared_source_loop() {
  local contents
  contents="$(cat "${AGENTS}")"

  [[ "$contents" == *"bash tests/test-olc-firefox-source.sh"* ]] || fail "expected AGENTS.md to record the shared Firefox source workflow test"
}

test_docs_record_recommended_source_loop() {
  local readme_contents
  local workflow_contents
  readme_contents="$(cat "${README}")"
  workflow_contents="$(cat "${WORKFLOW_DOC}")"

  [[ "$readme_contents" == *"This is the recommended Firefox development loop"* ]] || fail "expected README to mark the shared source-tree path as the recommended Firefox loop"
  [[ "$readme_contents" != *'`patched-firefox`'* ]] || fail "expected README not to keep the retired patched-firefox loop"
  [[ "$readme_contents" == *"0003-add-plugin-button-dev-icon.patch"* ]] || fail "expected README to mention the current dev-loop proof patch"
  [[ "$workflow_contents" == *"This is the recommended Firefox development loop"* ]] || fail "expected workflow doc to describe the shared source-tree loop as recommended"
  [[ "$workflow_contents" != *'`patched-firefox`'* ]] || fail "expected workflow doc not to keep the retired patched-firefox loop"
  [[ "$workflow_contents" == *"Recommended Proof Loop"* ]] || fail "expected workflow doc to document the proof-oriented source-tree loop"
}

test_pending_proof_patch_exists() {
  local contents
  contents="$(cat "${ROOT_DIR}/patches/firefox/pending/0003-add-plugin-button-dev-icon.patch")"

  [[ "$contents" == *"browser/base/content/navigator-toolbox.inc.xhtml"* ]] || fail "expected the pending proof patch to insert a real toolbar button into the main browser chrome"
  [[ "$contents" == *'id="olc-dev-build-button"'* ]] || fail "expected the pending proof patch to define a dedicated dev toolbar button beside the plugin button"
  [[ "$contents" == *'tooltiptext="Switch to dark mode"'* ]] || fail "expected the pending proof patch to seed the appearance toggle with a light-mode action label"
  [[ "$contents" == *'olc-appearance-mode="light"'* ]] || fail "expected the pending proof patch to seed the appearance toggle with a default light-mode icon state"
  [[ "$contents" == *"browser/base/content/browser.js"* ]] || fail "expected the pending proof patch to connect the toolbar button to the browser appearance bridge"
  [[ "$contents" == *"gSecureOSAppearanceToolbarButton"* ]] || fail "expected the pending proof patch to define a chrome controller for the appearance toggle button"
  [[ "$contents" == *'setMode(this.nextMode())'* ]] || fail "expected the pending proof patch to toggle the existing appearance bridge"
  [[ "$contents" == *"browser/base/content/test/general/browser_localhost_shell.js"* ]] || fail "expected the pending proof patch to cover the appearance toolbar button in browser chrome tests"
  [[ "$contents" == *"browser/base/content/test/keyboard/browser_toolbarKeyNav.js"* ]] || fail "expected the pending proof patch to update toolbar keyboard navigation coverage"
  [[ "$contents" == *"browser/themes/shared/toolbarbutton-icons.css"* ]] || fail "expected the pending proof patch to style the dev toolbar button through the standard toolbar icon stylesheet"
  [[ "$contents" == *'olc-appearance-mode="dark"'* ]] || fail "expected the pending proof patch to swap the toolbar icon when dark mode is active"
  [[ "$contents" == *"data:image/svg+xml"* ]] || fail "expected the pending proof patch to embed sun and moon toolbar glyphs for the appearance toggle"
}

test_shared_source_script_contract
test_gitignore_documents_shared_source_workspace
test_flake_exports_firefox_dev_shell
test_firefox_dev_shell_defaults_to_clang
test_wasi_toolchain_does_not_poison_native_link_flags
test_guest_wrapper_contract
test_repo_init_contract
test_agents_records_shared_source_loop
test_docs_record_recommended_source_loop
test_pending_proof_patch_exists

echo "PASS: olc-firefox-source"
