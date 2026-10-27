#!/usr/bin/env python3
"""Compare immutable 1.4.2 and the working tree in the same offscreen Plasma harness."""
from pathlib import Path
import os
import subprocess
import sys

project = Path(__file__).resolve().parents[2]
binary = project / "build/menu-tests/build/check"
baseline = Path(sys.argv[1]).resolve()
output = project / "build/performance-validation"
for label, source in (("baseline", baseline), ("redesign", project)):
    for collection in ("installed", "large-2000"):
        work = output / f"{label}-{collection}"
        for directory in ("data/plasma/plasmoids", "config", "cache"):
            (work / directory).mkdir(parents=True, exist_ok=True)
        package = work / "data/plasma/plasmoids/org.fenestra.menu11"
        if not package.exists():
            package.symlink_to(source, target_is_directory=True)
        env = os.environ.copy()
        env.update(XDG_DATA_HOME=str(work / "data"), XDG_CONFIG_HOME=str(work / "config"),
                   XDG_CACHE_HOME=str(work / "cache"), QT_QPA_PLATFORM="offscreen", QT_QUICK_BACKEND="software",
                   QT_SCALE_FACTOR="1", FENESTRA_TEST_OUTPUT=str(work))
        args = [str(binary), "--benchmark"]
        if collection == "large-2000":
            args.append("--large")
        result = subprocess.run(["/usr/bin/time", "-v", *args], env=env, capture_output=True, text=True, timeout=60)
        log = result.stdout + result.stderr
        (work / "runtime.log").write_text(log)
        print(f"{label}/{collection}: exit={result.returncode}", flush=True)
        for line in log.splitlines():
            if line.startswith(("BENCH", "RESOURCE")) or any(marker in line for marker in ("Maximum resident", "User time (", "System time (")):
                print(line.strip(), flush=True)
        if result.returncode:
            sys.exit(result.returncode)
