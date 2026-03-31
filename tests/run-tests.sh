#!/bin/bash
set -eu

# Test suite for portable R builds
# Usage: ./tests/run-tests.sh <PORTABLE_R_DIR>
# Example: ./tests/run-tests.sh portable-r-4.5.3-macos-arm64

# ── Logging ──────────────────────────────────────────────────────────────────

if [ -t 1 ]; then
  BOLD="\033[1m"  DIM="\033[2m"
  RED="\033[31m"  GREEN="\033[32m"  YELLOW="\033[33m"  BLUE="\033[34m"
  RESET="\033[0m"
else
  BOLD="" DIM="" RED="" GREEN="" YELLOW="" BLUE="" RESET=""
fi

PASS=0
FAIL=0
SKIP=0

pass() { echo -e "  ${GREEN}PASS${RESET}  $1"; PASS=$((PASS + 1)); }
fail() { echo -e "  ${RED}FAIL${RESET}  $1"; FAIL=$((FAIL + 1)); }
skip() { echo -e "  ${YELLOW}SKIP${RESET}  $1"; SKIP=$((SKIP + 1)); }
section() { echo -e "\n${BOLD}${BLUE}── $1 ──${RESET}"; }

# ── Setup ────────────────────────────────────────────────────────────────────

R_DIR="${1:?Usage: ./tests/run-tests.sh <PORTABLE_R_DIR>}"

if [ ! -d "$R_DIR" ]; then
  echo "Error: $R_DIR does not exist"
  exit 1
fi

R_DIR="$(cd "$R_DIR" && pwd)"
RSCRIPT="$R_DIR/bin/Rscript"
R="$R_DIR/bin/R"

echo -e "${BOLD}Testing: $R_DIR${RESET}"

# ── 1. Structure ─────────────────────────────────────────────────────────────

section "Directory structure"

for path in \
  bin/R bin/Rscript bin/Rscript.bin bin/exec/R bin/fix-dylibs \
  lib/libR.dylib lib/libRblas.dylib \
  etc/Rprofile.site etc/Makeconf etc/Renviron \
  library modules/internet.so; do
  if [ -e "$R_DIR/$path" ]; then
    pass "$path exists"
  else
    fail "$path missing"
  fi
done

# ── 2. No hardcoded paths in scripts ─────────────────────────────────────────

section "Hardcoded path removal"

for f in bin/R etc/Makeconf etc/Renviron; do
  filepath="$R_DIR/$f"
  [ -f "$filepath" ] || continue
  if grep -q "/Library/Frameworks/R.framework/Versions/" "$filepath" 2>/dev/null; then
    fail "$f still has hardcoded R.framework paths"
  else
    pass "$f: no hardcoded paths"
  fi
done

# ── 3. Dylib references ─────────────────────────────────────────────────────

section "Dylib portability"

# bin/exec/R should use @executable_path, not absolute paths
if otool -L "$R_DIR/bin/exec/R" 2>/dev/null | grep -q "/Library/Frameworks/R.framework"; then
  fail "bin/exec/R: still references R.framework"
else
  pass "bin/exec/R: no R.framework references"
fi

# bin/exec/R should have LC_RPATH
if otool -l "$R_DIR/bin/exec/R" 2>/dev/null | grep -q LC_RPATH; then
  pass "bin/exec/R: has LC_RPATH"
else
  fail "bin/exec/R: missing LC_RPATH"
fi

# modules/*.so should not reference R.framework
MODULE_FAIL=0
for so in "$R_DIR"/modules/*.so; do
  [ -f "$so" ] || continue
  if otool -L "$so" 2>/dev/null | grep -q "/Library/Frameworks/R.framework"; then
    fail "$(basename "$so"): still references R.framework"
    MODULE_FAIL=1
  fi
done
[ "$MODULE_FAIL" -eq 0 ] && pass "modules/*.so: no R.framework references"

# Bundled library/*.so should not reference R.framework
LIB_FAIL=0
for so in $(find "$R_DIR/library" -name "*.so" -type f 2>/dev/null); do
  if otool -L "$so" 2>/dev/null | grep -q "/Library/Frameworks/R.framework"; then
    fail "$(basename "$so"): still references R.framework"
    LIB_FAIL=1
  fi
done
[ "$LIB_FAIL" -eq 0 ] && pass "library/**/*.so: no R.framework references"

