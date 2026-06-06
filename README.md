# LLM Systems Engineering Lab

A hands-on systems engineering lab for understanding modern LLM inference from the runtime layer down to the GPU and up to traffic admission.

This is not a generic "which GPU is faster?" benchmark.

The goal is to build a practical, evidence-driven inference engineering playbook for frontier serving architectures: **MoE**, **MLA**, **vLLM V1**, **KV-cache residency**, **prefill/decode behavior**, **scheduler pressure**, and **traffic-shape sensitivity**.

---

## Why This Repo Exists

Modern inference performance is not dictated by the GPU alone. It is shaped by the full serving stack:

```
model architecture
  ↓
attention / KV-cache design
  ↓
serving runtime
  ↓
scheduler and batching policy
  ↓
request arrival pattern
  ↓
host CPU + GPU execution
  ↓
TTFT / TPOT / throughput / failures
```

Most LLM inference writeups over-focus on GPU utilization or tokens/second. That misses the real systems problem.

An inference node is a balanced ecosystem:

| Layer | Why It Matters |
|---|---|
| Model architecture | MoE changes active compute; MLA changes KV-cache residency |
| Runtime | vLLM scheduling and batching decide how requests share the backend |
| KV cache | Long-lived decode sequences consume memory across iterations |
| Traffic shape | Burst and steady arrival can produce very different TTFT behavior |
| Host CPU | API serving, tokenization, async runtime, metrics, and benchmark clients are not free |
| GPU | Executes model work, but is only one part of the serving node |

The purpose of these builds is to answer mechanism-level questions:

- Why does TTFT spike?
- When does TPOT degrade?
- Is the backend compute-bound, memory-bound, scheduler-bound, or admission-bound?
- When does KV-cache residency become the limiting factor?
- How do prefill and decode behave differently?
- How do modern architectures like MoE + MLA change the expected bottleneck?
- What should a production router, scheduler, or Kubernetes control plane actually watch?

---

## Core Thesis

Frontier inference systems are moving from simple dense-model serving toward architectures that change the bottleneck profile.

In older dense-model mental models, the expected failure path is:

```
concurrency ↑
  → resident sequences ↑
  → KV cache usage ↑
  → memory pressure ↑
  → waiting / preemption / OOM
  → latency collapse
```

With modern architectures such as **MoE + MLA**, that pattern changes.

MLA reduces KV-cache residency. MoE changes the active compute path. vLLM V1 changes scheduling and batching behavior. Traffic shape changes how pressure appears at the backend.

The real question becomes:

> If KV cache is no longer the first bottleneck, where does the bottleneck move?

Build 002 answered that question in one concrete setup:

> KV-cache pressure did not appear. Burst-admission behavior did.

---

## Build Progress

| Build | Focus | Architecture / Runtime | Status | Main Artifact |
|---|---|---|---|---|
| Build 001 | vLLM performance triage | Dense model baseline on vLLM | Complete | TTFT / TPOT / throughput baseline |
| Build 002 | Modern vLLM V1 baseline | DeepSeek-V2-Lite-Chat, MoE + MLA, vLLM V1 | Complete | Prefill, decode, KV residency, request-rate comparison |
| Build 003 | Scheduler and admission tuning | vLLM V1 tuning knobs | Planned | `max_num_batched_tokens`, `max_num_seqs`, admission policy |
| Build 004 | Runtime-aware routing | Backend-state-aware routing | Planned | Routing rules based on TTFT, queueing, KV, and decode state |

---

## Build 001 — vLLM Performance Triage

Build 001 established the first serving baseline.

The goal was to learn how to measure basic inference health before making deeper claims.

**Measured:**

- TTFT
- TPOT / ITL
- request throughput
- output token throughput
- workload-shape sensitivity
- failure modes
- operational decision rules

**Artifacts:**

```
docs/builds/001-vllm-performance-triage/
results/processed/001-vllm-performance-triage/
```

**Build 001 answered:**

> How do I know when a vLLM backend is healthy, saturated, or failing?

---

## Build 002 — Modern vLLM V1 Baseline

Build 002 moved from basic triage to a modern architecture baseline.

