###
This is a project - kv cache

| Build | Focus | Status | Main Artifacts |
|---|---|---|---|
| Build 001 | vLLM performance triage | Complete | `docs/builds/001-vllm-performance-triage/` |
| Build 002 | Modern vLLM V1 MoE/MLA baseline | Complete | `docs/builds/002-modern-vllm-v1-baseline/` |

Build 002 found that DeepSeek-V2-Lite-Chat on vLLM V1 did not hit KV-cache or preemption pressure on the tested RTX PRO 6000 VM. Peak KV-cache usage stayed below 5%, preemptions stayed at zero, and the c8/c16 TTFT inversion disappeared when rerun with `request_rate=1`, indicating burst-admission behavior rather than stable GPU saturation.
