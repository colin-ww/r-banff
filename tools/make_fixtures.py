#!/usr/bin/env python3
"""Record golden test fixtures by running the upstream Python sample programs.

Every `banff.<proc>(...)` call made by `Python/sample_programs/conversion_examples/*.py` is
intercepted: its inputs (DataFrames), scalar parameters and the outputs Python banff produced
are written to `tests/testthat/fixtures/<sample>-<n>/`:

    meta.json       {"proc": "donorimp", "params": {...}, "outputs": [...], "banff_version": ...}
    in_<name>.arrows   / out_<name>.arrows   (Arrow IPC stream, readable by nanoarrow in R)

R tests then replay each call through the R package and compare against Python's output.
Sample data is synthetic (from the public upstream repo), safe to commit.

Usage (dev only):  python tools/make_fixtures.py <path/to/sample_programs/conversion_examples>
"""

import contextlib
import inspect
import io
import json
import runpy
import shutil
import sys
from pathlib import Path

import locale

if locale.getlocale()[0] is None:  # upstream import bug under C/POSIX locale
    locale.setlocale(locale.LC_CTYPE, "C.UTF-8")

import banff  # noqa: E402
import pandas as pd  # noqa: E402
import pyarrow as pa  # noqa: E402

OUT_DIR = Path(__file__).resolve().parent.parent / "tests" / "testthat" / "fixtures"
PY_ONLY = {"trace", "capture", "logger"}
SEED = 20261109  # injected where a sample omits `seed`
# Parameter values removed upstream, rewritten so old samples still run. Applied from `since` on.
# 3.2.0: outlier CURRENT/RATIO/HISTORIC merged into HB (variant chosen by with_var / indata_hist); SIGMAGAP -> SG.
REWRITES = [
    {"since": (3, 2, 0), "proc": "outlier", "param": "method",
     "map": {"current": "HB", "ratio": "HB", "historic": "HB", "sigmagap": "SG"}},
]


def version_tuple(v):
    return tuple(int(x) for x in v.split(".")[:3])


def write_arrows(tbl, path):
    if isinstance(tbl, pd.DataFrame):
        tbl = pa.Table.from_pandas(tbl, preserve_index=False)
    with pa.OSFile(str(path), "wb") as sink, pa.ipc.new_stream(sink, tbl.schema) as w:
        w.write_table(tbl)


def main(sample_dir: Path):
    calls = []
    procs = {name: getattr(banff, name) for name in banff.__all__ if isinstance(getattr(banff, name), type)}

    def make_wrapper(cls):
        def wrapper(**kwargs):
            # samples without `seed` use a time-based seed -> not reproducible; pin one
            patched = {}
            if "seed" in inspect.signature(cls.__init__).parameters and kwargs.get("seed") is None:
                kwargs["seed"] = SEED
                patched["seed"] = SEED
            for rw in REWRITES:
                val = kwargs.get(rw["param"])
                if (cls._proc_name["short"] == rw["proc"] and isinstance(val, str)  # noqa: SLF001
                        and version_tuple(banff.__version__) >= rw["since"] and val.lower() in rw["map"]):
                    kwargs[rw["param"]] = patched[rw["param"]] = rw["map"][val.lower()]
            obj = cls(**kwargs)
            calls[-1]["records"].append((cls, kwargs, obj, patched))
            return obj
        return wrapper

    for name, cls in procs.items():
        setattr(banff, name, make_wrapper(cls))

    shutil.rmtree(OUT_DIR, ignore_errors=True)
    OUT_DIR.mkdir(parents=True)
    for f in sorted(sample_dir.glob("*.py")):
        calls.append({"sample": f.stem, "records": []})
        with contextlib.redirect_stdout(io.StringIO()):
            runpy.run_path(str(f), run_name="__main__")

    n_written = 0
    for c in calls:
        for i, (cls, kwargs, obj, patched) in enumerate(c["records"], start=1):
            d = OUT_DIR / f"{c['sample']}-{i}"
            d.mkdir()
            params, outputs = {}, []
            out_names = [ds.name for ds in obj._output_datasets]  # noqa: SLF001
            for k, v in kwargs.items():
                if k in PY_ONLY:
                    continue
                if isinstance(v, (pd.DataFrame, pa.Table)):
                    write_arrows(v, d / f"in_{k}.arrows")
                elif k in out_names:
                    params[k] = v is not False  # R side: logical "request this output"
                else:
                    params[k] = v
            for ds in obj._output_datasets:  # noqa: SLF001
                if ds.user_output is not None and ds.is_requested:
                    write_arrows(ds.user_output, d / f"out_{ds.name}.arrows")
                    outputs.append(ds.name)
            meta = {"proc": cls._proc_name["short"], "params": params, "outputs": outputs,  # noqa: SLF001
                    "banff_version": banff.__version__, "sample": c["sample"], "patched": patched}
            (d / "meta.json").write_text(json.dumps(meta, indent=2))
            n_written += 1
    print(f"wrote {n_written} fixtures to {OUT_DIR}")


if __name__ == "__main__":
    main(Path(sys.argv[1]))
