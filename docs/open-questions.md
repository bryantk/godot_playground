# Open questions — one list

Every **unresolved** decision from [architecture.md](architecture.md),
[two-games.md](two-games.md) and [event-pages.md](event-pages.md), gathered here.
Assembled 2026-09-07.

## Two questions are open

**Question 46 — what drives a monster?** Opened 2026-09-14, deferred the same day.
**Question 53 — the `eval` leaf/node's binding and subscription shape.** Opened 2026-09-17,
parked the same day while planning segment 4 in detail.

Every other numbered question is answered — 50 of the 52 asked so far — and live in
[solved-questions.md](solved-questions.md) with their reasoning (questions 48–52 were added
and answered the same day 53 was opened, while planning segment 4 — see
[stage-c-plan.md](stage-c-plan.md)). This file emptied entirely on 2026-09-14 when question 16
closed cluster 4, and re-opened that afternoon when planning stage C struck the step pulse
(question 42) and left a hole where game 1's monster timing used to be.

The numbering rules still govern everything asked from here on. **The next question asked is
54.** Numbers are never reused and never renumbered, so "question 27" in a commit message or
a docstring still finds exactly one thing. A question added here takes the next number, gets
a recommendation, and moves to [solved-questions.md](solved-questions.md) the moment it is
answered — keeping its number, and keeping the reasoning so the decision is not re-argued.

| Marker | Meaning |
| --- | --- |
| 🔴 | Irreversible or expensive to change later. Answer before the work it gates starts. |
| 🟡 | Needed before the stage that depends on it, but cheap to revisit. |
| ⚪ | Can be decided when it comes up. Listed so it is not forgotten. |

---

## Cluster 11 — What the world does on its own 🟡

*Blocks: nothing yet. Wanted before game 1 has a monster worth fighting.*

46. **What drives a monster, now that the step pulse is struck?** (question 42,
    [stage-c-plan.md](stage-c-plan.md)) The docs had monsters acting on the player's step,
    with speed classes and `credit` deciding how often. All of that is gone, and nothing
    replaced it.

    **Deferred deliberately on 2026-09-14** — Kyle's call, and stage C is built so that it
    does not have to be answered first. **No recommendation yet**, on purpose: the three
    candidates are a real choice about what game 1 *is*, not an implementation detail.

    - **Its own clock, in real time.** Routes tick on delta as background runners, exactly
      like game 2's actors but grid-snapped. The player's stepping and the monster's stepping
      are unrelated, and contact triggers fire whenever the two meet.
    - **Still step-driven, minus the machinery.** `actor_stepped` is the cue — it already
      fires unconditionally for every grid actor — but with no credit accounting and no input
      gate. A slow monster keeps its own counter and skips every other step.
    - **Per-event choice.** A page setting picks, and both mechanisms exist.

    **What stage C assumes in the meantime:** routes run as background runners on delta,
    because that is the only clock left once the pulse is gone, and segment 7 needs *a* clock
    to be testable at all. That assumption is **one call site** — `EventScheduler.tick` — so a
    step-driven answer can replace it without touching route compilation, the runner, the save
    format or any authored document. This is the thing to check before the answer is written
    down: if it stops being one call site, the cost of deferring has gone up.

---

## Cluster 12 — The `eval` escape hatch 🟡

*Blocks: nothing in segment 4 as scoped — `eval` is additive, not on the path any existing
worked example needs. Wanted before an author reaches for logic the structured condition tree
can't express.*

53. **`eval` — a raw `Expression`-evaluated condition leaf and graph node, for logic outside
    the structured tree's grammar entirely** (e.g. `"chapter * 2 + State.gold > 200"`).
    Opened and parked 2026-09-17 while planning segment 4 — Kyle's call to resolve the shape
    later rather than now, leaning toward the recommendation below rather than deciding it.

    Confirmed already: it composes with `all`/`any`/`not` as a leaf (`{"eval": "..."}"`) and
    also exists as a standalone graph node mirroring `if`'s two-port shape, both backed by one
    execution function using Godot's real `Expression` class — deliberately not the hand-rolled
    tokenizer question 16 built, since the whole point is arithmetic and method calls the
    structured grammar doesn't have.

    **Not yet decided:**
    - **What `State` binds to inside the expression.** Leaning toward a small read-only facade
      (`_get(property)` proxying to `GameState.var_get`) rather than the live `GameState`
      autoload itself, so a condition can't reach a mutating method — but exposing the full
      autoload (flags, self flags, everything) is the more powerful alternative and hasn't been
      ruled out.
    - **How it answers `keys()`.** An `eval` string can't be statically analysed for what it
      reads the way a structured leaf can. Leaning toward an optional, author-supplied `watch`
      list (`{"eval": "...", "watch": ["chapter", "gold"]}`) — absent means the condition
      contributes no subscription keys, with a parse-time warning, the same "absent means
      false, and says so once" pattern `item`/`party_has` already use.
    - **Validation depth.** Only a syntax check (`Expression.parse()` succeeds) seems honest —
      no manifest cross-check the way `var`/`flag` leaves get, since the expression can
      reference arbitrary properties a manifest can't enumerate. Not yet confirmed as the final
      word on it.

---

Build stages referenced in both files are two-games.md §4.3: **A** shared spine, **B** game 1
slice, **C** event system, **D** game 2, **E** saves/battle/modes. Stage A is built and green,
and stage C is being built now to [stage-c-plan.md](stage-c-plan.md). **Nothing gates stage B
or C** — 46 is wanted before game 1 has a monster worth fighting, 53 before an author needs
`eval`'s expressive power, and nothing sooner. [next-session.md](next-session.md) is the work
queue; solved-questions.md is only the record.

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
  (an in-flight background runner records the node it was in); the harder version is capturing
  an `EventRunner` at whatever *command* it was mid-executing, and a `GridMotion` mid-step.
  Worth re-opening once stage C's runner exists, rather than deciding it in the abstract.
- **Condition tooling, unlocked by question 16.** Because `if` strings now parse to the same
  structured condition pages use, these become writable at any point and none is owed in
  stage C: a condition **builder widget** for `if`, a **rename-this-flag-everywhere**
  refactor across pages and graphs, and a **"what would make this branch take"** inspector.
