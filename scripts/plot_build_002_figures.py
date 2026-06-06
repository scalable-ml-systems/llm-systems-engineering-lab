from pathlib import Path
import matplotlib.pyplot as plt

OUT = Path("results/plots/build-002")
OUT.mkdir(parents=True, exist_ok=True)

concurrency = [1, 2, 4, 8, 16, 24, 32]

ttft_inf = [3289.06, 878.80, 101.10, 3439.63, 3263.37, 411.14, 992.92]
ttft_rate1 = [60.88, 57.53, 67.48, 73.77, 76.25, 80.16, 78.90]

tpot_inf = [4.93, 7.32, 9.46, 15.67, 16.99, 17.81, 18.02]
tpot_rate1 = [4.94, 7.35, 9.70, 12.29, 12.81, 14.19, 12.86]

out_inf = [187.90, 279.89, 431.41, 577.32, 893.64, 1165.92, 1349.53]
out_rate1 = [196.93, 269.24, 388.65, 462.28, 460.53, 462.51, 462.89]

kv_inf = [0.001482, 0.002946, 0.005863, 0.011569, 0.023166, 0.034346, 0.045961]
kv_rate1 = [0.001482, 0.002825, 0.005678, 0.011069, 0.016126, 0.014802, 0.016210]

def savefig(name):
    plt.savefig(OUT / name, bbox_inches="tight", dpi=160)
    plt.close()

def line_plot(name, title, ylabel, y1, y2, note=None):
    plt.figure(figsize=(9, 5))
    plt.plot(concurrency, y1, marker="o", label="request_rate=inf")
    plt.plot(concurrency, y2, marker="o", label="request_rate=1")
    plt.title(title)
    plt.xlabel("Max concurrency")
    plt.ylabel(ylabel)
    plt.xticks(concurrency)
    plt.grid(True, alpha=0.3)
    plt.legend()
    if note:
        plt.figtext(0.5, -0.05, note, ha="center", fontsize=9)
    savefig(name)

line_plot(
    "ttft_inf_vs_rate1.png",
    "TTFT p99: Burst Admission vs Controlled Arrival",
    "TTFT p99 (ms)",
    ttft_inf,
    ttft_rate1,
    "c8/c16 TTFT spikes appear under request_rate=inf and disappear under request_rate=1."
)

line_plot(
    "tpot_inf_vs_rate1.png",
    "TPOT p99: Burst Admission vs Controlled Arrival",
    "TPOT p99 (ms)",
    tpot_inf,
    tpot_rate1,
    "TPOT rises with concurrency, but the dramatic inversion was a TTFT/admission effect."
)

line_plot(
    "output_throughput_vs_concurrency.png",
    "Output Throughput vs Concurrency",
    "Output tokens / second",
    out_inf,
    out_rate1,
    "request_rate=inf exposes throughput scaling; request_rate=1 is arrival-rate limited."
)

line_plot(
    "kv_cache_vs_concurrency.png",
    "Peak KV Cache Usage vs Concurrency",
    "KV cache usage percentage scale, 0–1",
    kv_inf,
    kv_rate1,
    "Peak KV stayed below 0.05, so this run did not hit KV-cache pressure."
)

print(f"Wrote figures to {OUT}")