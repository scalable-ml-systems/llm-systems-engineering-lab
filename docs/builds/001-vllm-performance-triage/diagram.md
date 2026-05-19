# Diagram — Build 1: vLLM Performance Triage

## System Under Test

Build 1 studies a single vLLM backend serving Qwen2.5-7B-Instruct on one RTX 4090 GPU.

```text
                    ┌──────────────────────────┐
                    │   Benchmark Client        │
                    │   vllm bench serve        │
                    └─────────────┬────────────┘
                                  │
                                  │ OpenAI-compatible request
                                  │ /v1/completions
                                  ▼
                    ┌──────────────────────────┐
                    │   vLLM API Server         │
                    │   HTTP request handling   │
                    └─────────────┬────────────┘
                                  │
                                  ▼
                    ┌──────────────────────────┐
                    │   Request Scheduler       │
                    │   admission + batching    │
                    └─────────────┬────────────┘
                                  │
                    ┌─────────────┴────────────┐
                    │                          │
                    ▼                          ▼
        ┌──────────────────────┐    ┌──────────────────────┐
        │ Waiting / Queued     │    │ Running Requests     │
        │ Requests             │    │ Active Sequences     │
        └──────────────────────┘    └──────────┬───────────┘
                                               │
                                               ▼
                                ┌──────────────────────────┐
                                │ Prefill Phase             │
                                │ process input tokens      │
                                │ build KV state            │
                                └─────────────┬────────────┘
                                              │
                                              ▼
                                ┌──────────────────────────┐
                                │ KV Cache Residency        │
                                │ active sequence memory    │
                                └─────────────┬────────────┘
                                              │
                                              ▼
                                ┌──────────────────────────┐
                                │ Decode Loop               │
                                │ generate output tokens    │
                                └─────────────┬────────────┘
                                              │
                                              ▼
                                ┌──────────────────────────┐
                                │ Response Completion       │
                                │ return generated text     │
                                └──────────────────────────┘

Measurement Points
Benchmark Client
  ├── offered request rate
  ├── completed request throughput
  ├── TTFT
  ├── TPOT
  ├── ITL
  └── E2E latency

vLLM Runtime
  ├── admission behavior
  ├── request scheduling
  ├── prefill work
  ├── decode loop
  ├── active sequence residency
  └── context-window validation

GPU Node
  ├── GPU memory usage
  ├── GPU utilization
  └── CUDA/runtime compatibility
Latency Decomposition
Request latency
    │
    ├── Queue / admission wait
    │
    ├── Prefill time
    │     └── affected by prompt length
    │
    ├── Time to first token
    │     └── TTFT = queue/admission + scheduling + prefill
    │
    ├── Decode loop
    │     └── affected by output length and active sequence residency
    │
    └── Time per output token
          └── TPOT = per-token decode pacing
Build 1 Interpretation Map
Symptom:
  TTFT rises sharply
  TPOT remains stable
  actual req/s plateaus

Interpretation:
  backend is saturated before decode

Likely causes:
  request queueing
  scheduler/admission pressure
  prefill pressure
  long decode residency reducing available capacity

Operational response:
  reduce offered load
  identify saturation boundary
  tune batching/sequence limits later
  add replicas/routing only after single-backend behavior is understood
Prompt Pressure Path
Longer prompt
    │
    ▼
More prefill work
    │
    ▼
More KV state to initialize
    │
    ▼
Higher TTFT
    │
    ▼
Possible mild TPOT impact if active context pressure increases

Observed in Build 1:

input 512  → mean TTFT ~196 ms
input 3072 → mean TTFT ~1368 ms
Output Pressure Path
Longer output
    │
    ▼
Request remains active for more decode steps
    │
    ▼
Active sequence residency increases
    │
    ▼
Available request capacity decreases
    │
    ▼
New requests wait longer
    │
    ▼
TTFT rises even if TPOT stays stable

Observed in Build 1:

output 128  → actual throughput ~0.95 req/s, mean TTFT ~196 ms
output 1024 → actual throughput ~0.24 req/s, mean TTFT ~144074 ms

TPOT stayed near ~18 ms/token.

This is the central systems insight from Build 1:

Long outputs can harm request-level latency without slowing per-token decode.
Context-Window Safety Boundary
max_model_len = 4096

Request must satisfy:

prompt tokens
+ output tokens
+ chat/template overhead
< max_model_len

Build 1 observed a context validation failure:

requested tokens = 4422
max context = 4096

Operational implication:

Do not set prompt length equal to max_model_len.
Reserve headroom for output tokens and template overhead.
Scope Boundary

Build 1 stops at the single-backend system.

Included:
  benchmark client
  single vLLM backend
  Qwen2.5-7B-Instruct
  RTX 4090
  request-rate pressure
  prompt pressure
  output pressure
  context-window failure
  runtime bring-up failures

Excluded:
  multi-backend routing
  tensor parallelism
  MI350X
  larger context restarts
  optimization sweeps
  LoRA / adapter serving
  reliability injection

The next build can study prefill, decode, and KV behavior in more detail, but Build 1's purpose is complete once the single-backend triage behavior is documented.
