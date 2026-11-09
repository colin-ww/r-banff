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

| case | n | python (pyarrow in) | python (pandas in) | r-banff (C backend) | r-banff (python backend) | DIY reticulate (pandas) |
| --- | --- | --- | --- | --- | --- | --- |
| editstats | 1,000 | 0.003 (1.0x) | 0.008 (2.8x) | 0.006 (2.0x) | 0.015 (5.0x) | 0.030 (10.0x) |
| editstats | 10,000 | 0.005 (1.0x) | 0.014 (2.8x) | 0.011 (2.1x) | 0.021 (4.1x) | 0.043 (8.3x) |
| editstats | 100,000 | 0.039 (1.0x) | 0.097 (2.5x) | 0.040 (1.0x) | 0.053 (1.3x) | 0.192 (4.9x) |
| editstats | 1,000,000 | 0.460 (1.0x) | 1.029 (2.2x) | 0.446 (1.0x) | 0.484 (1.1x) | 2.254 (4.9x) |
| outlier | 1,000 | 0.003 (1.0x) | 0.008 (2.7x) | 0.005 (1.6x) | 0.009 (2.9x) | 0.023 (7.4x) |
| outlier | 10,000 | 0.009 (1.0x) | 0.021 (2.5x) | 0.012 (1.4x) | 0.023 (2.7x) | 0.074 (8.6x) |
| outlier | 100,000 | 0.107 (1.0x) | 0.142 (1.3x) | 0.083 (0.8x) | 0.112 (1.1x) | 0.523 (4.9x) |
| outlier | 1,000,000 | 1.348 (1.0x) | 2.327 (1.7x) | 1.624 (1.2x) | 1.622 (1.2x) | 5.992 (4.4x) |
| errorloc | 1,000 | 0.003 (1.0x) | 0.009 (2.8x) | 0.005 (1.6x) | 0.011 (3.6x) | 0.024 (7.9x) |
| errorloc | 10,000 | 0.016 (1.0x) | 0.025 (1.6x) | 0.019 (1.2x) | 0.028 (1.8x) | 0.061 (3.8x) |
| errorloc | 100,000 | 0.142 (1.0x) | 0.208 (1.5x) | 0.149 (1.0x) | 0.164 (1.2x) | 0.329 (2.3x) |
| errorloc | 1,000,000 | 1.560 (1.0x) | 2.321 (1.5x) | 1.843 (1.2x) | 1.804 (1.2x) | 3.477 (2.2x) |
| donorimp | 1,000 | 0.007 (1.0x) | 0.009 (1.3x) | 0.013 (1.8x) | 0.021 (2.9x) | 0.030 (4.2x) |
| donorimp | 10,000 | 0.101 (1.0x) | 0.089 (0.9x) | 0.109 (1.1x) | 0.101 (1.0x) | 0.148 (1.5x) |
| donorimp | 100,000 | 1.673 (1.0x) | 1.587 (0.9x) | 1.470 (0.9x) | 1.619 (1.0x) | 1.725 (1.0x) |
| donorimp | 1,000,000 | 44.847 (1.0x) | 44.584 (1.0x) | 48.121 (1.1x) | 53.446 (1.2x) | 53.967 (1.2x) |

Raw: `bench/results/all.csv` (regenerate the table with `Rscript bench/report.R`).

## Cold start (one-off per session)

| | seconds |
|---|---|
| bare `Rscript -e 1` | 0.18 |
| `Rscript`: `library(banff)` + first `verifyedits()` (C backend) | 0.21 (+0.03) |
| `python -c "import banff"` | 0.55 |
| `Rscript`: reticulate init + `import banff` | 2.25 |

A bash/CLI wrapper pays at least the `import banff` cost (~0.55 s) on **every call**, plus file I/O.

## Reading the numbers

- **R → C is on par with Python banff.** At ≥100k rows it runs at 0.8–1.2× of Python fed pyarrow Tables (its fastest
  path). It's faster than Python fed pandas DataFrames (the common Python usage) at most sizes.
- **Small calls carry a fixed ~2–6 ms R-side overhead**: JSON, Arrow conversion, temp-file log capture, tibble conversion.
  Irrelevant in practice. Even 1,000 calls (e.g. by-group loops) add only a few seconds.
- **Heavy procedures are C-bound.** donorimp at 1e6 rows takes 45–54 s on every path. The wrapper doesn't matter there.
  The run-to-run spread for the same path was ~±10% (40.9 vs 48.1 s across two runs of the C backend).
- **DIY reticulate is the slowest path at every size**: 2–10× slower than R → C on light procedures, because data is copied
  R → numpy/pandas → Arrow and back. It's also the path with the type-conversion bugs ([feasibility.md](feasibility.md)).
- **The r-banff python backend** (reticulate, but Arrow-bridged) lands close to R → C at large n. Its extra cost is reticulate
  call overhead (~5–10 ms) plus the 2.2 s one-off Python start-up.

### Finding: arrow-backed (ALTREP) data frames cost extra

A first run fed R `as.data.frame(arrow::read_parquet(...))`, whose columns are lazy, arrow-backed ALTREP vectors.
Presort then forced them to materialise:

| editstats, 1e6 rows | seconds |
|---|---|
| arrow-backed df, original presort (`[.data.frame`) | 1.36 |
| arrow-backed df, presort fix (skip-if-sorted + `vctrs::vec_slice`) | 1.09 |
| plain R df (table above) | 0.45 |
| Python, pyarrow Table in | 0.46 |

→ Plan item: pass Arrow inputs to C without a data.frame round-trip, and sort in Arrow/duckdb when needed
([plan.md](plan.md)). Raw results: `bench/results/all_altrep_inputs.csv`, `all_before_presort_fix.csv`.
