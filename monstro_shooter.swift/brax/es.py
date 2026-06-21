"""Evolution Strategies in JAX — mirrored sampling + centered-rank shaping (mirror GPUES.swift).
The whole population is evaluated in ONE vmapped pass (the pop× speedup MLX couldn't do)."""
import jax
import jax.numpy as jnp
import numpy as np


def _centered_ranks(f):
    ranks = np.argsort(np.argsort(np.asarray(f)))   # 0..P-1
    return (ranks / max(len(f) - 1, 1) - 0.5).astype(np.float32)


def train(fitness, params0, key, iters=20, pop=16, sigma=0.1, lr=0.05, on_iter=None):
    """`fitness(params)->scalar` for a SINGLE params pytree; vmapped over the population here."""
    theta = params0
    vfit = jax.jit(jax.vmap(fitness))
    for it in range(iters):
        key, k = jax.random.split(key)
        leaves, tree = jax.tree_util.tree_flatten(theta)
        ks = jax.random.split(k, len(leaves))
        noise = [jax.random.normal(kk, (pop,) + l.shape) for kk, l in zip(ks, leaves)]
        # batched params [2*pop] = plus(pop) then minus(pop)
        batched = [jnp.concatenate([l[None] + sigma * n, l[None] - sigma * n], 0) for l, n in zip(leaves, noise)]
        fits = vfit(jax.tree_util.tree_unflatten(tree, batched))      # [2*pop]
        w = jnp.asarray(_centered_ranks(fits))                       # [2*pop]
        wd = (w[:pop] - w[pop:])                                     # mirrored weights [pop]
        scale = lr / (2 * pop * sigma)
        new = []
        for l, n in zip(leaves, noise):
            grad = jnp.sum(wd.reshape((pop,) + (1,) * l.ndim) * n, 0)
            new.append(l + scale * grad)
        theta = jax.tree_util.tree_unflatten(tree, new)
        if on_iter is not None:
            on_iter(it, float(jnp.max(fits)), float(fitness(theta)))
    return theta
