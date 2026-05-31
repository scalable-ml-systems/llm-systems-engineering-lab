#!/usr/bin/env bash
set -euo pipefail

# Build 2 benchmark runner for vLLM OpenAI-compatible serving.
#
# Build 2 goal:
#   Classify backend runtime state under controlled workload pressure:
#   - prefill-bound
#   - decode-bound
#   - KV-bound
#   - scheduler/pathological pressure
#
# Raw benchmark outputs are immutable and written under:
#   results/raw/<build_id>/<suite>/<experiment>/<run_id>/
#
# Interpretation belongs in docs/, not in raw results.
#
# Usage:
#   bash scripts/run_benchmark_build_002.sh baseline
#   bash scripts/run_benchmark_build_002.sh prefill-pressure
#   bash scripts/run_benchmark_build_002.sh decode-pressure
#   bash scripts/run_benchmark_build_002.sh kv-pressure
#   bash scripts/run_benchmark_build_002.sh pathological
#   bash scripts/run_benchmark_build_002.sh all
#
# Optional env vars:
#   BASE_URL=http://localhost:8000
#   MODEL=Qwen/Qwen2.5-7B-Instruct
#   SERVED_MODEL_NAME=Qwen/Qwen2.5-7B-Instruct
#   BUILD_ID=002-prefill-decode-kv-behavior
#   NUM_PROMPTS=100
#   REQUEST_RATE=inf

SUITE="${1:-baseline}"

BASE_URL="${BASE_URL:-http://localhost:8000}"
MODEL="${MODEL:-Qwen/Qwen2.5-7B-Instruct}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-${MODEL}}"
BUILD_ID="${BUILD_ID:-002-prefill-decode-kv-behavior}"

NUM_PROMPTS="${NUM_PROMPTS:-100}"
REQUEST_RATE="${REQUEST_RATE:-inf}"

RAW_ROOT="${RAW_ROOT:-results/raw/${BUILD_ID}}"

log() {
  printf '\n[run_benchmark_build_002] %s\n' "$*"
}

require_server() {
  log "Checking server at ${BASE_URL}/v1/models"

  curl -fsS "${BASE_URL}/v1/models" >/dev/null || {
    echo "vLLM server is not reachable at ${BASE_URL}. Start it with scripts/run_server.sh." >&2
    exit 1
  }
}

capture_environment() {
  local out_dir="$1"

  {
    echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "hostname=$(hostname)"
    echo "whoami=$(whoami)"
    echo "base_url=${BASE_URL}"
    echo "model=${MODEL}"
    echo "served_model_name=${SERVED_MODEL_NAME}"
    echo "build_id=${BUILD_ID}"
    echo
    echo "### python"
    python --version || true
    echo
    echo "### vllm"
    python - <<'PY' || true
import vllm, torch, transformers, tokenizers
print("vllm", vllm.__version__)
print("torch", torch.__version__)
print("torch_cuda", torch.version.cuda)
print("cuda_available", torch.cuda.is_available())
if torch.cuda.is_available():
    print("device", torch.cuda.get_device_name(0))
    print("capability", torch.cuda.get_device_capability(0))
print("transformers", transformers.__version__)
print("tokenizers", tokenizers.__version__)
PY
    echo
    echo "### nvidia-smi"
    nvidia-smi || true
  } > "${out_dir}/environment.txt"
}

