#!/bin/bash
# Construit "Buzzer Trigger.app" dans le dossier dist/
set -euo pipefail
cd "$(dirname "$0")"

if ! command -v swift >/dev/null 2>&1; then
  echo "Swift introuvable. Lance d'abord : xcode-select --install"
  exit 1
fi

echo "== Compilation (Intel + Apple Silicon si possible) =="
if swift build -c release --arch arm64 --arch x86_64 >/tmp/buzzer-universal.log 2>&1; then
  BIN="$(swift build -c release --arch arm64 --arch x86_64 --show-bin-path)/BuzzerTrigger"
  echo "Binaire universel OK"
else
  echo "Binaire universel impossible ici (normal sans Xcode complet), compilation pour ce Mac seulement"
  swift build -c release
  BIN="$(swift build -c release --show-bin-path)/BuzzerTrigger"
fi

APP="dist/Buzzer Trigger.app"
rm -rf dist
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
cp "$BIN" "$APP/Contents/MacOS/BuzzerTrigger"
cp Info.plist "$APP/Contents/Info.plist"
codesign --force --deep --sign - "$APP"
(cd dist && ditto -c -k --keepParent "Buzzer Trigger.app" "Buzzer-Trigger-Mac.zip")

echo
echo "Terminé : $(pwd)/dist/Buzzer Trigger.app"
echo "Zip à copier sur les autres Mac : $(pwd)/dist/Buzzer-Trigger-Mac.zip"
if [ -z "${CI:-}" ]; then open dist; fi
