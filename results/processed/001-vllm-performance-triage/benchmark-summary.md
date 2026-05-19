# Benchmark Summary — Build 1: vLLM Performance Triage

| Suite | Experiment | Input | Output | Offered req/s | Actual req/s | Mean TTFT ms | P99 TTFT ms | Mean TPOT ms | P99 TPOT ms | Success |
| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |
| baseline | input512-output128-rate1 | 512 | 128 | 1.00 | 1.22 | 644.72 | 2333.96 | 18.43 | 19.13 |  |
| baseline | input512-output128-rate1 | 512 | 128 | 1.00 | 1.22 | 655.85 | 2361.75 | 18.50 | 19.11 |  |
| baseline | input512-output128-rate2 | 512 | 128 | 2.00 | 1.72 | 3717.48 | 7051.18 | 18.11 | 19.18 |  |
| baseline | baseline | 512 | 128 | 4.00 | 1.70 | 15030.65 | 30846.93 | 18.77 | 19.35 |  |
| baseline | input512-output128-rate4 | 512 | 128 | 4.00 | 1.71 | 14923.07 | 30669.51 | 18.70 | 19.17 |  |
| output-pressure | input512-output128-rate1 | 512 | 128 | 1.00 | 0.95 | 196.27 | 1463.57 | 18.19 | 18.99 |  |
| output-pressure | input512-output256-rate1 | 512 | 256 | 1.00 | 0.87 | 3098.23 | 8243.93 | 18.17 | 18.60 |  |
| output-pressure | input512-output512-rate1 | 512 | 512 | 1.00 | 0.46 | 49928.80 | 103257.27 | 18.00 | 18.67 |  |
| output-pressure | input512-output1024-rate1 | 512 | 1024 | 1.00 | 0.24 | 144073.92 | 294917.63 | 17.98 | 18.71 |  |
| prompt-pressure | input512-output128-rate1 | 512 | 128 | 1.00 | 0.95 | 192.00 | 1424.14 | 18.10 | 18.78 |  |
| prompt-pressure | input512-output128-rate1 | 512 | 128 | 1.00 | 0.95 | 195.90 | 1453.68 | 18.19 | 19.01 |  |
| prompt-pressure | input1024-output128-rate1 | 1024 | 128 | 1.00 | 0.95 | 318.65 | 1916.46 | 18.97 | 20.33 |  |
| prompt-pressure | input1024-output128-rate1 | 1024 | 128 | 1.00 | 0.95 | 332.65 | 1931.04 | 19.32 | 23.01 |  |
| prompt-pressure | input2048-output128-rate1 | 2048 | 128 | 1.00 | 0.94 | 761.70 | 2843.25 | 20.84 | 22.45 |  |
| prompt-pressure | input2048-output128-rate1 | 2048 | 128 | 1.00 | 0.94 | 777.74 | 2886.49 | 20.98 | 22.81 |  |
| prompt-pressure | input3072-output128-rate1 | 3072 | 128 | 1.00 | 0.92 | 1367.88 | 3935.80 | 24.50 | 26.62 |  |
| rate-pressure | input512-output128-rate1 | 512 | 128 | 1.00 | 0.95 | 196.73 | 1427.87 | 18.18 | 18.96 |  |
| rate-pressure | input512-output128-rate2 | 512 | 128 | 2.00 | 1.69 | 2589.05 | 5531.84 | 18.61 | 19.00 |  |
| rate-pressure | input512-output128-rate4 | 512 | 128 | 4.00 | 1.70 | 15000.25 | 30864.97 | 18.77 | 19.25 |  |
| rate-pressure | input512-output128-rate8 | 512 | 128 | 8.00 | 1.72 | 21043.59 | 43091.60 | 18.75 | 19.27 |  |
