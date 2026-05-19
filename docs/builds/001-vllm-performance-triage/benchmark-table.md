# Benchmark Table — Build 1: vLLM Performance Triage

| Suite | Experiment | Input | Output | Offered req/s | Actual req/s | Mean TTFT ms | P99 TTFT ms | Mean TPOT ms | P99 TPOT ms | Interpretation |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---|
| baseline | healthy-baseline | 512 | 128 | 1.0 | 0.95 | 196.73 | 1427.87 | 18.18 | 18.96 | Healthy low-pressure baseline |
| rate-pressure | input512-output128-rate2 | 512 | 128 | 2.0 | 1.69 | 2589.05 | 5531.84 | 18.61 | 19.00 | Moderate queue/prefill pressure |
| rate-pressure | input512-output128-rate4 | 512 | 128 | 4.0 | 1.70 | 15000.25 | 30864.97 | 18.77 | 19.25 | Saturated; throughput plateaus |
| rate-pressure | input512-output128-rate8 | 512 | 128 | 8.0 | 1.72 | 21043.59 | 43091.60 | 18.75 | 19.27 | Severe saturation; TTFT tail expands |
| prompt-pressure | input512-output128-rate1 | 512 | 128 | 1.0 | 0.95 | 195.90 | 1453.68 | 18.19 | 19.01 | Baseline prompt length |
| prompt-pressure | input1024-output128-rate1 | 1024 | 128 | 1.0 | 0.95 | 332.65 | 1931.04 | 19.32 | 23.01 | Longer prompt increases TTFT |
| prompt-pressure | input2048-output128-rate1 | 2048 | 128 | 1.0 | 0.94 | 777.74 | 2886.49 | 20.98 | 22.81 | Prefill pressure grows |
| prompt-pressure | input3072-output128-rate1 | 3072 | 128 | 1.0 | 0.92 | 1367.88 | 3935.80 | 24.50 | 26.62 | Long prompt increases TTFT and mild TPOT pressure |
| output-pressure | input512-output128-rate1 | 512 | 128 | 1.0 | 0.95 | 196.27 | 1463.57 | 18.19 | 18.99 | Baseline output length |
| output-pressure | input512-output256-rate1 | 512 | 256 | 1.0 | 0.87 | 3098.23 | 8243.93 | 18.17 | 18.60 | Longer residency begins queueing |
| output-pressure | input512-output512-rate1 | 512 | 512 | 1.0 | 0.46 | 49928.80 | 103257.27 | 18.00 | 18.67 | Decode residency halves request throughput |
| output-pressure | input512-output1024-rate1 | 512 | 1024 | 1.0 | 0.24 | 144073.92 | 294917.63 | 17.98 | 18.71 | Long outputs dominate capacity; TTFT explodes |
