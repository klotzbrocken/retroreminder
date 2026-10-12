#!/bin/bash
# Referenz-Snapshots erzeugen: ./Reference/snap.sh [zielordner]
cd "$(dirname "$0")/.."
D=${1:-/tmp/ml}; mkdir -p "$D"; pkill RetroReminder
"build/RetroReminder.app/Contents/MacOS/RetroReminder" -demo -ref -date=2012-06-18 -AppleLanguages "(en)" -AppleLocale en_US -snap="$D/ref_main.png" -pop -quit
