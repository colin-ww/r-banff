# Decision log

Format: decision · why · alternatives rejected · revisit when. Newest last.

### D1. Call the C libraries directly. Python is not the default path
- **Why:** the C ABI is simple and language-neutral (JSON + Arrow C data). This removes ~340 MB of Python deps,
  the pandas type-conversion bugs and the locale crash. Results are identical (15/15 fixtures). Speed is the same or better.
- **Rejected:** reticulate as the main path (heavy, type pain, invisible log). bash/CLI (≥0.5 s per call, still needs Python).
  Porting (forks the methodology, huge validation burden).
- **Revisit if:** upstream moves real logic from C into Python, or declares the C ABI private and starts breaking it.

### D2. Keep a reticulate backend, but only as oracle/fallback
- **Why:** it gives parity tests against the official Python front-end, a benchmark baseline, and a fallback
  where compiled R code can't be installed.
- Data moves over the Arrow C stream (R ↔ pyarrow), **never via pandas** (D11).
- **Revisit:** drop it if nobody uses the fallback. The golden fixtures (D9) already give parity without it.

### D3. Thin wrappers, generated from the upstream Python source
- **Why:** DRY. C does the strict validation. Params are JSON. `tools/gen_procs.py` (Python `ast`, no import needed)
  emits the formals, the docs and the ABI table. Each upstream release means rerunning one script.
- **Rejected:** hand-written wrappers (drift); a pure `...` pass-through (no autocomplete, no docs).

### D4. One check: unknown parameter names error
- **Why:** found in the spike that C silently ignores unknown JSON keys. So a typo changes results with no message.
  Python catches this for its users, so R must too.
- Did-you-mean via `agrep`. Escape hatch: `options(banff.pass_unknown = TRUE)`.
- **Rejected:** any value or type checks (C does those, and better).

### D5. Docs: copied from the Python docstrings, plus a link to the upstream procedure guide
- **Why:** reuse, single source. `@param` text comes verbatim from `:param x:`.
- **Later:** maybe pull the long-form guides (`docs/EN/Procedure Guides/*.md`) into vignettes.

### D6. Binaries come from the official PyPI wheel, not rebuilt
- **Why:** they're the exact binaries StatCan tests and signs. The wheel is a zip (R can unzip it). It's `py3-none`
  (no Python ABI). The libs depend only on libc/libm.
- `banff_install_binaries()` works against pypi.org or an Artifactory PyPI remote. sha256 is verified when
  `openssl`/`digest` is available.
- **Alternatives, for later:** vendor the libs inside the R package (single install, ~10 MB per platform+language; GPL-3 allows it);
  build from source in `src/` (CRAN-grade, ~164k lines incl. glpk; see plan phase 3).

### D7. Python-only preprocessing is re-implemented in R
- `presort`, `prefill_by_vars` and `exclude_where_*` live in Python, not C, so R mirrors them (~60 lines).
- Semantics are copied, including the quirks: prefill keeps only key/FIELDID/STATUS + BY; `exclude_where_indata`
  overrides `data_excl_var`; outlier *drops* rows while donorimp/estimator *flag* them.
- `exclude_where_*` uses duckdb SQL for parity (duckdb in Suggests).

### D8. R-flavoured output: tibbles, pipe-first, `$log`
- **Why:** tidyverse users. `indata |> donorimp(...)` works. The `$name` access mirrors Python's `res.outdata`.
- **Rejected:** returning Arrow objects by default (could become an option later).

### D9. Golden fixtures recorded from upstream sample programs
- `tools/make_fixtures.py` intercepts every `banff.<proc>()` call in `Python/sample_programs/conversion_examples`
  and saves inputs, params and Python's outputs as Arrow IPC.
- R tests replay them. That gives parity without Python at test time. The data is synthetic and public, so it's safe to commit.

### D10. Package name `banff`, repo `r-banff`
- **Why:** `banff::donorimp()` ↔ `banff.donorimp()`, the same mapping as the docs. Precedent: `gseries`.
- **Open:** if it stays unofficial, should it be `rbanff` to avoid implying StatCan ownership?

### D11. Never convert through pandas
- **Why:** reproduced the user-reported pain. An all-NA character column (`AUXVARIABLES`) goes R → pandas → object/None
  → pyarrow `null` → C error "must be character, but it is unknown".
- The Arrow C stream keeps the types.

### D12. Pin a seed in fixtures when a sample omits it
- **Why:** without `seed`, C uses a time-based seed (`seed = 1794196017 (value chosen by the system)`), so
  Estimator01/02 and MassImp01 weren't reproducible. That's not a wrapper bug.
