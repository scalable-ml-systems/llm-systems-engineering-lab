#!/usr/bin/env python3
"""Summarize raw vLLM benchmark results into processed CSV/Markdown tables.

Design rules:
- results/raw/ stays raw and unmodified.
- results/processed/ contains normalized summaries.
- docs/builds/ contains interpretation written by the operator.

The parser is intentionally tolerant because vLLM benchmark result JSON fields can vary by version.
"""

from __future__ import annotations

import argparse
import csv
import json
import math
import re
from pathlib import Path
from typing import Any

STANDARD_COLUMNS = [
    "Experiment",
    "Workload",
    "Changed Variable",
    "Controlled Variables",
    "TTFT p95",
    "TPOT p95",
    "E2E p95",
    "Throughput",
    "num_requests_waiting",
    "KV Usage",
    "Error Rate",
    "Interpretation",
]

FIELD_ALIASES = {
    "TTFT p95": [
        "p95_ttft_ms",
        "p95_ttft",
        "ttft_p95_ms",
        "ttft_p95",
        "Time to First Token p95 (ms)",
    ],
    "TPOT p95": [
        "p95_tpot_ms",
        "p95_tpot",
        "tpot_p95_ms",
        "tpot_p95",
        "p95_itl_ms",
        "itl_p95_ms",
        "inter_token_latency_p95_ms",
    ],
    "E2E p95": [
        "p95_e2el_ms",
        "p95_e2e_latency_ms",
        "e2e_latency_p95_ms",
        "request_latency_p95_ms",
        "p95_latency_ms",
    ],
    "Throughput": [
        "request_throughput",
        "requests_per_second",
        "output_throughput",
        "output_tokens_per_second",
        "total_token_throughput",
    ],
    "Error Rate": ["error_rate", "failed_rate", "failure_rate"],
}


def load_json(path: Path) -> Any | None:
    try:
        return json.loads(path.read_text())
    except Exception:
        return None


def flatten(obj: Any, prefix: str = "") -> dict[str, Any]:
    out: dict[str, Any] = {}
    if isinstance(obj, dict):
        for key, value in obj.items():
            child = f"{prefix}.{key}" if prefix else str(key)
            out.update(flatten(value, child))
    elif isinstance(obj, list):
        # Keep list summaries small. Raw lists remain in results/raw.
        out[prefix] = obj
    else:
        out[prefix] = obj
    return out


def numeric(value: Any) -> float | None:
    if value is None or value == "":
        return None
    if isinstance(value, (int, float)):
        if math.isnan(float(value)):
            return None
        return float(value)
    if isinstance(value, str):
        cleaned = value.strip().replace("ms", "").replace("s", "").replace(",", "")
        try:
            return float(cleaned)
        except ValueError:
            return None
    return None


def percentile(values: list[float], pct: float) -> float | None:
    if not values:
        return None
    values = sorted(values)
    k = (len(values) - 1) * pct
    f = math.floor(k)
    c = math.ceil(k)
    if f == c:
        return values[int(k)]
    return values[f] * (c - k) + values[c] * (k - f)


def find_alias(flat: dict[str, Any], aliases: list[str]) -> Any | None:
    # Exact suffix match first, then lowercase fuzzy match.
    for alias in aliases:
        for key, value in flat.items():
            if key == alias or key.endswith(f".{alias}"):
                return value
    lowered = {key.lower(): value for key, value in flat.items()}
    for alias in aliases:
        alias_l = alias.lower()
        for key, value in lowered.items():
            if key.endswith(alias_l):
                return value
    return None


def extract_from_result_json(experiment_dir: Path) -> dict[str, Any]:
    row: dict[str, Any] = {}
    candidates = sorted(experiment_dir.glob("*.json"))

    # Prefer files that are not our metadata if available.
    candidates = sorted(candidates, key=lambda p: ("metadata" in p.name, p.name))

    for path in candidates:
        data = load_json(path)
        if data is None:
            continue
        flat = flatten(data)
        for column, aliases in FIELD_ALIASES.items():
            if column not in row or row[column] in (None, ""):
                value = find_alias(flat, aliases)
                if value is not None:
                    row[column] = value

        # Derive p95 from raw arrays if vLLM emits per-request arrays.
        for key, value in flat.items():
            if not isinstance(value, list):
                continue
            values = [numeric(v) for v in value]
            nums = [v for v in values if v is not None]
            key_l = key.lower()
            if nums and "ttft" in key_l and "TTFT p95" not in row:
                row["TTFT p95"] = percentile(nums, 0.95)
            if nums and ("tpot" in key_l or "itl" in key_l or "inter_token" in key_l) and "TPOT p95" not in row:
                row["TPOT p95"] = percentile(nums, 0.95)
            if nums and ("latenc" in key_l or "e2e" in key_l) and "E2E p95" not in row:
                row["E2E p95"] = percentile(nums, 0.95)

    return row


