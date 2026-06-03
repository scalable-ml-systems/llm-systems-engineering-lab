# Build 2 Results Summary — Modern vLLM V1 Architecture Baseline

## Scope

Build 2 measured baseline runtime behavior for `deepseek-ai/DeepSeek-V2-Lite-Chat` on vLLM V1 using one GPU. The run focused on prefill/context growth, decode residency, and KV/concurrency pressure.

## Runtime Baseline


## Runtime Baseline

| Input | Output | Concurrency | TTFT p99 ms | TPOT p99 ms | ITL p99 ms | Req/s | Out tok/s | KV Cache | Waiting | Preemptions | Success | Failed |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1024 | 128 | 1 | 182.55 | 4.79 | 5.31 | 1.47 | 187.93 | 0.0006298570780188806 | 0.0 | 0.0 | 25 | 0 |


## Prefill Context Stretch

| Input | Output | Concurrency | TTFT p99 ms | TPOT p99 ms | ITL p99 ms | Req/s | Out tok/s | KV Cache | Waiting | Preemptions | Success | Failed |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1024 | 128 | 1 | 4847.15 | 4.80 | 5.24 | 1.11 | 142.69 | 0.0006391196821073919 | 0.0 | 0.0 | 25 | 0 |
| 12288 | 128 | 1 | 247.14 | 5.71 | 6.36 | 1.03 | 132.35 | 0.0 | 0.0 | 0.0 | 25 | 0 |
| 15360 | 128 | 1 | 261.50 | 5.98 | 6.70 | 0.99 | 126.68 | 0.008929150341326908 | 0.0 | 0.0 | 25 | 0 |
| 2048 | 128 | 1 | 83.94 | 4.88 | 5.32 | 1.43 | 183.40 | 0.0012597141560378722 | 0.0 | 0.0 | 25 | 0 |
| 4096 | 128 | 1 | 110.62 | 5.04 | 5.55 | 1.34 | 171.31 | 0.002389751854836475 | 0.0 | 0.0 | 25 | 0 |
| 8192 | 128 | 1 | 201.40 | 5.40 | 5.89 | 1.14 | 145.63 | 0.0 | 0.0 | 0.0 | 25 | 0 |


## Decode Residency Ramp

| Input | Output | Concurrency | TTFT p99 ms | TPOT p99 ms | ITL p99 ms | Req/s | Out tok/s | KV Cache | Waiting | Preemptions | Success | Failed |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1024 | 1024 | 4 | 689.50 | 9.77 | 10.06 | 0.41 | 421.51 | 0.0010651994701790235 | 0.0 | 0.0 | 25 | 0 |
| 1024 | 128 | 4 | 876.34 | 9.29 | 10.34 | 2.97 | 380.62 | 0.0026398421652262805 | 0.0 | 0.0 | 25 | 0 |
| 1024 | 1536 | 4 | 79.45 | 9.32 | 10.13 | 0.28 | 423.29 | 0.0014171784255425646 | 0.0 | 0.0 | 25 | 0 |
| 1024 | 256 | 4 | 65.79 | 9.11 | 10.15 | 1.68 | 429.29 | 0.0006113318698418579 | 0.0 | 0.0 | 25 | 0 |
| 1024 | 512 | 4 | 77.31 | 9.83 | 10.47 | 0.81 | 414.97 | 0.0007965839516121953 | 0.0 | 0.0 | 25 | 0 |


## KV Concurrency Ramp

| Input | Output | Concurrency | TTFT p99 ms | TPOT p99 ms | ITL p99 ms | Req/s | Out tok/s | KV Cache | Waiting | Preemptions | Success | Failed |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2048 | 512 | 1 | 91.76 | 4.90 | 5.35 | 0.39 | 199.17 | 0.0 | 0.0 | 0.0 | 50 | 0 |
| 2048 | 512 | 16 | 3968.60 | 18.32 | 17.56 | 1.65 | 845.70 | 0.0028991950797047084 | 0.0 | 0.0 | 50 | 0 |
| 2048 | 512 | 2 | 83.58 | 7.24 | 7.70 | 0.55 | 283.54 | 0.0028158316429081065 | 0.0 | 0.0 | 50 | 0 |
| 2048 | 512 | 24 | 400.87 | 17.19 | 19.93 | 2.29 | 1174.45 | 0.0028991950797047084 | 0.0 | 0.0 | 50 | 0 |
| 2048 | 512 | 32 | 462.38 | 17.53 | 19.78 | 2.77 | 1416.71 | 0.026222432174581534 | 0.0 | 0.0 | 50 | 0 |
| 2048 | 512 | 4 | 109.29 | 9.37 | 10.25 | 0.85 | 432.95 | 0.0 | 0.0 | 0.0 | 50 | 0 |
| 2048 | 512 | 8 | 3199.87 | 14.97 | 14.41 | 1.14 | 584.93 | 0.0014820166541621438 | 0.0 | 0.0 | 50 | 0 |


## Notes

- TTFT, TPOT, ITL, throughput, success, and failed request counts are parsed from `benchmark.log`.
- KV cache usage, waiting requests, running requests, and preemptions are taken from the latest raw `/metrics` scrape in each run directory when available.
- `vllm:kv_cache_usage_perc` is a 0–1 scale.
- `vllm:num_preemptions_total` is cumulative over server lifetime, so interpret deltas carefully if the server stayed up across multiple experiments.
- Raw evidence is preserved under `results/raw/002-modern-vllm-v1-baseline/`.

## Data Quality Correction

The original `prefill-context-stretch/input1024-output128-concurrency1` run produced an anomalous TTFT p99 of 4847.15 ms. A clean rerun of the same workload completed successfully with:

- Successful requests: 25
- Failed requests: 0
- TTFT p99: 166.59 ms
- TPOT p99: 4.80 ms
- ITL p99: 5.33 ms
- Request throughput: 1.47 req/s
- Output token throughput: 188.29 tok/s

The original 4847.15 ms TTFT result is treated as a warmup/transient outlier and excluded from trend interpretation.
