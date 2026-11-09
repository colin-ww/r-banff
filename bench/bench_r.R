# Time the R paths on the same cases/data. Needs: bench/data (make_data.R), python.csv (bench_python.py)
#   1. r-banff, C backend             (R -> C, no Python)
#   2. r-banff, python backend        (R -> reticulate -> Python banff, Arrow bridge)
#   3. DIY reticulate                 (what users do today: r_to_py(data.frame) -> pandas, pandas outputs)
# Env vars: BENCH_PATHS=c,python,diy (subset to run)  BENCH_OUT=bench/results/all.csv
library(banff)
options(banff.quiet = TRUE)
only <- strsplit(Sys.getenv("BENCH_PATHS", "c,python,diy"), ",")[[1]]
out_file <- Sys.getenv("BENCH_OUT", "bench/results/all.csv")
cfg <- jsonlite::read_json("bench/cases.json", simplifyVector = FALSE)
py_banff <- if (any(c("python", "diy") %in% only)) banff:::py_banff()
time_it <- function(f) median(vapply(seq_len(cfg$reps), function(i) system.time(f())[["elapsed"]], numeric(1)))

diy <- function(proc, ins, params) {
  bf <- py_banff
  outs <- banff:::.banff_specs[[proc]]$outputs
  res <- do.call(bf[[proc]], c(lapply(ins, reticulate::r_to_py), params, capture = NA,
                               stats::setNames(as.list(rep("pandas", length(outs))), outs)))
  lapply(outs, function(o) reticulate::py_to_r(res[[o]]))
}

rows <- list()
for (n in unlist(cfg$sizes)) {
  # plain in-memory R data.frames (materialise arrow's lazy ALTREP columns, like data built/joined in R).
  # Python gets native pyarrow Tables, so this is the like-for-like "native object" comparison.
  materialise <- function(df) { df[] <- lapply(df, function(v) v[seq_along(v)]); df }
  data <- list(indata = materialise(as.data.frame(arrow::read_parquet(sprintf("bench/data/indata_%d.parquet", n)))),
               instatus = materialise(as.data.frame(arrow::read_parquet(sprintf("bench/data/instatus_%d.parquet", n)))))
  for (c in cfg$cases) {
    ins <- data[unlist(c$inputs)]
    run <- function(backend) withr::with_options(list(banff.backend = backend),
                                                 do.call(getExportedValue("banff", c$proc), c(ins, c$params)))
    paths <- list(c = list("r-banff (C backend)", function() run("c")),
                  python = list("r-banff (python backend)", function() run("python")),
                  diy = list("DIY reticulate (pandas)", function() diy(c$proc, ins, c$params)))
    for (p in paths[only]) {
      t <- tryCatch(time_it(p[[2]]), error = function(e) { message(p[[1]], ": ", conditionMessage(e)); NA_real_ })
      rows[[length(rows) + 1]] <- data.frame(case = c$name, n = n, path = p[[1]], median_s = t)
      message(c$name, " n=", n, " ", p[[1]], ": ", signif(t, 3), "s")
    }
  }
}
res <- do.call(rbind, rows)
if (file.exists(out_file)) {  # replace only the rows we re-ran
  old <- read.csv(out_file)
  res <- rbind(old[!paste(old$case, old$n, old$path) %in% paste(res$case, res$n, res$path), ], res)
} else res <- rbind(res, read.csv("bench/results/python.csv"))
write.csv(res, out_file, row.names = FALSE)
