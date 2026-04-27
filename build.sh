#!/bin/bash
set -eu

# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  build.sh — Build portable R for macOS from CRAN .pkg installers        ║
# ║                                                                         ║
# ║  Extracts the official CRAN R .pkg, rewrites hardcoded paths for        ║
# ║  portability, codesigns binaries, and packages as a tar.gz archive.     ║
# ║                                                                         ║
# ║  The resulting distribution runs from any directory without system       ║
# ║  installation. CRAN binary packages are automatically patched at        ║
# ║  install time via a .portable environment on the R search path.         ║
# ╚═══════════════════════════════════════════════════════════════════════════╝

# ── Logging ──────────────────────────────────────────────────────────────────
# Colors are auto-disabled when stdout is not a terminal (e.g., CI, pipes).

if [ -t 1 ]; then
  BOLD="\033[1m"    DIM="\033[2m"
  RED="\033[31m"    GREEN="\033[32m"  YELLOW="\033[33m"  BLUE="\033[34m"
  CYAN="\033[36m"   RESET="\033[0m"
else
  BOLD="" DIM="" RED="" GREEN="" YELLOW="" BLUE="" CYAN="" RESET=""
fi

step()  { echo -e "${BOLD}${BLUE}==> ${1}${RESET}"; }
info()  { echo -e "    ${CYAN}${1}${RESET}"; }
ok()    { echo -e "    ${GREEN}✓ ${1}${RESET}"; }
warn()  { echo -e "    ${YELLOW}⚠ ${1}${RESET}"; }
err()   { echo -e "    ${RED}✗ ${1}${RESET}" >&2; }
detail(){ echo -e "    ${DIM}${1}${RESET}"; }

# ── Help ─────────────────────────────────────────────────────────────────────

usage() {
  cat <<EOF
Usage: ./build.sh <R_VERSION> [ARCH]

Build a portable, relocatable R distribution for macOS from the official
CRAN .pkg installer. No system installation required.

Arguments:
  R_VERSION   R version to build (e.g., 4.5.3, 4.4.1)
  ARCH        Target architecture: arm64 or x86_64 (default: auto-detect)

Environment variables for codesigning:
  CODESIGN_IDENTITY    Signing identity (default: ad-hoc)
                       e.g., "Developer ID Application: Your Name (TEAM_ID)"
  NOTARIZE_APPLE_ID    Apple ID email for notarization
  NOTARIZE_PASSWORD    App-specific password for notarization
  NOTARIZE_TEAM_ID     Apple Developer team ID

Examples:
  ./build.sh 4.5.3                Build for current architecture (ad-hoc signed)
  ./build.sh 4.4.1 arm64         Build for Apple Silicon
  ./build.sh 4.3.3 x86_64        Build for Intel

  CODESIGN_IDENTITY="Developer ID Application: ..." ./build.sh 4.5.3

Output:
  portable-r-{VERSION}-macos-{ARCH}/            Unpacked portable R
  portable-r-{VERSION}-macos-{ARCH}.tar.gz      Archive for distribution
  portable-r-{VERSION}-macos-{ARCH}.tar.gz.sha256
EOF
}

if [ "${1:-}" = "--help" ] || [ "${1:-}" = "-h" ]; then
  usage
  exit 0
fi

# ── Arguments ────────────────────────────────────────────────────────────────

R_VERSION="${1:?Usage: ./build.sh <R_VERSION> [ARCH] (try --help)}"
ARCH="${2:-$(uname -m)}"
SIGN_ID="${CODESIGN_IDENTITY:--}"

case "$ARCH" in
  arm64|aarch64) CRAN_ARCH="arm64";  PKG_SUFFIX="arm64"  ;;
  x86_64)        CRAN_ARCH="x86_64"; PKG_SUFFIX="x86_64" ;;
  *) err "Unsupported architecture: $ARCH"; exit 1 ;;
esac

OUTPUT_NAME="portable-r-${R_VERSION}-macos-${CRAN_ARCH}"
OUTPUT_DIR="${OUTPUT_NAME}"
PKG_FILE="R-${R_VERSION}-${PKG_SUFFIX}.pkg"

