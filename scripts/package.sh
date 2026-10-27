#!/bin/sh
# Assemble and install a clean Plasma applet package.
#
# `kpackagetool6` copies the whole directory it is given, so installing the
# source checkout also installs build output (`build/`, `rust/target/`). This
# script assembles only the files Plasma needs and installs that copy.
#
# Usage:
#   scripts/package.sh                 # pure QML package
#   scripts/package.sh --native        # build and include the native module
#   scripts/package.sh --native --upgrade
#
# Environment:
#   OUT_DIR      assembled package directory (default: build/package)
#   PACKAGEROOT  passed to kpackagetool6 -p (default: the user's Plasma data dir)
#   plus the environment of scripts/build-native.sh when --native is used.
set -eu
cd "$(dirname "$0")/.."

OUT_DIR="${OUT_DIR:-build/package}"
NATIVE=0
ACTION="-i"
for argument in "$@"; do
    case "$argument" in
        --native) NATIVE=1 ;;
        --upgrade) ACTION="-u" ;;
        --install) ACTION="-i" ;;
        *)
            echo "Unknown option: $argument" >&2
            echo "Usage: $0 [--native] [--upgrade]" >&2
            exit 1
            ;;
    esac
done

if [ "$NATIVE" = "1" ]; then
    echo "==> Building and staging the native module"
    scripts/build-native.sh --stage
fi

echo "==> Assembling $OUT_DIR"
rm -rf "$OUT_DIR"
mkdir -p "$OUT_DIR"
cp -R metadata.json contents LICENSE "$OUT_DIR"/

# Only ship the native module when it was requested; a module staged by an
# earlier run must not leak into a pure-QML package.
if [ "$NATIVE" = "0" ]; then
    rm -rf "$OUT_DIR/contents/ui/core"
fi

if [ -n "${PACKAGEROOT:-}" ]; then
    set -- -p "$PACKAGEROOT"
else
    set --
fi

echo "==> kpackagetool6 $ACTION $OUT_DIR"
kpackagetool6 "$@" -t Plasma/Applet "$ACTION" "$OUT_DIR"

echo "==> Installed package contents"
du -sh "$OUT_DIR"
