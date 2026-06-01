# Build 2 Setup Runbook — Modern vLLM V1 Architecture Baseline

## Purpose

This runbook sets up the GPU node for **Build 2 — Modern vLLM V1 Architecture Baseline**.

Build 2 maps the runtime behavior of a modern MLA/MoE model on vLLM V1.

The purpose is not to tune.

The purpose is to observe baseline runtime behavior:

* prefill / chunked-prefill behavior
* decode residency
* KV-cache residency
* waiting requests
* preemption / recompute risk
* useful scaling versus inefficient saturation

This runbook is intentionally step-by-step. Execute each section manually and understand what it proves before moving to the next step.

---

# 0. Target Runtime

## Hardware

```text
GPU: RTX PRO 6000
VRAM: 96 GB
System RAM: 56 GB
vCPU: 11
```

## Model

```text
deepseek-ai/DeepSeek-V2-Lite-Chat
```

DeepSeek-V2-Lite-Chat is used because it exposes modern inference architecture behavior: Multi-head Latent Attention and Mixture-of-Experts. The model card describes DeepSeek-V2-Lite as 16B total parameters, 2.4B active parameters, and deployable on a single 40GB GPU, so the RTX PRO 6000 96GB node gives enough headroom for controlled residency experiments.

## Runtime

```text
vLLM V1 / modern model runner
```

vLLM V1 matters because chunked prefill is part of the normal scheduler behavior whenever possible. vLLM prioritizes decode requests, then uses the remaining `max_num_batched_tokens` budget for prefills. If a pending prefill cannot fit, it is automatically chunked.

---

# 1. Enter the Repo

## Command

```bash
cd ~/llm-systems-engineering-lab
```

## Verify

```bash
pwd
git status
git branch --show-current
```

## What this proves

You are working inside the correct repo and branch before creating artifacts or results.

Expected branch:

```text
build-002-modern-vllm-v1-baseline
```

If you are not on that branch:

```bash
git checkout build-002-modern-vllm-v1-baseline
```

---

# 2. Create the Compact Build 2 Layout

## Command

```bash
mkdir -p docs/builds/002-modern-vllm-v1-baseline

mkdir -p results/raw/002-modern-vllm-v1-baseline/server-logs
mkdir -p results/raw/002-modern-vllm-v1-baseline/runtime-baseline
mkdir -p results/raw/002-modern-vllm-v1-baseline/prefill-context-stretch
mkdir -p results/raw/002-modern-vllm-v1-baseline/decode-residency-ramp
mkdir -p results/raw/002-modern-vllm-v1-baseline/kv-concurrency-ramp

mkdir -p results/processed/002-modern-vllm-v1-baseline
```

## What this proves

Build 2 has a clean artifact boundary.

Raw evidence goes under:

```text
results/raw/002-modern-vllm-v1-baseline/
```

Processed summaries go under:

```text
results/processed/002-modern-vllm-v1-baseline/
```

Docs go under:

```text
docs/builds/002-modern-vllm-v1-baseline/
```

Do not create extra docs or extra result folders.

---

# 3. Verify GPU Visibility

## Command

```bash
nvidia-smi
```

Save evidence:

```bash
nvidia-smi | tee results/raw/002-modern-vllm-v1-baseline/server-logs/nvidia-smi-initial.txt
```

## What this proves

This proves the NVIDIA driver sees the GPU.

You want to confirm:

```text
RTX PRO 6000 visible
~96 GB VRAM visible
driver installed
CUDA runtime supported by driver
no other process consuming most VRAM
```

## Why it matters

vLLM can only use the GPU if CUDA can see it.

This is the bottom of the stack.

If this fails, do not debug vLLM yet. The problem is below vLLM.

---

# 4. Check Host Capacity

## Command

```bash
free -h
df -h
nproc
```

Save evidence:

```bash
{
  echo "timestamp_utc=$(date -u +%Y-%m-%dT%H:%M:%SZ)"
  echo
  echo "### memory"
  free -h
  echo
  echo "### disk"
  df -h
  echo
  echo "### cpu"
  nproc
} | tee results/raw/002-modern-vllm-v1-baseline/server-logs/host-capacity.txt
```

## What this proves

This validates the non-GPU parts of the machine.

Expected:

```text
System RAM: ~56 GB
vCPU: ~11
Disk: enough room for model cache and benchmark outputs
```

