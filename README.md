# banff (R)

R interface to [Banff](https://github.com/StatCan/gensol-banff), Statistics Canada's procedures for
statistical data editing and imputation.

> **Status: prototype / feasibility spike.** Not an official StatCan product. Results come from the official Banff C
> libraries, unmodified.

It calls the **same C libraries the Python `banff` package uses**, directly from R. There's no Python, no reticulate
and no pandas involved.

- Output is identical to Python banff on all upstream sample programs (all 9 procedures). See `tests/`.
- Install is ~30 MB, against ~340 MB for a Python banff environment.
- Speed is on par with Python banff and 2–10× faster than calling Python banff via reticulate yourself. The C log shows up in RStudio.

## Install (prototype)

```r
# install.packages("remotes")
remotes::install_github("colin-ww/r-banff")    # needs a C compiler (tiny shim)
banff::banff_install_binaries()                # once: fetches the official wheel from PyPI and extracts the .so/.dll
# behind Artifactory:
# options(banff.pypi_index = "https://<artifactory>/artifactory/api/pypi/<pypi-remote>/simple")
```

## Use

```r
library(banff)

res <- indata |>
  donorimp(instatus = instatus, unit_id = "IDENT", by = "PROV",
           edits = "Q1 + Q2 + Q3 + Q4 - TOTAL = 0", post_edits = "Q1 + Q2 + Q3 + Q4 - TOTAL <= 0",
           min_donors = 1, percent_donors = 1, n = 1, seed = 1)

res              # <banff_result: donorimp> + dims of each output
res$outdata      # tibbles, same names as Python (`banff_call.outdata`)
res$outstatus
res$log          # C log, also echoed via message() unless options(banff.quiet = TRUE)
```

- All 9 procedures are available, under Python's names and aliases: `verifyedits`, `editstats`, `outlier`, `errorloc`,
  `deterministic`, `donorimp`, `estimator`, `prorate`, `massimp`.
- Arguments and docs mirror Python (`?donorimp`). Upstream guides: <https://statcan.github.io/gensol-banff/>.
- Vectors are fine: `edits = c("Q1 >= 0", "Q2 >= 0")`, `by = c("PROV", "NAICS")`.
- Misspelled parameters are an error. Banff's C code would silently ignore them.

## Design docs

| | |
|---|---|
| [design/feasibility.md](design/feasibility.md) | findings, options (reticulate / bash / direct C / port), recommendation |
| [design/spec.md](design/spec.md) | API spec, Python → R mapping |
| [design/decisions.md](design/decisions.md) | decision log |
| [design/plan.md](design/plan.md) | phases, open questions, risks |
| [design/benchmarks.md](design/benchmarks.md) | R vs Python performance |
| [design/upstream-issues.md](design/upstream-issues.md) | draft issues for gensol-banff |

## Dev workflow

```sh
# regenerate wrappers/docs after an upstream release (reads upstream source; no import)
python3 tools/gen_procs.py <gensol-banff>/Python/src/banff/proc --version 3.1.3
Rscript -e 'roxygen2::roxygenise()'
# re-record golden fixtures (needs Python banff)
(cd <gensol-banff>/Python/sample_programs/conversion_examples && python <r-banff>/tools/make_fixtures.py .)
Rscript -e 'devtools::test()'
# benchmarks
Rscript bench/make_data.R && python bench/bench_python.py && Rscript bench/bench_r.R
```

`R/procs-generated.R` is generated. Don't hand-edit it. `src/shim.c` is hand-maintained: its `CALL_1..CALL_32` dispatch macros are mechanical, one per argument count.

## License

GPL (>= 3), same as Banff.
