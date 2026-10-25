#!/bin/sh
# Run the Fenestra Menu 11 regression tests from any directory.
set -eu
cd "$(dirname "$0")/.."
exec python3 -m unittest discover -s tests -v
