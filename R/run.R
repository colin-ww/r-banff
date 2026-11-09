#' Run a Banff procedure (engine behind every exported procedure function)
#'
#' Users normally call [donorimp()], [errorloc()], etc. Those generated wrappers forward their
#' arguments here unchanged.
#'
#' Backend is chosen with `options(banff.backend = )`:
#' * `"c"` (default): call the Banff C procedure directly (no Python). Needs the shared libraries,
#'   see [banff_install_binaries()].
#' * `"python"`: call the Python `banff` package through reticulate (reference / fallback).
#'
#' @param proc Procedure short name, e.g. `"donorimp"`.
#' @param args Named list of the wrapper's formal arguments.
#' @param dots Extra parameters. Banff's C code silently *ignores* unknown parameter names, so a
#'   typo (`acept_negative = TRUE`) would change results without any message. Unknown names are
#'   therefore an error, unless `options(banff.pass_unknown = TRUE)` (e.g. to use a parameter
#'   added in a newer Banff release than this package was generated for).
#' @return A `banff_result`.
#' @export
banff_run <- function(proc, args, dots = list()) {
  spec <- .banff_specs[[proc]]
  check_unknown(names(dots), c(spec$c_parms, names(args)))
  backend <- getOption("banff.backend", "c")
  req <- requested_outputs(spec, args)
  parms <- c(args[spec$c_parms], dots) |> compact() |> collapse_parms()
  opts <- args[intersect(names(args), .r_side_opts)] |> compact()
  inputs <- args[spec$inputs] |> compact()

  switch(backend,
    c = run_c(proc, spec, inputs, parms, opts, req),
    python = run_python(proc, spec, inputs, parms, opts, req),
    stop("unknown `banff.backend`: ", backend, call. = FALSE)
  )
}

check_unknown <- function(nms, known) {
  bad <- setdiff(nms, known)
  if (!length(bad) || isTRUE(getOption("banff.pass_unknown", FALSE))) return(invisible())
  hint <- vapply(bad, function(b) {
    m <- agrep(b, known, max.distance = 2, value = TRUE)
    if (length(m)) sprintf("`%s` (did you mean `%s`?)", b, m[1]) else sprintf("`%s`", b)
  }, character(1))
  stop("Unknown Banff parameter(s): ", paste(hint, collapse = ", "),
       "\nBanff's C code ignores unknown names silently. Set `options(banff.pass_unknown = TRUE)` ",
       "to pass them anyway.", call. = FALSE)
}

.r_side_opts <- c("presort", "prefill_by_vars", "exclude_where_indata", "exclude_where_indata_hist")

compact <- function(x) x[!vapply(x, is.null, logical(1))]

# character vectors -> the single string Banff expects ("a b c" / "e1; e2;")
collapse_parms <- function(parms) {
  parms[] <- Map(function(x, nm) {
    if (!is.character(x) || length(x) <= 1) return(x)
    if (grepl("edits", nm)) paste0(sub(";\\s*$", "", trimws(x)), ";", collapse = " ")
    else paste(x, collapse = " ")
  }, parms, names(parms))
  parms
}

requested_outputs <- function(spec, args) {
  req <- stats::setNames(rep(TRUE, length(spec$outputs)), spec$outputs)
  opt <- names(spec$optional_default)
  req[opt] <- vapply(opt, function(o) isTRUE(args[[o]] %||% spec$optional_default[[o]]), logical(1))
  if (!is.null(spec$verify_param) && isTRUE(args[[spec$verify_param]])) req[] <- FALSE
  req
}

`%||%` <- function(x, y) if (is.null(x)) y else x

# ---- C backend -------------------------------------------------------------------------------

