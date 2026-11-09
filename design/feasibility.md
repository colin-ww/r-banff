# Feasibility: R interface to Banff

Status: spike done 2026-11-09, against Banff **3.1.3** (PyPI). Verdict: **feasible, low risk, recommended**.

## TL;DR

- Python `banff` is itself only a front-end. The real work is 9 C shared libraries with a clean,
  language-neutral ABI: **JSON string for parameters + Arrow C Data Interface for datasets**.
- So R does not need to wrap Python. R can call the same C libraries directly, as a *sibling* of
  the Python package. That's what the prototype does: no Python, no reticulate, no pandas.
- Spike results:
  - Output **identical to Python banff** on all 15 upstream sample-program calls (all 9 procedures).
  - Install: ~30 MB (official binaries + `nanoarrow` + `jsonlite` + `tibble`) vs ~340 MB Python env.
  - Speed: **on par with Python banff**, 0.8–1.2× of Python+pyarrow at ≥100k rows, and 2–10× faster than DIY reticulate.
    Small calls add ~2–6 ms. Heavy procs are C-bound, so every path ties. Details in [benchmarks.md](benchmarks.md).
  - The C log gets captured into R, so it's visible in RStudio. With Python it goes to C stdout and RStudio never shows it.
- Keep a reticulate backend only as a test oracle / fallback, not as the main path.

## How Python banff works (what we're actually wrapping)

```
banff.donorimp(indata=df, ...)                      Python (banff/proc/*.py, ~5k lines)
  ├─ type checks only ("strict validation happens in C code")
  ├─ load inputs: DataFrame | pyarrow.Table | .parquet/.sas7bdat/.csv/.feather path
  ├─ preprocess: exclude_where_* (duckdb SQL) → prefill_by_vars (join) → presort (by BY vars)
  ├─ pack: params dict → json.dumps ; tables → nanoarrow ArrowArrayStream
  ├─ ctypes call ───────────────► libdonorimp_en.so   C (~164k lines incl. glpk, jansson, nanoarrow)
  │                                 int donorimp(char *json,
  │                                              ArrowArrayStream *indata, *instatus,
  │                                              ArrowSchema*, ArrowArray*  × each output)
  │                                 printf() log → process stdout
  └─ unpack Arrow outputs → pyarrow.Table (default) | pandas | file
```

Facts that make an R binding easy:

- `.so` files depend only on `libc`/`libm` (`ldd`). Everything else is statically linked.
- The wheel is `py3-none-<platform>`, so it isn't tied to any Python ABI. It's just a zip holding the libs.
- C accepts int8–64, float/double, string/large_string. That maps directly onto R int/double/character.
- Parameters travel as JSON, so a new upstream parameter needs **no ABI change**.
- Dataset arguments are positional. Their order is the ABI, and the generator reads it from Python's `_call_c_code()`.
- All 9 procedures share the same pattern, so one generic bridge covers all of them (`src/shim.c`, ~190 lines).

## Options compared

| | A. DIY reticulate (status quo) | B. R pkg over reticulate | C. bash / CLI (`system2("python …")`) | **D. R → C direct (prototype)** | E. Port (rewrite in R) |
|---|---|---|---|---|---|
| What it is | users `import("banff")` themselves | thin R funs calling Python banff | R writes files, runs a Python script, reads results | R calls the same C libs Python calls | reimplement algorithms |
| Python needed | yes (~340 MB env) | yes | yes | **no** | no |
| Install | pip env + reticulate config + locale workaround | same + R pkg | same + script | R pkg (+ tiny C shim) + 9 MB wheel download | R pkg |
| Type fidelity | **poor**: R→pandas loses types (see below) | ok if bridged via Arrow (done in prototype) | ok via parquet | **exact** (Arrow end to end) | n/a |
| C log in RStudio | lost (C stdout) unless `capture=True` | ok (Python reprints) | ok (captured stdout) | **ok** (fd redirect → `$log` + message) | n/a |
| Per-call overhead | ~20–30 ms + pandas copies (2–10× slower than D) | ~5–10 ms | **≥0.5 s** (`import banff`) + file I/O | **~2–6 ms** | n/a |
| Crash isolation | none (segfault kills R) | none | **yes** (separate process) | none (can add via `callr`) | n/a |
| Tracks upstream | automatic | automatic for params | automatic | regenerate per release (scripted) | **never**: forks the methodology |
| Maintenance | none, but every user pays the pain | low | low-med (serialization, errors via exit codes) | low (generated) + ABI watch | huge (LP solver, Chernikova, KD-tree, …) + re-validation |
| Verdict | baseline | fallback/oracle | rejected: slow, still needs Python | **recommended** | rejected |

