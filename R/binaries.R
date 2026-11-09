#' Install / locate the Banff C shared libraries
#'
#' The C backend calls the official, unmodified Banff procedure libraries (`libdonorimp_en.so`,
#' `donorimp_en.dll`, ...). They ship inside the Python wheel, which is a plain zip file, so we
#' download the wheel from a PyPI-compatible "simple" index (pypi.org, or an Artifactory PyPI
#' mirror) and extract only the binaries. **No Python is needed.**
#'
#' Lookup order for the library folder: `options(banff.lib_dir)`, env var `BANFF_LIB_DIR`,
#' then `tools::R_user_dir("banff", "data")/<version>/<platform>`. To reuse a pip-installed banff,
#' point `banff.lib_dir` at `<site-packages>/banff/proc/bin/<linux|windows>/x64`.
#'
#' @param version Banff version (PyPI version string).
#' @param index Simple-index base URL. For Artifactory use something like
#'   `https://artifactory.example/artifactory/api/pypi/pypi-remote/simple`.
#' @param dest Destination folder.
#' @return Path of the folder holding the libraries (invisibly).
#' @export
banff_install_binaries <- function(version = banff_default_version(),
                                   index = getOption("banff.pypi_index", "https://pypi.org/simple"),
                                   dest = banff_lib_dir(version)) {
  plat <- banff_platform()
  tag <- c(linux = "manylinux[^\"#]*x86_64", windows = "win_amd64")[[plat]]
  page <- paste(readLines(paste0(sub("/$", "", index), "/banff/"), warn = FALSE), collapse = "\n")
  hrefs <- regmatches(page, gregexpr("href=\"[^\"]+\"", page))[[1]] |> gsub(pattern = "^href=\"|\"$", replacement = "")
  pat <- sprintf("banff-%s-py3-none-%s\\.whl", gsub(".", "\\.", version, fixed = TRUE), tag)
  url <- hrefs[grepl(pat, hrefs)][1]
  if (is.na(url)) stop("No banff ", version, " wheel for ", plat, " found at ", index, call. = FALSE)
  if (!grepl("^https?://", url)) url <- paste0(sub("/$", "", index), "/banff/", url)  # relative link

  whl <- tempfile(fileext = ".whl")
  old <- options(timeout = max(600, getOption("timeout")))
  on.exit({ unlink(whl); options(old) })
  utils::download.file(sub("#.*$", "", url), whl, mode = "wb", quiet = TRUE)
  check_sha256(whl, sub("^.*#sha256=", "", url))

  libs <- grep("^banff/proc/bin/.*\\.(so|dll)$", utils::unzip(whl, list = TRUE)$Name, value = TRUE)
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  utils::unzip(whl, files = libs, exdir = dest, junkpaths = TRUE)
  message("Installed ", length(libs), " Banff ", version, " libraries to ", dest)
  invisible(dest)
}

#' @rdname banff_install_binaries
#' @export
banff_lib_dir <- function(version = banff_default_version()) {
  getOption("banff.lib_dir", Sys.getenv("BANFF_LIB_DIR", file.path(tools::R_user_dir("banff", "data"), version, banff_platform())))
}

#' Banff version this R package was generated against
#' @keywords internal
banff_default_version <- function() "3.1.3"

banff_platform <- function() {
  if (.Platform$OS.type == "windows") return("windows")
  if (Sys.info()[["sysname"]] == "Linux" && R.version$arch == "x86_64") return("linux")
  stop("Banff binaries exist only for Linux x86_64 and Windows x64", call. = FALSE)
}

check_sha256 <- function(path, expected) {
  if (!nzchar(expected) || grepl("/", expected)) return(invisible())
  got <- if (requireNamespace("openssl", quietly = TRUE)) {
    as.character(openssl::sha256(file(path)))
  } else if (requireNamespace("digest", quietly = TRUE)) {
    digest::digest(path, "sha256", file = TRUE)
  } else return(invisible())
  if (!isTRUE(tolower(as.vector(got)) == tolower(expected))) stop("sha256 mismatch for downloaded wheel", call. = FALSE)
}

#' Language of the Banff log ("en" or "fr")
#'
#' `options(banff.language = "fr")` switches to the French build of the procedures.
#' @keywords internal
banff_language <- function() {
  lang <- getOption("banff.language")
  if (is.null(lang)) lang <- if (grepl("^fr", Sys.getlocale("LC_MESSAGES"), ignore.case = TRUE)) "fr" else "en"
  match.arg(lang, c("en", "fr"))
}

.banff_cache <- new.env(parent = emptyenv())

# load (once per session) a procedure's library and look up its entry points
banff_symbols <- function(proc, lang = banff_language()) {
  key <- paste0(proc, "_", lang)
  if (is.null(.banff_cache[[key]])) {
    dir <- banff_lib_dir()
    file <- paste0(if (banff_platform() == "linux") "lib", key, .Platform$dynlib.ext)
    path <- file.path(dir, file)
    if (!file.exists(path)) {
      stop("Banff library not found: ", path, "\nRun `banff::banff_install_binaries()` first, ",
           "or set `options(banff.lib_dir = ...)`.", call. = FALSE)
    }
    dll <- dyn.load(path, local = TRUE, now = TRUE)
    .banff_cache[[key]] <- list(
      fn = getNativeSymbolInfo(proc, dll)$address,
      flush = getNativeSymbolInfo("flush_std_buffers", dll)$address,
      rc_desc = getNativeSymbolInfo("get_rc_description", dll)$address
    )
  }
  .banff_cache[[key]]
}

rc_description <- function(sym, rc) .Call(rbanff_rc_desc, sym$rc_desc, as.integer(rc))
