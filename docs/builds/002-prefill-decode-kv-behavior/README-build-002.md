# Build 2 — Prefill, Decode, and KV Behavior

## Objective

Build 2 explains why LLM inference backends behave the way they do under workload pressure.

Build 1 measured baseline serving behavior:

* TTFT
* TPOT / ITL
* Throughput
* GPU memory
* KV usage
* Saturation points

Build 2 moves one layer deeper.

The goal is not to tune the backend yet. The goal is to build a diagnostic model that explains which system state the backend enters, why it enters that state, and which metrics reveal the transition.

Build 2 is complete when raw benchmark metrics can be converted into an operational diagnosis.

---

## Core Question

When latency or throughput degrades, what state is the backend in, and why?

Every experiment must classify the backend into one of four states:

1. Prefill-bound
2. Decode-bound
3. KV-bound
4. Scheduler-bound

This classification is the central artifact of Build 2.

---

# 1. Build 2 Mental Model

```mermaid
flowchart LR
    A[Incoming Requests] --> B[vLLM Scheduler]

    B --> C[Prefill Phase]
    C --> D[Decode Phase]
    D --> E[Response Streaming]

    C --> F[KV Cache Allocation]
    D --> F

    B --> G[Waiting Queue]
    F --> H[GPU Memory / KV Residency]

    C --> I[TTFT]
    D --> J[TPOT / ITL]
    G --> K[num_requests_waiting]
    H --> L[KV Usage]

    I --> M[Backend State Diagnosis]
    J --> M
    K --> M
    L --> M
```

### How to read this

Requests enter the backend through the scheduler.

The backend first performs prefill, then decode.

Both phases interact with the KV cache.

Build 2 watches the metrics around these phases and asks:

> Which part of the runtime is now the bottleneck?

---

# 2. Pressure-to-State Map

```mermaid
flowchart TD
    A[Workload Pressure] --> B{What changed?}

    B -->|Long input prompts| C[Prefill Pressure]
    B -->|Long output generations| D[Decode Pressure]
    B -->|High active concurrency| E[KV Pressure]
    B -->|Mixed short + long requests| F[Scheduler Pressure]

    C --> G[TTFT rises first]
    D --> H[TPOT / ITL rises]
    E --> I[KV usage rises + waiting grows]
    F --> J[Tail latency cliffs + unfairness]

    G --> K[Prefill-Bound]
    H --> L[Decode-Bound]
    I --> M[KV-Bound]
    J --> N[Scheduler-Bound]
```

This is the core diagnostic model.

The experiment is not complete just because TTFT or TPOT changed.

The experiment is complete when the metric signature can be mapped to a backend state.

---

# 3. Experiment Execution Flow

```mermaid
flowchart TD
    A[Start vLLM Backend] --> B[Start Metrics Collection]
    B --> C[Run Baseline]

    C --> D[Run Prefill Pressure Ramp]
    C --> E[Run Decode Pressure Ramp]
    C --> F[Run KV Pressure Ramp]
    C --> G[Run Mixed Workload Interference]
    C --> H[Run One Pathological Scenario]

    D --> I[Summarize Metrics]
    E --> I
    F --> I
    G --> I
    H --> I

    I --> J[Apply Classification Rules]
    J --> K[Build State Classification Table]
    K --> L[Write Production Symptom Mapping]
    L --> M[Final Build 2 README]
```

Build 2 has one job:

```text
Raw benchmark result -> metric comparison -> state classification -> production interpretation
```

---

# 4. Minimal Experiment Matrix

