---
name: verify
description: Run Spindle's local checks (format lint, build, tests) and report the result. Use before every commit, after finishing a task, and whenever asked to check, verify or test the build.
allowed-tools: Bash(make *) Bash(swift build *) Bash(swift test *) Bash(swift format *)
---

# Verify

1. Run `make check`. It runs `swift format lint`, a debug build with warnings treated as errors, and the full test suite.
2. On failure, read the first error, fix the root cause and run it again. Never make a check pass by weakening it: no deleted assertions, skipped tests, `// swift-format-ignore` or relaxed warnings. If a check itself is wrong, fix it in a separate commit and say so.
3. Extra checks by area:
   - Scripts, `Support/Info.plist`, entitlements or resources: also `make app` and `make verify-bundle`.
   - Storage, search, ingest or the history list: also run the `performance` skill's checklist.
   - Anything visible in the panel or menu bar: `make run`, then describe exactly what the owner should look at. Don't claim UI works without it being seen.
   - Capture, paste or hotkeys: these need TCC grants, so unit tests can't cover them. Say which manual check (from docs/development.md) is required.
4. Report in one or two lines: which checks ran, pass or fail, the test count, and anything you couldn't verify.

If `swift build` fails with `Undefined symbols ... PackageDescription.Package.__allocating_init`, the machine has the stale Command Line Tools files described in docs/development.md ("Troubleshooting"). Apply the documented workaround; don't edit Package.swift to dodge it.
