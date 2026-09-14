# Open questions — one list

Every **unresolved** decision from [architecture.md](architecture.md),
[two-games.md](two-games.md) and [event-pages.md](event-pages.md), gathered here.
Assembled 2026-09-07.

**Answers live in [solved-questions.md](solved-questions.md).** Split out on 2026-09-13,
when the answered half had grown larger than this one and reading the list no longer told
you what was left to decide. A question moves there the moment it is answered and **keeps
its number** — numbers are never reused and never renumbered, so "question 27" in a commit
message or a docstring still finds exactly one thing. Cluster 4 and 7 appear in both files:
the heading stays here, where their open questions are. **Clusters 2 and 3 are fully answered
as of 2026-09-14** and so appear only in solved-questions.md now — a cluster heading moves
out entirely once nothing under it is still open, the same rule a single question follows.

Grouped by **when the answer is needed**, not by which document raised it. Several
questions filed separately turn out to be the same decision seen from different angles —
those are marked as clusters, and answering the cluster answers all of them.

Every question has a recommendation. If a recommendation is right, "yes" is a complete
answer; the reasoning is in the linked section.

**What is left: 15, 16, 18, 19** (authoring format), **22** (gizmo undo), **23, 25**
(deferred to stage E).

Clusters 2 and 3 are fully answered as of 2026-09-14 — 5, 6, 7, 9, 11, 12, 13 and 14 were
all decided that day, which unblocks both stage B and stage C's format design. Only cluster 4
and the two stage-E deferrals remain.

---

## How to read this

| Marker | Meaning |
| --- | --- |
| 🔴 | Irreversible or expensive to change later. Answer before the work it gates starts. |
| 🟡 | Needed before the stage that depends on it, but cheap to revisit. |
| ⚪ | Can be decided when it comes up. Listed so it is not forgotten. |

There is no ✅ row any more — a decided question is not here. See
[solved-questions.md](solved-questions.md).

Build stages referenced below are two-games.md §4.3: **A** shared spine, **B** game 1
slice, **C** event system, **D** game 2, **E** saves/battle/modes.

---

## Cluster 4 — Authoring format details 🟡

*Blocks: stage C's parser and the editor work. All cheap in isolation; listed together
because they should be consistent with each other.*

15. **Keep the terse command string form** `{"command": "mov n 2"}`? (architecture.md §12.1)
    The dock seeds it today. **Recommend keeping it as parse-time sugar** that expands
    immediately, so the graph editor only ever sees the long form.
16. **Structured conditions vs expression strings** (event-pages.md §6.1) — pages use
    structured entries, the `if` command uses strings. **Recommend keeping both**: pages are
    edited in a form and need validation, `if` is typed inline and needs arbitrary logic.
    Be explicit about the split rather than compromising.
18. **Route `wait` units** (event-pages.md §6.5) — steps or seconds? Steps are natural in
    game 1 and meaningless in game 2. **Recommend unit-tagged**, matching how
    conditions are structured.
19. **One document per event, or a map-level bundle?** (event-pages.md §6.6) Per-event files
    diff and move cleanly; a bundle avoids dozens of tiny files. **Recommend per-event**,
    with the dock able to open a map's worth at once.

Note that 15, 16 and 18 are the same instinct three times: **accept convenient shorthand at
the boundary, normalise immediately, keep exactly one shape in memory.** Worth adopting as a
stated rule so it does not have to be re-argued per field. 17 — answered, and now in
[solved-questions.md](solved-questions.md) — is that same rule applied to whole pages, which
is the argument that settled it.

---

## Cluster 6 — Editor tooling ⚪

*Blocks: the route gizmo work, which is late in stage B.*

22. **Gizmo undo strategy** (event-pages.md §6.3) — internal snapshot stack, or integrate
    with `EditorUndoRedoManager` so `Ctrl+Z` is uniform across gizmo and scene edits?
    **Recommend the snapshot stack**: routes are small, and the event dock already treats
    the file as source of truth with explicit Save/Reload, so it keeps one model of "when
    does my change hit disk" rather than two. The cost is that undo does not cross between
    gizmo edits and ordinary scene edits.

This is the largest single unknown in the plan in terms of implementation risk — not because
the decision is hard, but because Godot's editor undo is object-property shaped and the data
here is a file. Worth timeboxing when it comes up.

**Wishlist, added 2026-09-14** — not decisions, no recommendation needed, just noted so
they're not lost before the tooling work starts:

- **Area gizmos should scale with distance.** An `AreaZone`'s marker (§4.2's sibling problem
  for `core/areas/`, not routes) is presumably a fixed-size icon or handle today; at a
  Godot-editor-plugin level that reads as huge up close and invisible from across a large
  map unless it scales with camera distance the way Godot's own light and audio gizmos do.
- **A snap-to-cell button or shortcut on the root `Actor`/event node**, `@tool`-scripted, so
  placing a guard or a chest by eye and then snapping it onto the grid is one action instead
  of hand-typing a `Vector3i` into an inspector field or eyeballing pixel-perfect placement.
- **A static route preview, not just the animated one.** §4.2's ghost-sprite preview
  (event-pages.md) answers "what does walking it look like"; this is the cheaper, always-on
  question — draw the path over the map while editing waypoints or a `steps` list (event-
  pages.md §3), and colour a segment that would hit a wall, so a bad route is visible while
  authoring it rather than only discovered on playtest or by running the animated preview.
- **Resuming a save mid-step, mid-command.** Touches architecture.md §12 Q4 (save format),
  which currently recommends the simpler "ambient events always restart from the top" —
  this wishlist item is the harder version, capturing an `EventRunner` at whatever command it
  was mid-executing (and a `GridMotion` mid-step) rather than only at a graph's top or a
  round boundary. Worth re-opening Q4 with this in mind once stage C's runner exists, rather
  than deciding it in the abstract now.

---

## Cluster 7 — Deferred by design ⚪

*Not needed until stage E. Recorded so they are not discovered instead of decided.*

23. **Mid-execution page switch** (event-pages.md §6.2) — defer to graph completion, defer
    to round close, or swap immediately? **Recommend defer to graph completion.** Prevents
    "the chest changed art halfway through its own cutscene".
25. **Save format: in-flight ambient runners** (architecture.md §12.4) — captured, or are
    ambient events always restartable from the top? **Recommend restartable** — much simpler
    and almost always enough. Saved regardless, per two-games.md §3.10: self flags,
    variables, monster `credit`, **and route progress** (waypoint index plus `pingpong`
    direction) — the last of which the original envelope omitted.

24 and 26 were answered and have moved to [solved-questions.md](solved-questions.md).

---

## If there is only time for a few

Nothing 🔴 is left. Stage A is built and green, so the order is now the order the stages
need:

1. **Question 11** — is monster AI authored as graphs? Sets how much of stage C must be
   right before game 1 is playable, though routes make it a smaller bet than it looked.
   Needed before stage B's monster.
2. **Questions 6, 7, 9** — what opens and closes a round. All of stage B's step pulse.
   (8 is cut: no watchdog.)
3. **Question 5** — camera ownership, for the rigs already stubbed in stage A.
4. **Cluster 4** (15, 16, 18, 19) — the authoring format, before stage C's parser.

**No art decision is outstanding** — directions, yaw stops, pitch and texel density are all
settled, so tile and character art can start. Everything remaining can be answered as its
stage arrives.
