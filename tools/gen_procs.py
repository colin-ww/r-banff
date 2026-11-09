#!/usr/bin/env python3
"""Generate R wrappers + docs for the Banff procedures from the upstream Python source.

Single source of truth = upstream `banff/proc/proc_*.py`. This script reads them with `ast`
(no import, so no need to have banff installed) and writes `R/procs-generated.R`:

  * `.banff_specs`  - per procedure: C symbol, ordered input/output datasets (= the C ABI),
                      output flags (mandatory / requested by default), C parameter names
  * one exported R function per procedure (+ aliases), formals mirroring Python,
    roxygen docs copied from the Python docstrings.

Usage (dev only, end users never run this):
    python3 tools/gen_procs.py <path/to/banff/proc>  [--version 3.1.3]
    Rscript -e 'roxygen2::roxygenise()'
"""

import argparse
import ast
import re
import sys
from pathlib import Path

PY_ONLY = {"trace", "capture", "logger"}  # Python logging knobs, replaced by R-side behaviour
R_SIDE_OPTS = ["presort", "prefill_by_vars", "exclude_where_indata", "exclude_where_indata_hist"]
ALIASES = {  # same aliases as `banff/__init__.py`
    "determin": "deterministic",
    "editstat": "editstats",
    "estimato": "estimator",
    "massimpu": "massimp",
    "verifyed": "verifyedits",
}
DOC_URL = "https://github.com/StatCan/gensol-banff/blob/main/docs/EN/Procedure%20Guides/{}.md"
DOC_PAGE = {  # proc short name -> procedure guide file name
    "determin": "deterministic", "donorimp": "donorimp", "editstat": "editstats",
    "errorloc": "errorloc", "estimato": "estimator", "massimpu": "massimp",
    "outlier": "outlier", "prorate": "prorate", "verifyed": "verifyedits",
}


def rd_escape(s: str) -> str:
    """Escape text for roxygen markdown."""
    return s.replace("\\", "\\\\").replace("%", "\\%").replace("{", "\\{").replace("}", "\\}")


def parse_param_docs(docstring: str) -> dict:
    """`:param name: desc` lines -> {name: desc} (continuation lines appended)."""
    out, cur = {}, None
    for line in (docstring or "").splitlines():
        m = re.match(r"\s*:param (\w+):\s*(.*)", line)
        if m:
            cur = m.group(1)
            out[cur] = m.group(2).strip()
        elif re.match(r"\s*:", line) or not line.strip():
            cur = None
        elif cur:
            out[cur] += " " + line.strip()
    return out


def parse_proc(path: Path) -> dict | None:
    tree = ast.parse(path.read_text(encoding="utf-8"))
    cls = next((n for n in tree.body if isinstance(n, ast.ClassDef)), None)
    if cls is None:
        return None
    spec = {"class": cls.name, "doc": ast.get_docstring(cls) or ""}

    for node in cls.body:
        # _proc_name = {"short": ..., "long": ...}
        if isinstance(node, ast.Assign) and getattr(node.targets[0], "id", "") == "_proc_name":
            spec["proc"] = ast.literal_eval(node.value)
        if not isinstance(node, ast.FunctionDef):
            continue
        if node.name == "__init__":
            a = node.args
            spec["init_args"] = [x.arg for x in a.args[1:]]
            spec["param_docs"] = parse_param_docs(ast.get_docstring(node))
            # C parameters: parm_dict["x"] = x
            spec["c_parms"] = [
                n.targets[0].slice.value
                for n in ast.walk(node)
                if isinstance(n, ast.Assign) and isinstance(n.targets[0], ast.Subscript)
                and getattr(n.targets[0].value, "id", "") == "parm_dict"
            ]
            # output dataset flags (skip the all-disabled `verify_*` branch)
            spec["out_flags"] = {}
            for n in ast.walk(node):
                if isinstance(n, ast.Call) and getattr(n.func, "id", "") == "GensysOutputDataset":
                    kw = {k.arg: ast.literal_eval(k.value) for k in n.keywords if isinstance(k.value, ast.Constant)}
                    if kw.get("output_specification") is False:
                        continue
                    spec["out_flags"][n.args[0].value] = {
                        "mandatory": kw.get("mandatory", True),
                        "default": kw.get("requested_by_default", True),
                    }
            # `if verify_x is True:` disables all outputs
            spec["verify_param"] = next(
                (n.test.left.id for n in ast.walk(node)
                 if isinstance(n, ast.If) and isinstance(n.test, ast.Compare)
                 and isinstance(n.test.left, ast.Name) and n.test.left.id.startswith("verify")),
                None,
            )
        if node.name == "_call_c_code":
            ins, outs = [], []
            for n in ast.walk(node):
                if isinstance(n, ast.Attribute) and isinstance(n.value, ast.Attribute):
                    ds = n.value.attr.lstrip("_")
                    if n.attr == "c_arg":
                        ins.append(ds)
                    elif n.attr == "c_schema":
                        outs.append(ds)
            # ast.walk is breadth-first but all attrs are siblings in one Call -> source order kept;
            # sort by line/col to be safe
            def pos(name, attr):
                for n in ast.walk(node):
                    if isinstance(n, ast.Attribute) and n.attr == attr and getattr(n.value, "attr", "") == "_" + name:
                        return (n.lineno, n.col_offset)
                return (0, 0)
            spec["inputs"] = sorted(ins, key=lambda d: pos(d, "c_arg"))
            spec["outputs"] = sorted(outs, key=lambda d: pos(d, "c_schema"))
    return spec if "proc" in spec else None


