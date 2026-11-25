#!/bin/bash
# Construit "Cue Station.app" dans le dossier dist/
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift introuvable. Lance d'abord : xcode-select --install"
  exit 1
fi

echo "== Compilation (Intel + Apple Silicon si possible) =="
if swift build -c release --arch arm64 --arch x86_64 >/tmp/cuestation-universal.log 2>&1; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/CueStation"
  echo "Binaire universel OK"
else
  echo "Binaire universel impossible ici (normal sans Xcode complet), compilation pour ce Mac seulement"
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/CueStation"
fi

APP="dist/Cue Station.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/CueStation"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
(cd dist && ditto -c -k --keepParent "Cue Station.app" "Cue-Station-Mac.zip")

echo
echo "Terminé : $(pwd)/dist/Cue Station.app"
echo "Zip à copier sur les autres Mac : $(pwd)/dist/Cue-Station-Mac.zip"
if [ -z "${CI:-}" ]; then open dist; fi