# No debug symbol directories
DSYM_COUNT=$(find "$R_DIR/lib" -name "*.dSYM" -type d 2>/dev/null | wc -l | tr -d ' ')
if [ "$DSYM_COUNT" -eq 0 ]; then
  pass "No .dSYM debug symbols in lib/"
else
  fail "$DSYM_COUNT .dSYM directories remain in lib/"
fi

# ── 4. Codesigning ───────────────────────────────────────────────────────────

section "Codesigning"

for bin in bin/exec/R bin/Rscript.bin; do
  filepath="$R_DIR/$bin"
  [ -f "$filepath" ] || continue
  SIG=$(codesign -dvv "$filepath" 2>&1)
  if echo "$SIG" | grep -qE "valid on disk|Signature=adhoc|Authority="; then
    pass "$bin: valid signature"
  else
    fail "$bin: invalid or missing signature"
  fi

  # Check for Developer ID (not ad-hoc) — informational only
  if echo "$SIG" | grep -q "Developer ID Application"; then
    pass "$bin: Developer ID signed"
  else
    skip "$bin: ad-hoc signed (no Developer ID)"
  fi
done

# Check entitlements on bin/exec/R
ENTITLEMENTS=$(codesign -d --entitlements - "$R_DIR/bin/exec/R" 2>&1)
if echo "$ENTITLEMENTS" | grep -q "disable-library-validation"; then
  pass "bin/exec/R: has disable-library-validation entitlement"
else
  skip "bin/exec/R: no disable-library-validation entitlement (ad-hoc signing)"
fi

# ── 5. Basic execution ──────────────────────────────────────────────────────

section "Basic execution"

# Rscript --version
if "$RSCRIPT" --version >/dev/null 2>&1; then
  pass "Rscript --version"
else
  fail "Rscript --version"
fi

# R --version
if "$R" --version >/dev/null 2>&1; then
  pass "R --version"
else
  fail "R --version"
fi

# Code execution
RESULT=$("$RSCRIPT" -e 'cat(R.version.string)' 2>&1) && {
  pass "Code execution: $RESULT"
} || {
  fail "Code execution"
}

# R_HOME resolves correctly
R_HOME_VAL=$("$RSCRIPT" -e 'cat(R.home())' 2>&1)
if [ "$R_HOME_VAL" = "$R_DIR" ]; then
  pass "R_HOME resolves to portable directory"
else
  fail "R_HOME mismatch: expected $R_DIR, got $R_HOME_VAL"
fi

# R_SHARE_DIR resolves correctly
SHARE_VAL=$("$RSCRIPT" -e 'cat(Sys.getenv("R_SHARE_DIR"))' 2>&1)
if [ "$SHARE_VAL" = "$R_DIR/share" ]; then
  pass "R_SHARE_DIR resolves correctly"
else
  fail "R_SHARE_DIR: expected $R_DIR/share, got $SHARE_VAL"
fi

# .libPaths is local
LIB_VAL=$("$RSCRIPT" -e 'cat(.libPaths()[1])' 2>&1)
if [ "$LIB_VAL" = "$R_DIR/library" ]; then
  pass ".libPaths()[1] is local library/"
else
  fail ".libPaths()[1]: expected $R_DIR/library, got $LIB_VAL"
fi

# ── 6. Base packages ────────────────────────────────────────────────────────

section "Base package loading"

for pkg in stats graphics grDevices utils methods; do
  if "$RSCRIPT" -e "library($pkg)" >/dev/null 2>&1; then
    pass "library($pkg)"
  else
    fail "library($pkg)"
  fi
done

# ── 7. Capabilities ─────────────────────────────────────────────────────────

section "R capabilities"

for cap in http/ftp sockets libcurl; do
  RESULT=$("$RSCRIPT" -e "cat(capabilities('$cap'))" 2>&1)
  if [ "$RESULT" = "TRUE" ]; then
    pass "capabilities('$cap')"
  else
    fail "capabilities('$cap') = $RESULT"
  fi
done

# ── 8. Internet / download ──────────────────────────────────────────────────

section "Internet connectivity"

