#!/usr/bin/env bash
#
# Generate one image from the converted Core ML model, with no app involved.
#
# This is the checkpoint before any integration: it proves the converted weights actually denoise
# into a picture, using **the same Swift runtime the app will use** (Apple's `StableDiffusion`
# package). If this produces an image, every later failure is in our code rather than in the model.
# If it does not, nothing built on top of it could have worked.
#
#   bash scripts/test_raw_model.sh "molten glass poppies at dusk, macro"
#
# First run builds the Swift package and takes a few minutes; later runs are instant.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(dirname "$HERE")"
VENDOR="$ROOT/.vendor/ml-stable-diffusion"
RESOURCES="${RESOURCES:-$ROOT/models/coreml/sd15-split-einsum-v2-512x512-6bit/Resources}"
OUTPUT="${OUTPUT:-$ROOT/models/out}"

PROMPT="${1:-molten glass poppies at dusk, macro, shallow depth of field}"
STEPS="${STEPS:-20}"
SEED="${SEED:-42}"

if [[ ! -d "$RESOURCES" ]]; then
    echo "no converted model at:"
    echo "  $RESOURCES"
    echo "run scripts/convert_sd15_coreml.py first."
    exit 1
fi

if [[ ! -d "$VENDOR" ]]; then
    echo "cloning apple/ml-stable-diffusion (Swift runtime + sample CLI)…"
    mkdir -p "$(dirname "$VENDOR")"
    git clone --depth 1 https://github.com/apple/ml-stable-diffusion.git "$VENDOR"
fi

mkdir -p "$OUTPUT"

# `--compute-units cpuAndNeuralEngine` matches how the model was converted: SPLIT_EINSUM_V2 exists
# to put the unet on the Neural Engine, and running it with `.all` lets Core ML pick the GPU
# instead, which measures something other than what the phone will do.
echo "generating: \"$PROMPT\"  (${STEPS} steps, seed ${SEED})"
cd "$VENDOR"
swift run -c release StableDiffusionSample "$PROMPT" \
    --resource-path "$RESOURCES" \
    --output-path "$OUTPUT" \
    --seed "$SEED" \
    --step-count "$STEPS" \
    --compute-units cpuAndNeuralEngine \
    --disable-safety

echo
echo "wrote:"
ls -lh "$OUTPUT" | tail -5
