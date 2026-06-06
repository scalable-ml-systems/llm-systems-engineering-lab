# Build 2 — Modern vLLM V1 Architecture Baseline

## Objective

Build 2 establishes a compact, production-relevant baseline for a modern sparse/compressed LLM architecture on the vLLM V1 runtime.

The goal is to map how a modern MLA/MoE model behaves under vLLM V1 unified scheduling before any optimization is attempted.

Build 2 answers three questions:

1. How does context growth affect TTFT and GPU cache residency?
2. How does concurrency growth affect throughput, waiting requests, and preemption?
3. Where does the backend transition from useful scaling into inefficient saturation?

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

## Build Name

```text
Build 2 — Modern vLLM V1 Architecture Baseline
```

## One-Line Summary

```text
Map context growth, concurrency growth, KV residency, and preemption behavior for a modern MLA/MoE model on vLLM V1.
```

---

## Target Stack

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

## Scope

### In Scope

```text
single GPU
single model
single vLLM server
one baseline runtime config
context length stretch
concurrency ramp
vLLM /metrics scraping
server log capture
summary table
findings document
```

### Out of Scope

```text
Kubernetes
routing
multi-node inference
multi-GPU tensor parallelism
expert parallelism
training
LoRA
model comparison
dense-vs-MLA comparison
MoE backend tuning
max throughput tuning
large benchmark matrix
Nsight profiling unless results are confusing
```

---

## Project Structure

Keep only four docs:

```text
docs/builds/002-modern-vllm-v1-baseline/
  README.md
  setup.md
  results-summary.md
  findings.md
```

Keep only three scripts:

```text
scripts/
  run_server_build_002.sh
  run_benchmark_build_002.sh
  scrape_vllm_metrics.sh
```

Use this results layout:

```text
results/raw/002-modern-vllm-v1-baseline/
  server-logs/
  sanity/
  context-stretch/
  concurrency-ramp/

results/processed/002-modern-vllm-v1-baseline/
  summary.csv
```

No additional docs unless a real failure requires documenting.

---

## Baseline Runtime Configuration

Use one baseline configuration for Build 2.

Do not tune yet.

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

### Runtime Notes

`VLLM_USE_V2_MODEL_RUNNER=1` should be treated as an explicit runtime setting to verify through logs, not something to assume blindly. vLLM documents its environment variables under the `VLLM_` prefix, so every run must capture the exact runtime environment and startup logs.

`max_model_len=16384` is selected because Build 2 includes context stretch up to approximately 16K tokens.

`max_num_batched_tokens=8192` is selected as the baseline scheduler token budget. It is not tuned in Build 2. Build 3 may tune it later.

---

## Required Runtime Capture

Every run must capture:

```text
vLLM version
torch version
CUDA availability
GPU name
driver version
server command
environment variables
model name
max_model_len
max_num_batched_tokens
max_num_seqs
gpu_memory_utilization
server startup logs
/metrics sample
```

The report should not claim a metric exists unless it is observed in the installed vLLM `/metrics` endpoint.

---

## Experiments

Build 2 has exactly three experiments.

No additional experiments unless the model fails to load or metrics are unusable.

---

# Experiment 0 — Sanity Baseline

## Purpose

Validate the stack.

This confirms that the model loads, the vLLM server responds, the benchmark runs, and `/metrics` is available.

## Workload

```text
input_len=1024
output_len=128
concurrency=1
num_prompts=25
```

## Required Output

```text
TTFT p95
TPOT / ITL p95
request throughput
output token throughput
GPU cache usage
running requests
waiting requests
preemptions
success rate
```

## Expected Result

```text
healthy baseline
no preemption
low waiting requests
stable TTFT
stable TPOT
```

---

# Experiment 1 — Context Stretch

## Purpose

Map how context growth affects TTFT and GPU cache residency.

This is the compact baseline for native chunked prefill and MLA memory-residency behavior.

## Workload

```text
input_len=1024, 2048, 4096, 8192, 12288, 15360
output_len=128
concurrency=1
num_prompts=25
```

## What This Maps

```text
TTFT growth as prompt length increases
GPU cache usage as prompt length increases
waiting request behavior at single stream
preemption absence/presence at long context
baseline MLA residency curve
```

## Expected Result

```text
TTFT increases with prompt length
GPU cache usage increases with prompt length
preemptions should remain zero at concurrency 1
large prompts may show chunked-prefill behavior through TTFT slope changes
```

---

# Experiment 2 — Concurrency Ramp

## Purpose

Find the useful scaling boundary and preemption/inefficient saturation point.

## Workload

```text
input_len=2048
output_len=512
concurrency=1, 2, 4, 8, 16, 24, 32
num_prompts=50
```

## Run Rule

Run progressively.

Start with:

```text
1, 2, 4, 8, 16
```

Only run:

```text
24, 32
```

if concurrency 16 is stable.

## Stop Conditions

Stop the ramp if any of the following happens:

```text
preemptions spike
success rate drops sharply
server becomes unstable
OOM risk appears
waiting requests explode
throughput has already flattened clearly
```

## What This Maps

```text
throughput scaling
TTFT degradation under load
TPOT / ITL degradation under load
GPU cache residency
waiting request growth
preemption inflection
useful saturation vs inefficient saturation
```

## Expected Result

