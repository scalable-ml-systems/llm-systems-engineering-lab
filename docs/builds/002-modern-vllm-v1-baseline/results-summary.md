# Build 2 Results Summary — Modern vLLM V1 Architecture Baseline

## Scope

Build 2 measured prefill/context growth, decode residency, and KV/concurrency pressure for `deepseek-ai/DeepSeek-V2-Lite-Chat` on one RTX PRO 6000 GPU using vLLM V1.

## Executive Summary

| Runtime Area | Experiment | Variable Changed | Primary Signal | Interpretation |
|---|---|---|---|---|
| Runtime baseline | runtime-baseline | none | TTFT / TPOT reference | Healthy reference state |
| Prefill / context | prefill-context-stretch | input length | TTFT p99 and KV cache | Context-growth / chunked-prefill pressure |
| Decode residency | decode-residency-ramp | output length | TPOT / ITL p99 | Decode residency behavior |
| KV / concurrency | kv-concurrency-ramp | concurrency | throughput, waiting, preemptions | Scaling boundary and preemption check |


## Runtime Baseline

| Input | Output | Concurrency | TTFT p99 ms | TPOT p99 ms | ITL p99 ms | Req/s | Out tok/s | Peak KV Cache | Peak Waiting | Preemptions Δ | Success | Failed | Classification |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1024 | 128 | 1 | 182.55 | 4.79 | 5.31 | 1.47 | 187.93 | 0.00063 | 0 | 0 | 25 | 0 | healthy reference |
| 1024 | 128 | 1 | 166.59 | 4.80 | 5.33 | 1.47 | 188.29 | 0.00063 | 0 | 0 | 25 | 0 | healthy reference |


## Prefill Context Stretch

| Input | Output | Concurrency | TTFT p99 ms | TPOT p99 ms | ITL p99 ms | Req/s | Out tok/s | Peak KV Cache | Peak Waiting | Preemptions Δ | Success | Failed | Classification |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1024 | 128 | 1 | 4847.15 | 4.80 | 5.24 | 1.11 | 142.69 | 0.000658 | 0 | 0 | 25 | 0 | context growth |
| 2048 | 128 | 1 | 83.94 | 4.88 | 5.32 | 1.43 | 183.40 | 0.00126 | 0 | 0 | 25 | 0 | context growth |
| 4096 | 128 | 1 | 110.62 | 5.04 | 5.55 | 1.34 | 171.31 | 0.002445 | 0 | 0 | 25 | 0 | context growth |
| 8192 | 128 | 1 | 201.40 | 5.40 | 5.89 | 1.14 | 145.63 | 0.004817 | 0 | 0 | 25 | 0 | long-context pressure |
| 12288 | 128 | 1 | 247.14 | 5.71 | 6.36 | 1.03 | 132.35 | 0.007188 | 0 | 0 | 25 | 0 | long-context pressure |
| 15360 | 128 | 1 | 261.50 | 5.98 | 6.70 | 0.99 | 126.68 | 0.008929 | 0 | 0 | 25 | 0 | long-context pressure |


## Decode Residency Ramp

| Input | Output | Concurrency | TTFT p99 ms | TPOT p99 ms | ITL p99 ms | Req/s | Out tok/s | Peak KV Cache | Peak Waiting | Preemptions Δ | Success | Failed | Classification |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1024 | 128 | 4 | 876.34 | 9.29 | 10.34 | 2.97 | 380.62 | 0.00264 | 0 | 0 | 25 | 0 | decode residency |
| 1024 | 256 | 4 | 65.79 | 9.11 | 10.15 | 1.68 | 429.29 | 0.002779 | 0 | 0 | 25 | 0 | decode residency |
| 1024 | 512 | 4 | 77.31 | 9.83 | 10.47 | 0.81 | 414.97 | 0.003557 | 0 | 0 | 25 | 0 | decode residency |
| 1024 | 1024 | 4 | 689.50 | 9.77 | 10.06 | 0.41 | 421.51 | 0.004715 | 0 | 0 | 25 | 0 | long-output residency |
| 1024 | 1536 | 4 | 79.45 | 9.32 | 10.13 | 0.28 | 423.29 | 0.005891 | 0 | 0 | 25 | 0 | long-output residency |


## KV Concurrency Ramp

| Input | Output | Concurrency | TTFT p99 ms | TPOT p99 ms | ITL p99 ms | Req/s | Out tok/s | Peak KV Cache | Peak Waiting | Preemptions Δ | Success | Failed | Classification |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 2048 | 512 | 1 | 91.76 | 4.90 | 5.35 | 0.39 | 199.17 | 0.001482 | 0 | 0 | 50 | 0 | useful scaling |
| 2048 | 512 | 2 | 83.58 | 7.24 | 7.70 | 0.55 | 283.54 | 0.002964 | 0 | 0 | 50 | 0 | useful scaling |
| 2048 | 512 | 4 | 109.29 | 9.37 | 10.25 | 0.85 | 432.95 | 0.005872 | 0 | 0 | 50 | 0 | useful scaling |
| 2048 | 512 | 8 | 3199.87 | 14.97 | 14.41 | 1.14 | 584.93 | 0.011578 | 0 | 0 | 50 | 0 | latency pressure |
| 2048 | 512 | 16 | 3968.60 | 18.32 | 17.56 | 1.65 | 845.70 | 0.023323 | 0 | 0 | 50 | 0 | latency pressure |
| 2048 | 512 | 24 | 400.87 | 17.19 | 19.93 | 2.29 | 1174.45 | 0.035291 | 0 | 0 | 50 | 0 | high concurrency, no preemption |
| 2048 | 512 | 32 | 462.38 | 17.53 | 19.78 | 2.77 | 1416.71 | 0.04686 | 0 | 0 | 50 | 0 | high concurrency, no preemption |


## Data Quality Notes

- Workload shape comes from `experiment-metadata.json`.
- Benchmark latency and throughput values come from vLLM `--save-result` JSON files.
- `Peak KV Cache` is the maximum `vllm:kv_cache_usage_perc` observed across raw metrics scrapes for that run.
- `Peak Waiting` is the maximum `vllm:num_requests_waiting` observed across raw metrics scrapes.
- `Preemptions Δ` is final minus first observed `vllm:num_preemptions_total` during the run.
- `vllm:kv_cache_usage_perc` is a 0–1 scale.
- The original `prefill-context-stretch/input1024-output128-concurrency1` run had an anomalous TTFT p99 of 4847.15 ms. A clean rerun produced TTFT p99 of 166.59 ms. Treat the original as a warmup/transient outlier.
- All scripted Build 2 benchmark runs completed with `Failed requests: 0`.
