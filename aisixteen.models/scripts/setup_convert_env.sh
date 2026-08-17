#!/usr/bin/env bash
#
# Builds the conda env that runs Apple's Core ML conversion.
#
# Why a separate env. Apple's `ml-stable-diffusion` pins `diffusers==0.30.2`,
# `transformers==4.44.2`, `huggingface-hub==0.24.6` and `numpy<1.24`. The repo's `fantastic` env is
# on diffusers 0.39 / transformers 5.15 / numpy 2.5 and is used for other Core ML work, so
# installing the converter there would silently downgrade four packages and break it. The converter
# also cannot run on Python 3.14 — the pinned numpy has no wheel for it.
#
# Nothing here downloads a model; that is `fetch_sd15.py`. This is only the toolchain.
#
#   bash scripts/setup_convert_env.sh
#
set -euo pipefail

ENV_NAME="aisixteen-convert"
PYTHON_VERSION="3.11"

eval "$(conda shell.bash hook)"

if conda env list | grep -qE "^${ENV_NAME}\s"; then
    echo "env '${ENV_NAME}' already exists — reusing it"
else
    echo "creating env '${ENV_NAME}' (python ${PYTHON_VERSION})…"
    conda create -y -n "${ENV_NAME}" "python=${PYTHON_VERSION}"
fi

conda activate "${ENV_NAME}"

echo "installing the pinned conversion stack…"
# Versions exactly as Apple pins them, except numpy: `<1.24` is stale and coremltools 8/9 needs a
# newer one. `<2` is the real constraint — the 2.x ABI break makes the converter's own code fail.
pip install --upgrade pip
pip install \
    "torch" \
    "diffusers==0.30.2" \
    "transformers==4.44.2" \
    "huggingface-hub==0.24.6" \
    "coremltools>=8.0" \
    "numpy<2" \
    "scipy" \
    "safetensors" \
    "scikit-learn" \
    "pytest" \
    "peft==0.12.0"
# peft is what backs `load_lora_weights` / `fuse_lora`; without it diffusers raises
# "PEFT backend is required for this method". Pinned to 0.12 because a current peft drags
# huggingface-hub past the 0.24.6 the converter needs.
# pytest is not a test dependency here. `coremltools.converters.mil.testing_utils` imports it at
# module scope, and the converter imports that module on its own import path — so without pytest the
# conversion dies before it reads a single weight.

# --no-deps: the package's install_requires drags in invisible-watermark, diffusionkit, matplotlib
# and pytest, none of which the conversion path touches, and diffusionkit in particular pulls a
# conflicting mlx stack.
echo "installing python_coreml_stable_diffusion (no deps)…"
pip install --no-deps "git+https://github.com/apple/ml-stable-diffusion.git"

python - <<'PY'
import coremltools, diffusers, transformers, torch, numpy
import python_coreml_stable_diffusion as msd
print("\nready:")
print(f"  python_coreml_stable_diffusion {msd.__file__}")
print(f"  torch        {torch.__version__}")
print(f"  diffusers    {diffusers.__version__}")
print(f"  transformers {transformers.__version__}")
print(f"  coremltools  {coremltools.__version__}")
print(f"  numpy        {numpy.__version__}")
PY
