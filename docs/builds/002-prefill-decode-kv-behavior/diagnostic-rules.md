Rule 1 — Prefill-bound

Classify as prefill-bound when:
- TTFT p95 > 2× baseline
- TPOT p95 remains near baseline
- KV usage is below collapse threshold
- preemption is absent or rare

Reason:
The latency penalty happens before first-token generation.

Rule 2 — Decode-bound

Classify as decode-bound when:
- TPOT p95 > 2× baseline
- long-output requests dominate the workload
- streaming latency degrades
- active sequence residency increases

Reason:
The backend spends sustained time generating output tokens.

Rule 3 — KV-bound

Classify as KV-bound when:
- KV usage > 80%
- concurrency no longer improves throughput
- waiting requests increase
- throughput flattens or collapses
- preemption or eviction appears

Reason:
The backend cannot admit or progress more useful work because active sequences occupy too much KV memory.

Rule 4 — Scheduler-bound

Classify as scheduler-bound when:
- mixed workloads cause tail-latency cliffs
- short requests degrade behind long requests
- num_requests_waiting increases
- TTFT and TPOT both become unstable
- preemption events increase

Reason:
The backend struggles to fairly admit, batch, or progress heterogeneous requests.