run_c <- function(proc, spec, inputs, parms, opts, req) {
  pp <- preprocess(proc, inputs, parms, opts)
  json <- jsonlite::toJSON(pp$parms, auto_unbox = TRUE, digits = NA, null = "null") |> enc2utf8()

  in_ptrs <- lapply(spec$inputs, function(nm) {
    x <- pp$inputs[[nm]]
    if (is.null(x)) NULL else nanoarrow::as_nanoarrow_array_stream(to_arrowable(x))
  })
  out <- lapply(spec$outputs, function(nm) {
    if (!req[[nm]]) return(list(NULL, NULL))
    sch <- nanoarrow::nanoarrow_allocate_schema()
    list(sch, nanoarrow::nanoarrow_allocate_array())
  }) |> stats::setNames(spec$outputs)

  sym <- banff_symbols(proc)
  res <- .Call(rbanff_call, sym$fn, sym$flush, json, c(in_ptrs, unlist(out, recursive = FALSE)), TRUE)
  emit_log(res$log)

  if (res$rc != 0L) banff_abort(spec$long, res$rc, rc_description(sym, res$rc), res$log)

  outputs <- lapply(names(out)[req], function(nm) {
    arr <- out[[nm]][[2]]
    nanoarrow::nanoarrow_array_set_schema(arr, out[[nm]][[1]])
    tibble::as_tibble(as.data.frame(arr))
  }) |> stats::setNames(names(out)[req])
  new_result(proc, outputs, res$log, "c")
}

# make an R object Arrow-convertible the way Banff wants it (factors -> character)
to_arrowable <- function(x) {
  if (!is.data.frame(x)) return(x)
  fct <- vapply(x, is.factor, logical(1))
  x[fct] <- lapply(x[fct], as.character)
  x
}

# ---- Python-only preprocessing, re-implemented in R (mirror banff/_common/src/proc/stc_proc.py)

.exclude_rules <- list(  # proc -> option -> c(dataset, parm to set; NA = drop rows instead)
  donorimp = list(exclude_where_indata = c("indata", "data_excl_var")),
  estimato = list(exclude_where_indata = c("indata", "data_excl_var"),
                  exclude_where_indata_hist = c("indata_hist", "hist_excl_var")),
  outlier  = list(exclude_where_indata = c("indata", NA))
)

preprocess <- function(proc, inputs, parms, opts) {
  inputs <- lapply(inputs, function(x) if (is.data.frame(x)) x else as.data.frame(x))

  # exclude_where_* (SQL, evaluated by duckdb like upstream)
  for (opt in intersect(names(opts), names(.exclude_rules[[proc]]))) {
    rule <- .exclude_rules[[proc]][[opt]]
    if (is.null(inputs[[rule[1]]]) || !nzchar(trimws(opts[[opt]]))) next
    if (grepl(";", opts[[opt]], fixed = TRUE)) stop("`", opt, "` cannot contain ';'", call. = FALSE)
    if (is.na(rule[2])) {
      inputs[[rule[1]]] <- sql_drop_rows(inputs[[rule[1]]], opts[[opt]])
    } else {
      col <- unique_name("_exclude", names(inputs[[rule[1]]]))
      inputs[[rule[1]]][[col]] <- sql_flag(inputs[[rule[1]]], opts[[opt]])
      parms[[rule[2]]] <- col
    }
  }

  by <- split_vars(parms$by)
  uid <- parms$unit_id
  pairs <- list(c("instatus", "indata"), c("instatus_hist", "indata_hist"))
  sorted <- character()

  if (opts$prefill_by_vars %||% TRUE && length(by) && length(uid) && nzchar(uid)) {
    for (p in pairs) {
      if (is.null(inputs[[p[1]]]) || is.null(inputs[[p[2]]])) next
      filled <- prefill_by_vars(inputs[[p[1]]], inputs[[p[2]]], uid, by)
      if (!is.null(filled)) {
        inputs[[p[1]]] <- sort_by_vars(filled, by)
        sorted <- c(sorted, p[1])
      }
    }
  }
  if (opts$presort %||% TRUE && length(by)) {
    for (nm in setdiff(intersect(names(inputs), c("indata", "indata_hist", "instatus", "instatus_hist")), sorted)) {
      inputs[[nm]] <- sort_by_vars(inputs[[nm]], by)
    }
  }
  list(inputs = inputs, parms = parms)
}

