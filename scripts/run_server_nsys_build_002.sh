#!/usr/bin/env bash
set -euo pipefail

PROFILE_NAME="${1:?Usage: scripts/run_server_nsys_build_002.sh <profile-name>}"

MODEL="${MODEL:-Qwen/Qwen2.5-7B-Instruct}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-${MODEL}}"

OUT_DIR="${OUT_DIR:-results/profiles/build-002/nsight-systems/${PROFILE_NAME}}"
mkdir -p "${OUT_DIR}"

echo "[nsys] Writing profile to ${OUT_DIR}/${PROFILE_NAME}.nsys-rep"

nsys profile \
  --trace=cuda,nvtx,osrt \
  --sample=cpu \
  --gpu-metrics-device=all \
  --output="${OUT_DIR}/${PROFILE_NAME}" \
  --force-overwrite=true \
  vllm serve "${MODEL}" \
    --host 0.0.0.0 \
    --port 8000 \
    --served-model-name "${SERVED_MODEL_NAME}" \
    --dtype auto \
    --max-model-len 8192 \
    --gpu-memory-utilization 0.85 \
    --max-num-seqs 32 \
    --max-num-batched-tokens 8192
