# Open questions — one list

Every unresolved decision from [architecture.md](architecture.md),
[three-games.md](three-games.md) and [event-pages.md](event-pages.md), gathered here.
Assembled 2026-09-07. **Revised 2026-09-08** after a review pass: Clusters 1 and 7 closed,
`GameProfile` specified, two new 🔴 items found (27, 28), and one arithmetic error corrected
in three-games.md §3.6. The decision table below is the summary.

Grouped by **when the answer is needed**, not by which document raised it. Several
questions filed separately turn out to be the same decision seen from different angles —
those are marked as clusters, and answering the cluster answers all of them.

Every question has a recommendation. If a recommendation is right, "yes" is a complete
answer; the reasoning is in the linked section.

---

## How to read this

| Marker | Meaning |
| --- | --- |
| 🔴 | Irreversible or expensive to change later. Answer before the work it gates starts. |
| 🟡 | Needed before the stage that depends on it, but cheap to revisit. |
| ⚪ | Can be decided when it comes up. Listed so it is not forgotten. |
| ✅ | Decided. Kept here with its answer so the decision is not re-argued. |

Build stages referenced below are three-games.md §4.3: **A** shared spine, **B** game 1
slice, **C** event system, **D** game 3 slice, **E** game 2, **F** saves/battle/modes.

---

## Decided 2026-09-08 — the short version

| # | Decision |
| --- | --- |
| 1–4 | Game 1 steps 4-way with 4 sprite directions. Game 2 moves freely with 8. Game 3's mesh rotates to its true heading. Game 2's camera snaps to **4 yaw stops at 90°** at **pitch 30°** — a 16 × 8 px ground tile. Texel density is **16 px per tile** (14 on vertical faces), and game 2's player moves sub-pixel. |
| 10 | The step pulse **and** cell triggers both fire at step commit. `fire_on` is deleted; `wait_settle` replaces it. |
| 17 | Pages inherit nothing. Absent means default. |
| 24 | Game 1 has a **separate battle scene**. `ModeStack` therefore moves into stage A. |
| 26 | Games 2 and 3 do **not** share maps. A map belongs to exactly one profile. |
| 29 | `GameProfile` specified (three-games.md §2.1): a Resource with a closed capability enum **and** the three axis scripts. Each game is its own executable; no runtime selection. |
| — | Within one pulse, responders resolve **actor-at-a-time** (each drains its credit before the next acts). |
| — | Occupancy is only ever written through `Occupancy.commit(changes)`, including for a single step. |

---

## Cluster 1 — "Four or eight?" ✅

*Blocked: all art production, and stage B's movement feel. Resolved.*

1. **Grid movement: 4-way or 8-way?** → **4-way in game 1.** Games 2 and 3 use `FreeMotion`.
2. **Sprite directions: 4 or 8?** → **4 for game 1, 8 for game 2.** Game 3 uses `MeshView3D`
   and rotates to its true continuous heading, so the count never applied to it.
3. **Camera yaw stops in game 2: 4 or 8?** → **4, at 90°.**
4. **Ortho pitch for game 2** → **30°**, giving a 16 × 8 px ground tile, exactly 2:1. The
   shallowest of the pixel-clean angles, and so the one that shows height best — which suits
   the game that has jumping and ledges.

Plus two decisions this cluster did not originally contain: **texel density is 16 px per
tile** (one world unit = one tile = 16 px), with game 2's player moving sub-pixel; and
**vertical faces should be authored at 14 texels per world unit of height**, not 16.

**Only a short list of pitches was ever usable.** At 90° yaw stops a ground tile projects to
16 × 16·sin θ px, and a fractional height makes the tile grid drift against the pixel grid —
rows land 11 px in some places and 12 px in others. So the candidates were exactly the angles
where `16·sin θ` is an integer: 30.00°, 34.23°, 38.68°, 43.43°, 48.59°, 54.34°, 61.04°,
69.64°. Every round number that looks like a natural choice — 45°, 60° — is fractional.