split_vars <- function(x) if (is.null(x)) character() else strsplit(trimws(x), "\\s+")[[1]]

# case-insensitive column lookup (Banff variable names are case-insensitive)
match_cols <- function(df, vars) names(df)[match(tolower(vars), tolower(names(df)))]

unique_name <- function(nm, existing) {
  if (!tolower(nm) %in% tolower(existing)) return(nm)
  paste0(nm, "_", sample(1000:9999, 1))
}

sort_by_vars <- function(df, by) {
  cols <- match_cols(df, by)
  if (anyNA(cols)) cols <- character()  # upstream: missing BY vars -> sort skipped (C reports issues)
  if (!length(cols)) return(df)
  o <- do.call(order, c(unname(as.list(df[cols])), method = "radix"))  # radix: stable, C-locale like pyarrow
  if (!is.unsorted(o)) return(df)  # already sorted: skip the copy (big win for arrow/ALTREP-backed data)
  vctrs::vec_slice(df, o)          # ~2-8x faster than `[.data.frame`
}

prefill_by_vars <- function(status, data, uid, by) {
  sel_s <- match_cols(status, c(uid, "FIELDID", "STATUS"))
  sel_d <- match_cols(data, c(by, uid))
  if (anyNA(sel_s) || anyNA(sel_d)) {
    warning("Unable to add BY variables to status dataset, proceeding with original dataset", call. = FALSE)
    return(NULL)
  }
  merge(status[sel_s], data[sel_d], by.x = sel_s[1], by.y = sel_d[length(sel_d)], sort = FALSE)
}

sql_query <- function(df, sql) {
  if (!requireNamespace("duckdb", quietly = TRUE)) stop("`exclude_where_*` needs the duckdb package", call. = FALSE)
  con <- DBI::dbConnect(duckdb::duckdb())
  on.exit(DBI::dbDisconnect(con, shutdown = TRUE))
  duckdb::duckdb_register(con, "ds_temp", df)
  DBI::dbGetQuery(con, sql)
}
sql_flag <- function(df, where) sql_query(df, sprintf("SELECT CASE WHEN %s THEN 'E' END AS f FROM ds_temp", where))$f
sql_drop_rows <- function(df, where) {
  keep <- sql_query(df, sprintf("SELECT (%s) IS NOT TRUE AS k FROM ds_temp", where))$k
  df[keep, , drop = FALSE]
}

# ---- results, logging, errors ----------------------------------------------------------------

new_result <- function(proc, outputs, log, backend) {
  structure(c(outputs, list(log = log)), class = "banff_result", proc = proc, backend = backend)
}

#' @export
print.banff_result <- function(x, ...) {
  cat(sprintf("<banff_result: %s (%s backend)>\n", attr(x, "proc"), attr(x, "backend")))
  for (nm in setdiff(names(x), "log")) cat(sprintf("  $%-20s %d x %d\n", nm, nrow(x[[nm]]), ncol(x[[nm]])))
  cat(sprintf("  $%-20s %d lines\n", "log", length(strsplit(x$log %||% "", "\n")[[1]])))
  invisible(x)
}

emit_log <- function(log) {
  if (!isTRUE(getOption("banff.quiet", FALSE)) && !is.null(log) && nzchar(log)) message(log, appendLF = FALSE)
}

banff_abort <- function(long, rc, desc, log) {
  msg <- sprintf("Banff procedure '%s' terminated early: %s (return code %d)", long, desc, rc)
  cond <- structure(class = c("banff_error", "error", "condition"),
                    list(message = msg, call = NULL, rc = rc, log = log))
  stop(cond)
}
