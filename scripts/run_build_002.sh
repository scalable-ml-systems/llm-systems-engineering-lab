#!/usr/bin/env bash
set -euo pipefail

mkdir -p results/build-002/raw

scripts/run_benchmark.sh \
  configs/workloads/build-002/00-baseline.yaml \
  results/build-002/raw/00-baseline

scripts/run_benchmark.sh \
  configs/workloads/build-002/01-prefill-pressure.yaml \
  results/build-002/raw/01-prefill-pressure

scripts/run_benchmark.sh \
  configs/workloads/build-002/02-decode-pressure.yaml \
  results/build-002/raw/02-decode-pressure

scripts/run_benchmark.sh \
  configs/workloads/build-002/03-kv-pressure.yaml \
  results/build-002/raw/03-kv-pressure

scripts/run_benchmark.sh \
  configs/workloads/build-002/05-pathological.yaml \
  results/build-002/raw/05-pathological