```text
+--------------------------+------------------------+----------------------+------------------+----------------------+
| Experiment               | Input Shape            | Output Shape         | Concurrency       | Expected State       |
+--------------------------+------------------------+----------------------+------------------+----------------------+
| Baseline                 | Short                  | Short                | 1                | Healthy              |
| Prefill Pressure         | Long                   | Short                | 1, 2, 4, 8        | Prefill-Bound        |
| Decode Pressure          | Short / Moderate       | Long                 | 1, 2, 4, 8        | Decode-Bound         |
| KV Pressure              | Moderate / Long        | Moderate / Long      | 4, 8, 16          | KV-Bound             |
| Mixed Workload           | Short + Long Mixed     | Short + Long Mixed   | 4, 8, 16          | Scheduler-Bound      |
| Pathological Scenario    | Long                   | Long                 | 16               | Combined Failure     |
+--------------------------+------------------------+----------------------+------------------+----------------------+
```

Do not expand this into a giant benchmark matrix.

Build 2 is about mechanism isolation, not exhaustive sweeping.

---

# 5. Required Metrics

Each experiment must collect enough data to explain backend state.

## Primary Metrics

| Metric               | Purpose                                        |
| -------------------- | ---------------------------------------------- |
| TTFT                 | Reveals first-token delay and prefill pressure |
| TPOT / ITL           | Reveals decode speed and streaming degradation |
| KV usage             | Reveals cache residency and concurrency limits |
| num_requests_waiting | Reveals queueing and admission pressure        |
| Preemption events    | Reveals scheduler or KV pressure               |
| Success rate         | Reveals hard failure or admission collapse     |

## Supporting Metrics

| Metric                       | Purpose                                                              |
| ---------------------------- | -------------------------------------------------------------------- |
| Throughput                   | Shows useful system output under pressure                            |
| GPU memory used              | Provides memory context                                              |
| GPU utilization              | Helps distinguish compute pressure from memory or scheduler pressure |
| Request latency distribution | Shows tail-latency cliffs                                            |
| Error rate                   | Captures OOMs, timeouts, or rejected requests                        |

---

# 6. Metric Signature Cheat Sheet

```text
+------------------+---------------------+---------------------+---------------------+--------------------------+
| Backend State    | TTFT                | TPOT / ITL          | KV Usage            | Queue / Waiting          |
+------------------+---------------------+---------------------+---------------------+--------------------------+
| Healthy          | Baseline            | Baseline            | Stable              | Near zero                |
| Prefill-Bound    | Sharp increase      | Near baseline       | Moderate            | May rise                 |
| Decode-Bound     | Stable/moderate ↑   | Sharp increase      | Moderate/high       | May rise slowly          |
| KV-Bound         | Unstable ↑          | Unstable ↑          | High, often >80%    | Rises                    |
| Scheduler-Bound  | Tail latency cliff  | Unstable            | Variable            | Rises under mixed load   |
+------------------+---------------------+---------------------+---------------------+--------------------------+
```

The important signal is not one metric alone.

The important signal is the shape of multiple metrics together.

---

# 7. State Classification Decision Tree

```mermaid
flowchart TD
    A[Benchmark Result] --> B{TTFT p95 > 2x baseline?}

    B -->|Yes| C{TPOT near baseline?}
    C -->|Yes| D{KV usage below collapse threshold?}
    D -->|Yes| E[Classify: Prefill-Bound]

    C -->|No| F{KV usage high or waiting rising?}
    F -->|Yes| G[Possible KV or Scheduler Pressure]

    B -->|No| H{TPOT p95 > 2x baseline?}
    H -->|Yes| I[Classify: Decode-Bound]

    H -->|No| J{KV usage > 80%?}
    J -->|Yes| K{Throughput flat or waiting rising?}
    K -->|Yes| L[Classify: KV-Bound]

    J -->|No| M{Mixed workload tail latency cliff?}
    M -->|Yes| N[Classify: Scheduler-Bound]

    M -->|No| O[Healthy or Inconclusive]
```

This decision tree is intentionally simple.

It is a diagnostic heuristic, not a universal law.

---

# 8. Prefill-Bound State

## Runtime Mechanism

Prefill is the phase where the model processes the input prompt before producing the first output token.

Long prompts increase pre-generation work.