**Target stack:**

| Component | Value |
|---|---|
| Model | `deepseek-ai/DeepSeek-V2-Lite-Chat` |
| Architecture | MoE + MLA |
| Runtime | vLLM V1 |
| GPU | RTX PRO 6000 |
| VRAM | 96 GB |
| Host RAM | 56 GB |
| vCPU | 11 |
| Provider | CloudRift |

**Build 002 asked:**

> How do prefill, decode, KV-cache residency, scheduler pressure, and request arrival shape interact when serving a modern MoE + MLA model on vLLM V1?

### Experiment Tracks

| Track | Name | Question |
|---|---|---|
| T0 | Runtime baseline | Is the server healthy before stress? |
| T1 | Prefill / context stretch | Does longer context primarily affect TTFT or TPOT? |
| T2 | Decode residency ramp | Does longer output degrade token smoothness? |
| T3 | KV / concurrency ramp | Does higher concurrency trigger KV pressure or preemption? |
| T4 | request_rate repeatability | Was the c8/c16 TTFT inversion burst-admission behavior? |

### Headline Finding

The expected failure mode was KV-cache pressure. That did not happen.

**Observed:**

```
Peak KV-cache usage stayed below 5%
Preemptions stayed at 0
Waiting stayed at 0
Failed requests stayed at 0
```

The surprising behavior appeared under traffic shape. At `request_rate=inf`, the c8/c16 concurrency points showed multi-second TTFT spikes. At `request_rate=1`, the same concurrency ramp normalized.

| Concurrency | TTFT p99 at `request_rate=inf` | TTFT p99 at `request_rate=1` | Interpretation |
|---:|---:|---:|---|
| 8 | 3439.63 ms | 73.77 ms | Burst-admission artifact |
| 16 | 3263.37 ms | 76.25 ms | Burst-admission artifact |

**Final Build 002 conclusion:**

> DeepSeek-V2-Lite-Chat on vLLM V1 did not hit KV-cache or preemption pressure on the tested RTX PRO 6000 VM. The visible instability was TTFT sensitivity under burst-style request admission, not GPU memory collapse.

The systems lesson:

> MoE + MLA changed the bottleneck. KV residency stayed low, so the bottleneck moved upward into request admission, scheduler/runtime behavior, and node balance.

**Artifacts:**

```
docs/builds/002-modern-vllm-v1-baseline/
results/processed/002-modern-vllm-v1-baseline/
```

**Key docs:**

```
docs/builds/002-modern-vllm-v1-baseline/README.md
docs/builds/002-modern-vllm-v1-baseline/setup.md
docs/builds/002-modern-vllm-v1-baseline/results-summary.md
docs/builds/002-modern-vllm-v1-baseline/findings.md
docs/builds/002-modern-vllm-v1-baseline/cloudrift-rate1-repeatability.md
```

---

## What Build 002 Teaches

### 1. KV cache is not always the first bottleneck

With this model and workload, KV-cache usage remained low. That matters because many serving mental models assume concurrency pressure will immediately become memory pressure.

Build 002 showed a different behavior:

```
concurrency ↑
  → KV cache stayed low
  → no preemptions
  → no failures
  → latency behavior depended on request arrival shape
```

### 2. `request_rate=inf` and `request_rate=1` are different systems tests

`request_rate=inf` is a burst/saturation probe. It answers:

> What happens when the client pushes as fast as possible, bounded by max concurrency?

`request_rate=1` is a controlled-arrival probe. It answers:

> What happens when requests arrive at a bounded rate?

Both are useful. They answer different questions. Build 002 used both because the c8/c16 TTFT inversion needed attribution.

### 3. A benchmark is an argument about causality

The first run showed TTFT spikes. A weak conclusion would have been:

> The GPU saturated.

The evidence disagreed:

```
KV cache < 5%
preemptions = 0
waiting = 0
failed requests = 0
```

Build 002 changed one variable: request arrival rate. When the spikes disappeared under `request_rate=1`, the conclusion became stronger:

> The c8/c16 inversion was burst-admission behavior, not KV-cache pressure or stable GPU saturation.

That is systems engineering.

