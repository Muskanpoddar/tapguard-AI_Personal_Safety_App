#!/usr/bin/env python3
"""
DEPRECATED — kept only for backwards compatibility.

The real builder lives at `tools/build_models_minimal.py` and trains
proper TFLite models via TensorFlow. Run that instead:

    pip install -r tools/requirements.txt
    python tools/build_models_minimal.py

(This file used to generate a minimal TFLite flatbuffer with hand-picked
weights, but the format isn't compatible with modern TFLite runtimes.
See git history for the prior implementation.)
"""

import runpy
import sys
from pathlib import Path

target = Path(__file__).resolve().parent / "build_models_minimal.py"
if not target.exists():
    sys.exit(f"build_models_minimal.py not found next to {__file__}")

print("[build_stub_model.py] DEPRECATED — running build_models_minimal.py instead.\n")
runpy.run_path(str(target), run_name="__main__")
