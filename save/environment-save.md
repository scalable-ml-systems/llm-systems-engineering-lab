# Environment Save : 

torch: 2.11.0+cu130
torch_cuda: 13.0
cuda_available: True
device: NVIDIA RTX PRO 6000 Blackwell Max-Q Workstation Edition
capability: (12, 0)
device_count: 1
vllm: 0.22.0
VLLM_USE_V2_MODEL_RUNNER: None

## Relevant VLLM FLAGS
=======================
vllm serve --help | grep -Ei "v2|runner|moe|chunk|prefix|batched|preempt|scheduler|cache"
  CacheConfig             Configuration for the KV cache.
  SchedulerConfig         Scheduler configuration.
          - [`cache_dir`][vllm.config.CompilationConfig.cache_dir]

“Modern vLLM Runtime Uses Python Config, Not CLI Flags”
Modern vLLM (v0.5.x → v1.x) intentionally exposes a minimal CLI.  
Most of the tuning knobs that used to be CLI flags — things like --max-model-len, --max-num-batched-tokens, --enable-prefix-caching, --disable-chunked-prefill, --scheduler, and even runner‑level options — have been removed from the command line.
Instead, vLLM now uses a Python‑first configuration model. All runtime behavior is controlled through structured config objects such as:
EngineConfig
ModelConfig
CacheConfig
SchedulerConfig
ParallelConfig
These objects define everything from KV‑cache size to MoE backend selection, chunked prefill, prefix caching, batching limits, and the v2 model runner.
The CLI (vllm serve) is now intentionally minimal — it only accepts high‑level server parameters (host, port, model path). All performance tuning, scheduling behavior, and GPU execution strategy must be set in Python when constructing the engine.
If a flag doesn’t appear in vllm serve --help, it’s not missing — it has been moved into the Python config layer.

Why this matters
✔️ You now know your vLLM version uses the new runtime architecture
This means:
No more --max-model-len
No more --device
No more --cpu-kv-cache-space
No more --max-num-batched-tokens
No more --max-num-seqs
No more --enforce-eager
No more --disable-chunked-prefill
No more --enable-prefix-caching
No more --scheduler CLI flags
All of these are now controlled by Python-side config objects:
ModelConfig
CacheConfig
SchedulerConfig
ParallelConfig
EngineConfig
