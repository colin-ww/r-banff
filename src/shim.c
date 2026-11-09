/* Minimal bridge: R -> Banff C procedure (shared library loaded with dyn.load()).
 *
 * Banff C ABI (all procedures, see banff/proc/proc_*.py `_call_c_code`):
 *   int proc(char *json_parms,
 *            struct ArrowArrayStream *in_1, ..., in_k,          (NULL = not given)
 *            struct ArrowSchema *out_sch_1, struct ArrowArray *out_arr_1, ...)  (NULL = not requested)
 * All arguments are pointers, so we dispatch on argument count only.
 *
 * C log output goes to the process' stdout (printf). In RStudio that is invisible, so while the
 * procedure runs we point fd 1 at a temp file and hand the text back to R.
 */
#include <R.h>
#include <Rinternals.h>
#include <R_ext/Rdynload.h>
#include <stdio.h>
#include <stdlib.h>
#ifdef _WIN32
#include <io.h>
#define DUP _dup
#define DUP2 _dup2
#define CLOSE _close
#define FILENO _fileno
#else
#include <unistd.h>
#define DUP dup
#define DUP2 dup2
#define CLOSE close
#define FILENO fileno
#endif

#define MAX_ARGS 32
typedef void *vp;

#define CALL_1 rc = ((int (*)(vp)) f)(a[0])
#define CALL_2 rc = ((int (*)(vp, vp)) f)(a[0], a[1])
#define CALL_3 rc = ((int (*)(vp, vp, vp)) f)(a[0], a[1], a[2])
#define CALL_4 rc = ((int (*)(vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3])
#define CALL_5 rc = ((int (*)(vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4])
#define CALL_6 rc = ((int (*)(vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5])
#define CALL_7 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6])
#define CALL_8 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7])
#define CALL_9 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8])
#define CALL_10 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9])
#define CALL_11 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10])
#define CALL_12 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11])
#define CALL_13 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12])
#define CALL_14 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13])
#define CALL_15 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14])
#define CALL_16 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15])
#define CALL_17 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16])
#define CALL_18 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17])
#define CALL_19 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18])
#define CALL_20 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19])
#define CALL_21 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20])
#define CALL_22 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20], a[21])
#define CALL_23 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20], a[21], a[22])
#define CALL_24 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23])
#define CALL_25 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23], a[24])
#define CALL_26 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23], a[24], a[25])
#define CALL_27 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23], a[24], a[25], a[26])
#define CALL_28 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23], a[24], a[25], a[26], a[27])
#define CALL_29 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23], a[24], a[25], a[26], a[27], a[28])
#define CALL_30 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23], a[24], a[25], a[26], a[27], a[28], a[29])
#define CALL_31 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23], a[24], a[25], a[26], a[27], a[28], a[29], a[30])
#define CALL_32 rc = ((int (*)(vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp, vp)) f)(a[0], a[1], a[2], a[3], a[4], a[5], a[6], a[7], a[8], a[9], a[10], a[11], a[12], a[13], a[14], a[15], a[16], a[17], a[18], a[19], a[20], a[21], a[22], a[23], a[24], a[25], a[26], a[27], a[28], a[29], a[30], a[31])

static void *ptr_or_null(SEXP x) {
  if (x == R_NilValue) return NULL;
  if (TYPEOF(x) != EXTPTRSXP) Rf_error("banff: dataset arguments must be external pointers or NULL");
  return R_ExternalPtrAddr(x);
}

static SEXP read_all(FILE *fp) {
  fflush(fp);
  fseek(fp, 0, SEEK_END);
  long n = ftell(fp);
  rewind(fp);
  if (n <= 0) return Rf_mkString("");
  char *buf = R_alloc((size_t) n + 1, 1);
  size_t got = fread(buf, 1, (size_t) n, fp);
  buf[got] = '\0';
  return Rf_ScalarString(Rf_mkCharLenCE(buf, (int) got, CE_UTF8));
}

/* fn: NativeSymbol address of the procedure; flush: NativeSymbol of `flush_std_buffers`
 * json: character(1); ptrs: list of external pointers / NULL in C argument order
 * capture: logical(1) -> redirect stdout to a temp file and return its contents */
