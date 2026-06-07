# Build 2 — Modern vLLM V1 Architecture Baseline

## Objective

Build 2 establishes a compact, production-relevant baseline for a modern sparse/compressed LLM architecture on the vLLM V1 runtime.

The goal is to map how a modern MLA/MoE model behaves under vLLM V1 unified scheduling before any optimization is attempted.

Build 2 answers three questions:

1. How does context growth affect TTFT and GPU cache residency?
2. How does concurrency growth affect throughput, waiting requests, and preemption?
3. Where does the backend transition from useful scaling into inefficient saturation?
   

![Results dashboard summary](results/plots/build-002/build2_summary_dashboard_white.png)

---

## Why This Build Exists

Build 1 measured dense-model performance triage.

Build 2 moves to a modern architecture baseline.

Modern inference is no longer only about dense transformer serving. Current systems increasingly involve:

* native chunked prefill
* unified scheduler token budgets
* compressed KV-cache architectures such as MLA
* sparse expert activation through MoE
* preemption/recompute behavior under memory pressure

vLLM V1 makes chunked prefill part of the normal scheduler path whenever possible. Its scheduling policy prioritizes decode requests, then uses the remaining `max_num_batched_tokens` budget for prefills; if a prefill cannot fit, vLLM chunks it. This makes `max_num_batched_tokens` a first-class runtime variable for understanding TTFT/TPOT tradeoffs.

DeepSeek-V2-Lite-Chat is selected because it exposes both modern architectural ideas in one accessible model: MLA and MoE. The model card describes it as a 16B total parameter model with 2.4B active parameters and deployable on a single 40GB GPU, making it suitable for the RTX PRO 6000 96GB node.

---
## Visual Summary

### 1. KV cache was not the bottleneck

![Peak KV Cache Usage vs Concurrency](results/plots/build-002/kv_cache_vs_concurrency.png)

Peak KV-cache usage stayed below 5% even under the burst-style `request_rate=inf` concurrency ramp. This supports the conclusion that the observed TTFT behavior was not caused by KV-cache exhaustion.

### 2. The c8/c16 inversion was burst-admission behavior

![TTFT p99: request_rate=inf vs request_rate=1](results/plots/build-002/ttft_p99_vs_concurrency.png)

The original c8/c16 TTFT spikes appeared under `request_rate=inf` and disappeared under `request_rate=1`.

### 3. TPOT rose with concurrency, but did not explain the inversion

![TPOT p99: request_rate=inf vs request_rate=1](results/plots/build-002/tpot_inf_vs_rate1.png)

TPOT increased with concurrency, but the dramatic anomaly was in TTFT, not TPOT.

### 4. Throughput depends on arrival shape

![Output Throughput vs Concurrency](results/plots/build-002/output_throughput_vs_concurrency.png)

The `request_rate=inf` run exposed burst throughput scaling. The `request_rate=1` run was intentionally arrival-rate limited.


---

### Hardware

```text
Instance: rtxpro6000mq-11-56-850-1lg.1
GPU: RTX PRO 6000
VRAM: 96 GB
System RAM: 56 GB
vCPU: 11
```

### Model

```text
deepseek-ai/DeepSeek-V2-Lite-Chat
```

### Runtime

```text
vLLM V1 / modern model runner
```

### Primary Architecture Features

```text
MLA — Multi-head Latent Attention
MoE — Mixture of Experts
Native chunked prefill
Unified scheduler token budget
KV-cache residency
Preemption / recompute behavior
```

---

## Baseline Runtime Configuration

```bash
VLLM_USE_V2_MODEL_RUNNER=1 \
vllm serve deepseek-ai/DeepSeek-V2-Lite-Chat \
  --host 0.0.0.0 \
  --port 8000 \
  --served-model-name deepseek-ai/DeepSeek-V2-Lite-Chat \
  --dtype bfloat16 \
  --max-model-len 16384 \
  --gpu-memory-utilization 0.85 \
  --max-num-seqs 32 \
  --max-num-batched-tokens 8192 \
  --disable-log-stats false \
  2>&1 | tee results/raw/002-modern-vllm-v1-baseline/server-logs/vllm-server.log
```

