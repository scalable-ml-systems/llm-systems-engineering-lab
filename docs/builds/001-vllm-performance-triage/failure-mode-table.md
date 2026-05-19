# Failure Mode Table — Build 1: vLLM Performance Triage

| Failure Mode | Trigger | Symptom | Evidence Signal | Mitigation | Operational Rule |
|---|---|---|---|---|---|
| Runtime/driver mismatch | Latest vLLM install pulled incompatible CUDA/PyTorch stack | Engine failed during GPU initialization | `NVIDIA driver too old` | Pin vLLM/PyTorch/CUDA-compatible versions | Pin the full runtime stack before benchmarking |
| Tokenizer/runtime mismatch | Qwen tokenizer path incompatible with installed package versions | Tokenizer attribute error | `Qwen2Tokenizer has no attribute all_special_tokens_extended` | Pin Transformers/Tokenizers/HF Hub versions | Pin vLLM + torch + transformers + tokenizers together |
| Benchmark CLI mismatch | Script used unsupported benchmark flag | `unrecognized arguments: --backend openai-chat` | Local `vllm bench serve --help` showed no backend flag | Remove invalid flag; align script to pinned CLI | Benchmark scripts must match installed runtime version |
| Context window overflow | Prompt + completion + template overhead exceeded `max_model_len` | Request validation failure | Requested 4422 tokens, max context 4096 | Cap prompt sweep at 3072 or increase server max context | Always reserve context headroom |
| Request-rate saturation | Offered request rate exceeded sustainable capacity | TTFT rose sharply while TPOT stayed stable | Actual throughput plateaued around ~1.7 req/s | Lower offered load, tune server config, or add replicas | If throughput plateaus and TTFT rises, suspect queue/prefill saturation |
| Prompt-length pressure | Input length increased | TTFT rose with longer prompts | Mean TTFT rose from ~196ms to ~1368ms | Isolate/tune long-context workloads | Longer prompts primarily stress prefill and TTFT |
| Long-output residency pressure | Output length increased | Actual req/s collapsed and TTFT exploded while TPOT stayed stable | Output 1024 dropped to ~0.24 req/s with ~18ms TPOT | Cap output length or add capacity | Long outputs can cause queueing without TPOT degradation |
