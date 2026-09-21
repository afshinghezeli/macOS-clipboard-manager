# Spindle build commands. `make help` lists them. docs/development.md explains the details.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Per-machine overrides (git-ignored). Scripts/clt-workaround.sh writes one when needed.
-include local.mk

SWIFT_SOURCES := Package.swift Sources Tests
STRICT := -Xswiftc -warnings-as-errors

.PHONY: help setup build test lint format check clean

help: ## List the available commands
	@grep -hE '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-14s %s\n", $$1, $$2}'

setup: ## Enable the repository's git hooks
	git config core.hooksPath .githooks

build: ## Debug build of every target
	swift build

test: ## Run the test suites
	swift test

lint: ## Check formatting
	swift format lint --strict --recursive --parallel $(SWIFT_SOURCES)

format: ## Apply formatting
	swift format --in-place --recursive --parallel $(SWIFT_SOURCES)

check: lint ## Lint, build with warnings as errors, and test (run before every commit)
	swift build --build-tests $(STRICT)
	swift test --skip-build

clean: ## Remove build products
	rm -rf .build dist