## Why it matters

The model runs on GPU, but model download, tokenizer, Python runtime, server process, and logs still use host RAM and disk.

If the process gets killed during model load, the issue may be host RAM or disk, not VRAM.

---

# 5. Create Python Environment

## Command

```bash
python3 -m venv .venv-build-002
source .venv-build-002/bin/activate
```

Verify:

```bash
which python
python --version
```

## What this proves

This isolates Build 2 dependencies from older Build 1 packages.

Build 1 may have used an older vLLM runtime. Build 2 should be a clean modern-runtime baseline.

---

# 6. Install vLLM and Minimal Tools

## Command

```bash
python -m pip install --upgrade pip setuptools wheel
pip install --upgrade vllm
pip install --upgrade pandas requests pyyaml
```

## What this proves

This installs the runtime and the minimal tools needed for:

```text
vLLM server
vLLM benchmark runner
metrics scraping
later summary generation
```

Do not install Kubernetes tools, dashboards, Grafana, Prometheus, or extra profiling stacks here.

Build 2 is single-node runtime analysis.

---

# 7. Verify Python, CUDA, Torch, and vLLM

## Command

```bash
python - <<'PY'
import os
import torch

print("torch:", torch.__version__)
print("torch_cuda:", torch.version.cuda)
print("cuda_available:", torch.cuda.is_available())

if torch.cuda.is_available():
    print("device:", torch.cuda.get_device_name(0))
    print("capability:", torch.cuda.get_device_capability(0))
    print("device_count:", torch.cuda.device_count())

try:
    import vllm
    print("vllm:", vllm.__version__)
except Exception as e:
    print("vllm_import_error:", repr(e))
    raise

print("VLLM_USE_V2_MODEL_RUNNER:", os.environ.get("VLLM_USE_V2_MODEL_RUNNER"))
PY
```

Save evidence:

```bash
python - <<'PY' | tee results/raw/002-modern-vllm-v1-baseline/server-logs/python-vllm-runtime.txt
import os
import torch

print("torch:", torch.__version__)
print("torch_cuda:", torch.version.cuda)
print("cuda_available:", torch.cuda.is_available())

if torch.cuda.is_available():
    print("device:", torch.cuda.get_device_name(0))
    print("capability:", torch.cuda.get_device_capability(0))
    print("device_count:", torch.cuda.device_count())

try:
    import vllm
    print("vllm:", vllm.__version__)
except Exception as e:
    print("vllm_import_error:", repr(e))
    raise

print("VLLM_USE_V2_MODEL_RUNNER:", os.environ.get("VLLM_USE_V2_MODEL_RUNNER"))
PY
```

## What this proves

This confirms that Python can import torch and vLLM, and that torch can see CUDA.

If `torch.cuda.is_available()` is false, do not continue to vLLM serving.

---

# 8. Confirm Relevant vLLM Flags

## Command

```bash
vllm serve --help | grep -Ei "v2|runner|moe|chunk|prefix|batched|preempt|scheduler|cache"
```

Save evidence:

```bash
vllm serve --help \
  | grep -Ei "v2|runner|moe|chunk|prefix|batched|preempt|scheduler|cache" \
  | tee results/raw/002-modern-vllm-v1-baseline/server-logs/vllm-serve-flags.txt
```

## What this proves

This confirms which runtime flags exist in the installed vLLM version.

You are looking for flags or references related to:

```text
model runner
moe backend
max num batched tokens
max model len
scheduler
prefix caching
chunked prefill
preemption
cache
```

## Why it matters

Do not assume a flag exists.

Build 2 should be tied to the installed vLLM runtime, not memory or old blog posts.

---

# 9. Set Build 2 Runtime Environment

## Command

```bash
export VLLM_USE_V2_MODEL_RUNNER=1
```

Verify:

```bash
echo $VLLM_USE_V2_MODEL_RUNNER
```

## What this means

This requests the modern vLLM model-runner path.

Treat this as a runtime setting to verify through logs, not as blind proof.

The actual server startup logs are the source of truth.

---

# 10. Start the vLLM Server

Open **Terminal 1**.

Activate environment:

```bash
cd ~/llm-systems-engineering-lab
source .venv-build-002/bin/activate
export VLLM_USE_V2_MODEL_RUNNER=1
```

Start server:

```bash
bash scripts/run_server_build_002.sh
```

