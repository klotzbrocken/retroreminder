#!/bin/bash
# Erzeugt die README-Bilder aus der App (Demo-Daten, keine echten Erinnerungen): ./docs/make-screenshots.sh
cd "$(dirname "$0")/.."
B="build/RetroReminder.app/Contents/MacOS/RetroReminder"; T=/tmp/rr-shots; mkdir -p $T docs/screenshots; pkill RetroReminder
EN='-AppleLanguages (en) -AppleLocale en_US'; DE='-AppleLanguages (de) -AppleLocale de_DE'
shot() { name=$1; shift; "$B" -demo -active -scale=2 "$@" -snap=$T/$name.png -quit >/dev/null; }
shot main-en        -AppleLanguages "(en)" -AppleLocale en_US
shot main-de        -AppleLanguages "(de)" -AppleLocale de_DE
shot completed-en   -AppleLanguages "(en)" -AppleLocale en_US -mode=completed
shot lists-en       -AppleLanguages "(en)" -AppleLocale en_US -mode=multi
shot search-en      -AppleLanguages "(en)" -AppleLocale en_US -mode=search
shot compact-en     -AppleLanguages "(en)" -AppleLocale en_US -compact
shot listwindow-en  -AppleLanguages "(en)" -AppleLocale en_US -listwindow
shot prefs-de       -prefs -AppleLanguages "(de)" -AppleLocale de_DE
shot popover-en     -AppleLanguages "(en)" -AppleLocale en_US -popfull -pop
python3 docs/process-screenshots.py $T
