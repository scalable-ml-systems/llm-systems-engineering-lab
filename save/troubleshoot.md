1 . Backend/Kernel Issue : 
Error : /home/riftuser/.cache/flashinfer/0.6.11.post2/120f/cached_ops/fused_moe_120/moe_gemm_moe_gemm_kernels_fp8_uint4.cuda.o (EngineCore pid=7597) ninja: build stopped: subcommand failed. (EngineCore pid=7597)

The key line is:

cached_ops/fused_moe_120/moe_gemm_moe_gemm_kernels_fp8_uint4.cuda.o
ninja: build stopped: subcommand failed

Interpretation:

vLLM selected a FlashInfer fused MoE kernel path for SM120 / RTX PRO 6000.
FlashInfer tried to JIT-compile a fused MoE kernel.
The JIT compile failed before the server could start.

So the current failure is:

MoE backend auto-selection picked a FlashInfer path that is not stable on this RTX PRO 6000 setup.

Solution : 

rm -rf ~/.cache/flashinfer

So the current failure is:

MoE backend auto-selection picked a FlashInfer path that is not stable on this RTX PRO 6000 setup.

This matches the current ecosystem reality: vLLM exposes multiple MoE backends including auto, triton, deep_gemm, cutlass, and several FlashInfer variants; auto may choose a backend that is best in theory but brittle on newer SM120 / Blackwell paths. There are also current reports of FlashInfer/CUTLASS MoE kernel issues on RTX PRO 6000 / SM120-class systems, especially around JIT/autotuning and fused MoE paths.

Do this next: force Triton MoE backend

For Build 2, we do not need the fastest MoE backend. We need the server to load reliably so we can baseline behavior.

Patch:

python - <<'PY'
from pathlib import Path

p = Path("scripts/run_server_build_002.sh")
s = p.read_text()

s = s.replace('MOE_BACKEND="${MOE_BACKEND:-auto}"', 'MOE_BACKEND="${MOE_BACKEND:-triton}"')

p.write_text(s)
PY
