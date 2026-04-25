#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════════════════════════╗
# ║  generate-readme.sh - Update README.md from GitHub releases             ║
# ║                                                                         ║
# ║  Queries the GitHub releases API to find published assets, then         ║
# ║  injects the version table + freshness subscript between                ║
# ║  <!-- BEGIN RELEASES --> and <!-- END RELEASES --> markers, and         ║
# ║  syncs example version numbers in non-table prose.                      ║
# ╚═══════════════════════════════════════════════════════════════════════════╝
set -euo pipefail

REPO="${REPO:-portable-r/portable-r-macos}"
README="README.md"

if ! command -v gh &>/dev/null; then
    echo "Error: gh CLI is required" >&2
    exit 1
fi

if [ ! -f "$README" ]; then
    echo "Error: $README not found" >&2
    exit 1
fi

echo "==> Querying releases from $REPO"

# ── Fetch releases ───────────────────────────────────────────────────────────

RELEASES_JSON=$(gh api "repos/${REPO}/releases" --paginate --jq '
  [.[] | {
    tag: .tag_name,
    published_at: .published_at,
    assets: [.assets[] | {name: .name, size: .size}]
  }]
')

# ── Compute latest version + last-built date ─────────────────────────────────

DL="https://github.com/${REPO}/releases/download"

R_VERSIONS=$(echo "$RELEASES_JSON" | jq -r '
  [.[].tag | select(startswith("v")) | ltrimstr("v")] | unique | sort_by(split(".") | map(tonumber)) | reverse | .[]
')

LATEST=$(echo "$R_VERSIONS" | head -n1)

LAST_BUILT=$(echo "$RELEASES_JSON" | jq -r '
  [.[].published_at | select(. != null)] | max // "never"
')
if [ "$LAST_BUILT" != "never" ]; then
    LAST_BUILT="${LAST_BUILT%%T*}"  # YYYY-MM-DD
fi

# ── Read last-checked from LAST_CHECKED ──────────────────────────────────────

if [ -f LAST_CHECKED ]; then
    LAST_CHECKED=$(head -1 LAST_CHECKED)
    LAST_CHECKED="${LAST_CHECKED%%T*}"  # YYYY-MM-DD
else
    LAST_CHECKED="never"
fi

# ── Build the table ──────────────────────────────────────────────────────────

asset_link() {
    local tag="$1" pattern="$2" dl_url="$3"
    local match size_bytes size_mb
    match=$(echo "$RELEASES_JSON" | jq -r --arg tag "$tag" --arg pat "$pattern" '
      .[] | select(.tag == $tag) | .assets[] | select(.name | test($pat)) | "\(.name)\t\(.size)"
    ' | head -1)
    [ -z "$match" ] && return
    size_bytes=$(echo "$match" | cut -f2)
    if [ "$size_bytes" -gt 0 ]; then
        size_mb=$(( size_bytes / 1048576 ))
        echo "[download](${dl_url}) (${size_mb} MB)"
    else
        echo "[download](${dl_url}) (?? MB)"
    fi
}

generate_table() {
    echo "| R Version | arm64 (Apple Silicon) | x86_64 (Intel) |"
    echo "|-----------|----------------------|----------------|"
    for v in $R_VERSIONS; do
        arm=$(asset_link "v${v}" "portable-r-${v}-macos-arm64\\.tar\\.gz$" "${DL}/v${v}/portable-r-${v}-macos-arm64.tar.gz")
        x86=$(asset_link "v${v}" "portable-r-${v}-macos-x86_64\\.tar\\.gz$" "${DL}/v${v}/portable-r-${v}-macos-x86_64.tar.gz")
        echo "| ${v} | ${arm} | ${x86} |"
    done
}

# ── Sync example version numbers in non-table prose ──────────────────────────
# Bound to the section above "## Related" so the License + Related sections
# stay verbatim.

if [ -n "$LATEST" ]; then
    LATEST="$LATEST" perl -i -pe '
        BEGIN { our $past = 0; our $V = $ENV{LATEST}; }
        $past = 1 if /^## Related/;
        unless ($past) {
            s{(portable-r-)\d+\.\d+\.\d+(-macos-(?:arm64|x86_64))}{$1$V$2}g;
            s|(/v)\d+\.\d+\.\d+(/portable-r-)|$1$V$2|g;
            s|(Replace `)\d+\.\d+\.\d+(` with)|$1$V$2|;
            s|(\./build\.sh )\d+\.\d+\.\d+|$1$V|g;
            s{(make (?:build|test|clean) VERSION=)\d+\.\d+\.\d+}{$1$V}g;
        }
    ' "$README"
    echo "==> Synced example versions to ${LATEST}"
fi

# ── Splice table into README ─────────────────────────────────────────────────

if [ -z "$R_VERSIONS" ]; then
    echo "No releases found — skipping table regeneration"
    # Still update the dates subscript so it doesn't say "never" forever.
    LAST_CHECKED="$LAST_CHECKED" LAST_BUILT="$LAST_BUILT" perl -i -pe '
        s|<sub>Last CRAN check: [^·]*· Last release built: [^<]*</sub>|<sub>Last CRAN check: $ENV{LAST_CHECKED} \xc2\xb7 Last release built: $ENV{LAST_BUILT}</sub>|;
    ' "$README"
    exit 0
fi

TABLE_FILE=$(mktemp)
{
    generate_table
    echo ""
    echo "<sub>Last CRAN check: ${LAST_CHECKED} · Last release built: ${LAST_BUILT}</sub>"
} > "$TABLE_FILE"

{
    sed -n '1,/<!-- BEGIN RELEASES -->/p' "$README"
    echo ""
    cat "$TABLE_FILE"
    echo ""
    sed -n '/<!-- END RELEASES -->/,$p' "$README"
} > "${README}.tmp"
mv "${README}.tmp" "$README"
rm -f "$TABLE_FILE"

COUNT=$(echo "$R_VERSIONS" | wc -w | tr -d ' ')
echo "==> Updated README with ${COUNT} R versions (latest: ${LATEST})"
echo "    Last CRAN check: ${LAST_CHECKED} · Last release built: ${LAST_BUILT}"
