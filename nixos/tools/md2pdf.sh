#!/usr/bin/env bash
# Render a guide (a folder with README.md + NN-*.md chapters) into one PDF styled
# like the original NixOS guides: A4, blue headings, boxed tables, callouts, footer.
#
# Usage:
#   nixos/tools/md2pdf.sh                      # both NixOS guides -> nixos/build/
#   nixos/tools/md2pdf.sh <guide-dir> [out.pdf] [footer text]
#     e.g. nixos/tools/md2pdf.sh gentoo        # works for the Gentoo docs too
#
# Needs pandoc plus one PDF engine, tried in this order:
#   weasyprint  ->  chromium / google-chrome  ->  Chrome Flatpak (com.google.Chrome)
# On NixOS: nix shell nixpkgs#pandoc nixpkgs#chromium -c nixos/tools/md2pdf.sh
set -euo pipefail

tools=$(cd "$(dirname "$0")" && pwd)
nixos=$(dirname "$tools")

if [ $# -eq 0 ]; then
  "$0" "$nixos/install"    "$nixos/build/NixOS-HP-ZBook-Install-Guide.pdf" \
       "NixOS on the HP ZBook - installation guide"
  "$0" "$nixos/operations" "$nixos/build/NixOS-Daily-Operations-Guide.pdf" \
       "Working with NixOS - daily operations guide"
  exit
fi

src=$(cd "$1" && pwd)
[ -f "$src/README.md" ] || { echo "md2pdf: $src/README.md not found" >&2; exit 1; }
out=$(realpath -m "${2:-$nixos/build/$(basename "$src").pdf}")
title=$(sed -n 's/^# //p' "$src/README.md" | head -1)
footer=${3:-$title}

command -v pandoc >/dev/null || { echo "md2pdf: pandoc not found" >&2; exit 1; }
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
mkdir -p "$(dirname "$out")"

# One document; each chapter starts with an anchor that links.lua points to.
shopt -s nullglob
for f in "$src/README.md" "$src"/[0-9][0-9]-*.md; do
  printf '\n\n<div id="file-%s" class="chapter"></div>\n\n' "$(basename "$f" .md)"
  cat "$f"
done > "$tmp/guide.md"

esc=${footer//\\/\\\\}; esc=${esc//\"/\\\"}
printf '@page { @bottom-left { content: "%s"; } }\n' "$esc" > "$tmp/footer.css"

pandoc "$tmp/guide.md" -f gfm -t html5 --standalone --embed-resources \
  --metadata pagetitle="$title" --css "$tools/guide.css" --css "$tmp/footer.css" \
  --lua-filter "$tools/links.lua" -o "$tmp/guide.html"

chrome_print() {   # $@ = command to start Chrome/Chromium
  "$@" --headless --disable-gpu --no-pdf-header-footer --user-data-dir="$tmp/profile" \
    --print-to-pdf="$tmp/guide.pdf" "file://$tmp/guide.html" >"$tmp/chrome.log" 2>&1 \
    || { cat "$tmp/chrome.log" >&2; return 1; }
}

if command -v weasyprint >/dev/null; then
  weasyprint "$tmp/guide.html" "$tmp/guide.pdf"
elif c=$(command -v chromium || command -v chromium-browser || command -v google-chrome-stable \
         || command -v google-chrome); then
  chrome_print "$c"
elif flatpak info com.google.Chrome >/dev/null 2>&1; then
  chrome_print flatpak run --filesystem="$tmp" com.google.Chrome
else
  echo "md2pdf: no PDF engine (weasyprint, chromium/chrome, or the Chrome Flatpak)" >&2
  exit 1
fi

[ -s "$tmp/guide.pdf" ] || { echo "md2pdf: engine produced no PDF" >&2; exit 1; }
mv "$tmp/guide.pdf" "$out"
echo "$out"
