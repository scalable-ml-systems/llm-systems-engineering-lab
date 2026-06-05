#!/usr/bin/env bash
set -euo pipefail

# Scrape vLLM /metrics during Build 2 benchmark runs.
#
# Usage:
#   scripts/scrape_vllm_metrics.sh <output-dir>
#
# Optional env vars:
#   BASE_URL=http://localhost:8000
#   SCRAPE_INTERVAL_SECONDS=2

OUT_DIR="${1:?Usage: scripts/scrape_vllm_metrics.sh <output-dir>}"

BASE_URL="${BASE_URL:-http://localhost:8000}"
SCRAPE_INTERVAL_SECONDS="${SCRAPE_INTERVAL_SECONDS:-2}"

METRICS_DIR="${OUT_DIR}/metrics"
RAW_DIR="${METRICS_DIR}/raw"
FILTERED_FILE="${METRICS_DIR}/vllm-metrics-filtered.prom"
DISCOVERY_FILE="${METRICS_DIR}/vllm-metric-names.txt"

mkdir -p "${RAW_DIR}"

echo "[metrics] Scraping ${BASE_URL}/metrics every ${SCRAPE_INTERVAL_SECONDS}s"
echo "[metrics] Output dir: ${METRICS_DIR}"

# Initial discovery snapshot.
curl -fsS "${BASE_URL}/metrics" \
  | awk -F '[{ ]' '/^vllm:/ {print $1}' \
  | sort -u \
  > "${DISCOVERY_FILE}" || true

echo "[metrics] Metric names discovered:"
cat "${DISCOVERY_FILE}" || true

while true; do
  ts="$(date -u +%Y%m%dT%H%M%SZ)"
  raw_file="${RAW_DIR}/metrics-${ts}.prom"

  if curl -fsS "${BASE_URL}/metrics" > "${raw_file}"; then
    {
      echo
      echo "### scrape_utc=${ts}"
      grep -Ei "cache|kv|waiting|running|preempt|prefix|prompt|decode|token|time_to_first|time_per_output|success|finish" "${raw_file}" || true
    } >> "${FILTERED_FILE}"
  else
    echo "[metrics] WARN: failed to scrape ${BASE_URL}/metrics at ${ts}" >&2
  fi

  sleep "${SCRAPE_INTERVAL_SECONDS}"
done
