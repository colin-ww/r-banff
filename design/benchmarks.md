# Benchmarks: R vs Python banff

Run 2026-11-09. Container: 4 vCPU, 15 GB, Ubuntu 24.04, R 4.3.3, Python 3.12, banff 3.1.3 (PyPI),
reticulate 1.47, nanoarrow 0.9 (R).

These are single runs on a shared cloud container. Treat ±10–20% as noise, and redo on The Zone before quoting.

## Method

- Synthetic data (`bench/make_data.R`): n units, 10 provinces (BY groups), Q1–Q4 lognormal, TOTAL = sum, 10%
  inconsistent TOTAL, instatus with 1 FTI per inconsistent unit. Sizes 1e3 → 1e6.
- The same cases and params for every path come from `bench/cases.json`: editstats, outlier (HB, current), errorloc, donorimp.
- Each figure is the median of 5 calls. It covers the full call: input conversion → preprocessing (presort, prefill) →
  C → output conversion to the caller's native type. Console log is suppressed. Python import is excluded (see cold start).
- Paths:
  - **python (pyarrow in)**: `banff.<proc>(indata=pa.Table, ...)` in Python. This is the reference.
  - **python (pandas in)**: same, with pandas DataFrames in.
  - **r-banff (C backend)**: this package, R → C, no Python.
  - **r-banff (python backend)**: this package via reticulate, data bridged as Arrow (no pandas).
  - **DIY reticulate (pandas)**: what users do today. `r_to_py(data.frame)` → pandas, pandas outputs → `py_to_r`.

## Results (median seconds per call; ratio vs python/pyarrow)

RESULTS_TABLE

## Cold start (one-off per session)

| | seconds |
|---|---|
| bare `Rscript -e 1` | 0.18 |
| `Rscript`: `library(banff)` + first `verifyedits()` (C backend) | 0.21 (+0.03) |
| `python -c "import banff"` | 0.55 |
| `Rscript`: reticulate init + `import banff` | 2.25 |

A bash/CLI wrapper pays at least the `import banff` cost (~0.55 s) on **every call**, plus file I/O.

## Reading the numbers

READING
