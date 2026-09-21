---
name: next-task
description: Take the next open task from docs/roadmap.md (or a given task ID such as M1.3) and carry it all the way through: plan, implement, test, verify, commit and tick it off. Use when asked to continue the roadmap, work on the next task, or implement a specific task.
argument-hint: "[task-id]"
---

# Next task

Work in small, finished steps. One task at a time, never two half-done ones.

1. **Pick.** Read docs/roadmap.md. Use `$ARGUMENTS` if a task ID was given; otherwise take the first unchecked task in the lowest open milestone whose prerequisites are done. Say which task you are taking.
2. **Load context.** Read the task's acceptance notes, the ADRs it touches (docs/adr/), and the relevant part of docs/ARCHITECTURE.md. For capture, paste, hotkey, permission or panel-window work, load the `macos-clipboard` skill. For storage, search, ingest or list work, load the `performance` skill.
3. **Size it.** If the task looks bigger than about 400 changed lines or one sitting, split it into subtasks in the roadmap first and commit that as `docs: split <task-id> into smaller steps`.
4. **Plan briefly.** List the files and types you will add or change and the tests that prove it works. If you hit a real design choice that no ADR covers and that is hard to reverse, write one with `/adr` before coding.
5. **Implement in small steps.** For pure logic (SpindleCore, SpindleStorage), write the test first. Keep every intermediate commit building and green.
6. **Verify.** Run `/verify`. For UI or system integration, also run the app and list what was checked by hand and what still needs the owner's eyes.
7. **Update docs** affected by the change: ARCHITECTURE.md, the README shortcut table, docs/development.md.
8. **Tick the box** in docs/roadmap.md in the same commit as the last piece of the work.
9. **Commit** with `/commit`. A task usually ends up as one to three commits.
10. **Report** what was done, how it was verified, and anything deferred. Add deferred work to the roadmap as a new task instead of leaving a TODO.

Stop and ask the owner before continuing when:
- the acceptance notes are ambiguous in a way that changes what users see,
- a new third-party dependency, entitlement or permission would be needed,
- the work touches a non-goal from CLAUDE.md,
- an accepted ADR turns out to be wrong.
