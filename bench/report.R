# bench/results/all.csv -> markdown table (median seconds per call; ratio vs Python banff with pyarrow input)
res <- read.csv("bench/results/all.csv")
paths <- c("python (pyarrow in)", "python (pandas in)", "r-banff (C backend)", "r-banff (python backend)", "DIY reticulate (pandas)")
wide <- reshape(res[res$path %in% paths, ], idvar = c("case", "n"), timevar = "path", direction = "wide")
names(wide) <- sub("^median_s\\.", "", names(wide))
wide <- wide[order(match(wide$case, unique(res$case)), wide$n), c("case", "n", intersect(paths, names(wide)))]
fmt <- function(x, base) ifelse(is.na(x), "–", sprintf("%.3f (%.1fx)", x, x / base))
base <- wide[["python (pyarrow in)"]]
cells <- as.data.frame(lapply(wide[paths], fmt, base = base), check.names = FALSE)
out <- cbind(wide[c("case", "n")], cells)
out$n <- format(out$n, big.mark = ",", scientific = FALSE)
lines <- c(paste("|", paste(names(out), collapse = " | "), "|"),
           paste("|", paste(rep("---", ncol(out)), collapse = " | "), "|"),
           apply(out, 1, function(r) paste("|", paste(trimws(r), collapse = " | "), "|")))
writeLines(lines, "bench/results/table.md")
cat(lines, sep = "\n")