# Resolve the CRAN baseline directory for this version. CRAN occasionally
# bumps the macOS baseline (e.g., R 4.6.0 arm64 moved to sonoma-arm64 from
# big-sur-arm64). versions.json lists candidate URLs newest-first; we HEAD
# each and use the first that has the .pkg.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VERSIONS_JSON="${SCRIPT_DIR}/versions.json"

if ! command -v jq &>/dev/null; then
  err "jq is required to resolve the CRAN download URL (brew install jq)"
  exit 1
fi
if [ ! -f "$VERSIONS_JSON" ]; then
  err "versions.json not found at $VERSIONS_JSON"
  exit 1
fi

DOWNLOAD_URL=""
for base_url in $(jq -r ".r.urls.${CRAN_ARCH}[]" "$VERSIONS_JSON"); do
  candidate="${base_url}/${PKG_FILE}"
  if curl -fsI --retry 2 --retry-delay 3 "$candidate" -o /dev/null 2>&1; then
    DOWNLOAD_URL="$candidate"
    break
  fi
done

if [ -z "$DOWNLOAD_URL" ]; then
  err "Could not find $PKG_FILE on any CRAN baseline; tried:"
  for u in $(jq -r ".r.urls.${CRAN_ARCH}[]" "$VERSIONS_JSON"); do
    err "  $u/$PKG_FILE"
  done
  exit 1
fi

echo ""
echo -e "${BOLD}Portable R ${R_VERSION} for macOS (${CRAN_ARCH})${RESET}"
if [ "$SIGN_ID" != "-" ]; then
  detail "Signing: $SIGN_ID"
else
  detail "Signing: ad-hoc (set CODESIGN_IDENTITY for Developer ID signing)"
fi
echo ""

# ═══════════════════════════════════════════════════════════════════════════════
# Step 1: Download R .pkg from CRAN
# ═══════════════════════════════════════════════════════════════════════════════

step "Downloading R installer"
if [ ! -f "$PKG_FILE" ]; then
  detail "$DOWNLOAD_URL"
  curl -fSL -o "$PKG_FILE" "$DOWNLOAD_URL"
  ok "Downloaded $PKG_FILE"
else
  ok "Using cached $PKG_FILE"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 2: Extract .pkg without installing
# ═══════════════════════════════════════════════════════════════════════════════

step "Extracting .pkg"
EXTRACT_DIR=$(mktemp -d)
pkgutil --expand-full "$PKG_FILE" "$EXTRACT_DIR/expanded"

R_PAYLOAD=$(find "$EXTRACT_DIR/expanded" -name "R.framework" -type d | head -1)
if [ -z "$R_PAYLOAD" ]; then
  err "Could not find R.framework in the .pkg"
  find "$EXTRACT_DIR/expanded" -maxdepth 3 -type d
  rm -rf "$EXTRACT_DIR"
  exit 1
fi
ok "Found R.framework"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 3: Create portable directory structure
# The R.framework Versions directory varies by version (e.g., 4.3-arm64,
# 4.4-arm64). We try the Current symlink first, then versioned paths.
# ═══════════════════════════════════════════════════════════════════════════════

step "Creating portable directory structure"
rm -rf "$OUTPUT_DIR"
mkdir -p "$OUTPUT_DIR/bin" "$OUTPUT_DIR/library" "$OUTPUT_DIR/etc"

R_RESOURCES="$R_PAYLOAD/Versions/Current/Resources"
if [ ! -d "$R_RESOURCES" ]; then
  R_MAJOR=$(echo "$R_VERSION" | cut -d. -f1)
  R_MINOR=$(echo "$R_VERSION" | cut -d. -f2)
  R_RESOURCES="$R_PAYLOAD/Versions/${R_MAJOR}.${R_MINOR}-${CRAN_ARCH}/Resources"
