# Build details

Technical details on how portable R for macOS is built, patched, and how CRAN binary packages are handled at runtime.

## Build overview

The build script (`build.sh`) takes the official CRAN R `.pkg` installer and transforms it into a self-contained, relocatable directory. The process has 11 steps:

1. **Download** the `.pkg` from CRAN
2. **Extract** with `pkgutil --expand-full` (no system installation)
3. **Copy** the R.framework Resources into a flat directory structure
4. **Rewrite dylib paths** from absolute to relative references
5. **Codesign** all Mach-O binaries
6. **Patch shell scripts and config** to remove hardcoded framework paths
7. **Create launcher wrappers** for `Rscript` and `fix-dylibs`
8. **Configure Rprofile.site** with local library paths and the `.portable` environment
9. **Verify** the build runs correctly
10. **Archive** as `.tar.gz` with SHA256 checksum
11. **Notarize** with Apple (optional, requires Developer ID)

## Dylib path rewriting

CRAN R binaries hardcode absolute paths like `/Library/Frameworks/R.framework/Versions/4.5-arm64/Resources/lib/libR.dylib` in their Mach-O load commands (`LC_LOAD_DYLIB`). These are rewritten using `install_name_tool`:

| Component | Original path | Rewritten to |
|-----------|--------------|--------------|
| `bin/exec/R` | `/Library/.../lib/libR.dylib` | `@executable_path/../../lib/libR.dylib` |
| `lib/*.dylib` (ID) | `/Library/.../lib/libR.dylib` | `@rpath/libR.dylib` |
| `lib/*.dylib` (refs) | `/Library/.../lib/libFoo.dylib` | `@loader_path/libFoo.dylib` |
| `bin/Rscript` | `/Library/.../lib/libR.dylib` | `@executable_path/../lib/libR.dylib` |
| `library/**/*.so` | `/Library/.../lib/libR.dylib` | `@rpath/libR.dylib` |
| `modules/*.so` | `/Library/.../lib/libR.dylib` | `@rpath/libR.dylib` |

`LC_RPATH` entries are added so `@rpath` resolves correctly:

| Component | LC_RPATH added |
|-----------|---------------|
| `bin/exec/R` | `@executable_path/../../lib` |
| `library/pkg/libs/pkg.so` | `@loader_path/../../../lib` |
| `modules/internet.so` | `@loader_path/../lib` |

## Script and config patching

The CRAN `.pkg` embeds the framework path in several text files. All occurrences are replaced:

| File | What's fixed |
|------|-------------|
| `bin/R` | `R_HOME_DIR` (set to self-relative), `R_SHARE_DIR`, `R_INCLUDE_DIR`, `R_DOC_DIR` |
| `bin/fc-cache` | Framework path references |
| `etc/Makeconf` | `LIBR` changed from `-F... -framework R` to `-L"$(R_HOME)/lib" -lR`; all framework paths replaced with `$(R_HOME)` |
| `etc/Renviron` | Hardcoded qpdf path and any framework references |

The `Makeconf` fix is critical for source package compilation (`install.packages(..., type = "source")`), since portable R has no `R.framework` and must link directly against `libR.dylib`.

## CRAN binary package patching

CRAN distributes pre-compiled binary packages (`.tgz`) for macOS. These contain `.so` files with the same hardcoded `/Library/Frameworks/R.framework/...` paths. If these paths happen to resolve (e.g., a system R is installed), they load the *wrong* `libR.dylib`, causing crashes. If the paths don't resolve, the package fails to load entirely.

Portable R handles this transparently via the `.portable` environment.

### `.portable` environment

A hidden R environment is attached at position 2 on the search path (above `package:utils`) during startup via `etc/Rprofile.site`. It provides an `install.packages()` wrapper that masks `utils::install.packages()`:

```r
# Simplified; see etc/Rprofile.site for full implementation
.portable$install.packages <- function(pkgs, ...) {
  utils::install.packages(pkgs, ...)     # call the real function
  .portable$fix_pkgs(pkgs, ...)          # then patch all .so files in library/
}
```

After each install, the wrapper scans *all* packages in the library (not just the requested ones) to catch dependencies. For each `.so` file that still references the R framework path, it:

1. Rewrites the reference to `@rpath/libR.dylib` (or whatever the lib name is)
2. Adds `LC_RPATH` pointing to `@loader_path/../../../lib`

When packages are patched, R reports:

```
Portable R: patched 11 shared libraries
```

The `.portable` environment is attached via a `setHook(packageEvent("stats", "attach"), ...)` hook. This fires after all default packages have loaded, allowing `.portable` to be inserted at position 2 (above `package:utils`) so its `install.packages` is found first.

### `bin/fix-dylibs` (manual utility)

A standalone shell script is also included at `bin/fix-dylibs` for manual use. It scans `library/` and `modules/` and applies the same `install_name_tool` patches. This is useful if `.so` files were added outside of `install.packages()` (e.g., manually unpacking a `.tgz`).

```bash
./portable-r-4.5.3-macos-arm64/bin/fix-dylibs
```

### Why `RHOME` instead of `R_HOME`?

The CRAN `Rscript` binary (Mach-O) reads the `RHOME` environment variable to locate the R installation for code execution. It does *not* read `R_HOME`. This was discovered by examining `strings Rscript.bin`, which revealed a compiled-in fallback path and a check for `RHOME` before using it. The `bin/Rscript` wrapper sets both.

## Codesigning

### Ad-hoc signing (default)

All Mach-O binaries are signed with `codesign --force --sign -` after modification. This satisfies macOS's requirement that all executed code be signed, but won't pass Gatekeeper for downloaded binaries.

### Developer ID signing (CI)

CI builds sign with a Developer ID Application certificate:

- **Hardened runtime** (`--options runtime`) is enabled, which is required for notarization
- **Entitlements** are applied to executables (`bin/exec/R`, `bin/Rscript.bin`):
  - `allow-unsigned-executable-memory`: R uses memory that may not be signed
  - `allow-jit`: R may JIT-compile code
  - `allow-dyld-environment-variables`: allows DYLD_* env vars
  - `disable-library-validation`: allows loading `.so` files signed by other teams (i.e., CRAN binary packages)

Libraries (`.dylib`, `.so`) are signed without entitlements. Executables are signed last to avoid the catch-all step overwriting them.

### Notarization

After signing, the build is submitted to Apple's notary service via `xcrun notarytool`. If accepted, macOS Gatekeeper allows the binaries to run without warnings when downloaded from the internet.

## R.framework version directories

The CRAN `.pkg` uses architecture-suffixed version directories inside `R.framework/Versions/`:

| R version | Directory name |
|-----------|---------------|
| R 4.3.x arm64 | `4.3-arm64` |
| R 4.3.x x86_64 | `4.3-x86_64` |
| R 4.4.x arm64 | `4.4-arm64` |
| R 4.5.x arm64 | `4.5-arm64` |

The build script tries the `Current` symlink first, then arch-suffixed, then plain `major.minor`, then falls back to `find`.

## Test suite

The test suite (`tests/run-tests.sh`) validates the build across 13 categories and 48 individual checks:

| Category | What it checks |
|----------|---------------|
| Directory structure | All required files exist (`bin/R`, `lib/libR.dylib`, etc.) |
| Hardcoded paths | No `/Library/Frameworks/R.framework/Versions/` in text files |
| Dylib portability | No framework references in Mach-O binaries; `LC_RPATH` present |
| Codesigning | Valid signatures; Developer ID and entitlements (when applicable) |
| Execution | `--version`, code eval, `R_HOME`, `R_SHARE_DIR`, `.libPaths()` |
| Base packages | `stats`, `graphics`, `grDevices`, `utils`, `methods` all load |
| Capabilities | `http/ftp`, `sockets`, `libcurl` |
| Internet | HTTPS connection to CRAN |
| Numeric | Arithmetic, BLAS matrix operations, `det()` |
| `.portable` env | On search path, masking `install.packages` |
| Binary install | Install + load + use `jsonlite`; verify `.so` patched |
| Source install | Compile + load + use `glue` |
| Makeconf | `-lR` linking, no `-framework R` |

Run with `make test VERSION=4.5.3` or `./tests/run-tests.sh <dir>`.