The user experiences this as slow first-token latency.

```mermaid
sequenceDiagram
    participant Client
    participant Scheduler
    participant Prefill
    participant Decode
    participant Stream

    Client->>Scheduler: Long prompt request
    Scheduler->>Prefill: Admit request
    Note over Prefill: Large input context processed before first token
    Prefill-->>Scheduler: Prefill complete
    Scheduler->>Decode: Begin generation
    Decode->>Stream: Tokens stream normally

    Note over Client,Stream: Symptom: first token is slow, but streaming speed is normal
```

## Metric Signature

```text
TTFT: sharp increase
TPOT: near baseline
KV usage: moderate
Preemption: absent or rare
Classification: Prefill-Bound
```

## Classification Rule

Classify as prefill-bound when:

* TTFT p95 > 2x baseline
* TPOT p95 remains near baseline
* KV usage is below collapse threshold
* Preemption is absent or rare

## Production Interpretation

This explains document-heavy, RAG-heavy, or long-context workloads where the response takes a long time to begin, but streams normally once generation starts.

---

# 9. Decode-Bound State

## Runtime Mechanism

Decode is the phase where the model generates output tokens one step at a time.

Long outputs keep active sequences resident longer.

The user experiences this as slow streaming.

```mermaid
sequenceDiagram
    participant Client
    participant Scheduler
    participant Prefill
    participant Decode
    participant Stream

    Client->>Scheduler: Short prompt, long output request
    Scheduler->>Prefill: Small/moderate prefill
    Prefill-->>Decode: First token ready
    Decode->>Stream: Token 1
    Decode->>Stream: Token 2
    Decode->>Stream: Token 3
    Decode->>Stream: Many decode steps continue

    Note over Decode: Active sequence remains resident for many output tokens
    Note over Client,Stream: Symptom: response starts, but tokens arrive slowly
```

## Metric Signature

```text
TTFT: stable or moderately elevated
TPOT: sharp increase
KV usage: moderate/high
Classification: Decode-Bound
```

## Classification Rule

Classify as decode-bound when:

* TPOT p95 > 2x baseline
* Long-output requests dominate the workload
* Streaming latency degrades
* Active sequence residency increases

## Production Interpretation

This explains workloads where the assistant starts responding, but tokens arrive slowly during long generations.

---

# 10. KV-Bound State

## Runtime Mechanism

The KV cache stores attention state for active sequences.

Every active request consumes KV cache.

Long prompts, long outputs, and high concurrency increase KV residency.

```mermaid
flowchart TD
    A[Concurrency Increases] --> B[More Active Sequences]
    B --> C[More KV Cache Residency]
    C --> D[KV Usage Rises]
    D --> E{KV Near Capacity?}

    E -->|No| F[Backend admits more work]
    E -->|Yes| G[Admission slows]
    G --> H[num_requests_waiting rises]
    H --> I[Throughput flattens]
    I --> J[Possible preemption / eviction]
    J --> K[Classify: KV-Bound]
```

## Metric Signature

```text
KV usage: high, often >80%
num_requests_waiting: rising
throughput: flat or collapsing
TTFT/TPOT: unstable
Preemption: possible
Classification: KV-Bound
```

## Classification Rule

Classify as KV-bound when:

* KV usage > 80%
* Concurrency stops improving throughput
* num_requests_waiting increases
* Throughput flattens or collapses
* Preemption or eviction appears

## Production Interpretation

This explains why adding concurrency does not always improve throughput.

The backend may have compute available, but active sequences occupy too much KV memory to admit more useful work.

---

# 11. Scheduler-Bound State

## Runtime Mechanism

Scheduler pressure appears when the backend struggles to fairly admit, batch, or progress heterogeneous requests.

Mixed workloads are the key trigger.

A few large requests can degrade otherwise small interactive requests.