def parse_metadata(experiment_dir: Path) -> dict[str, Any]:
    metadata_path = experiment_dir / "experiment-metadata.json"
    data = load_json(metadata_path) if metadata_path.exists() else None
    return data if isinstance(data, dict) else {}


def infer_changed_variable(name: str) -> str:
    patterns = [
        (r"prompt-length-(\d+)", "random_input_len=\\1"),
        (r"output-length-(\d+)", "random_output_len=\\1"),
        (r"request-rate-(\d+)", "request_rate=\\1"),
    ]
    for pattern, repl in patterns:
        match = re.match(pattern, name)
        if match:
            return re.sub(pattern, repl, name)
    if name == "baseline":
        return "none"
    return name


def controlled_variables(meta: dict[str, Any]) -> str:
    keys = ["model", "random_input_len", "random_output_len", "num_prompts", "request_rate"]
    parts = [f"{key}={meta[key]}" for key in keys if key in meta]
    return "; ".join(parts)


def normalize_value(value: Any) -> str:
    n = numeric(value)
    if n is None:
        return "TBD"
    if abs(n) >= 100:
        return f"{n:.2f}"
    return f"{n:.4f}"


def build_rows(raw_root: Path) -> list[dict[str, str]]:
    rows: list[dict[str, str]] = []
    experiment_dirs = [p for p in sorted(raw_root.iterdir()) if p.is_dir() and p.name != "metrics"]

    for exp_dir in experiment_dirs:
        meta = parse_metadata(exp_dir)
        extracted = extract_from_result_json(exp_dir)
        experiment = meta.get("experiment", exp_dir.name)

        row = {column: "TBD" for column in STANDARD_COLUMNS}
        row["Experiment"] = str(experiment)
        row["Workload"] = "random"
        row["Changed Variable"] = infer_changed_variable(str(experiment))
        row["Controlled Variables"] = controlled_variables(meta) or "See experiment-metadata.json"
        row["TTFT p95"] = normalize_value(extracted.get("TTFT p95"))
        row["TPOT p95"] = normalize_value(extracted.get("TPOT p95"))
        row["E2E p95"] = normalize_value(extracted.get("E2E p95"))
        row["Throughput"] = normalize_value(extracted.get("Throughput"))
        row["Error Rate"] = normalize_value(extracted.get("Error Rate"))
        row["Interpretation"] = "Operator interpretation required"
        rows.append(row)

    return rows


def write_csv(rows: list[dict[str, str]], path: Path) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("w", newline="") as f:
        writer = csv.DictWriter(f, fieldnames=STANDARD_COLUMNS)
        writer.writeheader()
        writer.writerows(rows)


def markdown_table(rows: list[dict[str, str]]) -> str:
    if not rows:
        return "No benchmark rows found.\n"
    header = "| " + " | ".join(STANDARD_COLUMNS) + " |"
    sep = "| " + " | ".join(["---"] * len(STANDARD_COLUMNS)) + " |"
    body = []
    for row in rows:
        body.append("| " + " | ".join(str(row.get(col, "TBD")).replace("\n", " ") for col in STANDARD_COLUMNS) + " |")
    return "\n".join([header, sep, *body]) + "\n"


def main() -> int:
    parser = argparse.ArgumentParser(description="Summarize vLLM benchmark raw results.")
    parser.add_argument("--input", default="results/raw/001-vllm-performance-triage", help="Raw results root")
    parser.add_argument("--output", default="results/processed/001-vllm-performance-triage", help="Processed output root")
    args = parser.parse_args()

    raw_root = Path(args.input)
    output_root = Path(args.output)
    if not raw_root.exists():
        raise SystemExit(f"Raw results path does not exist: {raw_root}")

    rows = build_rows(raw_root)
    write_csv(rows, output_root / "benchmark-summary.csv")
    (output_root / "benchmark-summary.md").write_text(markdown_table(rows))

    print(f"Wrote {len(rows)} rows")
    print(f"CSV: {output_root / 'benchmark-summary.csv'}")
    print(f"Markdown: {output_root / 'benchmark-summary.md'}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
