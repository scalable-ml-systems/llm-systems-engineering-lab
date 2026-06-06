# Build 2 Findings — Modern vLLM V1 Architecture Baseline

## Executive Summary

Build 2 successfully established a compact runtime baseline for `deepseek-ai/DeepSeek-V2-Lite-Chat` on vLLM V1 using a single RTX PRO 6000 GPU.

The build measured three runtime curves:

1. Prefill/context growth
2. Decode residency
3. KV-cache/concurrency pressure

The purpose was not to tune. The purpose was to identify the runtime inflection points that Build 3 should tune against.

---

## Runtime Baseline

The runtime baseline validates that the model, server, benchmark client, and metrics endpoint were working.

Evidence captured:

- vLLM server logs
- runtime environment
- `/v1/models`
- `/metrics`
- benchmark logs
- per-run metadata
- raw metrics scrapes

The V1 metrics endpoint exposed the required signals:

- `vllm:time_to_first_token_seconds`
- `vllm:request_time_per_output_token_seconds`
- `vllm:inter_token_latency_seconds`
- `vllm:kv_cache_usage_perc`
- `vllm:num_requests_running`
- `vllm:num_requests_waiting`
- `vllm:num_preemptions_total`
- `vllm:request_success_total`
- `vllm:generation_tokens_total`

This confirms Build 2 is using V1-compatible telemetry rather than older v0 swap-based metrics.

---

## Prefill / Context Stretch Findings

The prefill-context-stretch experiment increased prompt length while keeping output length and concurrency fixed.

Workload:

```text
input_len = 1024, 2048, 4096, 8192, 12288, 15360
output_len = 128
concurrency = 1

## Data Quality Note

The first 1024-token prefill-context-stretch run showed an anomalous TTFT p99 of 4847.15 ms. A clean rerun of the same workload produced TTFT p99 of 166.59 ms with 25/25 successful requests.

Therefore, the 4847.15 ms value is treated as a warmup/transient outlier and excluded from the prefill-context trend.

The corrected baseline confirms that context-growth pressure is visible as prompt length increases, while TPOT remains comparatively stable.

## Data Quality Note

The first 1024-token prefill-context-stretch run showed an anomalous TTFT p99 of 4847.15 ms. A clean rerun of the same workload produced TTFT p99 of 166.59 ms with 25/25 successful requests.

Therefore, the 4847.15 ms value is treated as a warmup/transient outlier and excluded from the prefill-context trend.

The corrected baseline confirms that context-growth pressure is visible as prompt length increases, while TPOT remains comparatively stable.
