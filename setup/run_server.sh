#!/usr/bin/env bash
set -euo pipefail

# Start vLLM OpenAI-compatible server for the evidence stack.
# Defaults are intentionally conservative for RTX 4090 24GB + Qwen2.5-7B-Instruct.
#
# Usage:
#   bash scripts/run_server.sh
#
# Optional env vars:
#   MODEL=Qwen/Qwen2.5-7B-Instruct
#   SERVED_MODEL_NAME=Qwen/Qwen2.5-7B-Instruct
#   HOST=0.0.0.0
#   PORT=8000
#   DTYPE=auto
#   MAX_MODEL_LEN=8192
#   GPU_MEMORY_UTILIZATION=0.90
#   MAX_NUM_SEQS=64
#   MAX_NUM_BATCHED_TOKENS=8192
#   ENABLE_CHUNKED_PREFILL=true|false|unset
#   EXTRA_VLLM_ARGS="--some-flag value"

MODEL="${MODEL:-Qwen/Qwen2.5-7B-Instruct}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-${MODEL}}"
HOST="${HOST:-0.0.0.0}"
PORT="${PORT:-8000}"
DTYPE="${DTYPE:-auto}"
MAX_MODEL_LEN="${MAX_MODEL_LEN:-8192}"
GPU_MEMORY_UTILIZATION="${GPU_MEMORY_UTILIZATION:-0.90}"
MAX_NUM_SEQS="${MAX_NUM_SEQS:-64}"
MAX_NUM_BATCHED_TOKENS="${MAX_NUM_BATCHED_TOKENS:-8192}"
ENABLE_CHUNKED_PREFILL="${ENABLE_CHUNKED_PREFILL:-}"
EXTRA_VLLM_ARGS="${EXTRA_VLLM_ARGS:-}"
LOG_DIR="${LOG_DIR:-logs}"

mkdir -p "${LOG_DIR}"
LOG_FILE="${LOG_DIR}/vllm-$(date -u +%Y%m%dT%H%M%SZ).log"

if ! command -v vllm >/dev/null 2>&1; then
  echo "vllm command not found. Activate your venv or run scripts/setup_env.sh first." >&2
  exit 1
fi

if command -v nvidia-smi >/dev/null 2>&1; then
  echo "[run_server] GPU summary:"
  nvidia-smi --query-gpu=name,memory.total,driver_version --format=csv || true
fi

ARGS=(
  serve "${MODEL}"
  --served-model-name "${SERVED_MODEL_NAME}"
  --host "${HOST}"
  --port "${PORT}"
  --dtype "${DTYPE}"
  --max-model-len "${MAX_MODEL_LEN}"
  --gpu-memory-utilization "${GPU_MEMORY_UTILIZATION}"
  --max-num-seqs "${MAX_NUM_SEQS}"
  --max-num-batched-tokens "${MAX_NUM_BATCHED_TOKENS}"
)

if [[ "${ENABLE_CHUNKED_PREFILL}" == "true" ]]; then
  ARGS+=(--enable-chunked-prefill)
elif [[ "${ENABLE_CHUNKED_PREFILL}" == "false" ]]; then
  ARGS+=(--no-enable-chunked-prefill)
fi

# shellcheck disable=SC2206
EXTRA_ARGS_ARRAY=(${EXTRA_VLLM_ARGS})
ARGS+=("${EXTRA_ARGS_ARRAY[@]}")

echo "[run_server] Starting vLLM server"
echo "[run_server] Model: ${MODEL}"
echo "[run_server] Endpoint: http://${HOST}:${PORT}"
echo "[run_server] Log file: ${LOG_FILE}"
echo "[run_server] Command: vllm ${ARGS[*]}"

exec vllm "${ARGS[@]}" 2>&1 | tee "${LOG_FILE}"
