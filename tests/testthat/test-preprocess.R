# Pure-R re-implementations of the Python-only preprocessing (no binaries needed)

test_that("collapse_parms joins vectors like Banff expects", {
  p <- banff:::collapse_parms(list(edits = c("a>0", "b>0;"), by = c("prov", "naics"), unit_id = "id", n = 1))
  expect_identical(p$edits, "a>0; b>0;")
  expect_identical(p$by, "prov naics")
  expect_identical(p$unit_id, "id")
  expect_identical(p$n, 1)
})

test_that("requested_outputs: mandatory always, optional per arg/default, verify disables all", {
  s <- banff:::.banff_specs$donorimp
  r <- banff:::requested_outputs(s, list(outmatching_fields = FALSE))
  expect_identical(unname(r), c(TRUE, TRUE, TRUE, FALSE))
  s <- banff:::.banff_specs$estimato
  expect_true(all(banff:::requested_outputs(s, list())))
  expect_false(any(banff:::requested_outputs(s, list(verify_specs = TRUE))))
})

test_that("sort_by_vars is case-insensitive, stable, C-locale", {
  d <- data.frame(PROV = c("b", "a", "B", "a"), k = 1:4)
  out <- banff:::sort_by_vars(d, "prov")
  expect_identical(out$k, c(3L, 2L, 4L, 1L))  # "B" < "a" < "b" bytewise; ties keep order
  expect_identical(banff:::sort_by_vars(d, "missing_var"), d)
})

test_that("prefill_by_vars adds BY vars to status, keeps only key/FIELDID/STATUS", {
  st <- data.frame(Ident = c("r1", "r2"), FieldID = c("q1", "q2"), status = "FTI", extra = 1)
  dat <- data.frame(IDENT = c("r2", "r1"), prov = c(10, 11))
  out <- banff:::prefill_by_vars(st, dat, "ident", "PROV")
  expect_setequal(names(out), c("Ident", "FieldID", "status", "prov"))
  expect_identical(out$prov[match(c("r1", "r2"), out$Ident)], c(11, 10))
  expect_warning(expect_null(banff:::prefill_by_vars(st, dat, "nope", "prov")))
})

test_that("exclude_where_* uses SQL via duckdb (flag vs drop)", {
  skip_if_not_installed("duckdb")
  d <- data.frame(id = 1:4, total = c(10, 2000, NA, 5))
  expect_identical(banff:::sql_flag(d, "total > 1000"), c(NA, "E", NA, NA))
  expect_identical(banff:::sql_drop_rows(d, "total > 1000")$id, c(1L, 3L, 4L))
})

test_that("unique_name avoids clashing with existing column (case-insensitive)", {
  expect_identical(banff:::unique_name("_exclude", c("a", "b")), "_exclude")
  expect_match(banff:::unique_name("_exclude", c("_EXCLUDE")), "^_exclude_\\d{4}$")
})
