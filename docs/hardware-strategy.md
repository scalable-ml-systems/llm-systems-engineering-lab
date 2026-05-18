## MI350X + ROCm Evidence Package

The **AMD Instinct MI350X** is used as the **high‑memory, large‑context, and ROCm‑native flagship node** in this lab. It anchors the **“large‑model, large‑context, and distributed inference evidence”** bucket, while the RTX 4090 represents **7B–32B, product‑facing, latency‑sensitive serving workloads**.

### Why MI350X fits this role

- The MI350X / MI355X family is documented to run **Llama‑2/3‑70B, Qwen‑2/72B, and Mixtral‑8x‑style models** efficiently, both in FP16 and lower‑bit‑width formats.  
- ROCm‑accelerated vLLM has been shown to maintain **acceptable latency and throughput** on these large models, especially when continuous batching and tensor‑parallelism are tuned.  
- In enterprise‑style deployments, MI350X‑class GPUs are used where **memory bandwidth and large‑batch capacity** are more important than “100B+ tokens/day” micro‑latency.

### Scope of the MI350X + ROCm evidence package

This package serves as the **“large‑model, large‑context, ROCm‑native”** counterpart to the RTX‑4090 “7B‑to‑32B, latency‑sensitive” base. It covers:

- **Large‑model inference behavior**  
  - 32B–72B models (Qwen2.5‑32B‑Instruct, Qwen2.5‑72B‑Instruct, Llama‑3.1‑70B‑Instruct) under controlled concurrency and context sweeping.  
  - Measure how TTFT, ITL, and E2E latency change with model width and memory usage.

- **Large‑context stress**  
  - 1K → 32K context sweeps on 32B and 72B models.  
  - Measure KV‑cache pressure, OOM‑risk, and tail‑latency behavior.

- **Distributed inference strategy (Build 5, on MI350X)**  
  - Compare single‑GPU, replica‑scaling, and tensor‑parallel setups on MI350X.  
  - Show how tensor‑parallel overhead and inter‑device latency affect 70B‑style models under real‑world load.

- **Training‑to‑serving pathway (Build 6, optional flagship)**  
  - Fine‑tune a 32B‑ or 72B‑class model or adapter on MI350X (INT4/FP16) and package it for serving.  
  - Measure adapter‑load latency, memory overhead, and quality‑vs‑cost versus a 7B‑baseline.

- **ROCM‑specific tuning and configuration**  
  - Document ROCm / HIP / vLLM‑ROCM flags, memory layout, and kernel tuning.  
  - Capture baseline and tuned throughput/latency for each 32B‑ and 72B run, and compare against “default” settings.

### Narrative and risk‑management framing

This evidence package answers questions such as:

- _“How much latency must you accept when running 70B‑class models on a single MI350X under a 10k‑RPM workload?”_  
- _“When does KV‑cache‑pressure become the dominant failure mode instead of GPU‑utilization?”_  
- _“How much can ROCm‑specific tuning recover in throughput without harming latency SLOs?”_  

By pairing this with the RTX‑4090 evidence, the lab becomes **two complementary production‑style reference points**:

- **RTX 4090** → 7B–32B, low‑latency, multi‑replica, product‑facing inference.  
- **MI350X** → 32B–72B, large‑context, ROCm‑native, high‑memory‑bandwidth workloads.
