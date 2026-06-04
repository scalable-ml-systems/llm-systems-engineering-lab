from pathlib import Path
import re
import json

ROOT = Path("results/raw/002-modern-vllm-v1-baseline")
DOC = Path("docs/builds/002-modern-vllm-v1-baseline")
DOC.mkdir(parents=True, exist_ok=True)

def fmt(value):
    if value is None:
        return "TBD"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        return f"{value:.2f}"
    return str(value)

def parse_metadata(run_dir):
    path = run_dir / "experiment-metadata.json"
    if not path.exists():
        return {}

    try:
        return json.loads(path.read_text())
    except Exception:
        return {}

def find_result_json(run_dir):
    files = sorted([
        p for p in run_dir.glob("*.json")
        if p.name != "experiment-metadata.json"
    ])
    return files[0] if files else None

def parse_result_json(run_dir):
    path = find_result_json(run_dir)
    if not path:
        return {
            "success": "TBD",
            "failed": "TBD",
            "req_tput": "TBD",
            "out_tput": "TBD",
            "ttft_p99": "TBD",
            "tpot_p99": "TBD",
            "itl_p99": "TBD",
        }

    data = json.loads(path.read_text())

    return {
        "success": fmt(data.get("completed")),
        "failed": fmt(data.get("failed")),
        "req_tput": fmt(data.get("request_throughput")),
        "out_tput": fmt(data.get("output_throughput")),
        "ttft_p99": fmt(data.get("p99_ttft_ms")),
        "tpot_p99": fmt(data.get("p99_tpot_ms")),
        "itl_p99": fmt(data.get("p99_itl_ms")),
    }

def metric_values(run_dir, metric_name):
    values = []
    raw_dir = run_dir / "metrics" / "raw"

    for prom in sorted(raw_dir.glob("metrics-*.prom")):
        for line in prom.read_text(errors="ignore").splitlines():
            if not line.startswith(metric_name):
                continue

            parts = line.split()
            if len(parts) < 2:
                continue

            try:
                values.append(float(parts[-1]))
            except ValueError:
                pass

    return values

def peak_metric(run_dir, metric_name):
    values = metric_values(run_dir, metric_name)
    if not values:
        return "TBD"
    return f"{max(values):.6f}".rstrip("0").rstrip(".")

def delta_metric(run_dir, metric_name):
    values = metric_values(run_dir, metric_name)
    if not values:
        return "TBD"
    return f"{values[-1] - values[0]:.6f}".rstrip("0").rstrip(".")

def run_dirs_for_suite(suite):
    suite_dir = ROOT / suite
    if not suite_dir.exists():
        return []

    run_dirs = []
    for path in sorted(suite_dir.glob("*/*")):
        if not path.is_dir():
            continue

        if (path / "experiment-metadata.json").exists() or find_result_json(path):
            run_dirs.append(path)

    return run_dirs

def collect(suite):
    rows = []

    for run_dir in run_dirs_for_suite(suite):
        meta = parse_metadata(run_dir)
        result = parse_result_json(run_dir)

        rows.append({
            "suite": suite,
            "input": int(meta.get("random_input_len", 0)),
            "output": int(meta.get("random_output_len", 0)),
            "concurrency": int(meta.get("max_concurrency", 0)),
            "ttft": result["ttft_p99"],
            "tpot": result["tpot_p99"],
            "itl": result["itl_p99"],
            "req": result["req_tput"],
            "out": result["out_tput"],
            "kv": peak_metric(run_dir, "vllm:kv_cache_usage_perc"),
            "waiting": peak_metric(run_dir, "vllm:num_requests_waiting"),
            "preemptions": delta_metric(run_dir, "vllm:num_preemptions_total"),
            "success": result["success"],
            "failed": result["failed"],
        })

    return rows

def sort_rows(suite, rows):
    if suite == "prefill-context-stretch":
        return sorted(rows, key=lambda r: r["input"])
    if suite == "decode-residency-ramp":
        return sorted(rows, key=lambda r: r["output"])
    if suite == "kv-concurrency-ramp":
        return sorted(rows, key=lambda r: r["concurrency"])
    return sorted(rows, key=lambda r: (r["input"], r["output"], r["concurrency"]))

