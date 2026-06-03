#!/usr/bin/env bash
set -euo pipefail

# Build 2 — Modern vLLM V1 Architecture Baseline
#
# Purpose:
#   Start one vLLM server for DeepSeek-V2-Lite-Chat on RTX PRO 6000.
#
# This script does not tune.
# It defines the fixed baseline runtime used by all Build 2 experiments.

BUILD_ID="${BUILD_ID:-002-modern-vllm-v1-baseline}"

MODEL="${MODEL:-deepseek-ai/DeepSeek-V2-Lite-Chat}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-${MODEL}}"

HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"

DTYPE="${DTYPE:-bfloat16}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-16384}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.85}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-32}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-8192}"
MOE_BACKEND="${MOE_BACKEND:-triton}"

export VLLM_USE_V2_MODEL_RUNNER="${VLLM_USE_V2_MODEL_RUNNER:-1}"

RAW_ROOT="${RAW_ROOT:-results/raw/${BUILD_ID}}"
LOG_DIR="${LOG_DIR:-${RAW_ROOT}/server-logs}"
mkdir -p "${LOG_DIR}"

SERVER_LOG="${LOG_DIR}/vllm-server.log"
ENV_LOG="${LOG_DIR}/runtime-environment.txt"

echo "[server] Build ID: ${BUILD_ID}"
echo "[server] Model: ${MODEL}"
echo "[server] Served model name: ${SERVED_MODEL_NAME}"
echo "[server] Logs: ${SERVER_LOG}"
echo "[server] VLLM_USE_V2_MODEL_RUNNER=${VLLM_USE_V2_MODEL_RUNNER}"

{
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "build_id=${BUILD_ID}"
  echo "model=${MODEL}"
  echo "served_model_name=${SERVED_MODEL_NAME}"
  echo "host=${HOST}"
  echo "port=${PORT}"
  echo "dtype=${DTYPE}"
  echo "max_model_len=${MAX_MODEL_LEN}"
  echo "gpu_memory_utilization=${GPU_MEMORY_UTILIZATION}"
  echo "max_num_seqs=${MAX_NUM_SEQS}"
  echo "max_num_batched_tokens=${MAX_NUM_BATCHED_TOKENS}"
  echo "moe_backend=${MOE_BACKEND}"
  echo "VLLM_USE_V2_MODEL_RUNNER=${VLLM_USE_V2_MODEL_RUNNER}"
  echo
  echo "### python"
  python --version || true
  echo
  echo "### vllm / torch"
  python - <<'PY' || true
import os
import torch
try:
    import vllm
    print("vllm", vllm.__version__)
except Exception as e:
    print("vllm_import_error", repr(e))

print("torch", torch.__version__)
print("torch_cuda", torch.version.cuda)
print("cuda_available", torch.cuda.is_available())
if torch.cuda.is_available():
    print("device", torch.cuda.get_device_name(0))
    print("capability", torch.cuda.get_device_capability(0))

print("VLLM_USE_V2_MODEL_RUNNER", os.environ.get("VLLM_USE_V2_MODEL_RUNNER"))
PY
  echo
  echo "### nvidia-smi"
  nvidia-smi || true
  echo
  echo "### vllm serve help flags"
  vllm serve --help | grep -Ei "v2|runner|moe|chunk|prefix|batched|preempt|scheduler|cache" || true
} > "${ENV_LOG}"

echo "[server] Runtime environment captured at ${ENV_LOG}"

vllm serve "${MODEL}" \
  --host "${HOST}" \
  --port "${PORT}" \
  --served-model-name "${SERVED_MODEL_NAME}" \
  --dtype "${DTYPE}" \
  --max-model-len "${MAX_MODEL_LEN}" \
  --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}" \
  --max-num-seqs "${MAX_NUM_SEQS}" \
  --max-num-batched-tokens "${MAX_NUM_BATCHED_TOKENS}" \
  --moe-backend "${MOE_BACKEND}" \
  2>&1 | tee "${SERVER_LOG}"
