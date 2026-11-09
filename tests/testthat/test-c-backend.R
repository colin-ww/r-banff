test_that("all 9 procedures + aliases are exported", {
  procs <- c("determin", "donorimp", "editstat", "errorloc", "estimato", "massimpu", "outlier", "prorate", "verifyed")
  aliases <- c("deterministic", "editstats", "estimator", "massimp", "verifyedits")
  expect_true(all(c(procs, aliases) %in% getNamespaceExports("banff")))
  expect_setequal(names(banff:::.banff_specs), procs)
})

test_that("C errors become banff_error with return code and log", {
  skip_if_no_binaries()
  err <- expect_error(
    withr::with_options(list(banff.quiet = TRUE), verifyedits(edits = "x + y = ; nonsense")),
    class = "banff_error"
  )
  expect_true(err$rc != 0)
  expect_type(err$log, "character")
})

test_that("log is captured, not lost to C stdout; banff.quiet silences it", {
  skip_if_no_binaries()
  expect_message(r <- verifyedits(edits = "x >= 0; y >= 0; x + y <= 10;"), "VERIFYEDITS|Verify|NOTE")
  expect_match(r$log, "NOTE")
  expect_silent(withr::with_options(list(banff.quiet = TRUE), verifyedits(edits = "x >= 0;")))
})

test_that("character vectors are collapsed (edits get ';')", {
  skip_if_no_binaries()
  r <- withr::with_options(list(banff.quiet = TRUE), verifyedits(edits = c("x >= 0", "y >= 0;", "x + y <= 10")))
  expect_match(r$log, "x \\+ y <= 10;|10;")
})

test_that("pipe-first: indata is the first argument", {
  for (p in c("donorimp", "errorloc", "estimato", "outlier", "prorate", "determin", "massimpu", "editstat")) {
    expect_identical(names(formals(getExportedValue("banff", p)))[1], "indata", label = p)
  }
})

test_that("unknown params pass straight through to C (forward compat)", {
  skip_if_no_binaries()
  # C rejects/ignores unknown keys itself; we only check R does not block them
  out <- tryCatch(withr::with_options(list(banff.quiet = TRUE), verifyedits(edits = "x >= 0;", not_a_real_option = 1)),
                  banff_error = function(e) "c-rejected")
  expect_true(inherits(out, "banff_result") || identical(out, "c-rejected"))
})

test_that("French build loads with banff.language = 'fr'", {
  skip_if_no_binaries()
  r <- withr::with_options(list(banff.quiet = TRUE, banff.language = "fr"), verifyedits(edits = "x >= 0;"))
  expect_match(r$log, "Statistique Canada|NOTE|REMARQUE")
})

test_that("factor columns are accepted (converted to character)", {
  skip_if_no_binaries()
  d <- data.frame(id = factor(c("a", "b", "c")), x = c(1, 2, 3), y = c(1, -1, 2))
  r <- withr::with_options(list(banff.quiet = TRUE), editstats(d, edits = "x >= 0; y >= 0;"))
  expect_s3_class(r, "banff_result")
})
