# Portable R for macOS

Portable, relocatable R distributions for macOS built from official CRAN binaries. No installation required. Extract and run.

All binaries are signed with a Developer ID certificate and notarized by Apple, so they won't trigger Gatekeeper warnings.

## Quick Install

**Apple Silicon (M1/M2/M3/M4)**

```bash
curl -fSL https://github.com/portable-r/portable-r-macos/releases/download/v4.5.3/portable-r-4.5.3-macos-arm64.tar.gz | tar xz
```

**Intel Mac**

```bash
curl -fSL https://github.com/portable-r/portable-r-macos/releases/download/v4.5.3/portable-r-4.5.3-macos-x86_64.tar.gz | tar xz
```

Replace `4.5.3` with your desired version. See [all releases](https://github.com/portable-r/portable-r-macos/releases).

## Usage

```bash
# Run an R script
./portable-r-4.5.3-macos-arm64/bin/Rscript my_script.R

# Start interactive R
./portable-r-4.5.3-macos-arm64/bin/R

# Install and use packages (works out of the box)
./portable-r-4.5.3-macos-arm64/bin/Rscript -e '
  install.packages("jsonlite")
  library(jsonlite)
  cat(toJSON(list(hello = "world"), auto_unbox = TRUE))
'
```

No system-wide changes. Packages install to the local `library/` directory inside the portable R folder. Both binary and source CRAN packages are supported. Binary packages are automatically patched at install time.

## Available Versions

<!-- BEGIN RELEASES -->

| R Version | arm64 (Apple Silicon) | x86_64 (Intel) |
|-----------|----------------------|----------------|
| 4.5.3 | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.5.3/portable-r-4.5.3-macos-arm64.tar.gz) (80 MB) | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.5.3/portable-r-4.5.3-macos-x86_64.tar.gz) (83 MB) |
| 4.5.2 | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.5.2/portable-r-4.5.2-macos-arm64.tar.gz) (80 MB) | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.5.2/portable-r-4.5.2-macos-x86_64.tar.gz) (83 MB) |
| 4.5.1 | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.5.1/portable-r-4.5.1-macos-arm64.tar.gz) (80 MB) | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.5.1/portable-r-4.5.1-macos-x86_64.tar.gz) (83 MB) |
| 4.5.0 | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.5.0/portable-r-4.5.0-macos-arm64.tar.gz) (80 MB) | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.5.0/portable-r-4.5.0-macos-x86_64.tar.gz) (83 MB) |
| 4.4.3 | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.4.3/portable-r-4.4.3-macos-arm64.tar.gz) (80 MB) | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.4.3/portable-r-4.4.3-macos-x86_64.tar.gz) (83 MB) |
| 4.4.2 | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.4.2/portable-r-4.4.2-macos-arm64.tar.gz) (77 MB) | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.4.2/portable-r-4.4.2-macos-x86_64.tar.gz) (79 MB) |
| 4.4.1 | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.4.1/portable-r-4.4.1-macos-arm64.tar.gz) (77 MB) | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.4.1/portable-r-4.4.1-macos-x86_64.tar.gz) (79 MB) |
| 4.4.0 | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.4.0/portable-r-4.4.0-macos-arm64.tar.gz) (77 MB) | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.4.0/portable-r-4.4.0-macos-x86_64.tar.gz) (79 MB) |
| 4.3.3 | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.3.3/portable-r-4.3.3-macos-arm64.tar.gz) (75 MB) | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.3.3/portable-r-4.3.3-macos-x86_64.tar.gz) (77 MB) |
| 4.3.2 | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.3.2/portable-r-4.3.2-macos-arm64.tar.gz) (75 MB) | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.3.2/portable-r-4.3.2-macos-x86_64.tar.gz) (77 MB) |
| 4.3.1 | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.3.1/portable-r-4.3.1-macos-arm64.tar.gz) (74 MB) | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.3.1/portable-r-4.3.1-macos-x86_64.tar.gz) (76 MB) |
| 4.3.0 | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.3.0/portable-r-4.3.0-macos-arm64.tar.gz) (74 MB) | [download](https://github.com/portable-r/portable-r-macos/releases/download/v4.3.0/portable-r-4.3.0-macos-x86_64.tar.gz) (76 MB) |

<sub>Last CRAN check: 2026-04-26 · Last release built: 2026-04-01</sub>

<!-- END RELEASES -->

## URL Pattern

All release assets follow a predictable URL:

```
https://github.com/portable-r/portable-r-macos/releases/download/v{VERSION}/portable-r-{VERSION}-macos-{ARCH}.tar.gz
```

Where `{VERSION}` is e.g. `4.5.3` and `{ARCH}` is `arm64` or `x86_64`. SHA256 checksums are at the same URL with a `.sha256` suffix.

## What gets patched

The build extracts the official CRAN R `.pkg` (without installing it) and patches it for portability:

- All hardcoded `/Library/Frameworks/R.framework/...` dylib paths are rewritten to relative references (`@rpath`, `@loader_path`, `@executable_path`)
- Shell scripts and config files (`bin/R`, `etc/Makeconf`, etc.) are updated to use `${R_HOME}` instead of absolute paths
- `etc/Makeconf` is changed from `-framework R` to `-lR` so source package compilation works
- A `.portable` R environment wraps `install.packages()` to automatically patch CRAN binary `.so` files and their dependencies after installation
- All binaries are codesigned (Developer ID + notarized in CI builds)

For full technical details, see [build-details.md](build-details.md).

## Development

### Building locally

`build.sh` downloads a CRAN `.pkg`, extracts it, patches all dylib paths and scripts, codesigns, and packages the result as a `.tar.gz`. It auto-detects the current architecture and falls back to ad-hoc signing when no identity is provided.

```bash
./build.sh 4.5.3                   # Build for current architecture
./build.sh 4.5.3 arm64             # Build for Apple Silicon
./build.sh --help                  # All options (signing, notarization)
```

A `Makefile` wraps common workflows. `make test` runs a test suite with 48 checks covering directory structure, dylib portability, codesigning, execution, package installation, and more.

```bash
make build VERSION=4.5.3           # Build one version
make test VERSION=4.5.3            # Run test suite
make build-all                     # Build all 12 versions
make list                          # Show versions and build status
make clean VERSION=4.5.3           # Remove build artifacts
```

### Codesigning

Local builds are ad-hoc signed by default, which is sufficient for development and testing. For distribution, pass a Developer ID identity and notarization credentials via environment variables:

```bash
CODESIGN_IDENTITY="Developer ID Application: ..." \
NOTARIZE_APPLE_ID="you@example.com" \
NOTARIZE_PASSWORD="xxxx-xxxx-xxxx-xxxx" \
NOTARIZE_TEAM_ID="XXXXXXXXXX" \
./build.sh 4.5.3
```

### Version management

`versions.json` is the single source of truth for supported R versions and CRAN URLs. `check-updates.sh` scrapes CRAN daily to detect new releases and append them to `versions.json` (additive — never removes). `generate-readme.sh` updates the version table in this README from GitHub releases and syncs example version numbers in Quick Install / Usage prose. `LAST_CHECKED` records the most recent CRAN scrape and is committed every cron run so the cron's liveness is auditable.

### CI / GitHub Actions

Three workflows are available:

- **Build Portable R** (`build-portable-r.yml`): Builds a single R version for both arm64 and x86_64, runs the test suite, creates a GitHub release, then regenerates the README's download table from the published release. Runs are serialized so releases are created in order. Triggered manually via `workflow_dispatch`.
- **Build All R Versions** (`build-all-versions.yml`): Builds every supported version (read from `versions.json`) across both architectures, with a release job per version. Includes a dry-run option for testing. Triggered manually via `workflow_dispatch`.
- **Check for Updates** (`check-updates.yml`): Runs daily at 08:00 UTC. Scrapes CRAN for new R releases, updates `versions.json` and regenerates the README when changes are detected, then dispatches the build workflow for any newly discovered versions. Always commits a fresh `LAST_CHECKED` even when nothing changed.

Releases for non-detected versions are **not created automatically** on push. They must be triggered manually from the [Actions tab](../../actions). This is intentional since rebuilds should only happen when the build script changes or when CRAN ships a new R version.

CI builds use repository secrets (`DEVELOPER_ID_P12`, `DEVELOPER_ID_IDENTITY`, `NOTARIZE_*`) for Developer ID signing and Apple notarization. Without these secrets, builds still succeed with ad-hoc signing.

## Related

- [portable-r-windows](https://github.com/portable-r/portable-r-windows): Portable R for Windows (x64 and ARM64)

## License

R itself is licensed under GPL-2 | GPL-3. This repository provides build automation only.