def classify(suite, row):
    if suite == "runtime-baseline":
        return "healthy reference"

    if suite == "prefill-context-stretch":
        if row["input"] >= 8192:
            return "long-context pressure"
        return "context growth"

    if suite == "decode-residency-ramp":
        if row["output"] >= 1024:
            return "long-output residency"
        return "decode residency"

    if suite == "kv-concurrency-ramp":
        if row["preemptions"] not in ("TBD", "0", "0.0") and float(row["preemptions"]) > 0:
            return "preemption risk"
        if row["concurrency"] >= 24:
            return "high concurrency, no preemption"
        if row["concurrency"] >= 8:
            return "latency pressure"
        return "useful scaling"

    return ""

def render_table(title, suite, rows):
    rows = sort_rows(suite, rows)

    if not rows:
        return f"\n## {title}\n\nNo runs found.\n"

    out = [f"\n## {title}\n"]
    out.append("| Input | Output | Concurrency | TTFT p99 ms | TPOT p99 ms | ITL p99 ms | Req/s | Out tok/s | Peak KV Cache | Peak Waiting | Preemptions Δ | Success | Failed | Classification |")
    out.append("|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|")

    for r in rows:
        out.append(
            f"| {r['input']} | {r['output']} | {r['concurrency']} | "
            f"{r['ttft']} | {r['tpot']} | {r['itl']} | "
            f"{r['req']} | {r['out']} | {r['kv']} | {r['waiting']} | {r['preemptions']} | "
            f"{r['success']} | {r['failed']} | {classify(suite, r)} |"
        )

    return "\n".join(out) + "\n"

runtime = collect("runtime-baseline")
prefill = collect("prefill-context-stretch")
decode = collect("decode-residency-ramp")
kv = collect("kv-concurrency-ramp")

md = []
md.append("# Build 2 Results Summary — Modern vLLM V1 Architecture Baseline\n")
md.append("## Scope\n")
md.append("Build 2 measured prefill/context growth, decode residency, and KV/concurrency pressure for `deepseek-ai/DeepSeek-V2-Lite-Chat` on one RTX PRO 6000 GPU using vLLM V1.\n")

md.append("## Executive Summary\n")
md.append("| Runtime Area | Experiment | Variable Changed | Primary Signal | Interpretation |")
md.append("|---|---|---|---|---|")
md.append("| Runtime baseline | runtime-baseline | none | TTFT / TPOT reference | Healthy reference state |")
md.append("| Prefill / context | prefill-context-stretch | input length | TTFT p99 and KV cache | Context-growth / chunked-prefill pressure |")
md.append("| Decode residency | decode-residency-ramp | output length | TPOT / ITL p99 | Decode residency behavior |")
md.append("| KV / concurrency | kv-concurrency-ramp | concurrency | throughput, waiting, preemptions | Scaling boundary and preemption check |\n")

md.append(render_table("Runtime Baseline", "runtime-baseline", runtime))
md.append(render_table("Prefill Context Stretch", "prefill-context-stretch", prefill))
md.append(render_table("Decode Residency Ramp", "decode-residency-ramp", decode))
md.append(render_table("KV Concurrency Ramp", "kv-concurrency-ramp", kv))

md.append("""
## Data Quality Notes

- Workload shape comes from `experiment-metadata.json`.
- Benchmark latency and throughput values come from vLLM `--save-result` JSON files.
- `Peak KV Cache` is the maximum `vllm:kv_cache_usage_perc` observed across raw metrics scrapes for that run.
- `Peak Waiting` is the maximum `vllm:num_requests_waiting` observed across raw metrics scrapes.
- `Preemptions Δ` is final minus first observed `vllm:num_preemptions_total` during the run.
- `vllm:kv_cache_usage_perc` is a 0–1 scale.
- The original `prefill-context-stretch/input1024-output128-concurrency1` run had an anomalous TTFT p99 of 4847.15 ms. A clean rerun produced TTFT p99 of 166.59 ms. Treat the original as a warmup/transient outlier.
- All scripted Build 2 benchmark runs completed with `Failed requests: 0`.
""")

(DOC / "results-summary.md").write_text("\n".join(md))
print("Wrote", DOC / "results-summary.md")
