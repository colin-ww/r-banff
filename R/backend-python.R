# Python backend: R -> reticulate -> Python `banff` -> ctypes -> same C libraries.
# Kept as (a) parity oracle in tests, (b) benchmark baseline, (c) fallback where compiled
# R code cannot be installed. Not the recommended path for users.

.py_cache <- new.env(parent = emptyenv())

py_banff <- function() {
  if (is.null(.py_cache$banff)) {
    # upstream bug: `import banff` crashes when Python's LC_CTYPE is C/POSIX (the case inside
    # an R process with no LANG set): `locale.getlocale()[0]` is None -> AttributeError.
    reticulate::py_run_string(paste(
      "import locale",
      "if locale.getlocale()[0] is None: locale.setlocale(locale.LC_CTYPE, 'C.UTF-8')",
      sep = "\n"
    ))
    .py_cache$banff <- reticulate::import("banff", convert = FALSE)
  }
  .py_cache$banff
}

run_python <- function(proc, spec, inputs, parms, opts, req) {
  bf <- py_banff()
  # pandas, not pyarrow, for outputs: reticulate converts pandas -> data.frame, not pyarrow
  out_spec <- lapply(req, function(r) if (r) "pandas" else FALSE)
  ins <- lapply(inputs, function(x) reticulate::r_to_py(to_arrowable(as.data.frame(x))))
  args <- c(ins, parms, opts, out_spec, list(capture = TRUE))

  res <- tryCatch(
    do.call(bf[[proc]], args),
    error = function(e) stop(structure(class = c("banff_error", "error", "condition"),
                                       list(message = conditionMessage(e), call = NULL, rc = NA_integer_, log = NULL)))
  )
  outputs <- lapply(names(req)[req], function(nm) py_df_to_r(res[[nm]])) |> stats::setNames(names(req)[req])
  new_result(proc, outputs, NULL, "python")
}

# pandas DataFrame (with pyarrow-backed string dtype) -> tibble
py_df_to_r <- function(df) {
  # force plain object/float64 dtypes first; pyarrow-backed dtypes convert badly via reticulate
  df <- df$astype("object")$infer_objects()
  out <- reticulate::py_to_r(df)
  attr(out, "pandas.index") <- NULL
  tibble::as_tibble(out)
}
