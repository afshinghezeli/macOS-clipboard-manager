---
status: accepted
date: 2026-09-22
---

# Build with SwiftPM and a bundle script, without an Xcode project

## Context and problem statement

Spindle is a menu bar app written in Swift with AppKit and SwiftUI. The main development Mac has only the Command Line Tools (Swift 6.1.2, macOS 15.5 SDK), and contributors shouldn't need Xcode to build or test it. CI runners have Xcode. The build has to produce a signed, universal `.app` with an embedded Sparkle framework, and it has to behave the same locally and in CI.

## Considered options

- Commit an `.xcodeproj`
- Generate the project with XcodeGen or Tuist
- `swift-bundler`
- Plain SwiftPM, plus a shell script that assembles and signs the `.app`

## Decision outcome

Chosen option: plain SwiftPM with `Scripts/bundle.sh` and a `Makefile`. It is the only option that builds with the Command Line Tools alone. XcodeGen and Tuist still need Xcode to build, an `.xcodeproj` produces unreviewable diffs, and swift-bundler's last release was in April 2025.

Platform baseline that goes with this:

- `swift-tools-version: 6.1`, Swift 6 language mode, only upcoming features that Swift 6.1 knows.
- Deployment target macOS 15.0. That was about 99% of active Macs in the TelemetryDeck sample from July 2026. It gives us the Swift Vision API for OCR and the macOS 15 SwiftUI window APIs. The pasteboard privacy APIs (15.4) and Liquid Glass (26) go behind availability checks.
- Universal binary, built one architecture at a time and joined with `lipo`, because multi-arch `swift build` needs Xcode.

### Consequences

- Good, because `swift build`, `swift test` and `make app` work on any Mac with the Command Line Tools, and CI runs the same commands.
- Good, because the whole build is readable in two files, and contributors with Xcode can still open `Package.swift`.
- Bad, because there are no asset catalogs or String Catalogs (`actool` and `xcstringstool` ship only with Xcode). The icon is an `.icns` built with `iconutil`, and localizations are `.strings` files.
- Bad, because macros whose plugins ship only with Xcode can't be used: `#Preview`, SwiftData `@Model`, SwiftUI `@Entry`, `#Predicate`. This also rules out dependencies that use them, such as KeyboardShortcuts.
- Bad, because SwiftPM's generated `Bundle.module` looks for resources in the wrong place inside a signed `.app`. Each target with resources gets its own accessor.
- Bad, because we own Info.plist generation, code signing order and rpaths.

## More information

- Precedents: CodexBar and Trimmy, both pure-SwiftPM menu bar apps.
- Revisit when the local toolchain moves to Swift 6.2 or later. Bump the tools version and the CI Xcode together. Swift 6.4 makes Swift Build the default, which changes where resource bundles land.