fi
if [ ! -d "$R_RESOURCES" ]; then
  R_RESOURCES="$R_PAYLOAD/Versions/${R_MAJOR}.${R_MINOR}/Resources"
fi
if [ ! -d "$R_RESOURCES" ]; then
  R_RESOURCES=$(find "$R_PAYLOAD/Versions" -name "Resources" -type d | head -1)
fi
if [ -z "$R_RESOURCES" ] || [ ! -d "$R_RESOURCES" ]; then
  err "Could not find R Resources directory"
  find "$R_PAYLOAD" -maxdepth 4 -type d
  rm -rf "$EXTRACT_DIR"
  exit 1
fi

detail "Source: $R_RESOURCES"
cp -R "$R_RESOURCES"/* "$OUTPUT_DIR/"
ok "Copied R resources"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 4: Rewrite dylib paths for portability
# CRAN binaries hardcode /Library/Frameworks/R.framework/... as absolute paths
# in Mach-O load commands. We rewrite these to relative references:
#   - bin/exec/R      → @executable_path/../../lib/
#   - bin/Rscript     → @executable_path/../lib/
#   - lib/*.dylib     → @loader_path/ (peer references) + @rpath (ID)
#   - library/**/*.so → @rpath + LC_RPATH → ../../../lib
#   - modules/*.so    → @rpath + LC_RPATH → ../lib
# ═══════════════════════════════════════════════════════════════════════════════

step "Fixing dylib references for portability"

# bin/exec/R — the main R executable
R_BIN="$OUTPUT_DIR/bin/exec/R"
if [ -f "$R_BIN" ]; then
  otool -L "$R_BIN" | grep "/Library/Frameworks/R.framework" | awk '{print $1}' | while read -r old_path; do
    lib_name=$(basename "$old_path")
    detail "bin/exec/R: $lib_name → @executable_path/../../lib/"
    install_name_tool -change "$old_path" "@executable_path/../../lib/$lib_name" "$R_BIN"
  done
  install_name_tool -add_rpath "@executable_path/../../lib" "$R_BIN" 2>/dev/null || true
fi

# lib/*.dylib — shared libraries referencing each other
find "$OUTPUT_DIR/lib" -name "*.dylib" -type f 2>/dev/null | while read -r dylib; do
  old_id=$(otool -D "$dylib" 2>/dev/null | tail -1)
  if echo "$old_id" | grep -q "/Library/Frameworks/R.framework"; then
    install_name_tool -id "@rpath/$(basename "$old_id")" "$dylib" 2>/dev/null || true
  fi
  otool -L "$dylib" | grep "/Library/Frameworks/R.framework" | awk '{print $1}' | while read -r old_path; do
    install_name_tool -change "$old_path" "@loader_path/$(basename "$old_path")" "$dylib" 2>/dev/null || true
  done
done

# bin/Rscript — the Rscript Mach-O binary
RSCRIPT_BIN="$OUTPUT_DIR/bin/Rscript"
if [ -f "$RSCRIPT_BIN" ] && file "$RSCRIPT_BIN" | grep -q "Mach-O"; then
  otool -L "$RSCRIPT_BIN" | grep "/Library/Frameworks/R.framework" | awk '{print $1}' | while read -r old_path; do
    lib_name=$(basename "$old_path")
    detail "bin/Rscript: $lib_name → @executable_path/../lib/"
    install_name_tool -change "$old_path" "@executable_path/../lib/$lib_name" "$RSCRIPT_BIN"
  done
fi

# library/**/*.so — bundled R package shared objects
find "$OUTPUT_DIR/library" -name "*.so" -type f 2>/dev/null | while read -r so; do
  otool -L "$so" 2>/dev/null | grep "/Library/Frameworks/R.framework" | awk '{print $1}' | while read -r old_path; do
    install_name_tool -change "$old_path" "@rpath/$(basename "$old_path")" "$so" 2>/dev/null || true
  done
  install_name_tool -add_rpath "@loader_path/../../../lib" "$so" 2>/dev/null || true
done

