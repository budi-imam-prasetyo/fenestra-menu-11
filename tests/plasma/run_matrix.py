#!/usr/bin/env python3
"""Isolated applet render/input scenarios; requires a Plasma user D-Bus session."""
from pathlib import Path
import os
import subprocess
import sys

project = Path(__file__).resolve().parents[2]
binary = project / "build/menu-tests/build/check"
output = project / "build/design-validation"
scenarios = [
    ("light-standard", 1366, "BreezeLight", "1"),
    ("dark-standard", 1366, "BreezeDark", "1"),
    ("light-compact", 460, "BreezeLight", "1"),
    ("dark-expanded", 2560, "BreezeDark", "1"),
    ("fractional-125", 1366, "BreezeDark", "1.25"),
    ("long-labels", 460, "BreezeLight", "1"),
    ("large-font", 1366, "BreezeDark", "1"),
]
if len(sys.argv) > 1:
    scenarios = [s for s in scenarios if s[0] in sys.argv[1:]]
failures = []
for name, width, theme, scale in scenarios:
    work = output / name
    for directory in ("data/plasma/plasmoids", "config", "cache"):
        (work / directory).mkdir(parents=True, exist_ok=True)
    package = work / "data/plasma/plasmoids/org.fenestra.menu11"
    if not package.exists():
        package.symlink_to(project, target_is_directory=True)
    scheme = Path("/usr/share/color-schemes") / (theme + ".colors")
    (work / "config/kdeglobals").write_bytes(scheme.read_bytes())
    env = os.environ.copy()
    env.update(XDG_DATA_HOME=str(work / "data"), XDG_CONFIG_HOME=str(work / "config"),
               XDG_CACHE_HOME=str(work / "cache"), QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
               QT_SCALE_FACTOR=scale, FENESTRA_TEST_OUTPUT=str(work),
               FENESTRA_TEST_SCREEN_WIDTH=str(width), FENESTRA_TEST_SCHEME=str(scheme))
    if name == "long-labels":
        env["FENESTRA_TEST_LONG_LABELS"] = "1"
    if name == "large-font":
        env["FENESTRA_TEST_FONT_SCALE"] = "1.4"
    result = subprocess.run([str(binary)], env=env, capture_output=True, text=True, timeout=40)
    log = result.stdout + result.stderr
    (work / "runtime.log").write_text(log)
    errors = [line for line in log.splitlines() if any(marker in line for marker in
              ("ReferenceError:", "TypeError:", "Binding loop detected", "Cannot assign", "failed to create object"))]
    passed = sum(line.startswith("PASS ") for line in log.splitlines())
    print(f"{name}: exit={result.returncode}, assertions={passed}, QML errors={len(errors)}", flush=True)
    if result.returncode or errors:
        failures.append(name)
        for line in log.splitlines():
            if line.startswith("FAIL") or line in errors:
                print("  " + line, flush=True)
if failures:
    sys.exit("Failed scenarios: " + ", ".join(failures))
print("All design scenarios passed; screenshots and logs: " + str(output))
