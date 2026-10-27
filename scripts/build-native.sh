#!/bin/sh
# Build the optional CXX-Qt accelerator for Fenestra Menu 11.
#
# Usage:
#   scripts/build-native.sh            # build into build/native
#   scripts/build-native.sh --stage    # also copy the module into the widget
#
# Environment:
#   BUILD_DIR          build directory (default: build/native)
#   STAGE_DIR          widget module root (default: contents/ui/core)
#   CMAKE_BUILD_TYPE   Release (default) or Debug
#   JOBS               parallel build jobs
#   QMAKE              path to qmake6, if CMake cannot find it
#   CXXQT_DIR          path to a CxxQt CMake package (otherwise fetched)
set -eu
cd "$(dirname "$0")/.."

BUILD_DIR="${BUILD_DIR:-build/native}"
STAGE_DIR="${STAGE_DIR:-contents/ui/core}"
JOBS="${JOBS:-$(getconf _NPROCESSORS_ONLN 2>/dev/null || echo 2)}"
STAGE="${STAGE:-0}"
for argument in "$@"; do
    [ "$argument" = "--stage" ] && STAGE=1
done

set -- -S rust -B "$BUILD_DIR" -DCMAKE_BUILD_TYPE="${CMAKE_BUILD_TYPE:-Release}"
if [ -n "${QMAKE:-}" ]; then
    set -- "$@" -DQT_QMAKE_EXECUTABLE="$QMAKE"
fi
if [ -n "${CXXQT_DIR:-}" ]; then
    set -- "$@" -DCxxQt_DIR="$CXXQT_DIR"
fi

echo "==> Configuring $BUILD_DIR"
cmake "$@"

echo "==> Building"
cmake --build "$BUILD_DIR" --parallel "$JOBS"

MODULE_SRC="$BUILD_DIR/qml/org/fenestra/menu11/core"

if [ "$STAGE" = "1" ]; then
    MODULE_DST="$STAGE_DIR/org/fenestra/menu11/core"
    echo "==> Staging $MODULE_DST"
    rm -rf "$STAGE_DIR/org"
    mkdir -p "$MODULE_DST"
    for file in "$MODULE_SRC"/*.so "$MODULE_SRC"/*.dylib "$MODULE_SRC"/qmldir "$MODULE_SRC"/plugin.qmltypes; do
        [ -e "$file" ] && cp "$file" "$MODULE_DST/"
    done
    echo "Staged module:"
    ls -l "$MODULE_DST"
fi

echo "==> Done: $MODULE_SRC"