**Floors and walls cannot both be clean**, which is what the 14-texel recommendation is for. A
vertical face is `√(256 − n²)` px per tile of height and 256 has no Pythagorean pair, so an
integer floor forces a fractional wall. Floors tile across the whole screen and walls once per
structure, so the floor takes the integer — but 30° has the tallest vertical faces of any
candidate (13.856 px per tile), so it has the most wall to resample. Authoring vertical art at
14 texels per unit maps it to 13.856 px: a 1% squash instead of 14% of rows dropped unevenly.

**Why 4 yaw stops turned out to be the cheap answer**, and the thing the original 🔴 framing
got wrong: at 90° stops all four views are congruent, so ground tiles stay axis-aligned and
there is exactly **one tile geometry** to draw. At 45° stops the odd stops render tiles as
diamonds and the even stops render them axis-aligned; those are not congruent at any pitch,
so 8 stops costs two distinct tile presentations rather than merely twice the sprite art.

**And why the pitch stopped being 🔴 at all:** because the four views are congruent, pitch
does not have to agree with any tile grid — game 2's tiles are real 3D meshes and carry no
implied camera angle. Only *sprites* bake in a pitch. So the pitch can be parameterised and
swept, and what actually gates art is the texel density, which is pitch-independent and
decided.

**8 facings against 90° stops is exact**, which is the property that makes the combination
work: frames are 45° apart, each stop is 90°, so
`frame = (facing_index - 2 * yaw_index) mod 8`. Integer arithmetic, no rounding, no yaw at
which some frame has no art.

**Correction on record.** The original text of this cluster and of three-games.md §3.6 gave
"2:1 dimetric at ≈26.57°". 26.57° is the *screen* angle of a tile edge, not a camera pitch.
A unit ground square at 45° yaw projects to a diamond of width √2 and height √2·sin θ, so a
2:1 diamond needs sin θ = 0.5 → **pitch 30°**. Using 26.57° as a pitch yields a ~2.24:1
diamond with no clean pixel stair-step. True isometric is `atan(1/√2)` ≈ 35.26°.

**Still open — the sub-question:** does `move_to` need A\* from the start, or is
straight-line-then-stop enough for the first cutscenes? Recommend straight-line first, with
`path: "astar"` already in the command schema (architecture.md §5) so adding it later is not
a format change. Now tracked as architecture.md §12.5.

---

## Cluster 2 — Who owns control? 🔴

*Blocks: stage A's `InputIntent`, `CameraRig` and now `ModeStack`; stage C's scheduler.*

**Upgraded from 🟡 to 🔴**, because the review found a live defect rather than a tidiness
concern, and because question 24's answer pulls `ModeStack` into stage A.

27. **Who owns "input is locked"?** 🔴 Three independent mechanisms exist on paper: the round
    gate and its watchdog (three-games.md §3.1), the input target stack
    (architecture.md §7.8) and the exclusive slot (architecture.md §7.5). The failure:
    the player steps onto a cell, the round opens, an `EnterCell` trigger takes the
    exclusive slot and puts up dialogue, and two seconds later the round watchdog
    force-closes the round, unlocks `InputIntent.step`, and logs an error naming a command
    that is legitimately waiting on the player. **Recommend `ModeStack` as the single
    arbiter** — it is in stage A now regardless — with the watchdog suspended for any mode
    that is not `Field`.
28. **`ActorRegistry` scope.** 🔴 It is an autoload keyed by map-unique ids
    (architecture.md §8), but game 1's battle keeps the field map resident
    (three-games.md §3.8), so two maps' worth of ids can be live at once. **Recommend moving
    it onto `MapContext`** beside `Occupancy`: ids stay map-unique with no collision, two
    maps can be resident, and map teardown disposes it for free. Events already carry
    `context.map`, so nothing above needs a new parameter.

Both are architecture.md §12.7. The remaining questions in this cluster are unchanged:

