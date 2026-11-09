has_binaries <- function() file.exists(file.path(banff_lib_dir(), paste0(if (.Platform$OS.type != "windows") "lib", "verifyed_en", .Platform$dynlib.ext)))
# In CI set BANFF_REQUIRE_BINARIES / BANFF_REQUIRE_PYTHON so a missing dependency fails instead of skipping
require_or_skip <- function(ok, env, msg) {
  if (ok) return(invisible())
  if (nzchar(Sys.getenv(env))) fail(paste(msg, "but", env, "is set")) else skip(msg)
}
skip_if_no_binaries <- function() require_or_skip(has_binaries(), "BANFF_REQUIRE_BINARIES", "Banff C libraries not installed (banff_install_binaries())")

has_py_banff <- function() {
  requireNamespace("reticulate", quietly = TRUE) &&
    nzchar(Sys.getenv("RETICULATE_PYTHON")) &&
    !inherits(try(banff:::py_banff(), silent = TRUE), "try-error")
}

read_arrows <- function(path) tibble::as_tibble(as.data.frame(nanoarrow::read_nanoarrow(path)))

fixture_dirs <- function() list.dirs(test_path("fixtures"), recursive = FALSE)

# replay one recorded Python call through the R package
replay_fixture <- function(dir) {
  meta <- jsonlite::read_json(file.path(dir, "meta.json"), simplifyVector = TRUE)
  ins <- list.files(dir, "^in_.*\\.arrows$", full.names = TRUE)
  inputs <- lapply(ins, read_arrows) |> stats::setNames(sub("^in_(.*)\\.arrows$", "\\1", basename(ins)))
  res <- withr::with_options(list(banff.quiet = TRUE), do.call(getExportedValue("banff", meta$proc), c(inputs, meta$params)))
  expected <- lapply(meta$outputs, function(o) read_arrows(file.path(dir, paste0("out_", o, ".arrows")))) |>
    stats::setNames(meta$outputs)
  list(meta = meta, res = res, expected = expected)
}
