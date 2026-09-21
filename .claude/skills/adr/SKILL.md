---
name: adr
description: Record an architecture decision in docs/adr using the short MADR 4.0 format. Use when a choice is hard to reverse, spans several modules, adds a dependency, changes the storage format, permissions or distribution, or when asked to "record a decision" or "write an ADR".
argument-hint: "[decision title]"
---

# Architecture decision record

Write ADRs only for decisions someone would later ask "why did we do it this way?" about. Trivial choices don't get one.

1. List `docs/adr/` and take the next four-digit number.
2. Create `docs/adr/NNNN-<decision-in-kebab-case>.md`. Title it with the decision itself, phrased as an action: "Store history in SQLite with GRDB", not "Database".
3. Use this template and keep the whole record under a page:

   ```markdown
   ---
   status: proposed | accepted | superseded by [NNNN](NNNN-title.md)
   date: YYYY-MM-DD
   ---

   # <Decision>

   ## Context and problem statement

   Two to five sentences: the forces at play, the constraint that makes this a real choice, measured numbers if there are any.

   ## Considered options

   - Option A
   - Option B

   ## Decision outcome

   Chosen option: "<option>", because <the deciding reason>.

   ### Consequences

   - Good, because ...
   - Bad, because ...

   ## More information

   Links to evidence, benchmarks, issues, and the condition under which to revisit this decision.
   ```

4. Only list options that were really considered, each with the reason it lost. Include the downside of the chosen option; there always is one.
5. Add a one-line entry to the "Decisions" list in docs/ARCHITECTURE.md.
6. To change an accepted decision, write a new ADR and set the old one's status to `superseded by`. Don't rewrite history.
7. Commit on its own: `docs: add ADR NNNN on <topic>`.
