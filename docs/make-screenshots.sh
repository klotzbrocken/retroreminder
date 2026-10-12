#!/bin/bash
# Regenerates the README images from the app (demo data, no real reminders): ./docs/make-screenshots.sh
cd "$(dirname "$0")/.."
B="build/RetroReminder.app/Contents/MacOS/RetroReminder"; T=/tmp/rr-shots; mkdir -p $T docs/screenshots; pkill RetroReminder
EN='-AppleLanguages (en) -AppleLocale en_US'; DE='-AppleLanguages (de) -AppleLocale de_DE'
shot() { name=$1; shift; "$B" -demo -active -scale=2 "$@" -snap=$T/$name.png -quit >/dev/null; }
shot hero       -AppleLanguages "(en)" -AppleLocale en_US
shot german-ui       -AppleLanguages "(de)" -AppleLocale de_DE
shot completed  -AppleLanguages "(en)" -AppleLocale en_US -mode=completed
shot lists      -AppleLanguages "(en)" -AppleLocale en_US -mode=multi
shot search     -AppleLanguages "(en)" -AppleLocale en_US -mode=search
shot compact    -AppleLanguages "(en)" -AppleLocale en_US -compact
shot list-window -AppleLanguages "(en)" -AppleLocale en_US -listwindow
shot settings -prefs -AppleLanguages "(en)" -AppleLocale en_US
shot popover    -AppleLanguages "(en)" -AppleLocale en_US -popfull -pop
python3 docs/process-screenshots.py $T