# modules/*.so — R internal modules (internet, lapack, etc.)
find "$OUTPUT_DIR/modules" -name "*.so" -type f 2>/dev/null | while read -r so; do
  otool -L "$so" 2>/dev/null | grep "/Library/Frameworks/R.framework" | awk '{print $1}' | while read -r old_path; do
    install_name_tool -change "$old_path" "@rpath/$(basename "$old_path")" "$so" 2>/dev/null || true
  done
  install_name_tool -add_rpath "@loader_path/../lib" "$so" 2>/dev/null || true
done

ok "Rewrote absolute paths to relative references"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 5: Codesign all Mach-O binaries
# Libraries are signed first (innermost), then executables (outermost).
# For Developer ID signing, we enable hardened runtime (required for
# notarization) and add entitlements so R can JIT-compile, dlopen packages
# signed by other teams, and use DYLD environment variables.
# ═══════════════════════════════════════════════════════════════════════════════

step "Codesigning binaries"

if [ "$SIGN_ID" != "-" ]; then
  detail "Identity: $SIGN_ID"
else
  detail "Ad-hoc signing (no Developer ID)"
fi

CODESIGN_OPTS=(--force --sign "$SIGN_ID")
if [ "$SIGN_ID" != "-" ]; then
  CODESIGN_OPTS+=(--timestamp --options runtime)

  ENTITLEMENTS_FILE=$(mktemp)
  cat > "$ENTITLEMENTS_FILE" << 'ENTITLEMENTS'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>com.apple.security.cs.allow-unsigned-executable-memory</key>
    <true/>
    <key>com.apple.security.cs.allow-jit</key>
    <true/>
    <key>com.apple.security.cs.allow-dyld-environment-variables</key>
    <true/>
    <key>com.apple.security.cs.disable-library-validation</key>
    <true/>
</dict>
</plist>
ENTITLEMENTS
fi

# 1. Sign dylibs
find "$OUTPUT_DIR/lib" -name "*.dylib" -type f 2>/dev/null | while read -r f; do
  codesign "${CODESIGN_OPTS[@]}" "$f" 2>/dev/null || true
done

# 2. Sign .so files (bundled packages + modules)
find "$OUTPUT_DIR/library" "$OUTPUT_DIR/modules" -name "*.so" -type f 2>/dev/null | while read -r f; do
  codesign "${CODESIGN_OPTS[@]}" "$f" 2>/dev/null || true
done

# 3. Sign executables (with entitlements for Developer ID)
EXEC_OPTS=("${CODESIGN_OPTS[@]}")
if [ "$SIGN_ID" != "-" ] && [ -n "${ENTITLEMENTS_FILE:-}" ]; then
  EXEC_OPTS+=(--entitlements "$ENTITLEMENTS_FILE")
fi

for bin in "$OUTPUT_DIR/bin/exec/R" "$OUTPUT_DIR/bin/Rscript" "$OUTPUT_DIR/bin/Rscript.bin"; do
  if [ -f "$bin" ] && file "$bin" | grep -q "Mach-O"; then
    codesign "${EXEC_OPTS[@]}" "$bin" 2>/dev/null || true
  fi
done

# 4. Catch-all: sign any remaining Mach-O files (skip those already signed with entitlements)
find "$OUTPUT_DIR" -type f \
  ! -path "$OUTPUT_DIR/bin/exec/R" \
  ! -path "$OUTPUT_DIR/bin/Rscript.bin" \
  2>/dev/null | while read -r f; do
  if file "$f" 2>/dev/null | grep -q "Mach-O"; then
    codesign "${CODESIGN_OPTS[@]}" "$f" 2>/dev/null || true
  fi
done

rm -f "${ENTITLEMENTS_FILE:-}"

if [ "$SIGN_ID" != "-" ]; then
  ok "Signed with hardened runtime: $SIGN_ID"
else
  ok "Ad-hoc signed all binaries"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 6: Patch shell scripts and config files
