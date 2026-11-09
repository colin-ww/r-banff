# Upstream issue drafts

**Single source of truth:** GitHub issues in private repo
[`colin-ww/sc-banff`](https://github.com/colin-ww/sc-banff/issues?q=label%3Aupstream-draft), label `upstream-draft`.
That's the same convention earlier sessions used (conda-forge, docs audit). They stay private until reported to the Banff team.

The drafts below came from building this package. They're filed there and checked against 3.1.3 (PyPI) and 3.2.0 (Zone image wheel):

| sc-banff | Draft | Status in 3.2.0 |
|---|---|---|
| [#17](https://github.com/colin-ww/sc-banff/issues/17) (existing) | `import banff` crashes under C/POSIX locale | **fixed** in 3.2.0; 3.1.3 only. Workaround in `R/backend-python.R` |
| [#21](https://github.com/colin-ww/sc-banff/issues/21) | C silently ignores unknown parameter names | still present. R guards it (`check_unknown()`) |
| [#22](https://github.com/colin-ww/sc-banff/issues/22) | `exclude_where_indata` silently overrides `data_excl_var` | still present (mirrored on purpose in R, D7) |
| [#23](https://github.com/colin-ww/sc-banff/issues/23) | sample programs without `seed` aren't reproducible | still present on upstream `main` |
| [#24](https://github.com/colin-ww/sc-banff/issues/24) | proposal: document the C ABI as a supported interface | n/a |
| [#10](https://github.com/colin-ww/sc-banff/issues/10) (existing) | `ProcedureCError` hides the reason (only on stdout) | related: R captures the log into `$log` and the error |

Not filed:
- **pandas presort may be unstable** (`sort_values` default quicksort). It isn't verified that C output depends on within-group order. Verify first.
- **Integer `NA` becomes `-2147483648` via reticulate.** That's reticulate/numpy, not Banff. See feasibility.md and the earlier
  [`sc-banff` reticulate notes](https://github.com/colin-ww/sc-banff/tree/ccr-aa7a8038-panyro/reticulate).
