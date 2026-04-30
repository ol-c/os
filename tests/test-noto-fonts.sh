#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)"
NIX=(nix --extra-experimental-features "nix-command flakes")

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

font_defaults_json="$("${NIX[@]}" eval --json "${ROOT_DIR}#nixosConfigurations.ol-c.config.fonts.fontconfig.defaultFonts")"
font_packages_json="$("${NIX[@]}" eval --json "${ROOT_DIR}#nixosConfigurations.ol-c.config.fonts.packages" --apply 'pkgs: map (p: p.name) pkgs')"
enable_default_packages="$("${NIX[@]}" eval --raw "${ROOT_DIR}#nixosConfigurations.ol-c.config.fonts.enableDefaultPackages" --apply 'enabled: if enabled then "true" else "false"')"

mapfile -t font_paths < <(
  "${NIX[@]}" build \
    --inputs-from "$ROOT_DIR" \
    --no-link \
    --print-out-paths \
    nixpkgs#noto-fonts \
    nixpkgs#noto-fonts-cjk-sans \
    nixpkgs#noto-fonts-cjk-serif \
    nixpkgs#noto-fonts-color-emoji
)

if [[ "${#font_paths[@]}" -ne 4 ]]; then
  fail "expected four Noto font package paths, got ${#font_paths[@]}"
fi

OLC_FONT_DEFAULTS_JSON="$font_defaults_json" \
OLC_FONT_PACKAGES_JSON="$font_packages_json" \
OLC_ENABLE_DEFAULT_PACKAGES="$enable_default_packages" \
  "${NIX[@]}" shell \
    --inputs-from "$ROOT_DIR" \
    nixpkgs#fontconfig \
    nixpkgs#python3 \
    --command python3 - "${font_paths[@]}" <<'PY'
import json
import os
import subprocess
import sys
from pathlib import Path

defaults = json.loads(os.environ["OLC_FONT_DEFAULTS_JSON"])
packages = json.loads(os.environ["OLC_FONT_PACKAGES_JSON"])
enable_default_packages = os.environ["OLC_ENABLE_DEFAULT_PACKAGES"]
font_roots = [Path(value) for value in sys.argv[1:]]

def fail(message):
    print(f"FAIL: {message}", file=sys.stderr)
    sys.exit(1)

if enable_default_packages != "false":
    fail("expected fonts.enableDefaultPackages to be false")

required_package_prefixes = [
    "noto-fonts-",
    "noto-fonts-cjk-sans-",
    "noto-fonts-cjk-serif-",
    "noto-fonts-color-emoji-",
]
for prefix in required_package_prefixes:
    if not any(name.startswith(prefix) for name in packages):
        fail(f"expected configured font package with prefix {prefix}")

expected_defaults = {
    "sansSerif": ["Noto Sans", "Noto Sans CJK SC", "Noto Color Emoji"],
    "serif": ["Noto Serif", "Noto Serif CJK SC", "Noto Color Emoji"],
    "monospace": ["Noto Sans Mono", "Noto Sans CJK SC", "Noto Color Emoji"],
    "emoji": ["Noto Color Emoji"],
}
for family, expected in expected_defaults.items():
    actual = defaults.get(family)
    if not isinstance(actual, list):
        fail(f"expected fontconfig default {family} to be a list")
    if actual[0] != expected[0]:
        fail(f"expected {family} to prefer {expected[0]}, got {actual[0]}")
    for font_name in expected:
        if font_name not in actual:
            fail(f"expected {family} defaults to include {font_name}")

font_files = []
for root in font_roots:
    if not root.exists():
        fail(f"font package path does not exist: {root}")
    for path in root.rglob("*"):
        name = path.name.lower()
        if path.is_file() and (
            name.endswith(".ttf")
            or name.endswith(".otf")
            or name.endswith(".ttc")
            or name.endswith(".otc")
        ):
            font_files.append(path)

if not font_files:
    fail("expected at least one font file in the Noto package set")

required_codepoints = {
    "latin": 0x0041,
    "latin-extended": 0x0141,
    "greek": 0x03A9,
    "cyrillic": 0x0416,
    "armenian": 0x0531,
    "hebrew": 0x05D0,
    "arabic": 0x0639,
    "devanagari": 0x0915,
    "bengali": 0x0995,
    "gurmukhi": 0x0A15,
    "gujarati": 0x0A95,
    "odia": 0x0B15,
    "tamil": 0x0B95,
    "telugu": 0x0C15,
    "kannada": 0x0C95,
    "malayalam": 0x0D15,
    "sinhala": 0x0D9A,
    "thai": 0x0E01,
    "lao": 0x0E81,
    "tibetan": 0x0F40,
    "myanmar": 0x1000,
    "georgian": 0x10D0,
    "hangul": 0xD55C,
    "ethiopic": 0x1200,
    "cherokee": 0x13A0,
    "canadian-aboriginal": 0x140A,
    "ogham": 0x1681,
    "runic": 0x16A0,
    "khmer": 0x1780,
    "mongolian": 0x1820,
    "hiragana": 0x3042,
    "katakana": 0x30A2,
    "cjk": 0x4E2D,
    "math-symbol": 0x2200,
    "emoji": 0x1F600,
}

remaining = dict(required_codepoints)
providers = {}

def check_charset_token(token, font_file):
    if "-" in token:
        start_hex, end_hex = token.split("-", 1)
    else:
        start_hex = token
        end_hex = token
    try:
        start = int(start_hex, 16)
        end = int(end_hex, 16)
    except ValueError:
        return
    for label, codepoint in list(remaining.items()):
        if start <= codepoint <= end:
            providers[label] = font_file.name
            del remaining[label]

for font_file in font_files:
    result = subprocess.run(
        ["fc-scan", "--format=%{charset}\\n", str(font_file)],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
    )
    for token in result.stdout.split():
        check_charset_token(token, font_file)
    if not remaining:
        break

if remaining:
    missing = ", ".join(f"{label}=U+{codepoint:04X}" for label, codepoint in sorted(remaining.items()))
    fail(f"missing Noto glyph coverage for sample codepoints: {missing}")

print(f"PASS: noto fonts ({len(required_codepoints)} sample codepoints covered)")
PY
