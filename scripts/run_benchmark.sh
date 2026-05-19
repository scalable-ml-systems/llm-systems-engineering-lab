#!/usr/bin/env bash
set -euo pipefail

# Run Build 1 benchmark suites against a running vLLM OpenAI-compatible server.
# Raw vLLM benchmark outputs are written under results/raw/...
# Interpretation belongs in docs/, not in raw results.
#
# Usage:
#   bash scripts/run_benchmark.sh baseline
#   bash scripts/run_benchmark.sh prompt-sweep
#   bash scripts/run_benchmark.sh output-sweep
#   bash scripts/run_benchmark.sh rate-sweep
#   bash scripts/run_benchmark.sh all
#
# Optional env vars:
#   BASE_URL=http://localhost:8000
#   MODEL=Qwen/Qwen2.5-7B-Instruct
#   BUILD_ID=001-vllm-performance-triage
#   NUM_PROMPTS=100
#   RANDOM_INPUT_LEN=512
#   RANDOM_OUTPUT_LEN=128
#   REQUEST_RATE=4
#   BACKEND=openai-chat

SUITE="${1:-baseline}"
BASE_URL="${BASE_URL:-http://localhost:8000}"
MODEL="${MODEL:-Qwen/Qwen2.5-7B-Instruct}"
BUILD_ID="${BUILD_ID:-001-vllm-performance-triage}"
NUM_PROMPTS="${NUM_PROMPTS:-100}"
RANDOM_INPUT_LEN="${RANDOM_INPUT_LEN:-512}"
RANDOM_OUTPUT_LEN="${RANDOM_OUTPUT_LEN:-128}"
REQUEST_RATE="${REQUEST_RATE:-4}"
BACKEND="${BACKEND:-openai-chat}"
RAW_ROOT="${RAW_ROOT:-results/raw/${BUILD_ID}}"

log() { printf '\n[run_benchmark] %s\n' "$*"; }

require_server() {
  log "Checking server at ${BASE_URL}/v1/models"
  curl -fsS "${BASE_URL}/v1/models" >/dev/null || {
    echo "vLLM server is not reachable at ${BASE_URL}. Start it with scripts/run_server.sh." >&2
    exit 1
  }
}

run_one() {
  local experiment="$1"
  local input_len="$2"
  local output_len="$3"
  local request_rate="$4"
  local num_prompts="$5"
  local out_dir="${RAW_ROOT}/${experiment}"

  mkdir -p "${out_dir}"

  log "Running ${experiment}: input=${input_len}, output=${output_len}, rate=${request_rate}, prompts=${num_prompts}"

  vllm bench serve \
    --backend "${BACKEND}" \
    --base-url "${BASE_URL}" \
    --model "${MODEL}" \
    --dataset-name random \
    --random-input-len "${input_len}" \
    --random-output-len "${output_len}" \
    --num-prompts "${num_prompts}" \
    --request-rate "${request_rate}" \
    --save-result \
    --result-dir "${out_dir}" \
    2>&1 | tee "${out_dir}/benchmark.log"

  cat > "${out_dir}/experiment-metadata.json" <<JSON
{
  "experiment": "${experiment}",
  "model": "${MODEL}",
  "base_url": "${BASE_URL}",
  "backend": "${BACKEND}",
  "dataset_name": "random",
  "random_input_len": ${input_len},
  "random_output_len": ${output_len},
  "num_prompts": ${num_prompts},
  "request_rate": ${request_rate},
  "created_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
}
JSON
}

run_baseline() {
  run_one "baseline" "${RANDOM_INPUT_LEN}" "${RANDOM_OUTPUT_LEN}" "${REQUEST_RATE}" "${NUM_PROMPTS}"
}

run_prompt_sweep() {
  for input_len in 512 1024 2048 4096 8192; do
    run_one "prompt-length-${input_len}" "${input_len}" "128" "4" "${NUM_PROMPTS}"
  done
}

run_output_sweep() {
  for output_len in 128 256 512 1024; do
    run_one "output-length-${output_len}" "512" "${output_len}" "4" "${NUM_PROMPTS}"
  done
}

run_rate_sweep() {
  for rate in 1 2 4 8 16; do
    run_one "request-rate-${rate}" "512" "128" "${rate}" "200"
  done
}

case "${SUITE}" in
  baseline)
    require_server
    run_baseline
    ;;
  prompt-sweep)
    require_server
    run_prompt_sweep
    ;;
  output-sweep)
    require_server
    run_output_sweep
    ;;
  rate-sweep)
    require_server
    run_rate_sweep
    ;;
  all)
    require_server
    run_baseline
    run_prompt_sweep
    run_output_sweep
    run_rate_sweep
    ;;
  *)
    echo "Unknown suite: ${SUITE}" >&2
    echo "Valid suites: baseline, prompt-sweep, output-sweep, rate-sweep, all" >&2
    exit 1
    ;;
esac

log "Done. Raw results are under ${RAW_ROOT}"
