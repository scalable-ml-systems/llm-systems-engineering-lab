# Build 2 — Prefill, Decode, and KV Behavior

## Objective
Explain why the backend enters prefill-bound, decode-bound, KV-bound, or scheduler-bound states.

## What Build 1 gave us
Baseline TTFT, TPOT, throughput, GPU memory, KV usage, and saturation points.

## What Build 2 adds
A diagnostic model that converts metrics into backend state classification.

## Experiments
1. Baseline
2. Prefill pressure
3. Decode pressure
4. KV pressure
5. Mixed workload interference
6. Pathological scenario

## Core classification table
Link to state-classification-table.md

## Main findings
- Prefill pressure signature:
- Decode pressure signature:
- KV pressure signature:
- Scheduler pressure signature:

## Production interpretation
Link to production-symptom-mapping.md

## Exit criteria
Build 2 is complete when raw benchmark metrics can be converted into a repeatable diagnostic judgment.