run_one() {
  local suite="$1"
  local experiment="$2"
  local input_len="$3"
  local output_len="$4"
  local request_rate="$5"
  local max_concurrency="$6"
  local num_prompts="$7"

  local run_id
  run_id="$(date -u +%Y%m%dT%H%M%SZ)"

  local out_dir="${RAW_ROOT}/${suite}/${experiment}/${run_id}"
  mkdir -p "${out_dir}"

  log "Running ${suite}/${experiment}"
  log "input=${input_len}, output=${output_len}, rate=${request_rate}, max_concurrency=${max_concurrency}, prompts=${num_prompts}"
  log "raw output: ${out_dir}"

  cat > "${out_dir}/experiment-metadata.json" <<JSON
{
  "build_id": "${BUILD_ID}",
  "suite": "${suite}",
  "experiment": "${experiment}",
  "run_id": "${run_id}",
  "model": "${MODEL}",
  "served_model_name": "${SERVED_MODEL_NAME}",
  "base_url": "${BASE_URL}",
  "dataset_name": "random",
  "random_input_len": ${input_len},
  "random_output_len": ${output_len},
  "num_prompts": ${num_prompts},
  "request_rate": "${request_rate}",
  "max_concurrency": ${max_concurrency},
  "created_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON

  capture_environment "${out_dir}"

  vllm bench serve \
    --base-url "${BASE_URL}" \
    --model "${MODEL}" \
    --served-model-name "${SERVED_MODEL_NAME}" \
    --dataset-name random \
    --random-input-len "${input_len}" \
    --random-output-len "${output_len}" \
    --num-prompts "${num_prompts}" \
    --request-rate "${request_rate}" \
    --max-concurrency "${max_concurrency}" \
    --save-result \
    --result-dir "${out_dir}" \
    2>&1 | tee "${out_dir}/benchmark.log"

  log "Completed ${suite}/${experiment}. Results saved to ${out_dir}"
}

run_baseline() {
  run_one \
    "baseline" \
    "input512-output128-concurrency1" \
    "512" \
    "128" \
    "${REQUEST_RATE}" \
    "1" \
    "${NUM_PROMPTS}"
}

run_prefill_pressure() {
  # Long input, short output.
  # Purpose: reveal prefill pressure and TTFT cliffs.
  # Keep total tokens below server max_model_len.
  for concurrency in 1 2 4 8; do
    run_one \
      "prefill-pressure" \
      "input6144-output128-concurrency${concurrency}" \
      "6144" \
      "128" \
      "${REQUEST_RATE}" \
      "${concurrency}" \
      "${NUM_PROMPTS}"
  done
}

run_decode_pressure() {
  # Short/moderate input, long output.
  # Purpose: reveal decode pressure and TPOT degradation.
  for concurrency in 1 2 4 8; do
    run_one \
      "decode-pressure" \
      "input512-output1024-concurrency${concurrency}" \
      "512" \
      "1024" \
      "${REQUEST_RATE}" \
      "${concurrency}" \
      "${NUM_PROMPTS}"
  done
}

run_kv_pressure() {
  # Moderate/long input and output with higher concurrency.
  # Purpose: reveal KV-cache residency pressure.
  for concurrency in 4 8 16; do
    run_one \
      "kv-pressure" \
      "input4096-output1024-concurrency${concurrency}" \
      "4096" \
      "1024" \
      "${REQUEST_RATE}" \
      "${concurrency}" \
      "${NUM_PROMPTS}"
  done
}

run_pathological() {
  # One intentionally bad scenario.
  # Purpose: demonstrate combined prefill + decode + KV + scheduler pressure.
  run_one \
    "pathological" \
    "input6144-output1536-concurrency16" \
    "6144" \
    "1536" \
    "${REQUEST_RATE}" \
    "16" \
    "${NUM_PROMPTS}"
}

case "${SUITE}" in
  baseline)
    require_server
    run_baseline
    ;;
  prefill-pressure)
    require_server
    run_prefill_pressure
    ;;
  decode-pressure)
    require_server
    run_decode_pressure
    ;;
  kv-pressure)
    require_server
    run_kv_pressure
    ;;
  pathological)
    require_server
    run_pathological
    ;;
  all)
    require_server
    run_baseline
    run_prefill_pressure
    run_decode_pressure
    run_kv_pressure
    run_pathological
    ;;
  *)
    echo "Unknown suite: ${SUITE}" >&2
    echo "Valid suites: baseline, prefill-pressure, decode-pressure, kv-pressure, pathological, all" >&2
    exit 1
    ;;
esac

log "Done. Raw results are under ${RAW_ROOT}"