#!/usr/bin/env python3
"""Delegate to benchmark/synthetics submodule validator."""
import os
import runpy
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
TARGET = ROOT / "benchmark" / "synthetics" / "scripts" / "validate.py"
if not TARGET.is_file():
    sys.stderr.write(
        "Missing fixtures submodule. Run: git submodule update --init benchmark/synthetics\n"
    )
    raise SystemExit(2)
os.chdir(ROOT / "benchmark" / "synthetics")
sys.argv[0] = str(TARGET)
runpy.run_path(str(TARGET), run_name="__main__")
