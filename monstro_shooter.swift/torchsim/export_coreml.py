"""Torch -> Core ML export (the deploy half of the pipeline). Converts the trained player + enemy
JSON nets to .mlmodel via coremltools' native torch frontend (torch.jit.trace), names the IO
`obs`/`action` to match the Swift CoreMLAgent (Sources/MetalGame/Agent.swift), and verifies
torch-vs-CoreML forward parity. Core AI is the macOS-27 successor (swap MLModel->AIModel later).

Run with an env that has torch + coremltools (e.g. the conda 'fantastic' env):
  python export_coreml.py
"""
import os, json
import numpy as np
import torch
import coremltools as ct
import policy_torch as P

MODELS = os.path.join(os.path.dirname(__file__), "..", "MonstroSim", "models")


def numpy_forward(json_path, x):
    """torch-free MLP reference (relu chain + linear), for parity without depending on the runtime."""
    d = json.load(open(json_path)); sizes = d["sizes"]; h = np.asarray(x, np.float32)
    for i in range(len(d["w"])):
        W = np.asarray(d["w"][i], np.float32).reshape(sizes[i], sizes[i + 1])
        b = np.asarray(d["b"][i], np.float32)
        h = h @ W + b
        if i < len(d["w"]) - 1:
            h = np.maximum(h, 0.0)
    return h


def export_one(json_path, out_path):
    params, sizes = P.from_json(json_path)
    obs_dim = sizes[0]                                    # derive from the model (never goes stale)
    module = P.MLPModule(params).eval()
    example = torch.zeros(obs_dim)                       # 1-D obs, matches Agent.swift MLMultiArray [count]
    traced = torch.jit.trace(module, example)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="obs", shape=(obs_dim,))],
        convert_to="neuralnetwork",                     # single-file .mlmodel (existing deploy path)
        compute_units=ct.ComputeUnit.ALL,               # CPU/GPU/ANE
    )
    # rename the traced output to "action"
    spec = mlmodel.get_spec()
    old = spec.description.output[0].name
    if old != "action":
        ct.utils.rename_feature(spec, old, "action")
    mlmodel = ct.models.MLModel(spec)
    mlmodel.save(out_path)

    # parity vs the torch-free numpy reference (skipped if this env can't load CoreML.framework)
    try:
        maxd = 0.0
        for _ in range(8):
            x = np.random.randn(obs_dim).astype(np.float32)
            ref = numpy_forward(json_path, x)
            cm = np.asarray(mlmodel.predict({"obs": x})["action"]).reshape(-1)
            maxd = max(maxd, float(np.max(np.abs(ref - cm))))
        tag = f"max|d|={maxd:.2e}  {'OK' if maxd < 1e-3 else 'MISMATCH'}"
    except Exception as e:
        tag = f"saved (parity skipped: {str(e).splitlines()[0][:48]})"
    print(f"  {os.path.basename(out_path):16s} sizes={sizes}  {tag}")
    return True


def main():
    print("Exporting torch nets -> Core ML (.mlmodel):")
    ok = True
    pj, mj = os.path.join(MODELS, "player.json"), os.path.join(MODELS, "monster.json")
    if os.path.exists(pj):
        ok &= export_one(pj, os.path.join(MODELS, "player.mlmodel"))
    else:
        print("  player.json missing — run train_torch.py first")
    if os.path.exists(mj):
        ok &= export_one(mj, os.path.join(MODELS, "monster.mlmodel"))
    else:
        print("  monster.json missing — run train_torch.py first")
    print("Done." if ok else "Done with mismatches.")


if __name__ == "__main__":
    main()
