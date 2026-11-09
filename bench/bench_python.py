"""Time Python banff directly (in-process, after import). Writes bench/results/python.csv"""
import csv, json, locale, statistics, sys, time
from pathlib import Path
if locale.getlocale()[0] is None:
    locale.setlocale(locale.LC_CTYPE, "C.UTF-8")
import banff  # noqa: E402
import pyarrow.parquet as pq  # noqa: E402

cfg = json.loads(Path("bench/cases.json").read_text())
rows = []
for n in cfg["sizes"]:
    data = {k: pq.read_table(f"bench/data/{k}_{n}.parquet") for k in ("indata", "instatus")}
    for c in cfg["cases"]:
        for fmt in ("pyarrow", "pandas"):
            ins = {k: (data[k] if fmt == "pyarrow" else data[k].to_pandas()) for k in c["inputs"]}
            proc = getattr(banff, c["proc"])
            times = []
            for _ in range(cfg["reps"]):
                t0 = time.perf_counter()
                proc(**ins, **c["params"], capture=None)  # capture=None: suppress console output
                times.append(time.perf_counter() - t0)
            rows.append({"case": c["name"], "n": n, "path": f"python ({fmt} in)", "median_s": statistics.median(times)})
            print(rows[-1], file=sys.stderr)
Path("bench/results").mkdir(exist_ok=True)
with open("bench/results/python.csv", "w", newline="") as f:
    w = csv.DictWriter(f, fieldnames=rows[0].keys()); w.writeheader(); w.writerows(rows)
