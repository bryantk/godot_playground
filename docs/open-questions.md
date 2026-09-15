# Open questions — one list

Every **unresolved** decision from [architecture.md](architecture.md),
[two-games.md](two-games.md) and [event-pages.md](event-pages.md), gathered here.
Assembled 2026-09-07.

## Nothing is open

**As of 2026-09-14 every numbered question is answered.** All 38 live in
[solved-questions.md](solved-questions.md) with their reasoning. Cluster 4 was the last to
close, and question 16 — conditions — was the last question in it.

This file is kept rather than deleted, for three reasons: the numbering rules below still
govern anything asked from here on; the tooling wishlist has nowhere better to live; and the
next real decision should arrive as a numbered question in this file rather than as a choice
someone quietly makes while implementing. **The next question asked is 39.** Numbers are
never reused and never renumbered, so "question 27" in a commit message or a docstring still
finds exactly one thing.

When a question is added here, it takes the next number, gets a recommendation, and moves to
[solved-questions.md](solved-questions.md) the moment it is answered — keeping its number,
and keeping the reasoning so the decision is not re-argued.

| Marker | Meaning |
| --- | --- |
| 🔴 | Irreversible or expensive to change later. Answer before the work it gates starts. |
| 🟡 | Needed before the stage that depends on it, but cheap to revisit. |
| ⚪ | Can be decided when it comes up. Listed so it is not forgotten. |

Build stages referenced in both files are two-games.md §4.3: **A** shared spine, **B** game 1
slice, **C** event system, **D** game 2, **E** saves/battle/modes. Stage A is built and
green. **Nothing gates stage B or C any more** — the remaining work is building them.
[next-session.md](next-session.md) is the work queue; solved-questions.md is only the record.

---

## Wishlist — editor tooling

Not decisions, no recommendation needed, just noted so they're not lost before the tooling
work starts. Added 2026-09-14, and kept here when question 22 closed cluster 6 — these are
not questions, so the rule about headings following their open questions does not apply.

- **A snap-to-cell button or shortcut on the root `Actor`/event node**, `@tool`-scripted, so
  placing a guard or a chest by eye and then snapping it onto the grid is one action instead
  of hand-typing a `Vector3i` into an inspector field or eyeballing pixel-perfect placement.
  Reaffirmed 2026-09-14: this will be wanted **often**, on events and actors both, so it is
  the first piece of gizmo tooling to build rather than a nicety at the end.
- **Area gizmos should scale with distance.** An `AreaZone`'s marker (§4.2's sibling problem
  for `core/areas/`, not routes) is presumably a fixed-size icon or handle today; at a
  Godot-editor-plugin level that reads as huge up close and invisible from across a large
  map unless it scales with camera distance the way Godot's own light and audio gizmos do.
- **A static route preview, not just the animated one.** §4.2's ghost-sprite preview
  (event-pages.md) answers "what does walking it look like"; this is the cheaper, always-on
  question — draw the path over the map while editing waypoints or a `steps` list (event-
  pages.md §3), and colour a segment that would hit a wall, so a bad route is visible while
  authoring it rather than only discovered on playtest or by running the animated preview.
- **Resuming a save mid-step, mid-command.** Question 25 took the first half of this
  (an in-flight ambient runner records the node it was in); the harder version is capturing
  an `EventRunner` at whatever *command* it was mid-executing, and a `GridMotion` mid-step.
  Worth re-opening once stage C's runner exists, rather than deciding it in the abstract.
- **Condition tooling, unlocked by question 16.** Because `if` strings now parse to the same
  structured condition pages use, these become writable at any point and none is owed in
  stage C: a condition **builder widget** for `if`, a **rename-this-flag-everywhere**
  refactor across pages and graphs, and a **"what would make this branch take"** inspector.
