# Build 2 Setup — RTX PRO 6000 vLLM Runtime-State Diagnosis

## Purpose

This document describes how to set up the GPU node and execute Build 2:

**Build 2 — Prefill, Decode, and KV Behavior**

Build 2 explains why the vLLM backend behaves the way it does under workload pressure.

The goal is not maximum throughput tuning.

The goal is to classify backend runtime state:

* Prefill-bound
* Decode-bound
* KV-bound
* Scheduler-bound / pathological pressure

Build 1 measured where serving performance degraded.

Build 2 explains which runtime mechanism caused the degradation.

---

## Hardware

GPU node:

```text
Instance: rtxpro6000mq-11-56-850-1lg.1
GPU: RTX PRO 6000
VRAM: 96 GB
System RAM: 56 GB
vCPU: 11
```

This machine is treated as a **single-GPU inference lab**.

---
## Setup environment
sudo apt-get update
sudo apt-get install -y git curl jq htop python3-venv python3-pip

## Repository Location

Clone or enter the repo:

```bash
cd ~/llm-systems-engineering-lab
```

Check current branch:

```bash
git status
git branch
```

Create the Build 2 branch if it does not already exist:

```bash
git checkout -b build-002-prefill-decode-kv-behavior
```

If the branch already exists:

```bash
git checkout build-002-prefill-decode-kv-behavior
```

---

## setup the enviornment : 

run scripts/setup_env.sh 

This will install all the dependencies on the GPU.

## Directory Layout

Create the Build 2 directories:

```bash
mkdir -p docs/builds/002-prefill-decode-kv-behavior
mkdir -p results/raw/002-prefill-decode-kv-behavior
mkdir -p results/processed/002-prefill-decode-kv-behavior
mkdir -p results/profiles/build-002/nsight-systems
mkdir -p scripts
```

Expected layout:

```text
docs/builds/002-prefill-decode-kv-behavior/
  setup.md
  README-build-2.md
  experiment-plan.md
  state-classification-rules.md
  state-classification-table.md
  production-symptom-mapping.md
  prefill-pressure-report.md
  decode-pressure-report.md
  kv-pressure-report.md
  pathological-scenario.md

results/raw/002-prefill-decode-kv-behavior/
  baseline/
  prefill-pressure/
  decode-pressure/
  kv-pressure/
  pathological/

results/profiles/build-002/nsight-systems/
  nsys-baseline/
  nsys-prefill/
  nsys-decode/
  nsys-pathological/
```

---

## System Verification

Check the GPU:

```bash
nvidia-smi
```

Check system memory and disk:

```bash
free -h
df -h
```

Check Python:

```bash
python --version
which python
```

Check CUDA visibility from PyTorch:

```bash
python - <<'PY'
import torch
print("torch:", torch.__version__)
print("cuda available:", torch.cuda.is_available())
if torch.cuda.is_available():
    print("device:", torch.cuda.get_device_name(0))
    print("capability:", torch.cuda.get_device_capability(0))
PY
```

Check vLLM:

```bash
python - <<'PY'
import vllm
print("vllm:", vllm.__version__)
PY
```

If vLLM is not installed, install it in a virtual environment.

---

## Python Environment

Create and activate a virtual environment:

```bash
python -m venv .venv
source .venv/bin/activate
```

Upgrade packaging tools:

```bash
pip install --upgrade pip setuptools wheel
```

Install vLLM:

```bash
pip install vllm
```

Install supporting tools:

```bash
pip install pandas matplotlib pyyaml requests
```

Validate installation:

```bash
python - <<'PY'
import vllm, torch
print("vllm:", vllm.__version__)
print("torch:", torch.__version__)
print("cuda available:", torch.cuda.is_available())
PY
```

---

## Hugging Face Authentication

If the model requires authentication, log in:

```bash
huggingface-cli login
```

For Qwen2.5-7B-Instruct, use:

```text
Qwen/Qwen2.5-7B-Instruct
```

---

## Start vLLM Server

Use one vLLM backend only.

Recommended Build 2 server config:

```bash
vllm serve Qwen/Qwen2.5-7B-Instruct \
  --host 0.0.0.0 \
  --port 8000 \
  --served-model-name Qwen/Qwen2.5-7B-Instruct \
  --dtype auto \
  --max-model-len 8192 \
  --gpu-memory-utilization 0.85 \
  --max-num-seqs 32 \
  --max-num-batched-tokens 8192
```

