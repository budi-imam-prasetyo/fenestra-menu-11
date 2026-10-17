#!/bin/sh
# Fenestra Menu 11 — compile the translations (needs gettext: msgfmt)
# Run from this folder:  sh build.sh
set -e
cd "$(dirname "$0")"
for po in *.po; do
    lang="${po%.po}"
    mkdir -p "../contents/locale/$lang/LC_MESSAGES"
    msgfmt -o "../contents/locale/$lang/LC_MESSAGES/plasma_applet_org.fenestra.menu11.mo" "$po"
    echo "$lang OK"
done
