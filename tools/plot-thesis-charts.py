"""Generate thesis charts from benchmark JSON output.

Usage: python tools/plot-thesis-charts.py bench-results.json
"""
import json, sys, re
import matplotlib.pyplot as plt
import matplotlib
matplotlib.use('Agg')
import numpy as np

with open(sys.argv[1] if len(sys.argv) > 1 else "bench-results.json") as f:
    data = json.load(f)

benches = data["benches"]

def extract(prefix):
    results = []
    for b in benches:
        name = b["name"]
        if name.startswith(prefix):
            val = int(re.search(r'=(\d+)', name).group(1))
            avg_ms = b["results"][0]["ok"]["avg"] / 1e6
            results.append((val, avg_ms))
    results.sort()
    return results

# Chart 1: N scaling
fig, ax = plt.subplots(figsize=(5, 3.5))
pts = extract("chart1-N=")
ns = [p[0] for p in pts]
ts = [p[1] for p in pts]
ax.plot(ns, ts, 'o-', color='#2563eb', linewidth=2, markersize=5, label='measured')
ns_ref = np.linspace(ns[0], ns[-1], 100)
scale = ts[0] / (ns[0]**2)
ax.plot(ns_ref, scale * ns_ref**2, '--', color='gray', alpha=0.5, label='$O(N^2)$')
ax.set_xlabel('$N$ (total events)')
ax.set_ylabel('Time (ms)')
ax.set_title('Varying $N$ ($P=2$, equal branches)')
ax.legend()
ax.grid(True, alpha=0.3)
fig.tight_layout()
fig.savefig("img/bench-n-scaling.pdf", bbox_inches='tight')
fig.savefig("img/bench-n-scaling.png", bbox_inches='tight', dpi=150)
print(f"Chart 1: {len(pts)} points")

# Chart 2: C_total scaling
fig, ax = plt.subplots(figsize=(5, 3.5))
pts = extract("chart2-C=")
cs = [p[0] for p in pts]
ts = [p[1] for p in pts]
ax.plot(cs, ts, 's-', color='#dc2626', linewidth=2, markersize=5, label='measured')
cs_ref = np.linspace(max(cs[0], 1), cs[-1], 100)
scale = ts[-1] / cs[-1]
ax.plot(cs_ref, scale * cs_ref, '--', color='gray', alpha=0.5, label='$O(C_{total})$')
ax.set_xlabel('$C_{total}$ (incomparable pairs)')
ax.set_ylabel('Time (ms)')
ax.set_title('Varying $C_{total}$ ($N=2000$, $P=2$)')
ax.legend()
ax.grid(True, alpha=0.3)
fig.tight_layout()
fig.savefig("img/bench-c-scaling.pdf", bbox_inches='tight')
fig.savefig("img/bench-c-scaling.png", bbox_inches='tight', dpi=150)
print(f"Chart 2: {len(pts)} points")

# Chart 3: P scaling (log-log)
fig, ax = plt.subplots(figsize=(5, 3.5))
pts = extract("chart3-P=")
ps = [p[0] for p in pts]
ts = [p[1] for p in pts]
ax.plot(ps, ts, 'D-', color='#16a34a', linewidth=2, markersize=5, label='measured')
ps_ref = np.linspace(ps[0], ps[-1], 100)
scale = ts[0] / ps[0]
ax.plot(ps_ref, scale * ps_ref, '--', color='gray', alpha=0.5, label='$O(P)$')
ax.set_xlabel('$P$ (number of peers)')
ax.set_ylabel('Time (ms)')
ax.set_title('Varying $P$ ($N=2000$, $C_{total}$ constant)')
ax.legend()
ax.set_xscale('log')
ax.set_yscale('log')
ax.grid(True, alpha=0.3)
fig.tight_layout()
fig.savefig("img/bench-p-scaling.pdf", bbox_inches='tight')
fig.savefig("img/bench-p-scaling.png", bbox_inches='tight', dpi=150)
print(f"Chart 3: {len(pts)} points")

print("Done!")