if "$RSCRIPT" -e '
  u <- url("https://cloud.r-project.org/")
  on.exit(close(u))
  r <- readLines(u, n = 1, warn = FALSE)
  if (nchar(r) > 0) quit(status = 0) else quit(status = 1)
' >/dev/null 2>&1; then
  pass "HTTPS connection to CRAN"
else
  fail "HTTPS connection to CRAN"
fi

# ── 9. Numeric / BLAS ───────────────────────────────────────────────────────

section "Numeric computation"

if "$RSCRIPT" -e '
  stopifnot(identical(sum(1:100), 5050L))
  stopifnot(all.equal(mean(1:10), 5.5))
  stopifnot(all.equal(as.numeric(crossprod(1:5)), 55))
  m <- matrix(c(1,2,3,4), 2, 2)
  stopifnot(all.equal(det(m), -2))
  cat("ok")
' 2>&1 | grep -q "ok"; then
  pass "Arithmetic, BLAS, and linear algebra"
else
  fail "Numeric computation"
fi

# ── 10. .portable environment ────────────────────────────────────────────────

section "Portable R environment"

# .portable should be on the search path
if "$RSCRIPT" -e 'stopifnot(".portable" %in% search()); cat("ok")' 2>&1 | grep -q "ok"; then
  pass ".portable on search path"
else
  fail ".portable not on search path"
fi

# .portable$install.packages should mask utils::install.packages
INSTALL_FROM=$("$RSCRIPT" -e '
  e <- environment(install.packages)
  nm <- environmentName(e)
  if (nchar(nm) == 0) nm <- "<anon>"
  cat(nm)
' 2>&1)
if [ "$INSTALL_FROM" != "utils" ]; then
  pass "install.packages masked by .portable (from: $INSTALL_FROM)"
else
  fail "install.packages resolves from utils (not masked)"
fi

# ── 11. Binary package install ───────────────────────────────────────────────

section "Binary package install"

# Install jsonlite (has compiled C code) and use it in a single call
if "$RSCRIPT" -e '
  install.packages("jsonlite", quiet = TRUE)
  library(jsonlite)
  result <- toJSON(list(test = TRUE, version = R.version.string), auto_unbox = TRUE)
  stopifnot(grepl("test", result))
  cat("ok")
' 2>&1 | grep -q "ok"; then
  pass "install + load + use jsonlite (single call)"
else
  fail "jsonlite binary package"
fi

# Verify the .so was patched (no R.framework references)
JSONLITE_SO="$R_DIR/library/jsonlite/libs/jsonlite.so"
if [ -f "$JSONLITE_SO" ]; then
  if otool -L "$JSONLITE_SO" 2>/dev/null | grep -q "/Library/Frameworks/R.framework"; then
    fail "jsonlite.so still has R.framework references after install"
  else
    pass "jsonlite.so patched correctly"
  fi
else
  skip "jsonlite.so not found (may have installed from source)"
fi

# ── 12. Source package install ───────────────────────────────────────────────

section "Source package install"

if "$RSCRIPT" -e '
  install.packages("glue", type = "source", quiet = TRUE)
  library(glue)
  result <- glue("R {R.version.string}")
  stopifnot(grepl("R version", result))
  cat("ok")
' 2>&1 | grep -q "ok"; then
  pass "install + load + use glue (from source)"
else
  fail "glue source package"
fi

# ── 13. Makeconf ─────────────────────────────────────────────────────────────

section "Makeconf"

# LIBR should use direct dylib linking, not -framework R
LIBR=$(grep "^LIBR " "$R_DIR/etc/Makeconf" 2>/dev/null)
if echo "$LIBR" | grep -q "\-lR"; then
  pass "LIBR uses -lR (direct dylib linking)"
else
  fail "LIBR: $LIBR"
fi

if echo "$LIBR" | grep -q "framework"; then
  fail "LIBR still uses -framework R"
else
  pass "LIBR: no framework references"
fi

# ── Summary ──────────────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL + SKIP))

echo ""
echo -e "${BOLD}Results: $PASS passed, $FAIL failed, $SKIP skipped ($TOTAL total)${RESET}"

if [ "$FAIL" -gt 0 ]; then
  echo -e "${RED}FAILED${RESET}"
  exit 1
else
  echo -e "${GREEN}ALL PASSED${RESET}"
  exit 0
fi