5. **Camera ownership** (architecture.md §12.6) — does the camera follow the player by
   default with events borrowing it, or is it always driven by whoever holds the exclusive
   slot? **Recommend:** follow by default; events borrow and return, via `CameraRig.lock()`.
6. **Does turning in place open a round?** (three-games.md §5.1) **Recommend no** — turning
   changes no cell. Also a difficulty lever: "no" lets the player re-aim for free before a
   fight.
7. **Does bumping a wall open a round?** (three-games.md §5.1) **Recommend no**, plus an
   explicit "wait one step" input, so passing time is a choice rather than a wall-bumping
   trick.
8. **Round watchdog timeout** (three-games.md §3.1) — what maximum round duration
   force-closes the gate and logs? **Recommend 2s**, generously above any legitimate action.
   Note this is only safe once 27 is answered.
9. **Does scripted player movement pulse?** (three-games.md §5.1) **Recommend no** — pulses
   suppressed outside `Field` mode, with an opt-in `pulse: true` on move commands. Another
   consumer of `ModeStack`.
10. ~~Pulse fires on step commit or visual settle?~~ ✅ **Commit — and cell triggers fire
    there too**, so monsters and traps observe identical state. `fire_on` is deleted rather
    than moved into page settings; the land-on-it case is a `wait_settle` command at the top
    of the trigger's own graph, which is `wait_for` against the step's existing completion
    key. One ordering, one default, one fewer knob to validate.

**The synthesis, revised:** 5 and 9 are "does the event system take over, or borrow?"; 6–8
are "what closes a round?"; 27 and 28 are "who arbitrates, and what is scoped to a map?".
The general principle — *events borrow and must return; rounds close on cell changes only,
with a hard time bound; `ModeStack` arbitrates and `MapContext` owns per-map state* —
answers all eight.

---

## Cluster 3 — How much is data, how much is code? 🟡

*Blocks: stage C. This is the project's central bet, and worth deciding as one thing.*

11. **Is monster AI authored as event graphs?** (three-games.md §5.3) **Recommend yes**, with
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
17. ~~Do pages inherit?~~ ✅ **No.** Pages are fully explicit and absent means default. The
    repetition inheritance would have saved goes to a "duplicate page" button in the page
    bar instead. What that buys: a page reads in isolation, diffs cleanly, and the in-memory
    page is always exactly the page in the file — no resolution pass between parse and
    `ActorView.apply_art`, which is the same rule as the boundary-normalisation note below.
18. **Route `wait` units** (event-pages.md §6.5) — steps or seconds? Steps are natural in
    game 1 and meaningless in games 2 and 3. **Recommend unit-tagged**, matching how
    conditions are structured.
19. **One document per event, or a map-level bundle?** (event-pages.md §6.6) Per-event files
    diff and move cleanly; a bundle avoids dozens of tiny files. **Recommend per-event**,
    with the dock able to open a map's worth at once.

Note that 15, 16 and 18 are the same instinct three times: **accept convenient shorthand at
the boundary, normalise immediately, keep exactly one shape in memory.** Worth adopting as a
stated rule so it does not have to be re-argued per field. 17's answer is that same rule
applied to whole pages, which is the argument that settled it.

---

## Cluster 5 — Structural, decide before writing files 🔴

*Blocks: literally the first commit of stage A. Recommendations stand; execution deferred.*

20. **One repository or three?** (three-games.md §5.6) **Recommend one**, with
    `core/`, `events/`, `ui/`, one `addons/`, and `games/{jrpg,isoish,action}/`. Three
    projects means duplicated editor plugins, three drifting sets of project settings, and a
    submodule bump per core change. Question 29's answer — three separate executables — does
    **not** decide this: three export presets from one project produce three exes.

    **One verification this now leans on**, since it was previously filed as the sharp cost of
    one repo: the renderer and `default_texture_filter` are project-global, and game 3 wants
    different values from games 1 and 2. Project settings take per-feature-tag overrides and
    the renderer is already overridden that way for platforms today, so a custom `action` tag
    should work — but three-games.md §3.9 flags it as a ten-minute test to run before the
    layout is committed rather than an assumption to build on.
