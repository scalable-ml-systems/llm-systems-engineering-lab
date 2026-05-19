# Operational Rule — Build 1: vLLM Performance Triage

## Rule Summary

Decompose LLM serving latency before changing infrastructure.

For a single vLLM backend, do not treat “high latency” as one generic problem. First separate the latency into:

- **TTFT** — time to first token
- **TPOT** — time per output token
- **actual request throughput**
- **offered request rate**
- **prompt length**
- **output length**
- **context-window limits**

The operational decision depends on which metric breaks first.

---

## Primary Rule

If **actual request throughput plateaus** while **offered request rate increases**, and **TTFT rises sharply** while **TPOT remains stable**, the backend is saturated before the decode loop.

Treat the bottleneck as one of:

- request queueing
- scheduler/admission pressure
- prefill pressure
- long decode residency reducing available request capacity

Do **not** immediately assume the GPU is slow at per-token generation.

---

## Evidence From This Build

The healthy low-pressure baseline was:

```text
input=512
output=128
offered_request_rate=1 req/s
actual_request_throughput=0.95 req/s
mean_TTFT=196.73 ms
p99_TTFT=1427.87 ms
mean_TPOT=18.18 ms
p99_TPOT=18.96 ms

At higher offered request rates, throughput plateaued while TTFT rose sharply:

rate=2:
  actual_request_throughput=1.69 req/s
  mean_TTFT=2589.05 ms
  p99_TTFT=5531.84 ms
  mean_TPOT=18.61 ms
  p99_TPOT=19.00 ms

rate=4:
  actual_request_throughput=1.70 req/s
  mean_TTFT=15000.25 ms
  p99_TTFT=30864.97 ms
  mean_TPOT=18.77 ms
  p99_TPOT=19.25 ms

rate=8:
  actual_request_throughput=1.72 req/s
  mean_TTFT=21043.59 ms
  p99_TTFT=43091.60 ms
  mean_TPOT=18.75 ms
  p99_TPOT=19.27 ms

The backend’s sustainable request throughput under this conservative server profile was approximately:

~1.7 requests/second

Above that point, more offered load did not produce more completed throughput. It produced higher TTFT.

Decision Rule 1 — Request-Rate Saturation

When:

offered_request_rate increases
actual_request_throughput stops increasing
TTFT rises sharply
TPOT remains stable

Then:

the backend is saturated before decode

Operational response:

Reduce offered load or apply admission control.
Separate short and long workloads if mixed traffic is present.
Tune batching and sequence limits in Build 3.
Add replicas or routing only after single-backend capacity is understood.
Do not diagnose this as per-token decode slowness.
Decision Rule 2 — Prompt-Length Pressure

When prompt length increased from 512 to 3072 tokens at rate 1:

input=512:
  mean_TTFT=195.90 ms
  p99_TTFT=1453.68 ms
  mean_TPOT=18.19 ms

input=3072:
  mean_TTFT=1367.88 ms
  p99_TTFT=3935.80 ms
  mean_TPOT=24.50 ms

Rule:

If prompt length increases and TTFT rises faster than TPOT, treat the workload as prefill-heavy.

Operational response:

Track prompt-length buckets.
Avoid mixing long-context requests blindly with short interactive traffic.
Reserve separate capacity or routing policy for long-context workloads in later builds.
Tune prefill/KV behavior only after baseline saturation is understood.
Decision Rule 3 — Output-Length Residency Pressure

When output length increased from 128 to 1024 tokens at rate 1:

output=128:
  actual_request_throughput=0.95 req/s
  mean_TTFT=196.27 ms
  mean_TPOT=18.19 ms

output=1024:
  actual_request_throughput=0.24 req/s
  mean_TTFT=144073.92 ms
  mean_TPOT=17.98 ms

Rule:

Long outputs can destroy request-level capacity even when TPOT remains stable.

The per-token decode speed stayed close to 18 ms/token, but requests stayed resident much longer. That reduced available capacity for new requests, causing TTFT to explode.

Operational response:

Cap output length for latency-sensitive traffic.
Separate long-generation workloads from short interactive workloads.
Monitor actual request throughput, not only token throughput.
Treat long-output traffic as a capacity-residency problem, not only a decode-speed problem.
Decision Rule 4 — Context-Window Safety

A prompt-pressure run failed when the request exceeded the server context limit:

requested_tokens=4422
max_model_len=4096

Rule:

prompt_tokens + output_tokens + chat_template_overhead must be less than max_model_len

Operational response:

Do not set prompt length equal to max_model_len.
Reserve headroom for output tokens.
Reserve headroom for tokenizer/chat-template overhead.
Use a lower prompt sweep ceiling unless the server is restarted with a larger context window.

For the Build 1 server profile:

max_model_len=4096
safe_prompt_sweep_with_output_128 = 512, 1024, 2048, 3072
Decision Rule 5 — Runtime Reproducibility

The first server bring-up failed because the latest vLLM install pulled an incompatible runtime stack.

Rule:

Pin the complete serving stack before collecting benchmark evidence.

Required runtime versions to record:

vLLM
PyTorch
CUDA wheel version
Transformers
Tokenizers
Hugging Face Hub
NVIDIA driver
GPU model
server launch flags

Operational response:

Do not benchmark with unpinned pip install vllm.
Record runtime versions in raw results.
Record server flags with every benchmark package.
Keep raw results immutable and put interpretation only in docs.
Build 1 Final Operational Rule

For this RTX 4090 + Qwen2.5-7B + vLLM server profile:

If TTFT rises sharply while TPOT remains stable, the backend is not primarily decode-bound.

First inspect:

offered request rate versus actual request throughput
prompt length
output length / decode residency
context-window limits
request queueing / admission pressure

Only after that should you tune vLLM, add replicas, or introduce routing.

Stop Condition

Build 1 is complete when the operator can answer:

What is the healthy baseline?
Where does request-rate saturation begin?
How does prompt length affect TTFT?
How does output length affect request capacity?
Which failure modes appeared during bring-up and benchmarking?
What operational rule follows from the evidence?

This build should stop at single-backend triage. Routing, distributed inference, larger context windows, and optimization sweeps belong to later builds.
EOF

