#' Install / locate the Banff C shared libraries
#'
#' The C backend calls the official, unmodified Banff procedure libraries (`libdonorimp_en.so`,
#' `donorimp_en.dll`, ...). They ship inside the Python wheel, which is a plain zip file, so R
#' extracts them itself. **No Python is needed.**
#'
#' `banff_install_binaries()` takes the wheel from, in order:
#' 1. `wheel =`: a local `.whl` path or a URL (e.g. The Zone's `Sys.glob("/opt/vendor/banff-*.whl")`);
#' 2. a built-in, sha256-pinned URL for this version and platform. For 3.2.0 (Linux), that's StatCan's public
#'    Zone image repo (`StatCan/zone-kubeflow-containers`), since 3.2.0 isn't on PyPI;
#' 3. a PyPI-compatible "simple" index (`index`): pypi.org (3.1.3) or an Artifactory PyPI repo.
#'
#' `banff_lib_dir()` finds the libraries in this order: `options(banff.lib_dir)`, env var `BANFF_LIB_DIR`,
#' `tools::R_user_dir("banff", "data")/<version>/<platform>`, then a **pip-installed banff of the same
#' version**. On The Zone that last one (`/opt/conda/lib/python3.*/site-packages/banff`) means no setup at all.
#'
#' @param version Banff version. Taken from the file name when `wheel` is given.
#' @param index Simple-index base URL. For Artifactory use something like
#'   `https://artifactory.example/artifactory/api/pypi/pypi-remote/simple`.
#' @param dest Destination folder.
#' @param wheel Optional local path or URL of a banff `.whl` file.
#' @return Path of the folder holding the libraries (invisibly).
#' @export
banff_install_binaries <- function(version = banff_default_version(),
                                   index = getOption("banff.pypi_index", "https://pypi.org/simple"),
                                   dest = banff_user_dir(version),
                                   wheel = NULL) {
  plat <- banff_platform()
  sha <- ""
  if (!is.null(wheel)) {
    stopifnot(length(wheel) == 1)
    version <- wheel_version(wheel)
  } else if (!is.null(known <- .banff_wheels[[version]][[plat]])) {
    wheel <- known[["url"]]
    sha <- known[["sha256"]]
  } else {
    wheel <- find_on_index(index, version, plat)
  }
  if (grepl("^https?://", wheel)) {
    if (!nzchar(sha) && grepl("#sha256=", wheel)) sha <- sub("^.*#sha256=", "", wheel)
    tmp <- tempfile(fileext = ".whl")
    old <- options(timeout = max(600, getOption("timeout")))
    on.exit({ unlink(tmp); options(old) })
    utils::download.file(sub("#.*$", "", wheel), tmp, mode = "wb", quiet = TRUE)
    wheel <- tmp
  }
  stopifnot(file.exists(wheel))
  check_sha256(wheel, sha)
  extract_libs(wheel, version, dest)
}

# Wheels not on PyPI, pinned by sha256. URL pinned to a commit of StatCan's public Zone image repo.
.banff_wheels <- list(
  "3.2.0" = list(linux = c(
    url = paste0("https://raw.githubusercontent.com/StatCan/zone-kubeflow-containers/",
                 "1f877f03f8e8e5b8d84a80b25abc04ccd4e0fcee/images/mid/vendor/",
                 "banff-3.2.0-py3-none-manylinux2014_x86_64.manylinux_2_17_x86_64.manylinux_2_28_x86_64.whl"),
    sha256 = "d9d5be2c747082536df7e8f26084d88df9b7a8ca97da227cd942cc9cbd9b604a"
  ))
)

wheel_version <- function(wheel) sub("^banff-([^-]+)-.*$", "\\1", basename(sub("#.*$", "", wheel)))

find_on_index <- function(index, version, plat) {
  tag <- c(linux = "manylinux[^\"#]*x86_64", windows = "win_amd64")[[plat]]
  page <- paste(readLines(paste0(sub("/$", "", index), "/banff/"), warn = FALSE), collapse = "\n")
  hrefs <- regmatches(page, gregexpr("href=\"[^\"]+\"", page))[[1]] |> gsub(pattern = "^href=\"|\"$", replacement = "")
  pat <- sprintf("banff-%s-py3-none-%s\\.whl", gsub(".", "\\.", version, fixed = TRUE), tag)
  url <- hrefs[grepl(pat, hrefs)][1]
  if (is.na(url)) stop("No banff ", version, " wheel for ", plat, " found at ", index, call. = FALSE)
  if (!grepl("^https?://", url)) url <- paste0(sub("/$", "", index), "/banff/", url)  # relative link
  url
}

extract_libs <- function(whl, version, dest) {
  libs <- grep("^banff/proc/bin/.*\\.(so|dll)$", utils::unzip(whl, list = TRUE)$Name, value = TRUE)
  dir.create(dest, recursive = TRUE, showWarnings = FALSE)
  utils::unzip(whl, files = libs, exdir = dest, junkpaths = TRUE)
  message("Installed ", length(libs), " Banff ", version, " libraries to ", dest)
  if (version != banff_default_version()) {
    warning("This package was generated for Banff ", banff_default_version(), ", not ", version, ". ",
            "Use `options(banff.lib_dir = \"", dest, "\")` to select these libraries. Parameters that differ need ",
            "`options(banff.pass_unknown = TRUE)`; see design/feasibility.md (upstream stability).", call. = FALSE)
  }
  invisible(dest)
}

#' @rdname banff_install_binaries
#' @export
banff_lib_dir <- function(version = banff_default_version()) {
  set <- getOption("banff.lib_dir", Sys.getenv("BANFF_LIB_DIR"))
  if (nzchar(set)) return(set)
  user <- banff_user_dir(version)
  if (dir.exists(user)) return(user)
  pip <- find_pip_banff(version)
  if (length(pip)) return(pip[[1]])
  user
}

banff_user_dir <- function(version = banff_default_version()) {
  file.path(tools::R_user_dir("banff", "data"), version, banff_platform())
}

# a pip/conda-installed Python banff of exactly this version (e.g. The Zone images ship one)
find_pip_banff <- function(version) {
  if (banff_platform() != "linux") return(character())
  prefixes <- unique(c(Sys.getenv("CONDA_PREFIX"), "/opt/conda", "/usr/local", "/usr", path.expand("~/.local")))
  sp <- Sys.glob(file.path(prefixes[nzchar(prefixes)], "lib", "python3*", "site-packages"))
  hit <- sp[dir.exists(file.path(sp, sprintf("banff-%s.dist-info", version)))]
  file.path(hit, "banff", "proc", "bin", "linux", "x64")
}

#' Banff version this R package was generated against
#' @keywords internal
banff_default_version <- function() "3.2.0"

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
