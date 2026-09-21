---
paths:
  - "**/*.md"
  - "Sources/**/*.strings"
---

# Writing docs and UI copy

Spindle's docs are read by people deciding whether to trust an app with everything they copy. Write like a careful engineer explaining their own project.

- Be specific. "Keeps 100,000 items; search answers in under 16 ms on an M1" beats "fast". Every claim must be true today and, where it is a number, measured (say how).
- Delete any sentence that would be equally true of another clipboard manager.
- No emoji in headings or bullets. No badge walls (two at most, in the README).
- Banned words: seamless, robust, powerful, blazing, lightning, effortless, elevate, supercharge, leverage, empower, delve, cutting-edge, game-changer, "take X to the next level", comprehensive, intuitive.
- Avoid the "not just X, but Y" construction, rule-of-three padding and bold scattered through paragraphs.
- Headings in sentence case. Short paragraphs. Lists only when the content is a list.
- Name exact places: "System Settings → Privacy & Security → Accessibility", "~/Library/Containers/com.afshinghezeli.Spindle".
- State limits and non-goals plainly. Say what Spindle doesn't do and why.
- First person singular ("I") is fine in the README motivation and release notes; the docs otherwise use "Spindle" or "you".
- American spelling.
- Size docs to the project: README around 100–150 lines, CONTRIBUTING under a page, SECURITY around 15 lines.
- Changelog lines describe what users notice ("Pasting into Terminal no longer drops the first character"), not code changes.
- Before committing a doc, grep it for placeholders: `TODO`, `TBD`, `example.com`, `yourname`, `INSERT`.