# The CRAN .pkg hardcodes /Library/Frameworks/R.framework/Versions/X.Y-ARCH/Resources
# throughout bin/R, bin/fc-cache, etc/Makeconf, and etc/Renviron.
# We replace ALL occurrences with ${R_HOME} or $(R_HOME).
# ═══════════════════════════════════════════════════════════════════════════════

step "Patching scripts and config for portability"

# Detect the exact hardcoded path from bin/R before we modify it
R_SCRIPT="$OUTPUT_DIR/bin/R"
HARDCODED_PATH=$(grep "^R_HOME_DIR=" "$R_SCRIPT" | sed 's/^R_HOME_DIR=//')

# bin/R — make R_HOME_DIR self-relative, replace all other occurrences
sed -i '' 's|^R_HOME_DIR=.*|R_HOME_DIR="$(cd "$(dirname "$0")/.." \&\& pwd)"|' "$R_SCRIPT"
sed -i '' "s|${HARDCODED_PATH}|\${R_HOME}|g" "$R_SCRIPT"
ok "bin/R: all hardcoded paths replaced"

# Other shell scripts in bin/
find "$OUTPUT_DIR/bin" -type f ! -name "*.bin" | while read -r f; do
  if file "$f" | grep -q "text" && grep -q "$HARDCODED_PATH" "$f" 2>/dev/null; then
    sed -i '' "s|${HARDCODED_PATH}|\${R_HOME}|g" "$f"
    detail "$(basename "$f"): hardcoded paths replaced"
  fi
done

# etc/Makeconf — replace framework linking with direct dylib linking
if [ -f "$OUTPUT_DIR/etc/Makeconf" ]; then
  sed -i '' "s|${HARDCODED_PATH}|\$(R_HOME)|g" "$OUTPUT_DIR/etc/Makeconf"
  sed -i '' 's|^LIBR = -F.*-framework R|LIBR = -L"$(R_HOME)/lib" -lR|' "$OUTPUT_DIR/etc/Makeconf"
  sed -i '' 's|-F/Library/Frameworks/R.framework/[^ ]*||g' "$OUTPUT_DIR/etc/Makeconf"
  detail "Makeconf: framework linking replaced with direct dylib linking"
fi

# etc/Renviron
if [ -f "$OUTPUT_DIR/etc/Renviron" ] && grep -q "/Library/Frameworks/R.framework" "$OUTPUT_DIR/etc/Renviron" 2>/dev/null; then
  sed -i '' "s|${HARDCODED_PATH}|\$(R_HOME)|g" "$OUTPUT_DIR/etc/Renviron"
  detail "Renviron: hardcoded paths replaced"
fi

# Strip debug symbols (~14MB savings)
find "$OUTPUT_DIR/lib" -name "*.dSYM" -type d -exec rm -rf {} + 2>/dev/null || true
ok "Removed debug symbols"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 7: Create launcher wrappers
# Rscript.bin uses the RHOME env var (not R_HOME) to locate the R installation.
# We wrap it to set RHOME before exec'ing the real binary.
# ═══════════════════════════════════════════════════════════════════════════════

step "Creating launcher wrappers"

# Rename the Rscript Mach-O binary
if [ -f "$OUTPUT_DIR/bin/Rscript" ]; then
  mv "$OUTPUT_DIR/bin/Rscript" "$OUTPUT_DIR/bin/Rscript.bin"
  chmod +x "$OUTPUT_DIR/bin/Rscript.bin"
fi

