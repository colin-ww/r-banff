# Trust, production use, and paths to "official"

## Same engine, three front-ends

```
Python banff            Python → ctypes ────────────────────────────┐
R → reticulate → Python banff   R → numpy/pandas or Arrow → Python → ctypes ──┤──> same Banff C libraries (.so/.dll)
R banff (this package)  R → Arrow → .Call shim ────────────────────┘
```

The methodology (error localisation, donor search, estimators, LP solver) is **the same compiled code** in all three.
What differs is the glue. That's where the risk sits.

| | Python banff | R via reticulate | R banff (bindings) |
|---|---|---|---|
| Validated by Banff team | **yes** | engine yes, glue no | engine yes, glue no |
| Glue you rely on | theirs (~6k lines) | theirs + reticulate's R↔Python type conversion | ~630 hand-written lines (R + C) + generated wrappers |
| Silent-data risk | low | **real**: integer `NA` → `-2147483648`, logical `NA` → `FALSE` (reticulate #197) unless you use the Arrow bridge or `reticulate.pandas_use_nullable_dtypes = TRUE` | low: Arrow carries NA exactly (tested) |
| Preprocessing (presort, prefill, exclude_where) | official | official | **re-implemented** in R (~60 lines), checked against Python by golden fixtures |
| Install | pip env (pins: pyarrow, nanoarrow; the Zone had to vendor wheels for Python 3.14) | Python env + reticulate config | CRAN/PPM packages (`jsonlite`, `nanoarrow`, `tibble`, `vctrs`) + the official binaries |
| Speed | reference | 2–10× slower on light procs; same on heavy | same as Python |
| "Legit" argument for an audit | "we ran the official package" | "we ran the official package, from R" | "we ran the official binaries; the R glue is tested to give identical outputs" |

**Reticulate does feel more legit**, because more of the code is official. But its extra layer (type conversion) is exactly
where the known silent bugs are. The bindings replace *more* glue with *less* code, and that code can be tested against
Python directly. Thin + tested is the safer bet, *provided* the parity tests are broad and run every release.

## Bar to clear before trusting results in production

Same bar whichever R route you use, because what you're trusting is the glue:

1. **Parity on the upstream suite:** all of `Python/tests/regression_tests` + `unit_tests` (methodologist-written),
   not just the 15 samples. All outputs identical. *(Now: 15 samples, all 9 procs.)*
2. **Parity on your own production inputs:** run your survey's real monthly cycle through Python banff **and** R banff,
   on the same inputs, and diff every output table. One full cycle, ideally two. This is the standard StatCan "parallel run".
3. **Edge cases tested:** NA in every column type, empty by-groups, zero rows, factors, long strings, French mode, errors.
   *(Now: NA int, factors, errors, French, unknown params.)*
4. **Version pinning + CI:** the package refuses or flags libraries of an untested version. CI runs on every change and on
   every new Banff release. *(Now: CI added; version guard planned.)*
5. **Review:** someone other than the author reads the ~630 hand-written lines (R + C shim). The generated part is reviewed
   by reviewing the generator.
6. **Your environment:** Zone RStudio + Windows if anyone uses it.

Steps 1, 3 and 4 are automatable. Step 2 is the one that convinces methodologists. Step 5 is what an endorsement would hinge on.

## Can it break with future Banff releases?

- **Loud breaks (OK):**
  - 3.2.0 removed outlier methods → C errors clearly
  - a dataset-ABI change → the generator diff shows it, and CI fails or segfaults before anyone uses it
- **Silent breaks (the real risk):** Python-only preprocessing semantics change and R keeps the old behaviour.
  Mitigation: re-record golden fixtures from the new Python release. A diff means investigate.
- **History so far:**
  - 3.1.3 → 3.2.0: dataset ABI unchanged
  - 2 parameters added, 1 parameter's values changed
  - about 2 releases a year
  - effort per release: run 2 scripts, read the diff (an hour, not a week)

## Paths to a "stamp of approval"

| Path | What it means | Who maintains | Likelihood |
|---|---|---|---|
| 1. Personal/team tool | GitHub/GitLab, your team uses it | you | ✅ now |
| 2. Internal GitLab + Zone | mirrored to internal GitLab, maybe preinstalled in Zone images like banff | you | high, low friction |
| 3. **Reviewed, not owned** | gensys reviews the code + parity results once (and per release?), links to it from their docs as "community R interface" | you, with their review | **realistic middle ground** |
| 4. Official, separate repo | `StatCan/gensol-banff-r`, released alongside Python | them (or you inside the team) | needs a mandate |
| 5. Official, in-repo | `R/` next to `Python/` in gensol-banff, same CI and release | them | needs a mandate. Cheapest for them once CI covers it |

Notes:
- Precedent: **G-Series is an official StatCan R package on CRAN**, so StatCan does own R packages.
- What an owner will ask: bus factor (who fixes it if you leave), Official Languages (bilingual), security scanning
  (they already run scans on gensol-banff), support channel.
- Your offer to maintain + their review (path 3) answers the bus-factor question only partly. Shared CI (their release
  pipeline also runs the R tests) is what makes path 5 cheap for them later.
- Pitch order: prototype → Zone parallel run with your survey (step 2 above) → show results → ask for review (path 3).
  The ABI documentation ask (sc-banff #24) helps every path.

## Bilingual (Official Languages)

| Piece | Now | Later |
|---|---|---|
| C log/messages | ✅ bilingual: `options(banff.language = "fr")` loads the `_fr` build | – |
| R-side messages (errors, warnings) | English only | wrap them in `gettext()`/`gettextf()` + `po/` (`tools::update_pkg_po()`). Cheap if done early |
| Function docs (`?donorimp`) | English, generated from EN docstrings | Rd has no language switch. Options: FR vignettes, a pkgdown site with an FR section, or link to upstream FR guides |
| Upstream guides | linked (EN) | link FR guides too (`docs/FR/...`) |

**Decision:** wrap new R messages in `gettext()` from now on, so an FR `po/` file can be added without touching code.

## Dependency weight: R vs Python

- **R banff:** 4 small CRAN packages, binary builds on PPM / Artifactory CRAN. Plus 20 MB of official `.so`. No interpreter
  pinning, and versions stay coherent the CRAN way.
- **Python banff:** pins like `pyarrow<19` (3.1.3) and `nanoarrow<0.9` (3.2.0) clash with newer Python. The Zone had to
  vendor internal wheels for Python 3.14 because the public ones pin `pyarrow<19` (see `zone-kubeflow-containers` `vendor/README.md`).
- **reticulate route:** both of the above, plus making R find the right Python.