def r_str(x):
    return "NULL" if x is None else '"' + x + '"'


def r_vec(xs):
    return "character()" if not xs else "c(" + ", ".join(f'"{x}"' for x in xs) + ")"


def r_lgl(xs):
    return "logical()" if not xs else "c(" + ", ".join(f"{k} = {str(v).upper()}" for k, v in xs) + ")"


def gen_r(specs: list, version: str, src: str) -> str:
    out = [
        "# GENERATED by tools/gen_procs.py -- do not edit by hand.",
        f"# Source: {src}",
        f"# Upstream banff version: {version}",
        "",
        "# Per-procedure C ABI + metadata. Order of `inputs`/`outputs` == C argument order.",
        ".banff_specs <- list(",
    ]
    rows = []
    for s in specs:
        p = s["proc"]["short"]
        optional = [(o, s["out_flags"][o]["default"]) for o in s["outputs"] if not s["out_flags"][o]["mandatory"]]
        rows.append(
            f'  {p} = list(\n'
            f'    long = "{s["proc"]["long"]}",\n'
            f'    inputs = {r_vec(s["inputs"])},\n'
            f'    outputs = {r_vec(s["outputs"])},\n'
            f'    optional_default = {r_lgl(optional)},\n'
            f'    c_parms = {r_vec(s["c_parms"])},\n'
            f'    verify_param = {r_str(s["verify_param"])}\n'
            f'  )'
        )
    out.append(",\n".join(rows))
    out += [")", ""]

    for s in specs:
        p, long = s["proc"]["short"], s["proc"]["long"]
        docs = s["param_docs"]
        doc_lines = s["doc"].split("\n\n")
        title = doc_lines[0].strip().rstrip(".")
        inputs = sorted(s["inputs"], key=lambda d: d != "indata")  # indata first -> pipe friendly
        opt_outs = [o for o in s["outputs"] if not s["out_flags"][o]["mandatory"]]
        r_opts = [o for o in R_SIDE_OPTS if o in s["init_args"]]

        formals = [f"{d} = NULL" for d in inputs]
        formals += [f"{c} = NULL" for c in s["c_parms"]]
        formals += [f"{o} = {str(s['out_flags'][o]['default']).upper()}" for o in opt_outs]
        formals += [f"{o} = NULL" for o in r_opts]
        formals += ["..."]

        r = [f"#' {rd_escape(title)}", "#'"]
        for para in doc_lines[1:]:
            r += [f"#' {rd_escape(line.strip())}" for line in para.strip().splitlines()]
            r.append("#'")
        r += [
            f"#' Thin R interface to the Banff *{long}* procedure (C symbol `{p}`). Arguments are",
            "#' passed through unchanged; validation happens in the Banff C code.",
            f"#' Upstream guide: <{DOC_URL.format(DOC_PAGE[p])}>",
            "#'",
        ]
        for d in inputs:
            r.append(f"#' @param {d} Input dataset (data frame, or anything `nanoarrow::as_nanoarrow_array_stream()` accepts). {rd_escape(docs.get(d, ''))}")
        for c in s["c_parms"]:
            r.append(f"#' @param {c} {rd_escape(docs.get(c, ''))}")
        for o in opt_outs:
            r.append(f"#' @param {o} Logical, request optional output. {rd_escape(docs.get(o, ''))}")
        for o in r_opts:
            r.append(f"#' @param {o} {rd_escape(docs.get(o, ''))}")
        r += [
            "#' @param ... Further Banff parameters, passed through as-is (forward compatibility).",
            "#' @return A `banff_result`: named list of output data frames",
            "#'   (" + ", ".join(f"`{o}`" for o in s["outputs"]) + ") plus the procedure `log`.",
            f"#' @seealso [banff_run()]",
            "#' @export",
            f"{p} <- function({', '.join(formals)}) {{",
            f'  banff_run("{p}", as.list(environment()), list(...))',
            "}",
            "",
        ]
        if p in ALIASES:
            r += [f"#' @rdname {p}", "#' @export", f"{ALIASES[p]} <- {p}", ""]
        out += r
    return "\n".join(out)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("proc_dir", type=Path)
    ap.add_argument("--version", default="unknown")
    ap.add_argument("--out", type=Path, default=Path(__file__).resolve().parent.parent / "R" / "procs-generated.R")
    args = ap.parse_args()
    specs = [s for f in sorted(args.proc_dir.glob("proc_*.py")) if (s := parse_proc(f))]
    if len(specs) != 9:
        sys.exit(f"expected 9 procedures, found {len(specs)}: upstream layout changed?")
    args.out.write_text(gen_r(specs, args.version, "banff/proc/proc_*.py"), encoding="utf-8")
    print(f"wrote {args.out} ({len(specs)} procedures)")


if __name__ == "__main__":
    main()
