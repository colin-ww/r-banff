# Golden tests: every upstream sample program call (recorded from Python banff by
# tools/make_fixtures.py) must give identical outputs through the R package.
for (dir in fixture_dirs()) {
  test_that(paste("matches Python banff:", basename(dir)), {
    skip_if_no_binaries()
    f <- replay_fixture(dir)
    expect_s3_class(f$res, "banff_result")
    expect_setequal(setdiff(names(f$res), "log"), f$meta$outputs)
    for (o in f$meta$outputs) {
      expect_equal(as.data.frame(f$res[[o]]), as.data.frame(f$expected[[o]]), tolerance = 1e-12, label = o)
    }
    expect_match(f$res$log, "Banff System")
  })
}