### Why not just "reticulate yourself into Banff" (A)?

Your experience matches what the spike hit:

- **Type conversion.** An R `data.frame` becomes pandas when it crosses over. An all-NA character column turns into
  object/None. pyarrow then infers type `null`, and the C code fails with
  `Variable 'AUXVARIABLES' … must be character, but it is unknown`. This was reproduced on the
  upstream Estimator01 sample.
- **pyarrow default output.** Results come back as `pyarrow.Table`, which reticulate doesn't convert. You need
  `set_default_output_spec("pandas")` or `$to_pandas()`, and then pandas' Arrow-backed string dtypes convert awkwardly.
  (You noted the same: "needed to use pandas not pyarrow".)
- **Import crash.** Under a C/POSIX locale (an R process with no `LANG` set, bare k8s jobs, `Rscript` in Docker),
  `import banff` dies with `AttributeError: 'NoneType' object has no attribute 'lower'`. See
  [upstream-issues.md](upstream-issues.md#1).
- **Invisible log.** The C log is `printf` to process stdout, which RStudio Server doesn't show.
- **Environment management.** Every user needs pip, a venv/conda and reticulate config. That's 340 MB per environment.

Option B fixes the type issue: the prototype's Python backend moves data R ↔ pyarrow over the Arrow C stream and never touches pandas.
It can't fix the dependency weight.

### Bash / CLI (C)

- Its one real advantage is **process isolation**: a C crash wouldn't take down the RStudio session.
- Cost: ≥0.5 s per call just for `import banff`, files written and read for every dataset, errors parsed
  from stderr, and you still need Python.
- If isolation turns out to matter, D can get it more cheaply: run the call in `callr::r()`
  (planned as an option, see [plan.md](plan.md)).

## Naming: wrapper vs binding vs port

- **Port**: reimplementing the algorithms in R. Example: G-Series SAS → R (`gseries`). *Not this.*
- **Wrapper**: R calls the Python package (options A/B).
- **Binding / interface**: R calls the shared C library directly (option D). Python banff is itself a binding.
- → Call it **"R interface to Banff"** or **"R bindings for the Banff procedures"**. It's a sibling of the Python package,
  not a wrapper of it. Package name `banff`, so calls read `banff::donorimp()`, mirroring Python `banff.donorimp()`.

## Thick vs thin

Thin wins here, with evidence:

- C does all the strict validation. Python's own code says so (`_validate_c_parameters`: "Strict
  validation happens in C code"), and Python itself only checks types.
- Params are JSON, so passing them through is natural. Docs are generated from the Python docstrings (DRY).
- **Exception, found in the spike:** C **silently ignores unknown parameter names**. `acept_negative = TRUE`
  (typo) runs fine and quietly changes results. Python catches this with `TypeError: unexpected keyword`. So the
  R side keeps exactly one check: unknown names error, with a did-you-mean hint, and
  `options(banff.pass_unknown = TRUE)` opts out. It's generated, so it costs nothing to maintain.

"Thin" still isn't "zero logic". These have to exist in R because Python does them, not C:

- the dataset ABI order (generated)
- which outputs are optional and their defaults (generated)
- presort, prefill_by_vars and exclude_where_* (~60 lines, mirrored from Python, unit-tested)
- log capture and error conditions

Sugar, cheap and non-validating:

- character vectors get collapsed (`edits = c("a>0", "b>0")` → `"a>0; b>0;"`, `by = c("prov","naics")`)
- factors → character
- `indata` is the first argument, so pipes work

## Does upstream API stability matter?

Yes, but less than it seems:

| Layer | Stability | Impact on R | Mitigation |
|---|---|---|---|
| Parameter names (JSON keys) | additive so far. One rename since 3.0 (`match_field_stat` → `outmatching_fields`, 3.1.1b12) | new params need a regenerate. Until then they fail the unknown-name check (or use `banff.pass_unknown`) | `tools/gen_procs.py` per release |
| Dataset argument order (C ABI) | internal, undocumented, no stability promise | a mismatch means wrong pointers, so **segfault** | generated from `_call_c_code()`; binaries pinned to the generated version (`banff_lib_dir(version)`); golden tests per release; ask upstream to document the ABI ([upstream-issues.md](upstream-issues.md#5)) |
| Python-only preprocessing semantics | could drift | R mirror could disagree | golden fixtures re-recorded from Python each release catch drift |
| Release cadence | ~2/yr (3.1.1 Jan-2025, 3.1.2/3.1.3 Jun-2025, 3.2.1 internal Aug-2026) | small effort per release | scripted: regenerate → re-record fixtures → test |

## G-Confid precedent (gconfid py → R, "SuppressR"/"yoho"?)

What I looked at: [`StatCan/gensol-gconfid`](https://github.com/StatCan/gensol-gconfid) (public; Python production
release 2026-04-30; on Artifactory `pypi-local`).

- **No R code in that repo.** No `SuppressR` or `yoho` on GitHub, CRAN or PyPI either. If an R wrapper
  exists, it's internal (GitLab). → Open question: link?
- **The same gensys framework as Banff.** `gconfid/_common` is a variant of `banff/_common`: the same
  `GeneralizedProcedure`, loader, JSON + Arrow C ABI and nls code. So the same NoneType locale bug probably applies.
- **But only 1 of its 4 modules is C.**

  | Module | Implementation | R route |
  |---|---|---|
  | Sensitivity | C (`int sensitiv(json, ArrowArrayStream*, 5 × out schema/array)`) | **direct C, same shim/generator as here** |
  | Suppression | pure Python + PuLP/HiGHS LP | reticulate (Arrow bridge), or a port on CRAN `highs` |
  | Auditing | pure Python + LP | same |
  | Optimized rounding | pure Python + LP | same |

- **Implication: generalise.** The shim, loader and runner here are system-agnostic. Only `.banff_specs` and the
  generator's input are Banff-specific. One small shared core (working name `gensysr`) plus generated per-system
  packages (`banff`, `gconfid`, …) would cover every gensys system that has a C engine. Python-only modules fall back to
  the reticulate + Arrow bridge proven here (D11). See plan phase 5.
- Related public precedent: [`gseries`](https://cran.r-project.org/package=gseries) is a *port* (SAS → R, on CRAN).
- Artifactory answer (from the gconfid README): StatCan hosts PyPI packages at
  `artifactory.cloud.statcan.ca` (`pypi-local`). So `banff_install_binaries(index = ".../api/pypi/pypi-local/simple")`
  should work on The Zone, and could fetch internal-only versions such as 3.2.1. Still to verify.

## What the spike proved (reproducible in this repo)

- Download the official wheel with R only (`banff_install_binaries()`), checking sha256 from the simple index.
- `dyn.load` + `.Call` bridge works for all 9 procedures, en + fr builds.
- 15/15 golden fixtures match Python output exactly (`tests/testthat/test-parity-python-fixtures.R`).
- The Python backend gives the same results as the C backend.
- Error path: non-zero C return code → `banff_error` condition carrying `rc` and `log`.
- Not yet tried: Windows (the shim has `#ifdef _WIN32` dup2 code, but it's untested), RStudio Server on The Zone, Artifactory PyPI mirror.