## Expected behavior

The server will:

```text
download/load DeepSeek-V2-Lite-Chat
initialize vLLM
allocate GPU memory
initialize KV/cache blocks
start OpenAI-compatible endpoint
start /metrics endpoint
```

## Watch startup carefully

In the server log, look for:

```text
model loaded
attention backend
MoE backend
chunked prefill / scheduler config
max_model_len
max_num_batched_tokens
max_num_seqs
GPU memory utilization
OpenAI server ready
```

## Why this matters

This is where the runtime becomes real.

Until the server starts successfully, Build 2 has not begun.

The server startup log is part of the evidence.

---

# 11. Verify Server Endpoints

Open **Terminal 2**.

Activate environment:

```bash
cd ~/llm-systems-engineering-lab
source .venv-build-002/bin/activate
```

Verify model endpoint:

```bash
curl http://localhost:8000/v1/models
```

Verify metrics endpoint:

```bash
curl http://localhost:8000/metrics | head
```

Save discovered metric names:

```bash
curl -s http://localhost:8000/metrics \
  | awk -F '[{ ]' '/^vllm:/ {print $1}' \
  | sort -u \
  | tee results/raw/002-modern-vllm-v1-baseline/server-logs/vllm-metric-names.txt
```

Filter relevant metrics:

```bash
curl -s http://localhost:8000/metrics \
  | grep -Ei "cache|kv|waiting|running|preempt|prefix|prompt|decode|token|time_to_first|time_per_output|success|finish" \
  | tee results/raw/002-modern-vllm-v1-baseline/server-logs/vllm-relevant-metrics-initial.prom
```

## What this proves

This proves the server is reachable and exporting observability.

Build 2 depends on both:

```text
benchmark output
/metrics endpoint
```

Do not run benchmarks until both endpoints work.

---

# 12. Understand the V1 Telemetry Before Benchmarking

The key metrics are:

| Runtime Area        | Metric                               |
| ------------------- | ------------------------------------ |
| First-token latency | `vllm:time_to_first_token_seconds`   |
| Decode smoothness   | `vllm:time_per_output_token_seconds` |
| Running requests    | `vllm:num_requests_running`          |
| Waiting requests    | `vllm:num_requests_waiting`          |
| Preemptions         | `vllm:num_preemptions_total`         |
| KV/cache residency  | `vllm:kv_cache_usage_perc`           |
| Success counter     | `vllm:request_success_total`         |
| Output tokens       | `vllm:generation_tokens_total`       |

vLLM documents `vllm:kv_cache_usage_perc` as KV-cache usage, where 1 means 100 percent usage. It also exposes request-state metrics such as running and waiting requests in its V1-oriented metrics documentation.

## V1 interpretation guardrail

Do not use old v0 swap language.

Avoid:

```text
CPU swap
swapped sequences
cpu_cache_usage_perc
num_requests_swapped
```

Use:

```text
KV-cache residency
preemption
recompute risk
waiting-request growth
inefficient saturation
```

---

# 13. Run Experiment 0 — Runtime Baseline

## Command

```bash
bash scripts/run_benchmark_build_002.sh runtime-baseline
```

## Workload

```text
input_len=1024
output_len=128
concurrency=1
```

## What this measures

This establishes the reference state:

```text
TTFT baseline
TPOT baseline
throughput baseline
KV cache baseline
waiting requests baseline
preemption baseline
```

## Expected result

```text
low waiting
zero preemptions
stable TTFT
stable TPOT
successful requests
```

## Why it matters

Every later result is compared against this.

Do not move to context stretch if runtime baseline fails.

---

# 14. Run Experiment 1 — Prefill Context Stretch

## Command

```bash
bash scripts/run_benchmark_build_002.sh prefill-context-stretch
```

## Workload

```text
input_len=1024, 2048, 4096, 8192, 12288, 15360
output_len=128
concurrency=1
```

## What this measures

This isolates context/prompt growth.

Primary signals:

```text
TTFT p95
KV cache usage
waiting requests
preemptions
```

## How to interpret

If:

```text
TTFT rises
TPOT remains mostly stable
preemptions remain zero
```

then the backend is showing context-growth / chunked-prefill pressure.

If:

```text
TTFT rises
KV cache usage rises
preemptions appear
```

then context growth is crossing into residency pressure.

## Why it matters

