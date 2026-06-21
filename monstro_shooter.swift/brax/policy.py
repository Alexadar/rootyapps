"""JAX MLP — same math as GPUPolicy.swift (weights stored [in,out], y = relu chain then linear).
load_player_json cross-checks against MonstroSim/models/player.json (bit-identical forward)."""
import json
import jax
import jax.numpy as jnp
import numpy as np


def init_mlp(sizes, key):
    params = []
    for i in range(1, len(sizes)):
        key, k = jax.random.split(key)
        W = jax.random.normal(k, (sizes[i - 1], sizes[i])) * 0.1
        params.append((W, jnp.zeros((sizes[i],))))
    return params


def apply_mlp(params, x):
    h = x
    for i, (W, b) in enumerate(params):
        h = h @ W + b
        if i < len(params) - 1:
            h = jnp.maximum(h, 0.0)
    return h


def load_player_json(path):
    d = json.load(open(path))
    sizes = d["sizes"]
    params = []
    for i in range(len(d["w"])):
        inc, outc = sizes[i], sizes[i + 1]
        W = jnp.asarray(np.array(d["w"][i], np.float32).reshape(inc, outc))
        b = jnp.asarray(np.array(d["b"][i], np.float32))
        params.append((W, b))
    return params, sizes
