# Development

How to build, run and debug Spindle. For how the code is organized, see [ARCHITECTURE.md](ARCHITECTURE.md).

## Requirements

- macOS 15.0 or later.
- The Command Line Tools (`xcode-select --install`) or Xcode 16.4 or later. Xcode isn't required; everything builds with the Command Line Tools and SwiftPM.

## First run

```sh
make setup           # point git at .githooks (commit message check)
make setup-signing   # create the local signing identity (see below)
make run             # build, assemble dist/debug/Spindle.app, launch it
```

Debug builds use the bundle id `com.afshinghezeli.Spindle.dev` and show up as "Spindle Dev". They keep their own history, settings and permissions, separate from a released copy of Spindle.

## Everyday commands

| Command | What it does |
|---|---|
| `make build` | Debug build of all targets |
| `make test` | Run the swift-testing suites |
| `make lint` / `make format` | Check / apply formatting with `swift format` |
| `make check` | lint, build with warnings as errors, tests: what CI runs |
| `make app` | Assemble and sign `dist/debug/Spindle.app` |
| `make run` | `make app`, quit the running copy, `open` the new one |
| `make logs` | Stream the app's log messages |
| `make verify-bundle` | Launch the packaged app with the source checkout unreadable, to catch resource lookups that only work on the build machine |
| `make clean` | Remove `.build` and `dist` |

Always launch the app with `open` (which `make run` does), never by running the binary inside the bundle. macOS attributes permission prompts from a bare binary to Terminal.

## Why a local signing identity

Spindle pastes by posting ⌘V to the app you were using. macOS only allows that for apps you have approved in System Settings → Privacy & Security → Accessibility, and it remembers the approval by the app's code signature. An ad-hoc signature changes with every build, so the approval silently stops applying: the switch in System Settings still looks on, but pasting does nothing.

`make setup-signing` creates a self-signed code-signing certificate in its own keychain, and every dev build is signed with it. The signature stays the same across rebuilds, so the approval survives. It isn't trusted by anyone else and can't be used to distribute builds.

To start over with permissions:

```sh
tccutil reset PostEvent com.afshinghezeli.Spindle.dev
tccutil reset Accessibility com.afshinghezeli.Spindle.dev
```

## Tests

- Tests use swift-testing (`import Testing`). XCTest isn't available with the Command Line Tools.
- Pasteboard tests run against private pasteboards (`NSPasteboard.withUniqueName()`), never the real clipboard, so running the tests doesn't disturb what you copied.
- Database tests use in-memory databases.
- Anything that needs a permission (posting events, reading other apps' windows) is behind a protocol and tested with a fake. The real thing is checked by hand; see below.

## Manual checks

Some behavior can't be tested automatically because it depends on permissions and other apps. Before merging changes to capture or paste, check the relevant items:

- Copy plain text, rich text from Safari or Pages, an image, and several files in Finder; each appears once, with the right kind and source app.
- Copy a password from 1Password or KeePassXC; it must not appear.
- Paste with ↵ into TextEdit, Safari's address bar, Terminal and an Electron app (Slack, VS Code); the text lands in the app you came from.
- Paste with a non-QWERTY layout (Dvorak, AZERTY) selected.
- Open the panel over a full-screen app and on a second display.

## Troubleshooting

### `swift build` fails with "Undefined symbols … PackageDescription.Package.__allocating_init"

Some Command Line Tools installs contain stale `*.private.swiftinterface` files left over from an older version. The compiler prefers them over the current ones, so every `Package.swift` fails to link. To check:

```sh
ls -l /Library/Developer/CommandLineTools/usr/lib/swift/pm/*/*.swiftmodule/
```

If a `*.private.swiftinterface` file is older than the `*.swiftinterface` file next to it, it is stale. Remove the stale ones (or reinstall the Command Line Tools):

```sh
sudo rm /Library/Developer/CommandLineTools/usr/lib/swift/pm/*/*.swiftmodule/*.private.swiftinterface
```

If you can't use `sudo`, `Scripts/clt-workaround.sh` makes a cleaned copy of those files inside the repo (`.local/`) and writes a `local.mk` that points SwiftPM at it. The Makefile picks up `local.mk` automatically. Both are git-ignored.

### Pasting does nothing

Check System Settings → Privacy & Security → Accessibility. If "Spindle Dev" is listed and on but pasting still fails, the build was probably signed ad hoc. Run `make setup-signing`, `make run`, then reset the permission as shown above and grant it again.

### Nothing gets captured on macOS 15.4 or later

Check System Settings → Privacy & Security → Paste from Other Apps. If Spindle is set to Ask or Deny, macOS blocks it from reading the clipboard in the background.
