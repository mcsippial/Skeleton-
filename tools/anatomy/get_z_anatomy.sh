#!/bin/bash
# Downloads the free Z-Anatomy atlas (CC BY-SA 4.0, prototyping only — see CLAUDE.md) and
# prepares it for Skeleton. Run from the repo folder on your Mac:
#
#     bash tools/anatomy/get_z_anatomy.sh
#
# Needs Blender (brew install --cask blender). Takes a few minutes; the download is large.
set -euo pipefail
cd "$(dirname "$0")/../.."

BLENDER=/Applications/Blender.app/Contents/MacOS/Blender
[ -x "$BLENDER" ] || { echo "Blender not found. Install it with: brew install --cask blender"; exit 1; }

WORK="$HOME/Downloads/z-anatomy"
mkdir -p "$WORK"
if [ ! -s "$WORK/Z-Anatomy.zip" ]; then
  echo "Downloading Z-Anatomy…"
  curl -L --fail --progress-bar -o "$WORK/Z-Anatomy.zip" \
    "https://github.com/Z-Anatomy/Models-of-human-anatomy/raw/master/Z-Anatomy.zip"
fi

echo "Unpacking…"
rm -rf "$WORK/unpacked" && mkdir -p "$WORK/unpacked"
unzip -q -o "$WORK/Z-Anatomy.zip" -d "$WORK/unpacked"
# The template may hold another zip inside it.
find "$WORK/unpacked" -name "*.zip" -exec unzip -q -o {} -d "$WORK/unpacked" \; 2>/dev/null || true

BLEND=$(find "$WORK/unpacked" -name "*.blend" -print0 | xargs -0 ls -S | head -1)
[ -n "$BLEND" ] || { echo "No .blend file found in the download. Send Claude: ls -R $WORK/unpacked | head -50"; exit 1; }
echo "Using $BLEND"

"$BLENDER" -b --python tools/anatomy/prepare_anatomy.py -- --input "$BLEND"

echo
echo "Done. Now quit Xcode and run: xcodegen generate && open Skeleton.xcodeproj"