This gives the prefill/context curve that Build 3 needs before touching `max_num_batched_tokens`.

---

# 15. Run Experiment 2 — Decode Residency Ramp

## Command

```bash
bash scripts/run_benchmark_build_002.sh decode-residency-ramp
```

## Workload

```text
input_len=1024
output_len=128, 256, 512, 1024, 1536
concurrency=4
```

## What this measures

This isolates output generation pressure.

Primary signals:

```text
TPOT / ITL p95
output token throughput
active request residency
KV cache usage
waiting requests
```

## How to interpret

If:

```text
TPOT rises as output length grows
TTFT rises only moderately
preemptions remain low
```

then the backend is showing decode-residency pressure.

If:

```text
TPOT rises
waiting rises
KV cache usage rises sharply
```

then decode residency is also pushing memory residency.

## Why it matters

This tells Build 3 whether tuning should protect stream smoothness, not just first-token latency.

---

# 16. Run Experiment 3 — KV Concurrency Ramp

## Command

```bash
bash scripts/run_benchmark_build_002.sh kv-concurrency-ramp
```

## Workload

```text
input_len=2048
output_len=512
concurrency=1, 2, 4, 8, 16, 24, 32
```

## What this measures

This finds the useful scaling boundary and preemption inflection.

Primary signals:

```text
throughput
KV cache usage
running requests
waiting requests
preemptions
success rate
TTFT / TPOT instability
```

## Stop conditions

Stop if:

```text
preemptions spike
success rate drops sharply
server becomes unstable
OOM risk appears
waiting requests explode
throughput has already flattened clearly
```

## How to interpret

If:

```text
throughput rises
waiting stays low
preemptions stay zero
```

then concurrency is scaling usefully.

If:

```text
waiting rises
throughput flattens
preemptions remain zero
```

then the system has reached scheduler/admission pressure.

If:

```text
waiting rises
throughput flattens
preemptions become non-zero
```

then the system has entered KV residency / recompute-risk territory.

## Why it matters

This identifies the first hard boundary Build 3 should tune around.

---

# 17. Inspect Raw Outputs

After each experiment, inspect:

```bash
find results/raw/002-modern-vllm-v1-baseline -maxdepth 4 -type f | sort
```

For a specific run:

```bash
ls -lah results/raw/002-modern-vllm-v1-baseline/<experiment>/<run-name>/<timestamp>/
```

Look for:

```text
benchmark.log
experiment-metadata.json
environment.txt
metrics/
exit-code.txt
```

## What this proves

Every benchmark run should produce:

```text
benchmark evidence
environment evidence
metric evidence
metadata evidence
```

If one is missing, fix the scripts before continuing.

---

# 18. Commit Setup Evidence

After setup and first successful runtime baseline:

```bash
git add docs/builds/002-modern-vllm-v1-baseline/setup.md
git add results/raw/002-modern-vllm-v1-baseline/server-logs
git add scripts/run_server_build_002.sh
git add scripts/run_benchmark_build_002.sh
git add scripts/scrape_vllm_metrics.sh

git commit -m "Add Build 2 GPU setup runbook and runtime evidence"
```

Do not commit huge model cache files.

Do not commit virtual environment directories.

---

# 19. Build 2 Execution Order

Final order:

```text
1. Verify repo and branch
2. Create compact directories
3. Verify GPU with nvidia-smi
4. Verify host memory/disk
5. Create Python virtual environment
6. Install vLLM and minimal tools
7. Verify torch/vLLM/CUDA
8. Confirm vLLM runtime flags
9. Export VLLM_USE_V2_MODEL_RUNNER=1
10. Start server
11. Verify /v1/models and /metrics
12. Run runtime-baseline
13. Run prefill-context-stretch
14. Run decode-residency-ramp
15. Run kv-concurrency-ramp
16. Inspect raw outputs
17. Write results-summary.md
18. Write findings.md
```

---

# 20. Build 2 Discipline

```text
One GPU.
One model.
One vLLM baseline config.
Four experiments.
No tuning.
No Kubernetes.
No model comparison.
No Nsight unless metrics are confusing.
No giant matrix.
```

Build 2 ends when you can answer:

```text
What is the prefill/context curve?
What is the decode-residency curve?
What is the KV/concurrency curve?
Where does waiting begin?
Where does throughput flatten?
Do preemptions appear?
Which knob should Build 3 tune first?
```

