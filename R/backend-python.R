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
  # Data crosses R <-> Python as Arrow (C stream interface), NOT via reticulate's
  # data.frame <-> pandas conversion: that path loses types (e.g. an all-NA character column
  # becomes pandas object/None -> pyarrow `null` -> Banff C: "must be character, but it is unknown").
  out_spec <- lapply(req, function(r) if (r) "pyarrow" else FALSE)
  ins <- lapply(inputs, r_to_pyarrow)
  args <- c(ins, parms, opts, out_spec, list(capture = TRUE))

  res <- tryCatch(
    do.call(bf[[proc]], args),
    error = function(e) stop(structure(class = c("banff_error", "error", "condition"),
                                       list(message = conditionMessage(e), call = NULL, rc = NA_integer_, log = NULL)))
  )
  outputs <- lapply(names(req)[req], function(nm) pyarrow_to_r(res[[nm]])) |> stats::setNames(names(req)[req])
  new_result(proc, outputs, NULL, "python")
}

# R -> pyarrow.Table, zero-copy-ish via the Arrow C stream interface (pyarrow takes ownership)
r_to_pyarrow <- function(x) {
  stream <- nanoarrow::as_nanoarrow_array_stream(to_arrowable(x))
  pa <- reticulate::import("pyarrow", convert = FALSE)
  addr <- reticulate::import_builtins(convert = FALSE)$int(nanoarrow::nanoarrow_pointer_addr_chr(stream))
  pa$RecordBatchReader$`_import_from_c`(addr)$read_all()
}

# pyarrow.Table -> tibble, same bridge in reverse
pyarrow_to_r <- function(tbl) {
  pa <- reticulate::import("pyarrow", convert = FALSE)
  dst <- nanoarrow::nanoarrow_allocate_array_stream()
  addr <- reticulate::import_builtins(convert = FALSE)$int(nanoarrow::nanoarrow_pointer_addr_chr(dst))
  pa$RecordBatchReader$from_batches(tbl$schema, tbl$to_batches())$`_export_to_c`(addr)
  tibble::as_tibble(as.data.frame(dst))
}
