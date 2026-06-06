#!/usr/bin/env bash
set -euo pipefail

# Build 2 — Modern vLLM V1 Architecture Baseline
#
# Experiments:
#   runtime-baseline
#   prefill-context-stretch
#   kv-concurrency-ramp
#   all
#
# This script does not tune.
# It runs a compact baseline to identify context-growth and concurrency inflection points.

SUITE="${1:-runtime-baseline}"

BUILD_ID="${BUILD_ID:-002-modern-vllm-v1-baseline}"

BASE_URL="${BASE_URL:-http://localhost:8000}"
MODEL="${MODEL:-deepseek-ai/DeepSeek-V2-Lite-Chat}"
SERVED_MODEL_NAME="${SERVED_MODEL_NAME:-${MODEL}}"

RAW_ROOT="${RAW_ROOT:-results/raw/${BUILD_ID}}"

REQUEST_RATE="${REQUEST_RATE:-inf}"
SEED="${SEED:-42}"

# Default prompt counts by experiment are intentionally small to avoid wasting GPU time.
RUNTIME_BASELINE_NUM_PROMPTS="${RUNTIME_BASELINE_NUM_PROMPTS:-25}"
CONTEXT_NUM_PROMPTS="${CONTEXT_NUM_PROMPTS:-25}"
RAMP_NUM_PROMPTS="${RAMP_NUM_PROMPTS:-50}"

SCRAPE_INTERVAL_SECONDS="${SCRAPE_INTERVAL_SECONDS:-2}"

log() {
  printf '\n[run_benchmark_build_002] %s\n' "$*"
}

require_server() {
  log "Checking server at ${BASE_URL}/v1/models"

  curl -fsS "${BASE_URL}/v1/models" >/dev/null || {
    echo "vLLM server is not reachable at ${BASE_URL}. Start it with scripts/run_server_build_002.sh." >&2
    exit 1
  }

  log "Checking metrics at ${BASE_URL}/metrics"

  curl -fsS "${BASE_URL}/metrics" >/dev/null || {
    echo "vLLM metrics endpoint is not reachable at ${BASE_URL}/metrics." >&2
    exit 1
  }
}

capture_environment() {
  local out_dir="$1"

  {
    echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
    echo "hostname=$(hostname)"
    echo "whoami=$(whoami)"
    echo "build_id=${BUILD_ID}"
    echo "base_url=${BASE_URL}"
    echo "model=${MODEL}"
    echo "served_model_name=${SERVED_MODEL_NAME}"
    echo "request_rate=${REQUEST_RATE}"
    echo "seed=${SEED}"
    echo
    echo "### environment"
    env | grep -E "VLLM|CUDA|NVIDIA|MODEL|TOKENIZERS" | sort || true
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
    echo "### metric discovery"
    curl -fsS "${BASE_URL}/metrics" \
      | awk -F '[{ ]' '/^vllm:/ {print $1}' \
      | sort -u \
      | grep -Ei "cache|kv|waiting|running|preempt|prefix|prompt|decode|token|time_to_first|time_per_output|success|finish" || true
  } > "${out_dir}/environment.txt"
}

write_metadata() {
  local out_dir="$1"
  local suite="$2"
  local experiment="$3"
  local input_len="$4"
  local output_len="$5"
  local max_concurrency="$6"
  local num_prompts="$7"

  cat > "${out_dir}/experiment-metadata.json" <<JSON
{
  "build_id": "${BUILD_ID}",
  "suite": "${suite}",
  "experiment": "${experiment}",
  "model": "${MODEL}",
  "served_model_name": "${SERVED_MODEL_NAME}",
  "base_url": "${BASE_URL}",
  "dataset_name": "random",
  "random_input_len": ${input_len},
  "random_output_len": ${output_len},
  "num_prompts": ${num_prompts},
  "request_rate": "${REQUEST_RATE}",
  "max_concurrency": ${max_concurrency},
  "seed": ${SEED},
  "created_at_utc": "$(date -u +%Y-%m-%dT%H:%M:%SZ)",
  "telemetry_notes": {
    "v1_correctness": "Do not use v0 swap metrics such as num_requests_swapped or cpu_cache_usage_perc.",
    "kv_cache_metric": "Prefer vllm:kv_cache_usage_perc. Treat vllm:gpu_cache_usage_perc only as legacy alias if exposed.",
    "preemption_metric": "Use vllm:num_preemptions_total if exposed.",
    "prefix_cache": "Compute hit rate from prefix cache hit/query counters only if exposed."
  }
}
JSON
}

