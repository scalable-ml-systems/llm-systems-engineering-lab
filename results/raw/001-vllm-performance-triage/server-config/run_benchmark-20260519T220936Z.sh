#!/usr/bin/env bash
set -euo pipefail

# Build 1 benchmark runner for vLLM OpenAI-compatible serving.
#
# Evidence stack:
#   GPU: RTX 4090 24GB
#   Model: Qwen/Qwen2.5-7B-Instruct
#   Runtime: vLLM OpenAI-compatible server
#
# Raw benchmark outputs are immutable and written under:
#   results/raw/<build_id>/<suite>/<experiment>/<run_id>/
#
# Interpretation belongs in docs/, not in raw results.
#
# Usage:
#   bash scripts/run_benchmark.sh baseline
#   bash scripts/run_benchmark.sh prompt-pressure
#   bash scripts/run_benchmark.sh output-pressure
#   bash scripts/run_benchmark.sh rate-pressure
#   bash scripts/run_benchmark.sh all
#
# Optional env vars:
#   BASE_URL=http://localhost:8000
#   MODEL=Qwen/Qwen2.5-7B-Instruct
#   SERVED_MODEL_NAME=Qwen/Qwen2.5-7B-Instruct
#   BUILD_ID=001-vllm-performance-triage
#   NUM_PROMPTS=100
#   RANDOM_INPUT_LEN=512
#   RANDOM_OUTPUT_LEN=128
#   REQUEST_RATE=1

SUITE="${1:-baseline}"

BASE_URL="${BASE_URL:-http://localhost:8000}"
MODEL="${MODEL:-Qwen/Qwen2.5-7B-Instruct}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-${MODEL}}"
BUILD_ID="${BUILD_ID:-001-vllm-performance-triage}"

NUM_PROMPTS="${NUM_PROMPTS:-100}"
RANDOM_INPUT_LEN="${RANDOM_INPUT_LEN:-512}"
RANDOM_OUTPUT_LEN="${RANDOM_OUTPUT_LEN:-128}"
REQUEST_RATE="${REQUEST_RATE:-1}"

RAW_ROOT="${RAW_ROOT:-results/raw/${BUILD_ID}}"

log() {
  printf '\n[run_benchmark] %s\n' "$*"
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
  local num_prompts="$6"

  local run_id
  run_id="$(date -u +%Y%m%dT%H%M%SZ)"

  local out_dir="${RAW_ROOT}/${suite}/${experiment}/${run_id}"
  mkdir -p "${out_dir}"

  log "Running ${suite}/${experiment}"
  log "input=${input_len}, output=${output_len}, rate=${request_rate}, prompts=${num_prompts}"
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
  "request_rate": ${request_rate},
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
    --save-result \
    --result-dir "${out_dir}" \
    2>&1 | tee "${out_dir}/benchmark.log"

  log "Completed ${suite}/${experiment}. Results saved to ${out_dir}"
}

run_baseline() {
  run_one \
    "baseline" \
    "input${RANDOM_INPUT_LEN}-output${RANDOM_OUTPUT_LEN}-rate${REQUEST_RATE}" \
    "${RANDOM_INPUT_LEN}" \
    "${RANDOM_OUTPUT_LEN}" \
    "${REQUEST_RATE}" \
    "${NUM_PROMPTS}"
}

run_prompt_pressure() {
  # Keep request rate low so prompt pressure is not contaminated by queue saturation.
  # Max input is capped at 3072 because server max_model_len=4096 and chat/template + output tokens need headroom.
  for input_len in 512 1024 2048 3072; do
    run_one \
      "prompt-pressure" \
      "input${input_len}-output128-rate1" \
      "${input_len}" \
      "128" \
      "1" \
      "100"
  done
}

run_output_pressure() {
  # Keep request rate low so output-length pressure is isolated.
  for output_len in 128 256 512 1024; do
    run_one \
      "output-pressure" \
      "input512-output${output_len}-rate1" \
      "512" \
      "${output_len}" \
      "1" \
      "100"
  done
}

run_rate_pressure() {
  # Rate sweep intentionally discovers saturation.
  for rate in 1 2 4 8; do
    run_one \
      "rate-pressure" \
      "input512-output128-rate${rate}" \
      "512" \
      "128" \
      "${rate}" \
      "100"
  done
}

case "${SUITE}" in
  baseline)
    require_server
    run_baseline
    ;;
  prompt-pressure)
    require_server
    run_prompt_pressure
    ;;
  output-pressure)
    require_server
    run_output_pressure
    ;;
  rate-pressure)
    require_server
    run_rate_pressure
    ;;
  all)
    require_server
    run_baseline
    run_rate_pressure
    run_prompt_pressure
    run_output_pressure
    ;;
  *)
    echo "Unknown suite: ${SUITE}" >&2
    echo "Valid suites: baseline, prompt-pressure, output-pressure, rate-pressure, all" >&2
    exit 1
    ;;
esac

log "Done. Raw results are under ${RAW_ROOT}"
