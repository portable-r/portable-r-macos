SHELL := /bin/bash

# ── Configuration ────────────────────────────────────────────────────────────

ARCH    ?= $(shell uname -m)
VERSIONS = $(shell jq -r '.r.arm64 + .r.x86_64 | unique | .[]' versions.json | tr '\n' ' ')

# Resolve CRAN arch name
ifeq ($(ARCH),arm64)
  CRAN_ARCH = arm64
else ifeq ($(ARCH),aarch64)
  CRAN_ARCH = arm64
else ifeq ($(ARCH),x86_64)
  CRAN_ARCH = x86_64
else
  $(error Unsupported architecture: $(ARCH))
endif

# ── Targets ──────────────────────────────────────────────────────────────────

.PHONY: help build build-all clean clean-all list verify test

help: ## Show this help
	@echo ""
	@echo "  Portable R for macOS — Build Targets"
	@echo ""
	@echo "  Requires: jq (brew install jq)"
	@echo ""
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'
	@echo ""
	@echo "  Examples:"
	@echo "    make build VERSION=4.5.3          Build R 4.5.3 for current arch"
	@echo "    make build VERSION=4.5.3 ARCH=x86_64"
	@echo "    make build-all                    Build all versions ($(words $(VERSIONS)))"
	@echo "    make verify VERSION=4.5.3         Test a build without rebuilding"
	@echo ""
	@echo "  Codesigning (via environment variables):"
	@echo "    CODESIGN_IDENTITY   Signing identity (default: ad-hoc)"
	@echo "    NOTARIZE_APPLE_ID   Apple ID for notarization"
	@echo "    NOTARIZE_PASSWORD   App-specific password"
	@echo "    NOTARIZE_TEAM_ID    Team ID"
	@echo ""

build: ## Build a single version (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make build VERSION=4.5.3)
endif
	@./build.sh $(VERSION) $(ARCH)

build-all: ## Build all supported versions
	@echo ""
	@echo -e "\033[1mBuilding $(words $(VERSIONS)) versions for $(CRAN_ARCH)\033[0m"
	@echo ""
	@PASS=0; FAIL=0; \
	for v in $(VERSIONS); do \
		echo -e "\033[1m── R $$v ──────────────────────────────────────\033[0m"; \
		if ./build.sh $$v $(ARCH); then \
			PASS=$$((PASS + 1)); \
		else \
			FAIL=$$((FAIL + 1)); \
			echo -e "\033[31m✗ R $$v failed\033[0m"; \
		fi; \
		echo ""; \
	done; \
	echo -e "\033[1mResults: $$PASS succeeded, $$FAIL failed\033[0m"

verify: ## Verify an existing build (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make verify VERSION=4.5.3)
endif
	@DIR="portable-r-$(VERSION)-macos-$(CRAN_ARCH)"; \
	if [ ! -d "$$DIR" ]; then \
		echo -e "\033[31m✗ $$DIR not found — run 'make build VERSION=$(VERSION)' first\033[0m"; \
		exit 1; \
	fi; \
	echo -e "\033[1mVerifying $$DIR\033[0m"; \
	echo -n "  Rscript --version: "; \
	"$$DIR/bin/Rscript" --version 2>&1 || exit 1; \
	echo -n "  Code execution:    "; \
	"$$DIR/bin/Rscript" -e 'cat(R.version.string, "\n")' 2>&1 || exit 1; \
	echo -n "  Package loading:   "; \
	"$$DIR/bin/Rscript" -e 'library(stats); cat("mean(1:10) =", mean(1:10), "\n")' 2>&1 || exit 1; \
	echo -e "\033[32m✓ All checks passed\033[0m"

list: ## List all supported R versions
	@echo "Supported versions ($(CRAN_ARCH)):"
	@for v in $(VERSIONS); do \
		DIR="portable-r-$$v-macos-$(CRAN_ARCH)"; \
		if [ -f "$$DIR.tar.gz" ]; then \
			echo -e "  \033[32m●\033[0m $$v  (built)"; \
		elif [ -d "$$DIR" ]; then \
			echo -e "  \033[33m●\033[0m $$v  (unpacked, not archived)"; \
		else \
			echo -e "  \033[2m○\033[0m $$v"; \
		fi; \
	done

test: ## Run full test suite on a build (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make test VERSION=4.5.3)
endif
	@./tests/run-tests.sh "portable-r-$(VERSION)-macos-$(CRAN_ARCH)"

clean: ## Remove build artifacts for a single version (VERSION=x.y.z)
ifndef VERSION
	$(error VERSION is required. Usage: make clean VERSION=4.5.3)
endif
	rm -rf portable-r-$(VERSION)-macos-$(CRAN_ARCH)
	rm -f  portable-r-$(VERSION)-macos-$(CRAN_ARCH).tar.gz
	rm -f  portable-r-$(VERSION)-macos-$(CRAN_ARCH).tar.gz.sha256

clean-all: ## Remove all build artifacts
	rm -rf portable-r-*-macos-*/
	rm -f  portable-r-*-macos-*.tar.gz
	rm -f  portable-r-*-macos-*.tar.gz.sha256
	rm -f  R-*.pkg
