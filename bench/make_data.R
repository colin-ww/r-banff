# Synthetic benchmark data (no real data). Writes bench/data/{indata,instatus}_<n>.parquet
set.seed(42)
cases <- jsonlite::read_json("bench/cases.json", simplifyVector = TRUE)
dir.create("bench/data", showWarnings = FALSE)
for (n in cases$sizes) {
  q <- matrix(round(rlnorm(4 * n, 5, 1)), n, dimnames = list(NULL, paste0("Q", 1:4)))
  indata <- data.frame(IDENT = sprintf("R%07d", seq_len(n)), PROV = sample(sprintf("%02d", 10:19), n, TRUE),
                       STAFF = round(rlnorm(n, 3, 1)), q, TOTAL = rowSums(q))
  bad <- sample(n, n %/% 10)                      # 10% inconsistent TOTAL
  indata$TOTAL[bad] <- round(indata$TOTAL[bad] * runif(length(bad), 0.5, 1.5))
  instatus <- data.frame(IDENT = indata$IDENT[bad], FIELDID = sample(paste0("Q", 1:4), length(bad), TRUE), STATUS = "FTI")
  arrow::write_parquet(indata, sprintf("bench/data/indata_%d.parquet", n))
  arrow::write_parquet(instatus, sprintf("bench/data/instatus_%d.parquet", n))
}
