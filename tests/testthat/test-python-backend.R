test_that("python backend (reticulate) agrees with C backend", {
  skip_if_no_binaries()
  require_or_skip(has_py_banff(), "BANFF_REQUIRE_PYTHON", "Python banff not available (set RETICULATE_PYTHON)")
  for (dir in fixture_dirs()[basename(fixture_dirs()) %in% c("DonorImp01-1", "Estimator01-1", "outlier03-1")]) {
    f_c <- replay_fixture(dir)
    f_py <- withr::with_options(list(banff.backend = "python"), replay_fixture(dir))
    for (o in f_c$meta$outputs) expect_equal(as.data.frame(f_py$res[[o]]), as.data.frame(f_c$res[[o]]), label = paste(basename(dir), o))
  }
})
