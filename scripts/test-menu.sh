#!/bin/sh
# Load the actual Plasma applet with isolated settings and exercise UI input.
# Requires Qt 6 Quick/Widgets/Test and Plasma/PlasmaQuick development packages.
set -eu
cd "$(dirname "$0")/.."
project_dir="$PWD"
test_dir="$project_dir/build/menu-tests"
mkdir -p "$test_dir/data/plasma/plasmoids" "$test_dir/config" "$test_dir/cache"
ln -sfn "$project_dir" "$test_dir/data/plasma/plasmoids/org.fenestra.menu11"
cmake -S tests/plasma -B "$test_dir/build"
cmake --build "$test_dir/build"
env XDG_DATA_HOME="$test_dir/data" XDG_CONFIG_HOME="$test_dir/config" \
    XDG_CACHE_HOME="$test_dir/cache" QT_QPA_PLATFORM=offscreen \
    QT_QUICK_BACKEND=software FENESTRA_TEST_OUTPUT="$test_dir" \
    timeout 30s "$test_dir/build/check"