```mermaid
flowchart LR
    A[Short Request] --> S[vLLM Scheduler]
    B[Long Prompt Request] --> S
    C[Long Output Request] --> S

    S --> D[Batching / Admission / Progress Decisions]

    D --> E[Long request occupies runtime resources]
    D --> F[Short request waits behind heavier work]

    E --> G[Tail Latency Cliff]
    F --> G

    G --> H[Scheduler-Bound Diagnosis]
```

## Metric Signature

```text
num_requests_waiting: rising
short-request TTFT: rising
tail latency: sharp increase
TTFT and TPOT: unstable
Preemption: possible
Classification: Scheduler-Bound
```

## Classification Rule

Classify as scheduler-bound when:

* Mixed workloads cause tail-latency cliffs
* Short requests degrade behind long requests
* num_requests_waiting increases
* TTFT and TPOT both become unstable
* Preemption events increase

## Production Interpretation

This explains the production symptom:

> A small request became slow because it was stuck behind heavier long-context or long-output work.

This is one of the most important Build 2 findings because average latency can hide this failure mode.

---

# 12. Pathological Scenario Cascade

Build 2 includes exactly one pathological scenario.

Recommended scenario:

```text
long-context + long-output + concurrency 16
```

The purpose is to demonstrate combined failure physics.

It is not an optimization exercise.

```mermaid
flowchart TD
    A[Long Context] --> B[Prefill Cost Increases]
    C[Long Output] --> D[Decode Residency Increases]
    E[Concurrency 16] --> F[More Active Sequences]

    B --> G[TTFT Cliff]
    D --> H[TPOT Instability]
    F --> I[KV Usage Rises]

    I --> J[Waiting Requests Increase]
    J --> K[Scheduler Pressure]
    K --> L[Preemption / Failure Possible]
    L --> M[Throughput Flattening or Collapse]

    G --> N[Combined Failure Physics]
    H --> N
    M --> N
```

## Expected Failure Chain

```text
Long prompts increase prefill cost.
Long outputs increase decode residency.
High concurrency increases KV pressure.
KV usage rises.
Requests begin waiting.
Scheduler pressure increases.
TTFT cliffs first.
TPOT becomes unstable.
Preemption or failure may appear.
Throughput flattens or collapses.
```

## Production Interpretation

This resembles a real production incident where multiple workload pressures combine:

* RAG-heavy requests
* Long answer generation
* High concurrency
* Insufficient admission control
* Tail-latency cliffs
* Throughput flattening

---

# 13. Final Build 2 Artifact Map

```mermaid
flowchart TD
    A[Raw Benchmark Results] --> B[Processed Summaries]
    B --> C[Metric Comparison vs Baseline]
    C --> D[Classification Rules]
    D --> E[State Classification Table]
    E --> F[Production Symptom Mapping]
    F --> G[Build 2 README]

    D --> H[Prefill Report]
    D --> I[Decode Report]
    D --> J[KV Report]
    D --> K[Mixed Workload Report]
    D --> L[Pathological Scenario Report]
```

The final Build 2 story should be:

```text
Measurement -> Mechanism -> Metric Signature -> Backend State -> Production Symptom
```

---

# 14. Experiment Report Template

Every experiment should follow the same structure.

## Experiment Name

Example:

```text
long-context-concurrency-8
```

## Objective

State which backend behavior the experiment is designed to reveal.

Example:

```text
Determine whether long-context prompts at concurrency 8 create a prefill-bound backend state.
```

## Operational Hypothesis

Use IF / THEN / BECAUSE.

Example:

```text
IF long-context prompts run at concurrency >= 8,
THEN TTFT increases sharply,
BECAUSE prefill dominates GPU time before first-token generation and KV is allocated early for active requests.
```

## Baseline

```text
Baseline:
- TTFT p95:
- TPOT p95:
- KV usage:
- num_requests_waiting:
- preemption events:
- success rate:
```

## Experiment Result