### 4. Host CPU is part of the inference node

The Build 002 VM had a powerful GPU but only 11 vCPUs. That matters because the host participates in:

- API serving
- tokenization
- async runtime coordination
- scheduler loop
- metrics scraping
- benchmark client execution

The GPU was not the only relevant resource. The inference node must be treated as a full system.

---

## Repository Structure

```
configs/
  models/
  workloads/

docs/
  builds/
    001-vllm-performance-triage/
    002-modern-vllm-v1-baseline/

results/
  processed/
    001-vllm-performance-triage/
    002-modern-vllm-v1-baseline/

scripts/
  run_server_build_002.sh
  run_benchmark_build_002.sh
  scrape_vllm_metrics.sh
  summarize_build_002.py
```

Raw benchmark data is intentionally not kept in `main`. The curated `main` branch contains docs, processed results, reproducibility scripts, and engineering conclusions. Raw evidence is preserved on experiment branches where needed.

---

## Reproducibility Philosophy

| Artifact Type | Purpose | Kept in `main`? |
|---|---|---|
| Raw logs | Full experiment evidence | No |
| Processed results | Tables and summaries | Yes |
| Findings | Engineering interpretation | Yes |
| Scripts | Reproduce and summarize runs | Yes |
| Scratch helpers | One-off local analysis | No |

The goal is to keep `main` readable and portfolio-quality while preserving enough structure to reproduce the work.

---

## Engineering Principles

**1. Separate measurement from tuning.**
Build 002 measured behavior. Build 003 will tune knobs.

**2. Do not claim GPU saturation without evidence.**
Look for KV usage, waiting, preemptions, failures, TTFT, TPOT, and throughput together.

**3. Treat traffic shape as a first-class variable.**
Burst arrival and steady arrival can produce different latency profiles.

**4. Use mechanism tables, not just benchmark tables.**
The goal is to explain why the system behaved that way.

**5. Do not hide hardware constraints.**
vCPU count, host RAM, runtime version, and benchmark client placement matter.

**6. Keep the repo clean.**
`main` should show final docs and processed results, not every raw scratch artifact.

---

## Planned Build 003

Build 003 starts from the Build 002 finding:

> KV pressure did not appear; burst admission did.

Build 003 focuses on scheduler and admission controls before chasing memory fixes.

**Planned knobs:**

| Priority | Knob | Question |
|---:|---|---|
| 1 | `max_num_batched_tokens` | Can scheduler token budget reduce TTFT spikes without hurting TPOT? |
| 2 | `max_num_seqs` | Can sequence limits reduce burst amplification? |
| 3 | router-side concurrency cap | Can upstream admission prevent pathological burst behavior? |
| 4 | finite request-rate policy | What arrival rate keeps TTFT within target bounds? |
| 5 | repeat trials | Are improvements stable or noisy? |

**Build 003 question:**

> Given a fixed inference node shape, which scheduler and admission knobs improve the TTFT / TPOT / throughput tradeoff?

---

## Why This Matters

LLM serving is not ordinary request/response infrastructure.

In a normal HTTP service, requests consume resources briefly and exit. In LLM serving, requests become long-lived decode sequences. They occupy scheduler slots, participate in continuous batching, consume KV-cache residency, and interact with token-level scheduling over time.

That is why the same "concurrency" number can mean different things depending on: input length, output length, KV-cache design, model architecture, request arrival rate, scheduler policy, host CPU, GPU memory, and runtime implementation.

This repo exists to make those interactions visible.

---

## Current Status

```
Build 001: Complete
Build 002: Complete
Build 003: Planned
Build 004: Planned
```

The current main result:

> The bottleneck moved. In Build 002, MoE + MLA on vLLM V1 avoided KV-cache pressure in the tested range. The meaningful serving behavior appeared in burst admission and scheduler/runtime sensitivity, not memory collapse.

---

## References

- DeepSeek-V2: MoE + MLA architecture
- Multi-head Latent Attention and KV-cache compression
- DeepSeekMoE sparse computation
- vLLM V1 serving runtime
- vLLM PagedAttention and continuous batching
- vLLM benchmark request-rate and max-concurrency behavior