---

## Telemetry Matrix

Collect only these metrics.

| Group       | Metric                  | Why It Matters                                               |
| ----------- | ----------------------- | ------------------------------------------------------------ |
| Latency     | TTFT p95                | First-token delay, prompt admission, chunked prefill effects |
| Latency     | TPOT / ITL p95          | Decode smoothness and stream degradation                     |
| Throughput  | Request throughput      | Request-level scaling                                        |
| Throughput  | Output token throughput | Decode-side useful output                                    |
| Scheduler   | Running requests        | Active request residency                                     |
| Scheduler   | Waiting requests        | Queueing and admission pressure                              |
| Scheduler   | Preemptions             | Memory pressure / recompute risk                             |
| Memory      | GPU cache usage         | KV/cache block residency                                     |
| Reliability | Success rate            | Hard failure or instability                                  |
| Hardware    | GPU memory used         | Runtime memory footprint                                     |

---

## Results Summary Format

`results-summary.md` 

## Table 1 — Prefill Context Stretch

| Input | Output | Concurrency | TTFT p99 ms | TPOT p99 ms | ITL p99 ms | Req/s | Out tok/s | Peak KV Cache | Peak Waiting | Preemptions Δ | Success | Failed | Classification |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 1024 | 128 | 1 | 4847.15 | 4.80 | 5.24 | 1.11 | 142.69 | 0.000658 | 0 | 0 | 25 | 0 | context growth |
| 2048 | 128 | 1 | 83.94 | 4.88 | 5.32 | 1.43 | 183.40 | 0.00126 | 0 | 0 | 25 | 0 | context growth |
| 4096 | 128 | 1 | 110.62 | 5.04 | 5.55 | 1.34 | 171.31 | 0.002445 | 0 | 0 | 25 | 0 | context growth |
| 8192 | 128 | 1 | 201.40 | 5.40 | 5.89 | 1.14 | 145.63 | 0.004817 | 0 | 0 | 25 | 0 | long-context pressure |
| 12288 | 128 | 1 | 247.14 | 5.71 | 6.36 | 1.03 | 132.35 | 0.007188 | 0 | 0 | 25 | 0 | long-context pressure |
| 15360 | 128 | 1 | 261.50 | 5.98 | 6.70 | 0.99 | 126.68 | 0.008929 | 0 | 0 | 25 | 0 | long-context pressure |


## Table 2 — KV Concurrency Ramp

| Input | Output | Concurrency | TTFT p99 ms | TPOT p99 ms | ITL p99 ms | Req/s | Out tok/s | Peak KV Cache | Peak Waiting | Preemptions Δ | Success | Failed | Classification |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| 2048 | 512 | 1 | 91.76 | 4.90 | 5.35 | 0.39 | 199.17 | 0.001482 | 0 | 0 | 50 | 0 | useful scaling |
| 2048 | 512 | 2 | 83.58 | 7.24 | 7.70 | 0.55 | 283.54 | 0.002964 | 0 | 0 | 50 | 0 | useful scaling |
| 2048 | 512 | 4 | 109.29 | 9.37 | 10.25 | 0.85 | 432.95 | 0.005872 | 0 | 0 | 50 | 0 | useful scaling |
| 2048 | 512 | 8 | 3199.87 | 14.97 | 14.41 | 1.14 | 584.93 | 0.011578 | 0 | 0 | 50 | 0 | latency pressure |
| 2048 | 512 | 16 | 3968.60 | 18.32 | 17.56 | 1.65 | 845.70 | 0.023323 | 0 | 0 | 50 | 0 | latency pressure |
| 2048 | 512 | 24 | 400.87 | 17.19 | 19.93 | 2.29 | 1174.45 | 0.035291 | 0 | 0 | 50 | 0 | high concurrency, no preemption |
| 2048 | 512 | 32 | 462.38 | 17.53 | 19.78 | 2.77 | 1416.71 | 0.04686 | 0 | 0 | 50 | 0 | high concurrency, no preemption |

---


