# Executive Summary — Build 1: vLLM Performance Triage

## Objective

Build 1 establishes a single-backend performance triage baseline for LLM serving.

The system under test was:

```text
GPU: CloudRift RTX 4090 24GB
Model: Qwen/Qwen2.5-7B-Instruct
Runtime: vLLM OpenAI-compatible server
vLLM version: 0.8.5.post1
Server profile: conservative first-boot configuration

The goal was to answer one operational question:

When latency degrades, can we tell whether the backend is suffering from request-rate saturation, prompt/prefill pressure, output/decode residency, or context-window limits?

This build intentionally focused on one backend only. Routing, distributed inference, larger context windows, and vLLM tuning are excluded from Build 1.

Workloads Run

The benchmark suite used synthetic random workloads against the OpenAI-compatible vLLM endpoint.

The run set included:

Suite	Purpose
Baseline	Establish healthy low-pressure behavior
Rate pressure	Find where offered request rate exceeds sustainable throughput
Prompt pressure	Measure how longer inputs affect first-token latency
Output pressure	Measure how longer generations affect request capacity and decode residency

The primary metrics were:

TTFT = Time to First Token
TPOT = Time Per Output Token
actual request throughput
offered request rate
output token throughput
prompt length
output length
Key Result

The backend’s healthy low-pressure baseline was approximately:

input_tokens=512
output_tokens=128
offered_request_rate=1 req/s
actual_request_throughput=0.95 req/s
mean_TTFT=196.73 ms
p99_TTFT=1427.87 ms
mean_TPOT=18.18 ms
p99_TPOT=18.96 ms

The request-rate pressure sweep showed that actual throughput plateaued around:

~1.7 requests/second

Above that point, increasing offered load did not increase completed request throughput. It increased TTFT.

At rate 4:

actual_request_throughput=1.70 req/s
mean_TTFT=15000.25 ms
p99_TTFT=30864.97 ms
mean_TPOT=18.77 ms
p99_TPOT=19.25 ms

At rate 8:

actual_request_throughput=1.72 req/s
mean_TTFT=21043.59 ms
p99_TTFT=43091.60 ms
mean_TPOT=18.75 ms
p99_TPOT=19.27 ms

This means the backend was not primarily decode-bound under rate pressure. TPOT stayed stable around 19 ms while TTFT expanded sharply.

Prompt Pressure Finding

Prompt length increased from 512 to 3072 tokens at request rate 1.

Observed behavior:

input=512:
  mean_TTFT=195.90 ms
  p99_TTFT=1453.68 ms
  mean_TPOT=18.19 ms

input=3072:
  mean_TTFT=1367.88 ms
  p99_TTFT=3935.80 ms
  mean_TPOT=24.50 ms

Longer prompts primarily increased first-token latency, which is consistent with increased prefill work. TPOT also rose mildly, suggesting longer active contexts can add runtime pressure beyond pure prefill.

Output Pressure Finding

Output length increased from 128 to 1024 tokens at request rate 1.

Observed behavior:

output=128:
  actual_request_throughput=0.95 req/s
  mean_TTFT=196.27 ms
  mean_TPOT=18.19 ms

output=1024:
  actual_request_throughput=0.24 req/s
  mean_TTFT=144073.92 ms
  mean_TPOT=17.98 ms

This was the strongest systems finding of Build 1.

Long outputs did not meaningfully worsen per-token decode speed. TPOT stayed near 18 ms. But long generations kept requests resident much longer, which reduced request-level capacity and caused new requests to wait. The symptom appeared as massive TTFT growth, not TPOT degradation.

Failure Modes Observed

Build 1 also produced real operational failure modes during bring-up and execution:

Failure Mode	Summary
Runtime/driver mismatch	Latest vLLM pulled a PyTorch/CUDA stack incompatible with the provider driver
Tokenizer/runtime mismatch	Qwen tokenizer path required aligned Transformers/Tokenizers versions
Benchmark CLI mismatch	Pinned vLLM benchmark CLI did not support the --backend flag
Context window overflow	Prompt + completion + template overhead exceeded max_model_len=4096
Request-rate saturation	Actual throughput plateaued while TTFT rose sharply
Long-output residency pressure	Long outputs reduced request-level capacity while TPOT stayed stable
Prompt-length pressure	Longer prompts increased TTFT and mildly increased TPOT

These are included in the Build 1 failure-mode table.

Operational Takeaway

The main operational rule from Build 1 is:

If actual request throughput plateaus while offered request rate increases, and TTFT rises sharply while TPOT remains stable, the backend is saturated before decode.

Do not diagnose this as per-token decode slowness.

First inspect:

offered request rate vs actual request throughput
TTFT vs TPOT
prompt length
output length
context-window limits
request residency
queueing/admission pressure

Only after this decomposition should the operator tune vLLM, change batching parameters, add replicas, or introduce routing.

Build 1 Conclusion

Build 1 successfully established a production-relevant single-backend triage baseline for Qwen2.5-7B-Instruct on RTX 4090.

The key evidence package is:

docs/builds/001-vllm-performance-triage/
  executive-summary.md
  diagram.md
  benchmark-table.md
  failure-mode-table.md
  operational-rule.md

results/raw/001-vllm-performance-triage/
results/processed/001-vllm-performance-triage/