### Why `max_model_len=8192`

The pathological Build 2 workload uses:

```text
input_len  = 6144
output_len = 1536
total      = 7680 tokens
```

The serving window is:

```text
max_model_len = input_len + output_len + safety margin
max_model_len = 6144 + 1536 + 512
max_model_len = 8192
```

The extra 512 tokens provide room for tokenizer and formatting overhead.

---

## Verify Server

In a second terminal:

```bash
curl http://localhost:8000/v1/models
```

Check metrics endpoint:

```bash
curl http://localhost:8000/metrics | head
```

If both commands work, the server is ready.

---

## Build 2 Benchmark Script

Create a Build 2-specific benchmark script:

```bash
nano scripts/run_benchmark_build_002.sh
```
---

## Execution Order

Do not run all experiments immediately.

Run one phase at a time.

### 1. Baseline

```bash
bash scripts/run_benchmark_build_002.sh baseline
```

Purpose:

```text
Establish comparison values for TTFT, TPOT, throughput, KV usage, waiting requests, and success rate.
```

Expected result:

```text
Healthy baseline.
Short prompt.
Short output.
Concurrency 1.
```

---

### 2. Prefill Pressure

```bash
bash scripts/run_benchmark_build_002.sh prefill-pressure
```

Workload:

```text
input_len=6144
output_len=128
concurrency=1,2,4,8
```

Expected metric signature:

```text
TTFT rises sharply.
TPOT stays near baseline.
KV usage may rise but should not dominate.
Classification: prefill-bound.
```

---

### 3. Decode Pressure

```bash
bash scripts/run_benchmark_build_002.sh decode-pressure
```

Workload:

```text
input_len=512
output_len=1024
concurrency=1,2,4,8
```

Expected metric signature:

```text
TPOT / ITL rises.
Streaming slows.
TTFT may rise moderately.
Classification: decode-bound.
```

---

### 4. KV Pressure

```bash
bash scripts/run_benchmark_build_002.sh kv-pressure
```

Workload:

```text
input_len=4096
output_len=1024
concurrency=4,8,16
```

Expected metric signature:

```text
KV usage rises.
num_requests_waiting rises.
Throughput flattens.
TTFT and TPOT may become unstable.
Classification: KV-bound.
```

---

### 5. Pathological Scenario

```bash
bash scripts/run_benchmark_build_002.sh pathological
```

Workload:

```text
input_len=6144
output_len=1536
concurrency=16
```

Expected metric signature:

```text
TTFT cliff.
TPOT instability.
KV pressure.
Waiting requests.
Possible failures or preemption.
Classification: combined failure.
```

---

## Optional Short Smoke Test

Before running 100 prompts, run a short test:

```bash
NUM_PROMPTS=8 bash scripts/run_benchmark_build_002.sh baseline
```

Then:

```bash
NUM_PROMPTS=8 bash scripts/run_benchmark_build_002.sh prefill-pressure
```

If both pass, run the full experiments.

---

## Monitor During Runs

In another terminal:

```bash
watch -n 2 nvidia-smi
```

Check system memory:

```bash
watch -n 2 free -h
```

Optional metrics scrape:

```bash
curl -s http://localhost:8000/metrics | grep -E "kv|waiting|running|preempt" | head -50
```

---

# Nsight Systems Visual Confirmation

Build 2 can optionally include a small Nsight Systems capture set.

The goal is visual confirmation, not exhaustive profiling.

Captured profiles:

| Profile           | Workload                | Purpose                            |
| ----------------- | ----------------------- | ---------------------------------- |
| nsys-baseline     | input512-output128-c1   | Reference timeline                 |
| nsys-prefill      | input6144-output128-c2  | Long-prompt prefill-heavy behavior |
| nsys-decode       | input512-output1024-c2  | Long-output decode-heavy behavior  |
| nsys-pathological | input6144-output1536-c8 | Combined pressure behavior         |

Nsight evidence is supporting visual evidence.

Runtime-state classification still comes from:

```text
TTFT
TPOT / ITL
KV usage
num_requests_waiting
throughput
preemption
success rate
```

---

## Nsight Server Script

Create:

```bash
nano scripts/run_server_nsys_build_002.sh
```
---

## Nsight Probe Script