run_one() {
  local suite="$1"
  local experiment="$2"
  local input_len="$3"
  local output_len="$4"
  local max_concurrency="$5"
  local num_prompts="$6"

  local run_id
  run_id="$(date -u +%Y%m%dT%H%M%SZ)"

  local out_dir="${RAW_ROOT}/${suite}/${experiment}/${run_id}"
  mkdir -p "${out_dir}"

  log "Running ${suite}/${experiment}"
  log "input=${input_len}, output=${output_len}, concurrency=${max_concurrency}, prompts=${num_prompts}"
  log "raw output: ${out_dir}"

  write_metadata "${out_dir}" "${suite}" "${experiment}" "${input_len}" "${output_len}" "${max_concurrency}" "${num_prompts}"
  capture_environment "${out_dir}"

  SCRAPE_INTERVAL_SECONDS="${SCRAPE_INTERVAL_SECONDS}" \
    scripts/scrape_vllm_metrics.sh "${out_dir}" &
  local scraper_pid="$!"

  cleanup() {
    if kill -0 "${scraper_pid}" >/dev/null 2>&1; then
      kill "${scraper_pid}" >/dev/null 2>&1 || true
      wait "${scraper_pid}" >/dev/null 2>&1 || true
    fi
  }
  trap cleanup RETURN

  set +e
  vllm bench serve \
    --base-url "${BASE_URL}" \
    --model "${MODEL}" \
    --served-model-name "${SERVED_MODEL_NAME}" \
    --dataset-name random \
    --random-input-len "${input_len}" \
    --random-output-len "${output_len}" \
    --num-prompts "${num_prompts}" \
    --request-rate "${REQUEST_RATE}" \
    --max-concurrency "${max_concurrency}" \
    --seed "${SEED}" \
    --save-result \
    --result-dir "${out_dir}" \
    2>&1 | tee "${out_dir}/benchmark.log"

  local bench_status="${PIPESTATUS[0]}"
  set -e

  cleanup
  trap - RETURN

  if [[ "${bench_status}" -ne 0 ]]; then
    echo "[run_benchmark_build_002] ERROR: benchmark failed for ${suite}/${experiment}" >&2
    echo "${bench_status}" > "${out_dir}/exit-code.txt"
    return "${bench_status}"
  fi

  echo "0" > "${out_dir}/exit-code.txt"
  log "Completed ${suite}/${experiment}"
}

run_runtime_baseline() {
  run_one \
    "runtime-baseline" \
    "input1024-output128-concurrency1" \
    "1024" \
    "128" \
    "1" \
    "${RUNTIME_BASELINE_NUM_PROMPTS}"
}

run_prefill_context_stretch() {
  # Context growth baseline:
  # output is small and concurrency=1 to isolate prompt/context behavior.
  for input_len in 1024 2048 4096 8192 12288 15360; do
    run_one \
      "prefill-context-stretch" \
      "input${input_len}-output128-concurrency1" \
      "${input_len}" \
      "128" \
      "1" \
      "${CONTEXT_NUM_PROMPTS}"
  done
}


run_decode_residency_ramp() {
  # Decode residency baseline:
  # input is fixed, concurrency is fixed, output length increases.
  # Purpose: isolate TPOT / ITL and output-token residency behavior.
  for output_len in 128 256 512 1024 1536; do
    run_one \
      "decode-residency-ramp" \
      "input1024-output${output_len}-concurrency4" \
      "1024" \
      "${output_len}" \
      "4" \
      "${CONTEXT_NUM_PROMPTS}"
  done
}

run_kv_concurrency_ramp() {
  # Concurrency growth baseline:
  # input/output fixed; concurrency scales until useful saturation or preemption.
  for concurrency in 1 2 4 8 16 24 32; do
    run_one \
      "kv-concurrency-ramp" \
      "input2048-output512-concurrency${concurrency}" \
      "2048" \
      "512" \
      "${concurrency}" \
      "${RAMP_NUM_PROMPTS}"
  done
}

case "${SUITE}" in
  runtime-baseline)
    require_server
    run_runtime_baseline
    ;;
  prefill-context-stretch)
    require_server
    run_prefill_context_stretch
    ;;
  decode-residency-ramp)
    require_server
    run_decode_residency_ramp
    ;;
  kv-concurrency-ramp)
    require_server
    run_kv_concurrency_ramp
    ;;
  all)
    require_server
    run_runtime_baseline
    run_prefill_context_stretch
    run_decode_residency_ramp
    run_kv_concurrency_ramp
    ;;
  *)
    echo "Unknown suite: ${SUITE}" >&2
    echo "Valid suites: runtime-baseline, prefill-context-stretch, decode-residency-ramp, kv-concurrency-ramp, all" >&2
    exit 1
    ;;
esac

log "Done. Raw results are under ${RAW_ROOT}"