```text
throughput rises initially
waiting requests eventually increase
GPU cache usage increases
preemptions identify memory/residency pressure if they occur
throughput flattening identifies the useful scaling boundary
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

Metric names may vary by vLLM version.

Discover available names with:

```bash
curl -s http://localhost:8000/metrics | grep -Ei "cache|kv|waiting|running|preempt|prefix|prompt|decode|token"
```

Do not report fake metrics.

Do not claim `gpu_kv_cache_compression_ratio` unless the metric exists in `/metrics`.

For MLA, report:

```text
MLA residency curve = GPU cache usage versus prompt length
```

This is a derived artifact, not necessarily a native vLLM metric.

---

## Results Summary Format

`results-summary.md` should contain only two tables.

## Table 1 — Context Stretch

| Input Len | Output Len | Concurrency | TTFT p95 | TPOT p95 | GPU Cache Usage | Waiting | Preemptions | Classification          |
| --------: | ---------: | ----------: | -------: | -------: | --------------: | ------: | ----------: | ----------------------- |
|      1024 |        128 |           1 |      TBD |      TBD |             TBD |     TBD |         TBD | baseline                |
|      2048 |        128 |           1 |      TBD |      TBD |             TBD |     TBD |         TBD | context growth          |
|      4096 |        128 |           1 |      TBD |      TBD |             TBD |     TBD |         TBD | context growth          |
|      8192 |        128 |           1 |      TBD |      TBD |             TBD |     TBD |         TBD | chunked-prefill visible |
|     12288 |        128 |           1 |      TBD |      TBD |             TBD |     TBD |         TBD | long-context pressure   |
|     15360 |        128 |           1 |      TBD |      TBD |             TBD |     TBD |         TBD | long-context pressure   |

## Table 2 — Concurrency Ramp

| Input Len | Output Len | Concurrency | TTFT p95 | TPOT p95 | Throughput | GPU Cache Usage | Waiting | Preemptions | Classification                |
| --------: | ---------: | ----------: | -------: | -------: | ---------: | --------------: | ------: | ----------: | ----------------------------- |
|      2048 |        512 |           1 |      TBD |      TBD |        TBD |             TBD |     TBD |         TBD | healthy                       |
|      2048 |        512 |           2 |      TBD |      TBD |        TBD |             TBD |     TBD |         TBD | scaling                       |
|      2048 |        512 |           4 |      TBD |      TBD |        TBD |             TBD |     TBD |         TBD | scaling                       |
|      2048 |        512 |           8 |      TBD |      TBD |        TBD |             TBD |     TBD |         TBD | pressure starts               |
|      2048 |        512 |          16 |      TBD |      TBD |        TBD |             TBD |     TBD |         TBD | useful/inefficient saturation |
|      2048 |        512 |          24 |      TBD |      TBD |        TBD |             TBD |     TBD |         TBD | optional                      |
|      2048 |        512 |          32 |      TBD |      TBD |        TBD |             TBD |     TBD |         TBD | optional                      |

---

## State Vocabulary

Use only these classifications:

```text
healthy
context-growth pressure
chunked-prefill pressure
useful concurrency scaling
preemption / inefficient saturation
```

Do not over-classify.

The point is to identify the minimal runtime state needed for Build 3.

---

## Findings Format

`findings.md` should answer only these questions:

```text
1. Did DeepSeek-V2-Lite-Chat load and serve correctly on RTX PRO 6000?

2. How did TTFT change as context length grew from 1K to 16K?

3. How did GPU cache usage change as context length grew?

4. Did preemptions appear during context stretch?

5. Up to what concurrency did throughput scale usefully?

6. At what concurrency did waiting requests increase?

7. At what concurrency did throughput flatten?

8. Did preemptions appear during concurrency ramp?

9. What is the first knob Build 3 should tune?

10. What should Build 4 eventually route around?
```

No long essay.

No theory expansion.

---

## Build 3 Dependency

Build 3 starts only after Build 2 identifies:

```text
baseline TTFT / TPOT
TTFT growth curve across context length
GPU cache usage curve across context length
safe concurrency range
throughput flattening point
waiting-request inflection point
preemption inflection point, if any
```

Build 3 may tune:

```text
max_num_batched_tokens
max_num_seqs
gpu_memory_utilization
max_model_len
moe_backend
prefix caching
scheduler reserve behavior
```

But none of those are tuned in Build 2.

---

## Build 4 Dependency

Build 4 will use Build 2 state signals for routing/control-plane logic.

Build 2 should identify whether a backend is:

```text
safe for short requests
unsafe for long-context requests
approaching cache pressure
showing waiting-request buildup
showing preemption/recompute risk
past useful concurrency scaling
```

Build 4 turns those signals into routing decisions.

---

## Success Standard

Build 2 is successful when the final summary can say:

```text
DeepSeek-V2-Lite-Chat served successfully on RTX PRO 6000 with vLLM V1.
```

```text
Context length growth from 1K to 16K increased TTFT from X to Y and GPU cache usage from A to B.
```

```text
Concurrency scaled usefully until N, after which waiting requests increased and throughput flattened.
```

```text
Preemptions began at N, or did not occur within the tested range.
```

```text
Build 3 should tune <first knob> because Build 2 showed <specific inflection>.
```

Build 2 should not say only:

```text
latency increased
throughput dropped
GPU memory increased
```

It must identify:

```text
what changed
where the inflection happened
which metric proved it
what Build 3 should tune next
```

---

## Hard Discipline Rules

```text
One model only.
One GPU only.
One baseline server config.
Three experiments only.
Four docs only.
Three scripts only.
No tuning.
No model comparison.
No Kubernetes.
No Nsight unless metrics are confusing.
Stop the concurrency ramp once useful saturation is clearly identified.
```

---

## Final One-Sentence Scope

Build 2 maps the baseline runtime behavior of DeepSeek-V2-Lite-Chat on vLLM V1 using one sanity run, one context stretch, and one concurrency ramp, producing only the inflection points needed for Build 3 tuning and Build 4 routing.

