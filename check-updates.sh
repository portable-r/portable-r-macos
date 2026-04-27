#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  check-updates.sh - Detect new R releases on CRAN macOS                 ║
# ║                                                                         ║
# ║  Scrapes CRAN's macOS pages for new R versions and updates              ║
# ║  versions.json. Designed to run in CI on a daily cron schedule.         ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

VERSIONS_FILE="versions.json"
CHANGED=false

if ! command -v jq &>/dev/null; then
    echo "Error: jq is required" >&2
    exit 1
fi

if [ ! -f "$VERSIONS_FILE" ]; then
    echo "Error: $VERSIONS_FILE not found" >&2
    exit 1
fi

echo "==> Checking for new R releases on CRAN (macOS)"
echo ""

fetch() {
    curl -fsSL --retry 3 --retry-delay 5 "$1" 2>/dev/null
}

# ── Per-architecture detection ──────────────────────────────────────────────

check_arch() {
    local ARCH="$1"     # arm64 or x86_64

    echo "-- R for macOS ($ARCH) --"

    # 1. Per-arch directory listings — iterate every CRAN baseline URL.
    # CRAN occasionally moves new versions to a fresher OS baseline (e.g.,
    # R 4.6.0 arm64 lives in sonoma-arm64/, while 4.3-4.5 stay in
    # big-sur-arm64/). The urls list in versions.json enumerates all live
    # baselines; we union the version sets across them.
    local DIR_VERSIONS=""
    local URLS
    URLS=$(jq -r ".r.urls.${ARCH}[]" "$VERSIONS_FILE")
    for url in $URLS; do
        local subdir_versions
        subdir_versions=$(fetch "${url}/" 2>/dev/null \
            | grep -oE "R-[0-9]+\.[0-9]+\.[0-9]+-${ARCH}\.pkg" \
            | sed -E "s/^R-//; s/-${ARCH}\.pkg$//" \
            | sort -V | uniq || true)
        if [ -n "$subdir_versions" ]; then
            DIR_VERSIONS=$(printf '%s\n%s\n' "$DIR_VERSIONS" "$subdir_versions")
        fi
    done
    DIR_VERSIONS=$(echo "$DIR_VERSIONS" | sort -V | uniq | grep -v '^$' || true)

    # 2. Landing page (announces "latest release")
    local LANDING_VERSIONS
    LANDING_VERSIONS=$(fetch "https://cran.r-project.org/bin/macosx/" \
        | grep -oE "R-[0-9]+\.[0-9]+\.[0-9]+" \
        | sed -E "s/^R-//" | sort -V | uniq)

    # 3. Union, filter to >= 4.3.0
    local DETECTED
    DETECTED=$(printf '%s\n%s\n' "$DIR_VERSIONS" "$LANDING_VERSIONS" \
        | sort -V | uniq | grep -v '^$' \
        | awk -F. '$1>=4 && ($1>4 || $2>=3)')

    if [ -z "$DETECTED" ]; then
        echo "  WARN: zero versions detected for $ARCH (CRAN format change?)"
        echo "        Skipping mutation; existing list preserved."
        return 0
    fi

    echo "  Detected on CRAN: $(echo "$DETECTED" | tr '\n' ' ')"

    # 4. Diff against known
    # Use lexicographic sort (not -V) at the comm boundary: comm requires
    # POSIX byte order. Version-sort and lex-sort agree for our current range
    # but diverge at R 4.10.0 (where -V puts 4.10.0 after 4.9.0 and lex puts
    # it between 4.1.x and 4.2.x), which would silently break diffing.
    local KNOWN
    KNOWN=$(jq -r ".r.${ARCH}[]" "$VERSIONS_FILE" | sort)

    local NEW
    NEW=$(comm -23 <(echo "$DETECTED" | sort) <(echo "$KNOWN"))

    if [ -z "$NEW" ]; then
        echo "  Up to date"
        return 0
    fi

    echo "  NEW: $(echo "$NEW" | tr '\n' ' ')"
    CHANGED=true

    # 5. Append + semver-sort each new version
    for v in $NEW; do
        local TMP
        TMP=$(mktemp)
        jq --arg arch "$ARCH" --arg v "$v" \
            '.r[$arch] += [$v] | .r[$arch] |= (map(split(".") | map(tonumber)) | sort | map(map(tostring) | join(".")))' \
            "$VERSIONS_FILE" > "$TMP"
        mv "$TMP" "$VERSIONS_FILE"
        echo "  Added R $v ($ARCH)"
    done
}

check_arch "arm64"
echo ""
check_arch "x86_64"

# ── Always write LAST_CHECKED ───────────────────────────────────────────────

echo ""
echo "-- Writing LAST_CHECKED --"

{
    date -u +"%Y-%m-%dT%H:%M:%SZ"
    ARM_COUNT=$(jq -r '.r.arm64 | length' "$VERSIONS_FILE")
    ARM_FIRST=$(jq -r '.r.arm64[0]' "$VERSIONS_FILE")
    ARM_LAST=$(jq -r '.r.arm64[-1]' "$VERSIONS_FILE")
    X86_COUNT=$(jq -r '.r.x86_64 | length' "$VERSIONS_FILE")
    X86_FIRST=$(jq -r '.r.x86_64[0]' "$VERSIONS_FILE")
    X86_LAST=$(jq -r '.r.x86_64[-1]' "$VERSIONS_FILE")
    echo "R arm64: ${ARM_FIRST}-${ARM_LAST} (${ARM_COUNT} versions)"
    echo "R x86_64: ${X86_FIRST}-${X86_LAST} (${X86_COUNT} versions)"
} > LAST_CHECKED

echo "  $(head -1 LAST_CHECKED)"

# ── Summary ──────────────────────────────────────────────────────────────────

echo ""
if [ "$CHANGED" = true ]; then
    echo "==> versions.json updated"
    echo "changed=true" >> "${GITHUB_OUTPUT:-/dev/null}"
else
    echo "==> Everything up to date"
    echo "changed=false" >> "${GITHUB_OUTPUT:-/dev/null}"
fi
