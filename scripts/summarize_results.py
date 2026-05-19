#!/usr/bin/env python3
"""Summarize Build 1 raw vLLM benchmark results.

Rules:
- results/raw/ stays immutable.
- results/processed/ contains normalized CSV/Markdown.
- docs/builds/ contains interpretation.
"""

from __future__ import annotations

import argparse
import csv
import json
from pathlib import Path
from typing import Any


DEFAULT_RAW = "results/raw/001-vllm-performance-triage"
DEFAULT_OUT = "results/processed/001-vllm-performance-triage"


def load_json(path: Path) -> dict[str, Any] | None:
    try:
        data = json.loads(path.read_text())
        return data if isinstance(data, dict) else None
    except Exception:
        return None


def find_result_jsons(raw_root: Path) -> list[Path]:
    result_files: list[Path] = []

    for path in raw_root.rglob("*.json"):
        if path.name == "experiment-metadata.json":
            continue

        data = load_json(path)
        if not data:
            continue

        # vLLM result JSONs usually contain one or more of these.
        if any(
            key in data
            for key in [
                "successful_requests",
                "request_throughput",
                "mean_ttft_ms",
                "median_ttft_ms",
                "p99_ttft_ms",
                "mean_tpot_ms",
                "p99_tpot_ms",
            ]
        ):
            result_files.append(path)

    return sorted(result_files)


def metadata_for(result_file: Path) -> dict[str, Any]:
    meta_path = result_file.parent / "experiment-metadata.json"
    if meta_path.exists():
        return load_json(meta_path) or {}

    # Fallback for old layout.
    return {}


def val(data: dict[str, Any], *keys: str) -> Any:
    for key in keys:
        if key in data:
            return data[key]
    return ""


def fmt(value: Any) -> str:
    if value is None or value == "":
        return ""
    try:
        return f"{float(value):.2f}"
    except Exception:
        return str(value)


def infer_suite_from_path(raw_root: Path, result_file: Path, meta: dict[str, Any]) -> str:
    if meta.get("suite"):
        return str(meta["suite"])

    rel = result_file.relative_to(raw_root)
    return rel.parts[0] if len(rel.parts) >= 1 else ""


def infer_experiment_from_path(raw_root: Path, result_file: Path, meta: dict[str, Any]) -> str:
    if meta.get("experiment"):
        return str(meta["experiment"])

    rel = result_file.relative_to(raw_root)
    if len(rel.parts) >= 2:
        return rel.parts[1]
    return result_file.parent.name


def build_rows(raw_root: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []

    for result_file in find_result_jsons(raw_root):
        data = load_json(result_file) or {}
        meta = metadata_for(result_file)

        suite = infer_suite_from_path(raw_root, result_file, meta)
        experiment = infer_experiment_from_path(raw_root, result_file, meta)

        offered_rate = meta.get("request_rate", "")
        actual_rps = val(data, "request_throughput")

        row = {
            "suite": suite,
            "experiment": experiment,
            "run_id": str(meta.get("run_id", result_file.parent.name)),
            "input_tokens": str(meta.get("random_input_len", "")),
            "output_tokens": str(meta.get("random_output_len", "")),
            "offered_request_rate": fmt(offered_rate),
            "actual_request_throughput": fmt(actual_rps),
            "successful_requests": fmt(val(data, "successful_requests")),
            "benchmark_duration_s": fmt(val(data, "benchmark_duration_s", "duration")),
            "output_token_throughput": fmt(val(data, "output_throughput", "output_token_throughput")),
            "total_token_throughput": fmt(val(data, "total_token_throughput")),
            "mean_ttft_ms": fmt(val(data, "mean_ttft_ms")),
            "median_ttft_ms": fmt(val(data, "median_ttft_ms")),
            "p99_ttft_ms": fmt(val(data, "p99_ttft_ms")),
            "mean_tpot_ms": fmt(val(data, "mean_tpot_ms")),
            "median_tpot_ms": fmt(val(data, "median_tpot_ms")),
            "p99_tpot_ms": fmt(val(data, "p99_tpot_ms")),
            "mean_itl_ms": fmt(val(data, "mean_itl_ms")),
            "median_itl_ms": fmt(val(data, "median_itl_ms")),
            "p99_itl_ms": fmt(val(data, "p99_itl_ms")),
            "result_file": str(result_file),
        }

        rows.append(row)

    def sort_key(row: dict[str, str]):
        def as_float(x: str) -> float:
            try:
                return float(x)
            except Exception:
                return 0.0

        return (
            row["suite"],
            as_float(row["input_tokens"]),
            as_float(row["output_tokens"]),
            as_float(row["offered_request_rate"]),
            row["experiment"],
            row["run_id"],
        )

    return sorted(rows, key=sort_key)


def write_csv(rows: list[dict[str, str]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    fields = [
        "suite",
        "experiment",
        "run_id",
        "input_tokens",
        "output_tokens",
        "offered_request_rate",
        "actual_request_throughput",
        "successful_requests",
        "benchmark_duration_s",
        "output_token_throughput",
        "total_token_throughput",
        "mean_ttft_ms",
        "median_ttft_ms",
        "p99_ttft_ms",
        "mean_tpot_ms",
        "median_tpot_ms",
        "p99_tpot_ms",
        "mean_itl_ms",
        "median_itl_ms",
        "p99_itl_ms",
        "result_file",
    ]

    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=fields)
        writer.writeheader()
        writer.writerows(rows)


def write_markdown(rows: list[dict[str, str]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)

    fields = [
        "suite",
        "experiment",
        "input_tokens",
        "output_tokens",
        "offered_request_rate",
        "actual_request_throughput",
        "mean_ttft_ms",
        "p99_ttft_ms",
        "mean_tpot_ms",
        "p99_tpot_ms",
        "successful_requests",
    ]

    headers = [
        "Suite",
        "Experiment",
        "Input",
        "Output",
        "Offered req/s",
        "Actual req/s",
        "Mean TTFT ms",
        "P99 TTFT ms",
        "Mean TPOT ms",
        "P99 TPOT ms",
        "Success",
    ]

    with path.open("w") as f:
        f.write("# Benchmark Summary — Build 1: vLLM Performance Triage\n\n")
        f.write("| " + " | ".join(headers) + " |\n")
        f.write("| " + " | ".join(["---"] * len(headers)) + " |\n")

        for row in rows:
            f.write("| " + " | ".join(row.get(field, "") for field in fields) + " |\n")


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--input", default=DEFAULT_RAW)
    parser.add_argument("--output", default=DEFAULT_OUT)
    args = parser.parse_args()

    raw_root = Path(args.input)
    out_root = Path(args.output)

    if not raw_root.exists():
        raise SystemExit(f"Raw root does not exist: {raw_root}")

    rows = build_rows(raw_root)

    csv_path = out_root / "benchmark-summary.csv"
    md_path = out_root / "benchmark-summary.md"

    write_csv(rows, csv_path)
    write_markdown(rows, md_path)

    print(f"Wrote {len(rows)} rows")
    print(f"CSV: {csv_path}")
    print(f"Markdown: {md_path}")

    if not rows:
        print("WARNING: no benchmark result rows found.")

    return 0


if __name__ == "__main__":
    raise SystemExit(main())
