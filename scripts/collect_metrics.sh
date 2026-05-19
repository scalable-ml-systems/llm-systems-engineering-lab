#!/usr/bin/env bash
set -euo pipefail

# Collect point-in-time host, GPU, and vLLM metrics without modifying raw benchmark files.
# Intended to run before/during/after benchmark suites.
#
# Usage:
#   bash scripts/collect_metrics.sh pre-baseline
#   bash scripts/collect_metrics.sh during-prompt-sweep
#
# Optional env vars:
#   BUILD_ID=001-vllm-performance-triage
#   BASE_URL=http://localhost:8000
#   SAMPLE_SECONDS=0       # 0 = single snapshot; >0 = repeated dmon samples
#   SAMPLE_INTERVAL=1

LABEL="${1:-snapshot}"
BUILD_ID="${BUILD_ID:-001-vllm-performance-triage}"
BASE_URL="${BASE_URL:-http://localhost:8000}"
SAMPLE_SECONDS="${SAMPLE_SECONDS:-0}"
SAMPLE_INTERVAL="${SAMPLE_INTERVAL:-1}"
RAW_DIR="${RAW_DIR:-results/raw/${BUILD_ID}/metrics/${LABEL}-$(date -u +%Y%m%dT%H%M%SZ)}"

mkdir -p "${RAW_DIR}"

echo "[collect_metrics] Writing metrics snapshot to ${RAW_DIR}"

{
  echo "created_at_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo "hostname=$(hostname)"
  echo "kernel=$(uname -a)"
  echo "base_url=${BASE_URL}"
} > "${RAW_DIR}/metadata.txt"

if command -v lscpu >/dev/null 2>&1; then
  lscpu > "${RAW_DIR}/lscpu.txt" || true
fi

free -h > "${RAW_DIR}/free-h.txt" || true
df -h > "${RAW_DIR}/df-h.txt" || true
ps aux --sort=-%mem | head -40 > "${RAW_DIR}/top-processes.txt" || true

if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi > "${RAW_DIR}/nvidia-smi.txt" || true
  nvidia-smi --query-gpu=timestamp,name,index,uuid,driver_version,memory.total,memory.used,memory.free,utilization.gpu,utilization.memory,temperature.gpu,power.draw,power.limit --format=csv > "${RAW_DIR}/nvidia-smi-query.csv" || true

  if [[ "${SAMPLE_SECONDS}" != "0" ]]; then
    echo "[collect_metrics] Capturing nvidia-smi dmon for ${SAMPLE_SECONDS}s"
    timeout "${SAMPLE_SECONDS}" nvidia-smi dmon -s pucvmet -d "${SAMPLE_INTERVAL}" > "${RAW_DIR}/nvidia-smi-dmon.txt" || true
  fi
else
  echo "nvidia-smi not found" > "${RAW_DIR}/nvidia-smi.txt"
fi

# vLLM exposes Prometheus-style metrics at /metrics in common server configurations.
# If unavailable, keep the failure as raw evidence without failing the whole collection.
curl -fsS "${BASE_URL}/metrics" -o "${RAW_DIR}/vllm-metrics.prom" || echo "metrics endpoint unavailable" > "${RAW_DIR}/vllm-metrics.prom"
curl -fsS "${BASE_URL}/v1/models" -o "${RAW_DIR}/vllm-models.json" || echo "models endpoint unavailable" > "${RAW_DIR}/vllm-models.json"

echo "[collect_metrics] Done"
