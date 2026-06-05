# CloudRift Repeatability Check — request_rate=inf vs request_rate=1

## Question

Did the original c8/c16 TTFT inversion persist when the KV concurrency ramp was rerun with a controlled request arrival rate?

## Workload

| Parameter | Value |
|---|---:|
| Model | `deepseek-ai/DeepSeek-V2-Lite-Chat` |
| Input tokens | 2048 |
| Output tokens | 512 |
| Concurrency ramp | 1, 2, 4, 8, 16, 24, 32 |
| Original request rate | `inf` |
| Repeat request rate | `1` |

## Comparison Table

| Concurrency | Rate | TTFT p99 ms | TPOT p99 ms | ITL p99 ms | Req/s | Out tok/s | Peak concurrent | Peak KV Cache | Peak Waiting | Preemptions Δ | Success | Failed |
|---:|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 1 | inf | 3289.06 | 4.93 | 5.39 | 0.37 | 187.90 | 2 | 0.001482 | 0 | 0 | 50 | 0 |
| 1 | 1 | 60.88 | 4.94 | 5.36 | 0.38 | 196.93 | 2 | 0.001482 | 0 | 0 | 50 | 0 |
| 2 | inf | 878.80 | 7.32 | 7.67 | 0.55 | 279.89 | 4 | 0.002946 | 0 | 0 | 50 | 0 |
| 2 | 1 | 57.53 | 7.35 | 7.88 | 0.53 | 269.24 | 3 | 0.002825 | 0 | 0 | 50 | 0 |
| 4 | inf | 101.10 | 9.46 | 10.29 | 0.84 | 431.41 | 8 | 0.005863 | 0 | 0 | 50 | 0 |
| 4 | 1 | 67.48 | 9.70 | 13.98 | 0.76 | 388.65 | 6 | 0.005678 | 0 | 0 | 50 | 0 |
| 8 | inf | 3439.63 | 15.67 | 14.52 | 1.13 | 577.32 | 16 | 0.011569 | 0 | 0 | 50 | 0 |
| 8 | 1 | 73.77 | 12.29 | 17.44 | 0.90 | 462.28 | 11 | 0.011069 | 0 | 0 | 50 | 0 |
| 16 | inf | 3263.37 | 16.99 | 17.27 | 1.75 | 893.64 | 32 | 0.023166 | 0 | 0 | 50 | 0 |
| 16 | 1 | 76.25 | 12.81 | 23.35 | 0.90 | 460.53 | 13 | 0.016126 | 0 | 0 | 50 | 0 |
| 24 | inf | 411.14 | 17.81 | 21.11 | 2.28 | 1165.92 | 48 | 0.034346 | 0 | 0 | 50 | 0 |
| 24 | 1 | 80.16 | 14.19 | 24.20 | 0.90 | 462.51 | 13 | 0.014802 | 0 | 0 | 50 | 0 |
| 32 | inf | 992.92 | 18.02 | 19.80 | 2.64 | 1349.53 | 49 | 0.045961 | 0 | 0 | 50 | 0 |
| 32 | 1 | 78.90 | 12.86 | 23.96 | 0.90 | 462.89 | 13 | 0.01621 | 0 | 0 | 50 | 0 |

## Interpretation Template

Fill this in after inspecting the table:

- If c8/c16 TTFT spikes appear only under `request_rate=inf`, the original inversion was likely burst-admission behavior.
- If c8/c16 TTFT spikes appear under both `request_rate=inf` and `request_rate=1`, the behavior is repeatable on the CloudRift VM shape.
- If neither repeat shows c8/c16 spikes, the original inversion was likely transient run noise.
- If waiting and preemptions remain zero, this is still not KV-cache pressure.
