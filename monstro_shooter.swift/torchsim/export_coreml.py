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
import policy_attn as A

MODELS = os.path.join(os.path.dirname(__file__), "..", "MonstroSim", "models")

# Fixed monster-slot capacity baked into the exported attention player. The masked softmax makes any
# count <= M behave identically (dead/empty slots -> zero weight), so pick comfortably above the worst
# map's peak CONCURRENT-alive (surround peaks ~18) with headroom. Swift fills slots + sets alive[].
ATTN_DEPLOY_M = 32


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


def export_attention(json_path, out_path, M=ATTN_DEPLOY_M):
    """CONVERSION-ONLY (build-time torch->Core ML; the .mlmodel it writes is what actually runs in the game).
    Export the kind:attention player to a .mlmodel (neuralnetwork, fp32). Fixed M slots + alive mask.
    IO: self_feat[Fs], mon_feat[M,Fm], alive[M] -> action[act] (mean). Parity vs the torch-free numpy
    reference; CoreML.predict is best-effort. NOTE: neuralnetwork (weights inline) — not mlprogram — so it
    saves in the conda 'fantastic' env, which lacks the native BlobWriter that .mlpackage needs; it also
    keeps the same single-file .mlmodel deploy path the Swift CoreMLAgent already loads for the enemy."""
    params, log_std, meta = A.from_json(json_path)
    Fs, Fm, act = meta["Fs"], meta["Fm"], meta["act"]
    module = A.AttnDeployModule(params).eval()
    ex = (torch.zeros(Fs), torch.zeros(M, Fm), torch.ones(M))
    traced = torch.jit.trace(module, ex)

    mlmodel = ct.convert(
        traced,
        inputs=[ct.TensorType(name="self_feat", shape=(Fs,)),
                ct.TensorType(name="mon_feat", shape=(M, Fm)),
                ct.TensorType(name="alive", shape=(M,))],
        convert_to="neuralnetwork",                     # fp32 inline weights; no native BlobWriter needed
        compute_units=ct.ComputeUnit.ALL,
    )
    spec = mlmodel.get_spec()
    old = spec.description.output[0].name
    if old != "action":
        ct.utils.rename_feature(spec, old, "action")
    mlmodel = ct.models.MLModel(spec)
    mlmodel.save(out_path)

    # --- CONVERSION-ONLY verification (does NOT ship / does NOT run in the game) ---
    # torch-free numpy reference (works without CoreML.framework); then best-effort CoreML.predict.
    params_np = [(W.detach().cpu().numpy(), b.detach().cpu().numpy()) for W, b in params]
    ls_np = log_std.detach().cpu().numpy()
    rng = np.random.default_rng(0)
    maxd_torch = maxd_cm = 0.0
    cm_ok = True
    for _ in range(8):
        sf = rng.standard_normal(Fs).astype(np.float32)
        mf = rng.standard_normal((M, Fm)).astype(np.float32)
        al = (rng.random(M) > 0.4).astype(np.float32)
        if al.sum() == 0:
            al[0] = 1.0
        ref = A.numpy_forward(params_np, ls_np, meta, sf, mf, al)
        with torch.no_grad():
            tw = module(torch.from_numpy(sf), torch.from_numpy(mf), torch.from_numpy(al)).numpy()
        maxd_torch = max(maxd_torch, float(np.max(np.abs(ref - tw))))    # numpy-ref vs traced torch
        if cm_ok:
            try:
                cm = np.asarray(mlmodel.predict(
                    {"self_feat": sf, "mon_feat": mf, "alive": al})["action"]).reshape(-1)
                maxd_cm = max(maxd_cm, float(np.max(np.abs(ref - cm))))
            except Exception as e:
                cm_ok = False
                cm_msg = str(e).splitlines()[0][:48]
    tag = f"M={M} act={act}  ref-vs-torch max|d|={maxd_torch:.2e} {'OK' if maxd_torch < 1e-4 else 'MISMATCH'}"
    tag += (f"  | CoreML max|d|={maxd_cm:.2e} {'OK' if maxd_cm < 1e-3 else 'MISMATCH'}"
            if cm_ok else f"  | CoreML predict skipped ({cm_msg})")
    print(f"  {os.path.basename(out_path):18s} {tag}")
    return maxd_torch < 1e-4


def export_player(json_path, out_dir):
    """CONVERSION-ONLY. Route by discriminator: kind:attention vs MLP {sizes,w,b} — both -> .mlmodel."""
    kind = json.load(open(json_path)).get("kind", "mlp")
    if kind == "attention":
        return export_attention(json_path, os.path.join(out_dir, "player.mlmodel"))
    return export_one(json_path, os.path.join(out_dir, "player.mlmodel"))


def main():
    print("Exporting torch nets -> Core ML:")
    ok = True
    pj, mj = os.path.join(MODELS, "player.json"), os.path.join(MODELS, "monster.json")
    if os.path.exists(pj):
        ok &= export_player(pj, MODELS)
    else:
        print("  player.json missing — run train_torch.py first")
    if os.path.exists(mj):
        ok &= export_one(mj, os.path.join(MODELS, "monster.mlmodel"))   # enemy stays MLP
    else:
        print("  monster.json missing — run train_torch.py first")
    print("Done." if ok else "Done with mismatches.")


if __name__ == "__main__":
    main()
