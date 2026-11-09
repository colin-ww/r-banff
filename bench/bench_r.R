# Time the R paths on the same cases/data. Needs: bench/data (make_data.R), python.csv (bench_python.py)
#   1. r-banff, C backend             (R -> C, no Python)
#   2. r-banff, python backend        (R -> reticulate -> Python banff, Arrow bridge)
#   3. DIY reticulate                 (what users do today: r_to_py(data.frame) -> pandas, pandas outputs)
library(banff)
options(banff.quiet = TRUE)
cfg <- jsonlite::read_json("bench/cases.json", simplifyVector = FALSE)
py_banff <- banff:::py_banff()
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
  data <- list(indata = as.data.frame(arrow::read_parquet(sprintf("bench/data/indata_%d.parquet", n))),
               instatus = as.data.frame(arrow::read_parquet(sprintf("bench/data/instatus_%d.parquet", n))))
  for (c in cfg$cases) {
    ins <- data[unlist(c$inputs)]
    run <- function(backend) withr::with_options(list(banff.backend = backend),
                                                 do.call(getExportedValue("banff", c$proc), c(ins, c$params)))
    for (p in list(list("r-banff (C backend)", function() run("c")),
                   list("r-banff (python backend)", function() run("python")),
                   list("DIY reticulate (pandas)", function() diy(c$proc, ins, c$params)))) {
      t <- tryCatch(time_it(p[[2]]), error = function(e) { message(p[[1]], ": ", conditionMessage(e)); NA_real_ })
      rows[[length(rows) + 1]] <- data.frame(case = c$name, n = n, path = p[[1]], median_s = t)
      message(c$name, " n=", n, " ", p[[1]], ": ", signif(t, 3), "s")
    }
  }
}
res <- rbind(do.call(rbind, rows), read.csv("bench/results/python.csv"))
write.csv(res, "bench/results/all.csv", row.names = FALSE)
