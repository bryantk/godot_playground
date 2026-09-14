# Open questions — one list

Every **unresolved** decision from [architecture.md](architecture.md),
[two-games.md](two-games.md) and [event-pages.md](event-pages.md), gathered here.
Assembled 2026-09-07.

**Answers live in [solved-questions.md](solved-questions.md).** Split out on 2026-09-13,
when the answered half had grown larger than this one and reading the list no longer told
you what was left to decide. A question moves there the moment it is answered and **keeps
its number** — numbers are never reused and never renumbered, so "question 27" in a commit
message or a docstring still finds exactly one thing. Clusters 2, 4 and 7 appear in both
files: the heading stays here, where their open questions are.

Grouped by **when the answer is needed**, not by which document raised it. Several
questions filed separately turn out to be the same decision seen from different angles —
those are marked as clusters, and answering the cluster answers all of them.

Every question has a recommendation. If a recommendation is right, "yes" is a complete
answer; the reasoning is in the linked section.

**What is left: 5, 6, 7, 9** (control and rounds), **11–14** (how much lives in data),
**15, 16, 18, 19** (authoring format), **22** (gizmo undo), **23, 25** (deferred to stage E).

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

## Cluster 2 — Who owns control? 🟡

*Stage A is built. 8, 10, 27 and 28 are answered and have moved to
[solved-questions.md](solved-questions.md); what remains is 🟡 again.*

5. **Camera ownership** (architecture.md §12.6) — does the camera follow the player by
   default with events borrowing it, or is it always driven by whoever holds the exclusive
   slot? **Recommend:** follow by default; events borrow and return, via `CameraRig.lock()`.
6. **Does turning in place open a round?** (two-games.md §5.1) **Recommend no** — turning
   changes no cell. Also a difficulty lever: "no" lets the player re-aim for free before a
   fight.
7. **Does bumping a wall open a round?** (two-games.md §5.1) **Recommend no**, plus an
   explicit "wait one step" input, so passing time is a choice rather than a wall-bumping
   trick.
9. **Does scripted player movement pulse?** (two-games.md §5.1) **Recommend no** — pulses
   suppressed outside `Field` mode, with an opt-in `pulse: true` on move commands. Another
   consumer of `ModeStack`.

**The synthesis, revised:** 5 and 9 are "does the event system take over, or borrow?"; 6 and
7 are "what closes a round?"; 27 and 28 were "who arbitrates, and what is scoped to a map?".
The general principle — *events borrow and must return; rounds close on cell changes only;
`ModeStack` arbitrates and `MapContext` owns per-map state* — answers all of them. It used to
read "rounds close on cell changes only, **with a hard time bound**"; the time bound was 8,
and 8 was cut.

---

## Cluster 3 — How much is data, how much is code? 🟡

*Blocks: stage C. This is the project's central bet, and worth deciding as one thing.*

11. **Is monster AI authored as event graphs?** (two-games.md §5.3) **Recommend yes**, with
    routes (event-pages.md §3) carrying the common cases so graphs are only needed for
    genuinely scripted monsters. Note this is a **smaller bet than first filed**:
    event-pages.md §3's `toward`/`away`/`random` route modes already handle most monsters
    with no graph at all, so "the format is expressive enough" is being asked of scripted
    monsters only, not of every slime.
12. **Sub-graphs** (architecture.md §12.2) — does `call` run another `.event.json`, and does
    the callee share the caller's context or get its own? **Recommend yes, own context**,
    with explicit argument passing.
13. **Can a graph set its own page?** (event-pages.md §6.7) A `set_page` command is
    convenient and undermines conditions being the single source of truth. **Recommend no.**
14. **`GameState` scope** (architecture.md §12.3) — flags and ints only, or typed variables
    with a declared manifest so editors can offer dropdowns? **Recommend the manifest**:
    event-pages.md §2.2 conditions want a variable picker, and a manifest is what makes one
    possible.

**Note how 11 and 14 pull together:** the more behaviour lives in data, the more the editors
need to know what the data *can* say. A manifest is cheap when written early and awkward to
retrofit once graphs reference bare strings.

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
