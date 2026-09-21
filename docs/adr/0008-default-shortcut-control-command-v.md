---
status: accepted
date: 2026-09-22
---

# Open Spindle with ⌃⌘V by default

## Context and problem statement

Spindle needs a global shortcut that works the moment it's installed. A global hotkey takes the combination away from every other app. Changing the default later is a breaking change for everyone who learned it (ADR 0006), so it should be right from the first release. The shortcut can be changed in Settings, and onboarding shows it.

## Considered options

- ⇧⌘V, used by Paste, Clipy and Flycut
- ⇧⌘C, Maccy's default
- ⌥⌘V
- ⌥⌘C, Alfred's clipboard default
- ⌃⌘V

## Decision outcome

Chosen option: ⌃⌘V. It keeps the V that clipboard users associate with pasting, and the collision it causes is the smallest:

| Shortcut | Taken from |
|---|---|
| ⇧⌘V | "Paste and Match Style" in Mail, Notes, Pages, Safari, Chrome, Slack, Notion and most text editors; many people use it daily |
| ⇧⌘C | Finder's "Go to Computer", Chrome's inspect-element picker |
| ⌥⌘V | Finder's "Move Item Here", which completes a cut-and-paste of files |
| ⌥⌘C | Finder's "Copy as Pathname" |
| ⌃⌘V | Microsoft Word's "Paste Special"; nothing built into macOS |

The combination doesn't type a character, so it also works while Secure Input is on, for example in password fields and in Terminal with Secure Keyboard Entry.

### Consequences

- Good, because nothing people use across the system is lost, and it's easy to press with one hand.
- Bad, because it's less familiar than ⇧⌘V to people coming from Paste or Clipy. The onboarding screen shows the shortcut and lets them change it.
- Bad, because Word users lose Paste Special until they change one of the two shortcuts.

## More information

If users overwhelmingly reassign it, reconsider before 1.0, when a change would still be cheap.