Create:

```bash
nano scripts/run_nsys_probe_build_002.sh
```
---

## Run Nsight Captures

Run each capture one at a time.

### Baseline

Terminal 1:

```bash
bash scripts/run_server_nsys_build_002.sh nsys-baseline
```

Terminal 2:

```bash
bash scripts/run_nsys_probe_build_002.sh baseline
```

Stop server in Terminal 1:

```text
Ctrl-C
```

### Prefill

Terminal 1:

```bash
bash scripts/run_server_nsys_build_002.sh nsys-prefill
```

Terminal 2:

```bash
bash scripts/run_nsys_probe_build_002.sh prefill
```

Stop server.

### Decode

Terminal 1:

```bash
bash scripts/run_server_nsys_build_002.sh nsys-decode
```

Terminal 2:

```bash
bash scripts/run_nsys_probe_build_002.sh decode
```

Stop server.

### Pathological

Terminal 1:

```bash
bash scripts/run_server_nsys_build_002.sh nsys-pathological
```

Terminal 2:

```bash
bash scripts/run_nsys_probe_build_002.sh pathological
```

Stop server.

---

## Expected Nsight Artifacts

Expected files:

```text
results/profiles/build-002/nsight-systems/nsys-baseline/nsys-baseline.nsys-rep
results/profiles/build-002/nsight-systems/nsys-prefill/nsys-prefill.nsys-rep
results/profiles/build-002/nsight-systems/nsys-decode/nsys-decode.nsys-rep
results/profiles/build-002/nsight-systems/nsys-pathological/nsys-pathological.nsys-rep
```

Download these `.nsys-rep` files and open them locally in Nsight Systems GUI.

Take screenshots and save them under:

```text
docs/builds/002-prefill-decode-kv-behavior/images/nsys-baseline-timeline.png
docs/builds/002-prefill-decode-kv-behavior/images/nsys-prefill-timeline.png
docs/builds/002-prefill-decode-kv-behavior/images/nsys-decode-timeline.png
docs/builds/002-prefill-decode-kv-behavior/images/nsys-pathological-timeline.png
```

---

# Result Interpretation

Build 2 results should not merely say:

```text
TTFT increased.
TPOT increased.
Throughput decreased.
```

They should say:

```text
The backend entered a prefill-bound state because TTFT p95 increased sharply while TPOT remained near baseline and KV usage stayed below the collapse threshold.
```

Or:

```text
The backend entered a KV-bound state because KV usage rose, waiting requests increased, and throughput flattened as concurrency increased.
```

Every report should answer:

```text
Which workload pressure was applied?
Which metric moved first?
Which backend state best explains the result?
Which alternative state was rejected?
What production symptom does this map to?
```

---

# Commit Work

After creating scripts and setup doc:

```bash
git add scripts/run_benchmark_build_002.sh
git add scripts/run_server_nsys_build_002.sh
git add scripts/run_nsys_probe_build_002.sh
git add docs/builds/002-prefill-decode-kv-behavior/setup.md
git commit -m "Add Build 2 RTX PRO 6000 setup and benchmark scripts"
```

After benchmark results:

```bash
git add results/raw/002-prefill-decode-kv-behavior
git commit -m "Add Build 2 raw benchmark results"
```

After Nsight screenshots:

```bash
git add results/profiles/build-002/nsight-systems
git add docs/builds/002-prefill-decode-kv-behavior/images
git commit -m "Add Build 2 Nsight Systems visual evidence"
```

---

# Final Build 2 Execution Checklist

```text
[ ] GPU visible with nvidia-smi
[ ] Python environment active
[ ] vLLM installed
[ ] Qwen2.5-7B-Instruct available
[ ] vLLM server starts with max_model_len=8192
[ ] /v1/models responds
[ ] /metrics responds
[ ] baseline benchmark completed
[ ] prefill-pressure benchmark completed
[ ] decode-pressure benchmark completed
[ ] kv-pressure benchmark completed
[ ] pathological benchmark completed
[ ] raw results saved
[ ] environment captured per run
[ ] Nsight baseline profile captured
[ ] Nsight prefill profile captured
[ ] Nsight decode profile captured
[ ] Nsight pathological profile captured
[ ] timeline screenshots saved
[ ] state classification table written
[ ] production symptom mapping written
[ ] final Build 2 README updated
```
