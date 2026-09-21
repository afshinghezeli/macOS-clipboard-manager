# Spindle

Clipboard history for the Mac. Press a shortcut, type a few letters, hit Return, and what you copied last week is pasted into the app you're using.

> **Status:** early development. There is no release yet. The [roadmap](docs/roadmap.md) shows what exists and what comes next.

## What it will do

The first release (0.1) is planned to:

- keep everything you copy (text, rich text, images, files, links, colors) for as long as you choose, with no item cap;
- find any of it as you type, including in a history of 100,000 items;
- paste the chosen item straight into the app you were in, or paste it as plain text;
- let you pin items you reuse;
- stay out of the way when nothing is happening.

It is a native macOS app written in Swift, with AppKit and SwiftUI, for macOS 15 and later.

## Privacy

These are design requirements, not features to add later:

- History stays on your Mac. There is no sync and no account.
- Copies that password managers mark as confidential ([nspasteboard.org](http://nspasteboard.org) markers) are never read or stored. Passwords, Keychain Access and common password managers are ignored by default.
- There is no telemetry, analytics or crash-reporting SDK. The only network traffic is the update check.
- The plan is to run inside the macOS App Sandbox with no network entitlement at all, so that other apps need your permission to read the history. [ADR 0002](docs/adr/0002-ship-a-sandboxed-developer-id-app.md) explains this and the test that confirms it works with pasting.

## Performance

Spindle is being built against explicit budgets: search results within 16 ms of a keystroke at 10,000 items, no measurable idle CPU, and memory use that doesn't grow with history size. [docs/performance.md](docs/performance.md) lists them and how they are measured; the benchmark suite arrives with the search work.

## Building from source

You need macOS 15 and the Command Line Tools (`xcode-select --install`); Xcode is optional.

```sh
git clone https://github.com/afshinghezeli/macOS-clipboard-manager.git
cd macOS-clipboard-manager
make setup && make run
```

[docs/development.md](docs/development.md) covers signing, permissions and troubleshooting.

## Contributing

Bug reports and pull requests are welcome. Please read [CONTRIBUTING.md](CONTRIBUTING.md) first, especially the list of things Spindle deliberately doesn't do. Security issues go through [private reporting](SECURITY.md).

## License

[GPL-3.0-only](LICENSE). The Spindle name and icon are not covered by the license.
