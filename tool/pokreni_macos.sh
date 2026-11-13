#!/bin/bash
# Pokreće Kalkulino na macOS-u tako da glasovne komande rade, uz hot reload.
#
# Zašto: kad `flutter run` (ili VS Code) pokrene aplikaciju, macOS dozvolu za
# mikrofon traži u ime VS Code-a/Terminala i ugasi aplikaciju. Ovdje se
# aplikacija otvara preko `open` (kao dvoklik), pa se flutter samo prikači.
#
# Upotreba:  ./tool/pokreni_macos.sh      (r = hot reload, R = restart, q = kraj)
set -euo pipefail
cd "$(dirname "$0")/.."

APP=build/macos/Build/Products/Debug/Kalkulino.app
LOG=$(mktemp -t kalkulino)

flutter build macos --debug
pkill -x Kalkulino 2>/dev/null || true

open -n --stdout "$LOG" --stderr "$LOG" "$APP"

URL=""
for _ in $(seq 1 60); do
  URL=$(grep -oE 'http://127\.0\.0\.1:[0-9]+/[^ ]+/' "$LOG" | head -1 || true)
  [ -n "$URL" ] && break
  sleep 0.5
done
if [ -z "$URL" ]; then
  echo "Nisam našao adresu Dart VM servisa. Log:"; cat "$LOG"; exit 1
fi

echo "Aplikacija pokrenuta, prikačinjem flutter ($URL)…"
flutter attach -d macos --debug-url "$URL"
