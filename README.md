## Interpretation

The original c8/c16 TTFT inversion did not persist under controlled request arrival.

Under `request_rate=inf`, the benchmark created burst-admission pressure. TTFT p99 spiked at c8 and c16:

- c8: 3439.63 ms
- c16: 3263.37 ms

Under `request_rate=1`, the same workload normalized:

- c8: 73.77 ms
- c16: 76.25 ms

This indicates that the original c8/c16 inversion was not a KV-cache pressure event and not a stable GPU saturation boundary. It was most likely burst-admission behavior caused by unbounded request arrival interacting with the vLLM runtime and the fixed 11-vCPU VM shape.

Across both runs:

- failed requests remained 0
- peak waiting remained 0
- preemptions remained 0
- peak KV-cache usage remained low

Therefore, the Build 2 conclusion is:

DeepSeek-V2-Lite-Chat on vLLM V1 did not hit KV-cache or preemption pressure on the tested RTX PRO 6000 VM. The main observed instability was TTFT sensitivity under burst-style admission, not memory collapse.

## Repeatability Check: Burst vs Controlled Arrival

The original KV concurrency ramp used `request_rate=inf`. That run showed non-monotonic TTFT p99 spikes at c8 and c16.

A follow-up repeatability check reran the same KV concurrency ramp with `request_rate=1`.

The c8/c16 TTFT spikes disappeared under controlled arrival:

| Concurrency | TTFT p99 at request_rate=inf | TTFT p99 at request_rate=1 |
|---:|---:|---:|
| 8 | 3439.63 ms | 73.77 ms |
| 16 | 3263.37 ms | 76.25 ms |

The result indicates that the original inversion was burst-admission behavior, not KV-cache pressure or stable GPU saturation. Waiting requests, preemptions, and failures remained zero.