SEXP rbanff_call(SEXP fn, SEXP flush, SEXP json, SEXP ptrs, SEXP capture) {
  DL_FUNC f = R_ExternalPtrAddrFn(fn);
  void (*flush_fn)(void *) = (void (*)(void *)) R_ExternalPtrAddrFn(flush);
  int n = 1 + Rf_length(ptrs);
  if (n > MAX_ARGS) Rf_error("banff: too many arguments (%d)", n);

  void *a[MAX_ARGS] = {0};
  a[0] = (void *) Rf_translateCharUTF8(STRING_ELT(json, 0));
  for (int i = 1; i < n; i++) a[i] = ptr_or_null(VECTOR_ELT(ptrs, i - 1));

  int do_cap = Rf_asLogical(capture) == TRUE;
  FILE *tmp = NULL;
  int saved = -1;
  if (do_cap) {
    fflush(stdout);
    tmp = tmpfile();
    if (tmp == NULL) do_cap = 0;
    else {
      saved = DUP(FILENO(stdout));
      DUP2(FILENO(tmp), FILENO(stdout));
    }
  }

  int rc = -1;
  switch (n) {
    case 1: CALL_1; break;
    case 2: CALL_2; break;
    case 3: CALL_3; break;
    case 4: CALL_4; break;
    case 5: CALL_5; break;
    case 6: CALL_6; break;
    case 7: CALL_7; break;
    case 8: CALL_8; break;
    case 9: CALL_9; break;
    case 10: CALL_10; break;
    case 11: CALL_11; break;
    case 12: CALL_12; break;
    case 13: CALL_13; break;
    case 14: CALL_14; break;
    case 15: CALL_15; break;
    case 16: CALL_16; break;
    case 17: CALL_17; break;
    case 18: CALL_18; break;
    case 19: CALL_19; break;
    case 20: CALL_20; break;
    case 21: CALL_21; break;
    case 22: CALL_22; break;
    case 23: CALL_23; break;
    case 24: CALL_24; break;
    case 25: CALL_25; break;
    case 26: CALL_26; break;
    case 27: CALL_27; break;
    case 28: CALL_28; break;
    case 29: CALL_29; break;
    case 30: CALL_30; break;
    case 31: CALL_31; break;
    case 32: CALL_32; break;
  }

  if (flush_fn) flush_fn(NULL);
  fflush(stdout);
  SEXP log = R_NilValue;
  if (do_cap) {
    DUP2(saved, FILENO(stdout));
    CLOSE(saved);
    log = read_all(tmp);
    fclose(tmp);
  }
  PROTECT(log);
  SEXP out = PROTECT(Rf_allocVector(VECSXP, 2));
  SET_VECTOR_ELT(out, 0, Rf_ScalarInteger(rc));
  SET_VECTOR_ELT(out, 1, log);
  SEXP nms = PROTECT(Rf_allocVector(STRSXP, 2));
  SET_STRING_ELT(nms, 0, Rf_mkChar("rc"));
  SET_STRING_ELT(nms, 1, Rf_mkChar("log"));
  Rf_setAttrib(out, R_NamesSymbol, nms);
  UNPROTECT(3);
  return out;
}

/* const char *get_rc_description(int rc) */
SEXP rbanff_rc_desc(SEXP fn, SEXP rc) {
  const char *(*f)(int) = (const char *(*)(int)) R_ExternalPtrAddrFn(fn);
  const char *s = f ? f(Rf_asInteger(rc)) : NULL;
  return Rf_mkString(s ? s : "<no description>");
}

static const R_CallMethodDef CallEntries[] = {
  {"rbanff_call", (DL_FUNC) &rbanff_call, 5},
  {"rbanff_rc_desc", (DL_FUNC) &rbanff_rc_desc, 2},
  {NULL, NULL, 0}
};

void R_init_banff(DllInfo *dll) {
  R_registerRoutines(dll, NULL, CallEntries, NULL, NULL);
  R_useDynamicSymbols(dll, FALSE);
}