# bin/fix-dylibs — standalone utility for manual use
# Scans library/ and modules/ for .so files with hardcoded R framework paths
# and rewrites them. Not called automatically — the .portable R environment
# handles this transparently via its install.packages() wrapper.
cat > "$OUTPUT_DIR/bin/fix-dylibs" << 'FIXSCRIPT'
#!/bin/bash
# Manually patch CRAN binary .so files that hardcode R framework paths.
# Usage: ./bin/fix-dylibs
# Normally not needed — install.packages() patches automatically.
R_HOME="$(cd "$(dirname "$0")/.." && pwd)"
FIXED=0
for dir in "$R_HOME/library" "$R_HOME/modules"; do
  [ -d "$dir" ] || continue
  find "$dir" -name "*.so" -type f 2>/dev/null | while read -r so; do
    if otool -L "$so" 2>/dev/null | grep -q "/Library/Frameworks/R.framework"; then
      otool -L "$so" | grep "/Library/Frameworks/R.framework" | awk '{print $1}' | while read -r old; do
        install_name_tool -change "$old" "@rpath/$(basename "$old")" "$so" 2>/dev/null
      done
      case "$so" in
        */modules/*) install_name_tool -add_rpath "@loader_path/../lib" "$so" 2>/dev/null || true ;;
        *)           install_name_tool -add_rpath "@loader_path/../../../lib" "$so" 2>/dev/null || true ;;
      esac
      echo "Patched: $so"
    fi
  done
done
FIXSCRIPT
chmod +x "$OUTPUT_DIR/bin/fix-dylibs"
ok "bin/fix-dylibs: standalone .so patcher (for manual use)"

# bin/Rscript — wrapper that sets RHOME before launching the real binary.
# R <= 4.5 derived R_SHARE_DIR / R_INCLUDE_DIR / R_DOC_DIR from R_HOME at
# startup if unset, but R 4.6.0 falls back to the compile-time default
# (/Library/Frameworks/R.framework/Resources/...) which is wrong for a
# portable build. Set them explicitly so the wrapper works on every
# supported R version.
cat > "$OUTPUT_DIR/bin/Rscript" << 'WRAPPER'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
export RHOME="$(cd "$SCRIPT_DIR/.." && pwd)"
export R_HOME="$RHOME"
export R_SHARE_DIR="${R_HOME}/share"
export R_INCLUDE_DIR="${R_HOME}/include"
export R_DOC_DIR="${R_HOME}/doc"
exec "$SCRIPT_DIR/Rscript.bin" "$@"
WRAPPER
chmod +x "$OUTPUT_DIR/bin/Rscript"
ok "bin/Rscript: sets RHOME before launch"

# Top-level Rscript (convenience wrapper)
if [ -f "$OUTPUT_DIR/Rscript" ] && file "$OUTPUT_DIR/Rscript" | grep -q "Mach-O"; then
  rm "$OUTPUT_DIR/Rscript"
  cat > "$OUTPUT_DIR/Rscript" << 'TOP_WRAPPER'
#!/bin/bash
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
exec "$SCRIPT_DIR/bin/Rscript" "$@"
TOP_WRAPPER
  chmod +x "$OUTPUT_DIR/Rscript"
  ok "Rscript (top-level): delegates to bin/Rscript"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 8: Configure Rprofile.site
# Sets up local library paths, CRAN mirror, and a .portable environment that
# wraps install.packages() to automatically patch CRAN binary .so files.
# ═══════════════════════════════════════════════════════════════════════════════

step "Configuring Rprofile.site"

cat > "$OUTPUT_DIR/etc/Rprofile.site" << 'RPROFILE'
# ── Portable R configuration ─────────────────────────────────────────────────
local({
  # Local library path — packages install inside the portable R directory
  r_home <- Sys.getenv("R_HOME", R.home())
  lib_dir <- file.path(r_home, "library")
  if (!dir.exists(lib_dir)) dir.create(lib_dir, recursive = TRUE)
  .libPaths(c(lib_dir, .Library))

  # Default CRAN mirror
  r <- getOption("repos")
  r["CRAN"] <- "https://cloud.r-project.org"
  options(repos = r)

  # ── .portable environment ──────────────────────────────────────────────────
  # CRAN binary packages (.so files) hardcode absolute paths like
  # /Library/Frameworks/R.framework/.../lib/libR.dylib which don't exist in
  # portable R. The .portable environment provides an install.packages()
  # wrapper that automatically rewrites these paths after installation.
  #
  # How it works:
  #   1. .portable$install.packages() calls the real utils::install.packages()
  #   2. After install completes, scans ALL packages in the library for .so
  #      files that still reference /Library/Frameworks/R.framework/...
  #   3. Rewrites them to @rpath and adds LC_RPATH via install_name_tool
  #   4. Reports how many shared libraries were patched
  #
  # The .portable environment is attached above package:utils on the R search
  # path so that install.packages() resolves to our wrapper first.

  .portable <- new.env(parent = baseenv())

  # Patch a single .so file: rewrite R.framework references to @rpath
  .portable$fix_so <- function(so) {
    refs <- system2("otool", c("-L", shQuote(so)), stdout = TRUE, stderr = FALSE)
    fw <- grep("/Library/Frameworks/R.framework", refs, value = TRUE)
    if (length(fw) == 0L) return(invisible(FALSE))
    for (line in fw) {
      old <- trimws(sub("\\s+\\(.*", "", line))
      system2("install_name_tool",
              c("-change", shQuote(old), shQuote(paste0("@rpath/", basename(old))), shQuote(so)),
              stdout = FALSE, stderr = FALSE)
    }
    system2("install_name_tool",
            c("-add_rpath", "@loader_path/../../../lib", shQuote(so)),
            stdout = FALSE, stderr = FALSE)
    invisible(TRUE)
  }

  # Scan all packages in a library directory and patch any unfixed .so files
  .portable$fix_pkgs <- function(pkgs = NULL, lib = .libPaths()[1L]) {
    all_pkgs <- list.dirs(lib, full.names = FALSE, recursive = FALSE)
    fixed <- 0L
    for (pkg in all_pkgs) {
      so_files <- list.files(file.path(lib, pkg, "libs"),
                             pattern = "\\.so$", full.names = TRUE)
      for (so in so_files) {
        if (isTRUE(.portable$fix_so(so))) fixed <- fixed + 1L
      }
    }
    if (fixed > 0L)
      message(sprintf("Portable R: patched %d shared librar%s",
                      fixed, if (fixed == 1L) "y" else "ies"))
    invisible(fixed)
  }

  # Wrapper around utils::install.packages that patches .so files after install
  .portable$install.packages <- function(pkgs, ...) {
    utils <- asNamespace("utils")
    result <- utils$install.packages(pkgs, ...)
    mc <- match.call()
    lib_dir <- if ("lib" %in% names(mc)) eval(mc$lib) else .libPaths()[1L]
    try(.portable$fix_pkgs(pkgs, lib = lib_dir), silent = TRUE)
    invisible(result)
  }

  # Attach .portable above package:utils so it masks install.packages.
  # Default packages load after Rprofile.site (pushing any early attach down),
  # so we hook into the last default package (stats) to re-attach at position 2.
  setHook(packageEvent("stats", "attach"), function(...) {
    if (".portable" %in% search()) try(detach(".portable"), silent = TRUE)
    attach(.portable, name = ".portable", pos = 2L, warn.conflicts = FALSE)
  })
})
RPROFILE

ok "Rprofile.site: local library paths, CRAN mirror, .portable environment"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 9: Clean up and verify
# ═══════════════════════════════════════════════════════════════════════════════

rm -rf "$EXTRACT_DIR"

step "Verifying portable R"
VERIFY_PASS=0
VERIFY_FAIL=0

if [ -f "$OUTPUT_DIR/bin/Rscript" ]; then
  if "$OUTPUT_DIR/bin/Rscript" --version >/dev/null 2>&1; then
    ok "Rscript --version"
    VERIFY_PASS=$((VERIFY_PASS + 1))
  else
    err "Rscript --version"
    VERIFY_FAIL=$((VERIFY_FAIL + 1))
  fi

  RESULT=$("$OUTPUT_DIR/bin/Rscript" -e 'cat(R.version.string)' 2>&1) && {
    ok "Code execution: $RESULT"
    VERIFY_PASS=$((VERIFY_PASS + 1))
  } || {
    err "Code execution failed"
    VERIFY_FAIL=$((VERIFY_FAIL + 1))
  }

  if "$OUTPUT_DIR/bin/Rscript" -e 'library(stats); cat(mean(1:10))' >/dev/null 2>&1; then
    ok "Package loading (stats)"
    VERIFY_PASS=$((VERIFY_PASS + 1))
  else
    err "Package loading failed"
    VERIFY_FAIL=$((VERIFY_FAIL + 1))
  fi
fi

if [ "$VERIFY_FAIL" -gt 0 ]; then
  warn "$VERIFY_PASS passed, $VERIFY_FAIL failed"
fi

# ═══════════════════════════════════════════════════════════════════════════════
# Step 10: Create archive
# ═══════════════════════════════════════════════════════════════════════════════

step "Creating archive"
ARCHIVE="${OUTPUT_NAME}.tar.gz"
tar czf "$ARCHIVE" "$OUTPUT_DIR"
shasum -a 256 "$ARCHIVE" > "${ARCHIVE}.sha256"
CHECKSUM=$(cut -d' ' -f1 "${ARCHIVE}.sha256")
SIZE=$(du -sh "$ARCHIVE" | cut -f1)

ok "$ARCHIVE ($SIZE)"
detail "SHA256: $CHECKSUM"

# ═══════════════════════════════════════════════════════════════════════════════
# Step 11: Notarize (optional, requires Developer ID signing)
# Submits a zip of the build to Apple's notary service. If accepted, macOS
# Gatekeeper will not block the binaries when downloaded from the internet.
# ═══════════════════════════════════════════════════════════════════════════════

NOTARIZE_APPLE_ID="${NOTARIZE_APPLE_ID:-}"
NOTARIZE_PASSWORD="${NOTARIZE_PASSWORD:-}"
NOTARIZE_TEAM_ID="${NOTARIZE_TEAM_ID:-}"

if [ -n "$NOTARIZE_APPLE_ID" ] && [ -n "$NOTARIZE_PASSWORD" ] && [ -n "$NOTARIZE_TEAM_ID" ] && [ "$SIGN_ID" != "-" ]; then
  step "Notarizing archive"

  NOTARIZE_ZIP="${OUTPUT_NAME}-notarize.zip"
  ditto -c -k --keepParent "$OUTPUT_DIR" "$NOTARIZE_ZIP"

  detail "Submitting to Apple notary service..."
  NOTARIZE_OUTPUT=$(xcrun notarytool submit "$NOTARIZE_ZIP" \
    --apple-id "$NOTARIZE_APPLE_ID" \
    --password "$NOTARIZE_PASSWORD" \
    --team-id "$NOTARIZE_TEAM_ID" \
    --wait 2>&1) || true

  echo "$NOTARIZE_OUTPUT" | while read -r line; do detail "$line"; done
  rm -f "$NOTARIZE_ZIP"

  if echo "$NOTARIZE_OUTPUT" | grep -q "status: Accepted"; then
    ok "Notarization accepted by Apple"
  elif echo "$NOTARIZE_OUTPUT" | grep -q "status: Invalid"; then
    SUBMISSION_ID=$(echo "$NOTARIZE_OUTPUT" | grep "  id:" | head -1 | awk '{print $2}')
    if [ -n "$SUBMISSION_ID" ]; then
      warn "Notarization rejected — fetching log..."
      xcrun notarytool log "$SUBMISSION_ID" \
        --apple-id "$NOTARIZE_APPLE_ID" \
        --password "$NOTARIZE_PASSWORD" \
        --team-id "$NOTARIZE_TEAM_ID" \
        2>&1 | while read -r line; do detail "$line"; done
    fi
    warn "Notarization failed — archive is still usable but may trigger Gatekeeper"
  else
    warn "Notarization status unknown — check Apple Developer portal"
  fi
elif [ "$SIGN_ID" != "-" ]; then
  detail "Skipping notarization (set NOTARIZE_APPLE_ID, NOTARIZE_PASSWORD, NOTARIZE_TEAM_ID)"
fi

# ═══════════════════════════════════════════════════════════════════════════════

echo ""
echo -e "${BOLD}${GREEN}Build complete${RESET}"
echo ""
