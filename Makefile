# Spindle build commands. `make help` lists them. docs/development.md explains the details.

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# Per-machine overrides (git-ignored). Scripts/clt-workaround.sh writes one when needed.
-include local.mk

SWIFT_SOURCES := Package.swift Sources Tests
STRICT := -Xswiftc -warnings-as-errors

.PHONY: help setup build test lint format check bench screenshots clean

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
	python3 -m unittest discover --start-directory Scripts/tests

bench: ## Time search, paging and ingest at 10,000 and 100,000 items (release build)
	swift run -c release SpindleBench

screenshots: ## Render the README's screenshots into docs/images
	rm -rf .build/screenshots
	SPINDLE_SNAPSHOT_DIR="$(CURDIR)/.build/screenshots" swift test --filter readmeScreenshots
	mkdir -p docs/images
	cp .build/screenshots/readme-panel-*.png docs/images/

clean: ## Remove build products
	rm -rf .build dist

# ------------------------------------------------------------------------------ the app

DEBUG_APP := dist/debug/Spindle.app
DEV_BUNDLE_ID := com.afshinghezeli.Spindle.dev

.PHONY: app release package run stop logs verify-bundle setup-signing sparkle-keys reset-permissions

app: ## Assemble and sign dist/debug/Spindle.app
	Scripts/bundle.sh debug

release: ## Assemble dist/release/Spindle.app, universal unless ARCHES is set
	ARCHES="$${ARCHES:-arm64 x86_64}" Scripts/bundle.sh release

package: ## Make the ZIP, DMG and dSYM archives from the release app
	Scripts/package.sh

run: stop app ## Rebuild and relaunch the debug app
	open "$(DEBUG_APP)"

stop: ## Quit the running debug app
	@pkill -f "$(DEBUG_APP)/Contents/MacOS/Spindle" || true

logs: ## Stream the debug app's log messages
	/usr/bin/log stream --style compact --level debug --predicate 'subsystem == "$(DEV_BUNDLE_ID)"'

verify-bundle: ## Check an app's signature and resources as another Mac would; APP=… for another bundle
	Scripts/verify-bundle.sh "$${APP:-$(DEBUG_APP)}"

setup-signing: ## One-time: create the local signing identity so permissions survive rebuilds
	Scripts/setup-dev-signing.sh

sparkle-keys: ## Owner only, once: create the key that signs updates (docs/releasing.md)
	swift package resolve
	@# Creates the key in the login keychain, or shows the existing one.
	.build/artifacts/sparkle/Sparkle/bin/generate_keys
	.build/artifacts/sparkle/Sparkle/bin/generate_keys -p > Support/sparkle-public-key.txt
	@echo "Wrote Support/sparkle-public-key.txt; commit it. The private key stays in your keychain."

reset-permissions: ## Forget the privacy permissions granted to the debug app
	tccutil reset All $(DEV_BUNDLE_ID)