```text
Experiment:
- TTFT p95:
- TPOT p95:
- KV usage:
- num_requests_waiting:
- preemption events:
- success rate:
```

## Classification Rules Applied

```text
Classification rules:
- TTFT p95 > 2x baseline:
- TPOT p95 > 2x baseline:
- KV usage > 80%:
- num_requests_waiting increasing:
- preemption events observed:
```

## System State Classification

```text
Classification:
Confidence:
```

## Classification Rationale

Explain why this state was selected and why other states were rejected.

## Hypothesis Result

```text
Hypothesis confirmed / partially confirmed / rejected.
```

## Production Interpretation

Map the result to a real production symptom.

---

# 15. State Classification Table Template

Use this as the central Build 2 summary table.

| Experiment       | Concurrency | TTFT vs Baseline | TPOT vs Baseline | KV Usage | Waiting Requests | Preemption | Classification   | Confidence |
| ---------------- | ----------: | ---------------: | ---------------: | -------: | ---------------: | ---------: | ---------------- | ---------- |
| baseline         |           1 |             1.0x |             1.0x |      TBD |              TBD |        TBD | healthy          | high       |
| prefill-pressure |           1 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| prefill-pressure |           2 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| prefill-pressure |           4 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| prefill-pressure |           8 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| decode-pressure  |           1 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| decode-pressure  |           2 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| decode-pressure  |           4 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| decode-pressure  |           8 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| kv-pressure      |           4 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| kv-pressure      |           8 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| kv-pressure      |          16 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| mixed-workload   |           4 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| mixed-workload   |           8 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| mixed-workload   |          16 |              TBD |              TBD |      TBD |              TBD |        TBD | TBD              | TBD        |
| pathological     |          16 |              TBD |              TBD |      TBD |              TBD |        TBD | combined failure | TBD        |

---

# 16. Production Symptom Mapping

| Backend State   | User Symptom                       | System Cause                              | Metric Signature                                |
| --------------- | ---------------------------------- | ----------------------------------------- | ----------------------------------------------- |
| Prefill-bound   | First token is slow                | Long prompts dominate pre-generation work | TTFT up, TPOT stable                            |
| Decode-bound    | Response starts but streams slowly | Long generations dominate decode loop     | TPOT up                                         |
| KV-bound        | More concurrency does not help     | Active sequences occupy KV memory         | KV usage up, waiting up, throughput flat        |
| Scheduler-bound | Small requests get slow randomly   | Mixed workloads interfere                 | tail latency up, waiting up, TTFT/TPOT unstable |

---

# 17. Build 2 Exit Criteria

Build 2 is complete when the following questions can be answered clearly:

* What does prefill pressure look like?
* What does decode pressure look like?
* What does KV pressure look like?
* What does scheduler pressure look like?
* Which metric reveals each behavior?
* How do mixed workloads interfere?
* When does the backend become prefill-bound?
* When does it become decode-bound?
* When does it become KV-bound?
* When does it become scheduler-bound?
* Where does saturation occur?
* What triggers the transition from healthy to degraded?
* What production symptom does each backend state explain?

---

# 18. Success Standard

The final output of Build 2 should not merely say:

```text
TTFT increased.
TPOT increased.
Throughput decreased.
```

It should say:

```text
The backend entered a prefill-bound state because TTFT p95 increased more than 2x baseline while TPOT remained near baseline and KV usage stayed below the collapse threshold.
```

That is the difference between measurement and diagnosis.

Build 2 succeeds when benchmark results can be converted into a repeatable diagnostic judgment.

An operator or engineer should be able to look at the Build 2 artifacts and answer:

```text
Is this prefill pressure?
Is this decode pressure?
Is this KV pressure?
Is this scheduler pressure?
What evidence supports that classification?
How confident are we?
What production symptom does this explain?
```

Build 2 is the explanatory layer of the LLM Inference Engineering Lab.

It turns raw serving measurements into systems understanding.
