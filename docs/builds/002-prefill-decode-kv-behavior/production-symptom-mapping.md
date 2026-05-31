| Backend State   | User Symptom                       | System Cause                              | Metric Signature                              |
| --------------- | ---------------------------------- | ----------------------------------------- | --------------------------------------------- |
| Prefill-bound   | First token is slow                | Long prompts dominate pre-generation work | TTFT ↑, TPOT stable                           |
| Decode-bound    | Response starts but streams slowly | Long generations dominate decode loop     | TPOT ↑                                        |
| KV-bound        | More concurrency does not help     | Active sequences occupy KV memory         | KV usage ↑, waiting ↑, throughput flat        |
| Scheduler-bound | Small requests get slow randomly   | Mixed workloads interfere                 | tail latency ↑, waiting ↑, TTFT/TPOT unstable |