21. **Move the root-level files** (three-games.md §3.9) — `TextBox/`, `constants.gd`,
    `event_bus.gd`, `input_manager.gd` are all shared infrastructure sitting at the repo
    root. **Recommend moving them into `core/` and `ui/` as the first task of stage A**,
    while it is four files and not forty. `run/main_scene` currently points at
    `TextBox/rich_text_block.tscn` and both autoload paths need updating with them.
29. ~~What is `GameProfile`, and how is one selected?~~ ✅ **Specified in
    three-games.md §2.1–2.2.** A `Resource` carrying id, capabilities (a **closed enum**, not
    free strings), input profile, mode list, tuning constants, **and** the three axis scripts
    — so §2's table is executable and an `ActorFactory` builds an actor's children from it.
    `MapContext.default_motion` overrides `GameProfile.motion_script`; that precedence is
    now on record in architecture.md §1.

    **Selection: none at runtime.** Each game ships as its own executable with exactly one
    profile compiled in — no launcher, no `--profile` flag, nothing to swap mid-session. The
    consequence worth keeping: capability tags become a purely **authoring-time** concern,
    since a build never asks whether a command is available to it. §3.7's whole payoff is the
    dock's validate pass and the graph editor's dropdown, and the dock can infer the profile
    from the event file's path.

🔴 because every path in every scene and every `preload` written before 20 and 21 has to be
revised after them.

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

*Not needed until stage F. Recorded so they are not discovered instead of decided.*

23. **Mid-execution page switch** (event-pages.md §6.2) — defer to graph completion, defer
    to round close, or swap immediately? **Recommend defer to graph completion.** Prevents
    "the chest changed art halfway through its own cutscene".
24. ~~Does game 1 have a separate battle scene?~~ ✅ **Yes**, as Lufia 2 does, and as
    [slime_a.event.json](events/slime_a.event.json) already assumed with its `start_battle`
    command. **Consequence: `ModeStack` moves from stage F into stage A**, since a Battle
    mode that keeps the field map resident is now a prerequisite for game 1 being playable
    end to end. It is also the arbiter question 27 needs.
25. **Save format: in-flight ambient runners** (architecture.md §12.4) — captured, or are
    ambient events always restartable from the top? **Recommend restartable** — much simpler
    and almost always enough. Saved regardless, per three-games.md §3.10: self flags,
    variables, monster `credit`, **and route progress** (waypoint index plus `pingpong`
    direction) — the last of which the original envelope omitted.
26. ~~Do games 2 and 3 share maps?~~ ✅ **No.** Separate map sets; the art styles do not mix.
    Technically they could have — the two differ only in camera rig and `ActorView` — so this
    is an art-direction call, and it earns a simplification: **a map belongs to exactly one
    profile**, so no map declares which presentations it supports, `MapContext` needs no
    profile-compatibility field, and no "view two ways" mode has to exist.

---

## If there is only time for a few

In order:

1. **Cluster 5** (20, 21) — one repo, and move the shared files. Blocks the first commit.
   29 is answered, so nothing else in stage A is waiting on a specification.
2. **Questions 27 and 28** — who arbitrates control, and what scope the registry has. These
   are 🔴 now: 27 is a soft-lock-shaped defect and 28 is a collision that only appears once
   battle exists, which is to say once it is expensive to change.
3. **Question 11** — is monster AI authored as graphs? Sets how much of stage C must be
   right before game 1 is playable, though routes make it a smaller bet than it looked.
4. **Question 8** — the watchdog timeout. One number, and it is the difference between a
   logged error and a game that appears to freeze. Answer 27 first.

Clusters 1 and 7 have left this list, and 29 with them. **No art decision is outstanding** —
directions, yaw stops, pitch and texel density are all settled, so tile and character art can
start. Everything remaining can be answered as its stage arrives.
