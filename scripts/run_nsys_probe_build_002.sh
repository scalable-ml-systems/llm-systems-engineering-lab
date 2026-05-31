#!/usr/bin/env bash
set -euo pipefail

PROFILE="${1:?Usage: scripts/run_nsys_probe_build_002.sh <baseline|prefill|decode|pathological>}"

BASE_URL="${BASE_URL:-http://localhost:8000}"
MODEL="${MODEL:-Qwen/Qwen2.5-7B-Instruct}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-${MODEL}}"
NUM_PROMPTS="${NUM_PROMPTS:-8}"
REQUEST_RATE="${REQUEST_RATE:-inf}"
OUT_ROOT="${OUT_ROOT:-results/profiles/build-002/nsight-systems/probes}"

mkdir -p "${OUT_ROOT}/${PROFILE}"

case "${PROFILE}" in
  baseline)
    INPUT_LEN=512
    OUTPUT_LEN=128
    CONCURRENCY=1
    ;;
  prefill)
    INPUT_LEN=6144
    OUTPUT_LEN=128
    CONCURRENCY=2
    ;;
  decode)
    INPUT_LEN=512
    OUTPUT_LEN=1024
    CONCURRENCY=2
    ;;
  pathological)
    INPUT_LEN=6144
    OUTPUT_LEN=1536
    CONCURRENCY=8
    ;;
  *)
    echo "Unknown profile: ${PROFILE}" >&2
    echo "Valid profiles: baseline, prefill, decode, pathological" >&2
    exit 1
    ;;
esac

echo "[probe] ${PROFILE}: input=${INPUT_LEN}, output=${OUTPUT_LEN}, concurrency=${CONCURRENCY}, prompts=${NUM_PROMPTS}"

curl -fsS "${BASE_URL}/v1/models" >/dev/null

vllm bench serve \
  --base-url "${BASE_URL}" \
  --model "${MODEL}" \
  --served-model-name "${SERVED_MODEL_NAME}" \
  --dataset-name random \
  --random-input-len "${INPUT_LEN}" \
  --random-output-len "${OUTPUT_LEN}" \
  --num-prompts "${NUM_PROMPTS}" \
  --request-rate "${REQUEST_RATE}" \
  --max-concurrency "${CONCURRENCY}" \
  --save-result \
  --result-dir "${OUT_ROOT}/${PROFILE}" \
  2>&1 | tee "${OUT_ROOT}/${PROFILE}/probe.log"
