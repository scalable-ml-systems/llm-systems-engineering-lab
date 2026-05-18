#!/usr/bin/env bash
set -euo pipefail

# LLM Systems Engineering Lab - environment setup
# Purpose:
#   - Prepare an Ubuntu host for vLLM serving/benchmarking.
#   - Safe to use for AWS CPU harness validation and CloudRift RTX 4090 runs.
#   - Does NOT install GPU drivers; the GPU host should already expose nvidia-smi.
#
# Usage:
#   bash scripts/setup_env.sh
#
# Optional env vars:
#   VENV_DIR=.venv
#   INSTALL_VLLM=true|false
#   INSTALL_DEV_TOOLS=true|false

VENV_DIR="${VENV_DIR:-.venv}"
INSTALL_VLLM="${INSTALL_VLLM:-true}"
INSTALL_DEV_TOOLS="${INSTALL_DEV_TOOLS:-true}"
PYTHON_BIN="${PYTHON_BIN:-python3}"

log() { printf '\n[setup_env] %s\n' "$*"; }

if [[ "$(uname -s)" != "Linux" ]]; then
  echo "This setup script is intended for Linux/Ubuntu hosts." >&2
  exit 1
fi

log "Updating apt metadata and installing system packages"
sudo apt-get update
sudo apt-get install -y \
  git curl wget jq htop tmux nvtop \
  python3 python3-venv python3-pip \
  build-essential ca-certificates lsb-release

log "Creating Python virtual environment at ${VENV_DIR}"
${PYTHON_BIN} -m venv "${VENV_DIR}"
# shellcheck disable=SC1091
source "${VENV_DIR}/bin/activate"

log "Upgrading pip tooling"
python -m pip install --upgrade pip setuptools wheel

log "Installing benchmark/reporting dependencies"
pip install \
  pandas \
  pyyaml \
  requests \
  openai \
  rich \
  tabulate \
  prometheus-client

if [[ "${INSTALL_VLLM}" == "true" ]]; then
  log "Installing vLLM"
  pip install vllm
else
  log "Skipping vLLM install because INSTALL_VLLM=false"
fi

if [[ "${INSTALL_DEV_TOOLS}" == "true" ]]; then
  log "Installing optional developer tools"
  pip install ruff pytest
fi

log "Creating expected project directories"
mkdir -p \
  logs \
  configs/models \
  configs/workloads \
  results/raw \
  results/processed \
  docs/builds/001-vllm-performance-triage

log "Writing default model config"
cat > configs/models/qwen2.5-7b-instruct.yaml <<'YAML'
model: Qwen/Qwen2.5-7B-Instruct
served_model_name: Qwen/Qwen2.5-7B-Instruct
host: 0.0.0.0
port: 8000
dtype: auto
max_model_len: 8192
gpu_memory_utilization: 0.90
YAML

log "Environment summary"
python --version
pip --version
if command -v nvidia-smi >/dev/null 2>&1; then
  nvidia-smi || true
else
  echo "nvidia-smi not found. This is fine for AWS CPU harness validation, but not for CloudRift GPU evidence runs."
fi

log "Done. Activate with: source ${VENV_DIR}/bin/activate"
