# Draft issues for StatCan/gensol-banff

Found while building the R interface (Banff 3.1.3). These are drafts: review them, then file via fork--sc-banff.

## 1. `import banff` crashes when the locale is C/POSIX

**Repro** (any process where Python's `LC_CTYPE` is `C`, e.g. Python embedded in R via reticulate, or k8s/Docker with no `LANG`):
```python
import locale; locale.setlocale(locale.LC_CTYPE, "C")
import banff
# AttributeError: 'NoneType' object has no attribute 'lower'
#   banff/_common/src/nls/nls.py:125  current_locale.lower()
```

**Cause:** `locale.getlocale()` returns `(None, None)` for the C locale. `determine_language()` only catches `IndexError`.

**Fix:** treat `None` as unknown, e.g. `current_locale = (locale.getlocale()[0] or "")`, or also catch `AttributeError`.

**Workaround:** `locale.setlocale(locale.LC_CTYPE, "C.UTF-8")` before importing.

## 2. Unknown parameters are silently ignored by the C procedures

`verifyedits` (and the others) accept unknown JSON keys without a message. Python front-end users are
protected by `_validate_keyword_args`. Any other caller of the C ABI (R, Banff Processor, future front-ends)
isn't: a typo such as `acept_negative` runs and changes results.

**Suggest:** C emits a `WARNING`/`ERROR` for unrecognised keys.

## 3. `exclude_where_indata` silently overrides `data_excl_var` (donorimp, estimator)

`_pp_exclude_where_indata()` sets `c_parms["data_excl_var"]` to the generated `_exclude` column. A
user-given `data_excl_var` is discarded without notice. Same for `exclude_where_indata_hist` / `hist_excl_var`.

**Suggest:** combine the two (exclude if either flag is set), or error when both are given.

## 4. Sample programs without `seed` aren't reproducible

`Estimator01.py`, `Estimator02.py` and `MassImp01.py` produce different output each run (`seed = … (value chosen
by the system)`).

**Suggest:** add `seed=` to the samples (they're used as documentation and as test references), and/or say in
the user guide that omitting `seed` means a time-based seed.

## 5. Request: document the C procedure ABI as a supported interface

The C entry points (`int <proc>(char *json, ArrowArrayStream*…, ArrowSchema*/ArrowArray* …)`, plus
`flush_std_buffers`, `get_rc_description`) are a clean, language-neutral interface. Documenting them would let other front-ends
(R first) bind safely:
- argument order per procedure
- ownership rules
- a version query function (e.g. `const char *banff_version(void)`)
- a stability promise or changelog

Today the only spec is `Python/src/banff/proc/proc_*.py::_call_c_code()`.

## 6. (to verify) presort with pandas input may use an unstable sort

`sort_dataset()` calls `DataFrame.sort_values(by=[...])` with the default `kind="quicksort"`, which isn't
stable. Row order within BY groups could then depend on the input type (pandas vs pyarrow, whose sort *is* stable).
I haven't checked whether C output depends on within-group order. Check before filing.
