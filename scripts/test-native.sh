#!/bin/sh
# Build and test the optional native accelerator.
#
# Requires cargo, cmake, Qt 6 (Core, Gui, Qml, Quick, QuickControls2) and the
# Qt 6 qmltestrunner. CxxQt is fetched on first build unless CXXQT_DIR is set.
#
# Set QMLTESTRUNNER to force a specific runner. Qt 5 and Qt 6 install a binary
# with the same name on some distributions, and the Qt 5 one exits silently.
set -eu
cd "$(dirname "$0")/.."

BUILD_DIR="${BUILD_DIR:-build/native}"
export QT_QPA_PLATFORM="${QT_QPA_PLATFORM:-offscreen}"

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
    # Qt 6 paths first: /usr/bin/qmltestrunner may be the Qt 5 build.
    for candidate in qmltestrunner6 /usr/lib/qt6/bin/qmltestrunner \
                     /usr/lib64/qt6/bin/qmltestrunner /usr/lib/qt6/bin/qmltestrunner6; do
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
    echo "Qt 6 qmltestrunner not found (set QMLTESTRUNNER)" >&2
    exit 1
fi

echo "==> QML bridge tests"
"$QMLTESTRUNNER" -import "$BUILD_DIR_ABS/qml" -input tests/qml/tst_core.qml

# A module staged by scripts/build-native.sh --stage is imported by
# RustBridge.qml relative to contents/ui, so the fallback test must not see it.
# Move it aside for the duration of that test, then put it back.
STAGED_MODULE="contents/ui/core/org"
STASHED_MODULE=""
restore_staged() {
    if [ -n "$STASHED_MODULE" ] && [ -d "$STASHED_MODULE" ]; then
        mv "$STASHED_MODULE" "$STAGED_MODULE"
        STASHED_MODULE=""
    fi
}
if [ -d "$STAGED_MODULE" ]; then
    STASHED_MODULE="$STAGED_MODULE.stashed-$$"
    echo "==> Hiding the staged native module for the fallback test"
    mv "$STAGED_MODULE" "$STASHED_MODULE"
fi
trap 'restore_staged' EXIT INT TERM

echo "==> QML fallback test"
"$QMLTESTRUNNER" -input tests/qml/tst_fallback.qml
restore_staged

echo "==> Widget-local relative import test"
TMP_DIR=$(mktemp -d)
trap 'restore_staged; rm -rf "$TMP_DIR"' EXIT INT TERM
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

if [ "${BENCH:-0}" = "1" ]; then
    echo "==> Benchmarks (Rust core vs JavaScript fallbacks)"
    "$QMLTESTRUNNER" -import "$BUILD_DIR_ABS/qml" -input tests/qml/bench_core.qml
fi

echo "==> All native checks passed"
