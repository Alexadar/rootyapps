#!/usr/bin/env python3
"""
OFFLINE export: models/player.json (GPUPolicy weights) -> models/player.mlpackage (Core ML / ANE).

This is the ONE place coremltools (Python) is used — a build/CI step, never the runtime engine.
It exists so the ANE connector (Sources/MonstroSimGPU/CoreMLPolicy.swift) has a model to load.

    pip install coremltools numpy
    python3 tools/export_coreml.py [models/player.json] [models/player.mlpackage]

Note: coremltools must match your Python version (it was broken on the dev box's Python 3.14;
use a supported Python, e.g. 3.11). The runtime Swift side needs none of this.
"""
import json
import sys
import numpy as np
import coremltools as ct
from coremltools.models import datatypes
from coremltools.models.neural_network import NeuralNetworkBuilder

src = sys.argv[1] if len(sys.argv) > 1 else "models/player.json"
dst = sys.argv[2] if len(sys.argv) > 2 else "models/player.mlpackage"

d = json.load(open(src))
sizes, W, B = d["sizes"], d["w"], d["b"]          # GPUPolicy: weights stored [in, out]
obs, out = sizes[0], sizes[-1]

builder = NeuralNetworkBuilder(
    [("obs", datatypes.Array(obs))],
    [("action", datatypes.Array(out))],
)

prev, n = "obs", len(W)
for i in range(n):
    in_c, out_c = sizes[i], sizes[i + 1]
    Wt = np.array(W[i], np.float32).reshape(in_c, out_c).T   # Core ML wants [out, in]
    ip_out = "action" if i == n - 1 else f"ip{i}"
    builder.add_inner_product(
        name=f"ip{i}", W=Wt, b=np.array(B[i], np.float32),
        input_channels=in_c, output_channels=out_c, has_bias=True,
        input_name=prev, output_name=ip_out,
    )
    prev = ip_out
    if i < n - 1:                                            # ReLU on hidden layers only
        builder.add_activation(name=f"relu{i}", non_linearity="RELU",
                               input_name=prev, output_name=f"relu{i}")
        prev = f"relu{i}"

ct.models.MLModel(builder.spec).save(dst)
print(f"wrote {dst}  (obs={obs} -> action={out}, {n} layers)")
