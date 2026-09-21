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

# ------------------------------------------------------------------------------ the app

DEBUG_APP := dist/debug/Spindle.app
DEV_BUNDLE_ID := com.afshinghezeli.Spindle.dev

.PHONY: app release run stop logs verify-bundle setup-signing reset-permissions

app: ## Assemble and sign dist/debug/Spindle.app
	Scripts/bundle.sh debug

release: ## Assemble dist/release/Spindle.app, universal unless ARCHES is set
	ARCHES="$${ARCHES:-arm64 x86_64}" Scripts/bundle.sh release

run: stop app ## Rebuild and relaunch the debug app
	open "$(DEBUG_APP)"

stop: ## Quit the running debug app
	@pkill -f "$(DEBUG_APP)/Contents/MacOS/Spindle" || true

logs: ## Stream the debug app's log messages
	/usr/bin/log stream --style compact --level debug --predicate 'subsystem == "$(DEV_BUNDLE_ID)"'

verify-bundle: ## Check the debug app's signature and resources as another Mac would see them
	Scripts/verify-bundle.sh "$(DEBUG_APP)"

setup-signing: ## One-time: create the local signing identity so permissions survive rebuilds
	Scripts/setup-dev-signing.sh

reset-permissions: ## Forget the privacy permissions granted to the debug app
	tccutil reset All $(DEV_BUNDLE_ID)
