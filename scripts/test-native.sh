#!/bin/sh
# Build and test the optional native accelerator.
#
# Requires cargo, cmake, Qt 6 (Core, Gui, Qml, Quick, QuickControls2) and
# qmltestrunner. CxxQt is fetched on first build unless CXXQT_DIR is set.
set -eu
cd "$(dirname "$0")/.."

BUILD_DIR="${BUILD_DIR:-build/native}"

if cargo fmt --version >/dev/null 2>&1; then
    echo "==> cargo fmt --check"
    (cd rust && cargo fmt --all -- --check)
else
    echo "==> cargo fmt unavailable; skipping formatting check"
fi

if cargo clippy --version >/dev/null 2>&1; then
    echo "==> cargo clippy"
    (cd rust && cargo clippy --workspace --all-targets -- -D warnings)
else
    echo "==> cargo clippy unavailable; skipping lint"
fi

echo "==> cargo test"
(cd rust && cargo test --workspace)

ORIGINAL_DIR=$(pwd)
BUILD_DIR_ABS="$ORIGINAL_DIR/$BUILD_DIR"

echo "==> CMake build"
scripts/build-native.sh

QMLTESTRUNNER="${QMLTESTRUNNER:-}"
if [ -z "$QMLTESTRUNNER" ]; then
    for candidate in qmltestrunner6 qmltestrunner /usr/lib/qt6/bin/qmltestrunner; do
        if command -v "$candidate" >/dev/null 2>&1; then
            QMLTESTRUNNER=$(command -v "$candidate")
            break
        fi
        if [ -x "$candidate" ]; then
            QMLTESTRUNNER="$candidate"
            break
        fi
    done
fi
if [ -z "$QMLTESTRUNNER" ]; then
    echo "qmltestrunner not found" >&2
    exit 1
fi

echo "==> QML bridge tests"
"$QMLTESTRUNNER" -import "$BUILD_DIR_ABS/qml" -input tests/qml/tst_core.qml

echo "==> QML fallback test"
"$QMLTESTRUNNER" -input tests/qml/tst_fallback.qml

echo "==> Widget-local relative import test"
TMP_DIR=$(mktemp -d)
trap 'rm -rf "$TMP_DIR"' EXIT
cp -R "$BUILD_DIR_ABS/qml/org" "$TMP_DIR/"
cat > "$TMP_DIR/tst_relative.qml" <<'QML'
import QtQuick
import QtTest
import "org/fenestra/menu11/core"

TestCase {
    name: "RelativeImport"
    function test_singleton_is_reachable() {
        verify(FenestraCore.version().length > 0)
        compare(FenestraCore.hibernate_available("yes"), true)
    }
}
QML
"$QMLTESTRUNNER" -input "$TMP_DIR/tst_relative.qml"

echo "==> All native checks passed"
