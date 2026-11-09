# Plan

## Phase 0: feasibility spike ✅ (this session)
- [x] Map the Python → C architecture and ABI
- [x] Generator: R wrappers + docs + ABI table from upstream source
- [x] C shim + loader. Binaries from the PyPI wheel, no Python
- [x] Python backend (reticulate, Arrow bridge) as oracle
- [x] testthat: 15 golden fixtures (all 9 procs) + preprocessing unit tests + error/log/language tests
- [x] Benchmarks vs Python ([benchmarks.md](benchmarks.md))
- [x] Write up feasibility / spec / decisions / upstream issue drafts

## Phase 1: usable internally on The Zone (Linux)
- [ ] Try on RStudio Server in The Zone. Check: compiler present? `R_user_dir` writable? Log shown in console?
- [ ] `banff_install_binaries()` against **Artifactory's PyPI remote** (index URL, auth?, sha256 in links?)
- [x] Perf: presort skips already-sorted data and uses `vctrs::vec_slice` instead of `[.data.frame` (editstats 1e6: 1.36 → 1.09 s on arrow-backed input)
- [ ] Perf: arrow/duckdb inputs are currently converted to data.frame for preprocessing. That forces arrow's lazy ALTREP columns to
      materialise (~0.45 s per 1e6 rows). Instead, pass Arrow objects straight to C when no preprocessing is needed, and sort in
      Arrow (`arrow::arrange()`/duckdb) when it is
- [ ] Version guard. Refuse libraries whose version ≠ the generated spec version, because an ABI mismatch means a segfault.
      Idea: check the binary folder's version, or a known symbol, before calling.
- [ ] Port more upstream tests: `Python/tests/regression_tests` (methodologist-written) → more fixtures
- [ ] `R CMD check` clean (now: tests pass; 1 NOTE = intentional `stdout` fd redirect in shim, CRAN-only concern). GitLab CI: check + tests on every push. Monthly job against the latest upstream
- [ ] Release script: `gen_procs.py` → `roxygenise` → `make_fixtures.py` → `devtools::test()` → bump
- [ ] README tutorial: one SAS-migration example in R (mirror `docs/EN/sas_migration_tutorial.md`)

## Phase 2: Windows + distribution
- [ ] Test the Windows `.dll` path (`_dup2` capture, `.dll` naming)
- [ ] GitLab CI builds **binary R packages** (Linux + Windows) so users don't need Rtools/gcc. Publish to the
      GitLab package registry, or an Artifactory local CRAN repo → `install.packages("banff", repos = ...)`
- [ ] Decide: vendor the libs in the package vs download on first use (D6)
- [ ] Optional `banff.isolate = TRUE`: run the call in `callr::r()` so a C crash can't kill the session

## Phase 3: source build (only if needed)
Needed for: macOS/arm64, CRAN, or if upstream stops publishing wheels.
- [ ] Compile the C sources in `src/` (Makevars over ~240 files: procedures + STC libs + glpk + jansson + nanoarrow)
- [ ] en/fr messages are compile-time (`STC_LANG`), so two builds or a runtime switch
- [ ] Pros: CRAN-grade, no download. Cons: build complexity, keeping up with upstream build changes

## Phase 4: upstream
- [ ] File the issues in [upstream-issues.md](upstream-issues.md) (via fork--sc-banff → StatCan/gensol-banff)
- [ ] Pitch gensol: document the C ABI as a supported interface. An official R package could live upstream
      (e.g. `R/` beside `Python/`), sharing CI

## Phase 5: other gensys systems (G-Confid first)
- [ ] Split the system-agnostic parts into a small core (shim, loader, runner, Arrow bridge): working name `gensysr`
- [ ] `gconfid` R package. Sensitivity via direct C (same ABI pattern). Suppression/Auditing/Rounding are pure Python (PuLP/HiGHS),
      so use reticulate + Arrow bridge, or evaluate a port on CRAN `highs`
- [ ] Generator takes the system name and proc dir, and drops the hard-coded "expect 9 procedures"

## Open questions (need you / others)
1. **G-Confid R wrapper ("SuppressR"/"yoho"?)**: `StatCan/gensol-gconfid` has no R code; nothing on CRAN/GitHub/PyPI either. Is there an internal repo? What did they choose and why?
2. **Name**: `banff` (mirrors Python, implies official) or `rbanff` while unofficial?
3. **Audience**: just your team, or StatCan-wide? This decides how much Phase 2 matters.
4. **Artifactory**: gconfid's README confirms `artifactory.cloud.statcan.ca` hosts PyPI packages (`pypi-local`). Is banff there, and reachable from The Zone? Can R binary packages be published there too?
5. **Compiler on The Zone RStudio image**: is gcc present? If not, Phase 2 binary packages become Phase 1.
6. **gensol relationship**: give them a heads-up early? They may change the C ABI. Better they know an R binding exists.
7. **3.2.1 internal**: is the ABI unchanged vs 3.1.3? Running `gen_procs.py` on 3.2.1 sources and diffing would tell us.

## Risks
| Risk | Likelihood | Impact | Mitigation |
|---|---|---|---|
| Upstream changes the dataset arg order or count | low-med | segfault | generated ABI; version pin + guard; fixtures per release; ask upstream to document it |
| Python-only preprocessing semantics change | low | silent result diffs | re-record fixtures from Python each release |
| C crash kills the R session | low | lost session | same as Python today; optional `callr` isolation |
| Wheel/PyPI not reachable in the air-gapped env | med | can't install | Artifactory remote, or vendor the libs |
| Seen as "unofficial", support questions go to gensol | med | friction | clear README disclaimer; engage gensol early |
