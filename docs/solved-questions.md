# Solved questions — the decision record

Every question from [open-questions.md](open-questions.md) that has an answer, kept with
its reasoning so the decision is not re-argued. Split out of that file on 2026-09-13, when
the solved half had grown larger than the open one.

**A question leaves [open-questions.md](open-questions.md) and arrives here the moment it
is answered, keeping its number.** Numbers are never reused and never renumbered, so a
reference to "question 27" in a commit message, a docstring or another document still finds
exactly one thing. No cluster spans both files any more — as of 2026-09-14 every question is
answered, so every cluster heading lives here. The rule stands for anything asked from now on:
the heading stays where its *open* questions are, and answered members move here under it.

Answered does not always mean built — cluster 9 is decided and unimplemented in part, and
says so. [next-session.md](next-session.md) is the work queue; this is only the record.

| Marker | Meaning |
| --- | --- |
| ✅ | Decided. The reasoning is kept so it does not have to be rediscovered. |

---

## Decided 2026-09-08 — the short version

| # | Decision |
| --- | --- |
| 1–4 | Game 1 steps 4-way with 4 sprite directions. Game 2 moves freely with 8. Game 2's camera snaps to **4 yaw stops at 90°** at **pitch 30°** — a 16 × 8 px ground tile. Texel density is **16 px per tile** (14 on vertical faces), and game 2's player moves sub-pixel. |
| 10 | The step pulse **and** cell triggers both fire at step commit. `fire_on` is deleted; `wait_settle` replaces it. |
| 17 | Pages inherit nothing. Absent means default. |
| 24 | Game 1 has a **separate battle scene**. `ModeStack` therefore moves into stage A. |
| 26 | The two games do **not** share maps. A map belongs to exactly one profile. |
| 29 | `GameProfile` specified (two-games.md §2.1): a Resource with a closed capability enum **and** the three axis scripts. Each game is its own executable; no runtime selection. |
| — | Within one pulse, responders resolve **actor-at-a-time** (each drains its credit before the next acts). |
| — | Occupancy is only ever written through `Occupancy.commit(changes)`, including for a single step. |

---

## Cluster 1 — "Four or eight?" ✅

*Blocked: all art production, and stage B's movement feel. Resolved.*

1. **Grid movement: 4-way or 8-way?** → **4-way in game 1.** Game 2 uses `FreeMotion`.
2. **Sprite directions: 4 or 8?** → **4 for game 1, 8 for game 2.**
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

**Correction on record.** The original text of this cluster and of two-games.md §3.6 gave
"2:1 dimetric at ≈26.57°". 26.57° is the *screen* angle of a tile edge, not a camera pitch.
A unit ground square at 45° yaw projects to a diamond of width √2 and height √2·sin θ, so a
2:1 diamond needs sin θ = 0.5 → **pitch 30°**. Using 26.57° as a pitch yields a ~2.24:1
diamond with no clean pixel stair-step. True isometric is `atan(1/√2)` ≈ 35.26°.

**Still open — the sub-question:** does `move_to` need A\* from the start, or is
straight-line-then-stop enough for the first cutscenes? Recommend straight-line first, with
`path: "astar"` already in the command schema (architecture.md §5) so adding it later is not
a format change. Now tracked as architecture.md §12.5.

---

## Cluster 5 — Structural ✅

*Executed 2026-09-08, in the commit that built stage A.*

20 and 21 are done: one repository, with `core/`, `actors/`, `events/`, `ui/`, `tests/`,
`tools/`, one `addons/`, and `games/{jrpg,isoish}/`. `TextBox/` became
`ui/text_box/`, `constants.gd` became `ui/anchor_constants.gd`, and `event_bus.gd` and
`input_manager.gd` moved into `core/`. Every `ext_resource` already carried a `uid://`, so
the scenes resolved by UID and only the `path=` strings and the two autoload entries needed
rewriting. 29 is specified in two-games.md §2.1.

**Nothing outstanding.** Both games are pixel-art games wanting `gl_compatibility` and
nearest-neighbour filtering, so the project-global renderer and `default_texture_filter`
never disagree and no custom feature-tag override has to be verified for them.

The original entries, for the reasoning:

20. **One repository or two?** (two-games.md §3.9) **Recommend one**, with
    `core/`, `events/`, `ui/`, one `addons/`, and `games/{jrpg,isoish}/`. Two separate
    projects means duplicated editor plugins, two drifting sets of project settings, and a
    submodule bump per core change. Question 29's answer — separate executables — does
    **not** decide this: two export presets from one project produce two exes.

    The project-global settings that would have argued for splitting — the renderer and
    `default_texture_filter` — are the same for both games, so there is no conflict to
    resolve and no tag override the layout depends on.
21. **Move the root-level files** (two-games.md §3.9) — `TextBox/`, `constants.gd`,
    `event_bus.gd`, `input_manager.gd` are all shared infrastructure sitting at the repo
    root. **Recommend moving them into `core/` and `ui/` as the first task of stage A**,
    while it is four files and not forty. `run/main_scene` currently points at
    `TextBox/rich_text_block.tscn` and both autoload paths need updating with them.
29. ~~What is `GameProfile`, and how is one selected?~~ ✅ **Specified in
    two-games.md §2.1–2.2.** A `Resource` carrying id, capabilities (a **closed enum**, not
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

## Cluster 8 — Areas entered and exited ✅

*Asked and answered 2026-09-13, then built. See architecture.md §6.2.*

30. ~~Are areas colliders or painted tile data?~~ ✅ **Colliders, queried rather than
    listened to.** The shape is an `Area2D` / `Area3D`; how a crossing is detected follows
    the **motion, not the space** — free motion uses the area's own `body_entered`, grid
    motion (in either space) uses a synchronous point query at the destination cell centre,
    at commit.

    This **contradicts architecture.md §7.6 as written**, which said "no raycast or `Area`
    involved" and treated colliders as a 3D-only affordance. That claim is now marked wrong
    in place. The reason the query has to be synchronous: an overlap signal arrives the
    *next* physics frame, by which time the step it was meant to slow already has its speed.

    Two smaller corrections came with it: **a cell holds many things, not one** — many
    events and many zones may sit on a tile and all fire — and a 3D grid query carries the
    cell's Y, because that game has floors.

31. ~~When does a speed change apply, and what restores it?~~ ✅ **At the commit of the step
    that enters, and nothing restores it.** A `SpeedModifier` is a **provider**, not a
    value: entering registers it with the actor's `MotionController`, leaving unregisters
    it, and in between the controller asks it for a scale every frame with the direction
    being travelled. Nothing writes `speed`, so there is no base to put back and a route's
    own speed change cannot be clobbered when a zone ends. Overlapping zones **multiply**.

    **Consequence, and the largest change this made:** the grid step's `Tween` is gone.
    `GridMotion` now walks the sprite's offset to zero in `_process`, keeping **remaining
    distance** rather than elapsed time, because a tween's duration is fixed when it starts
    and could not express slowing down halfway across a tile. `ActorView.apply_step_offset`
    became `set_step_offset`, and `step_trans` / `step_ease` were deleted — nothing is
    interpolated any more, which was already the only defensible setting.

32. ~~What do the four direction bools mean, and where do they live?~~ ✅ **The actor's
    heading, re-evaluated per step, on the component rather than the zone.** A staircase is
    slow to climb and ordinary to descend, and an actor that turns round inside the zone is
    re-evaluated on its next step rather than being latched at entry. All four unchecked
    means every direction, matching "an unpainted cell is open ground". `Passability.cardinals`
    resolves a heading to one or two flags, so a diagonal and an analog stick ask the same
    question a grid step does.

    Left open: whether a diagonal under 8-way movement should need **any** of its cardinals
    checked or **all** of them. Exported as `match_mode`, defaulting to ANY; it is a feel
    call and costs one line to flip.

33. ~~What counts as having exited?~~ ✅ **The visual settle, not the commit that left.**
    Four signals, because the body and the sprite disagree for the length of a step:
    `actor_entered` and `actor_leaving` at commit, `actor_arrived` and `actor_exited` at
    settle. A zone keeps an actor until `actor_exited`, which is also what lets a modifier
    apply to the step carrying the actor out — the default for `SpeedModifier` is origin
    **and** destination.

    Cross-map signalling is deliberately **not** here: a zone talks to the actor and to its
    own components only. Anything that needs to reach `EventBus` will be a separate
    component that does exactly that, rather than a flag on the zone.

---

## Cluster 9 — Sharing a cell, and the third dimension ✅

*Asked and answered 2026-09-13. **34 and 35 are built**; 36, 37 and 38 are decided and not
yet written. `Occupancy`, `Passability`, `Actor` and `GridMotion` all change.*

**This cluster has two scopes, and they are not the same scope.**

- **34 and 35 — sharing a cell, and through — are every grid game, in either space.**
  `Occupancy` is what all grid movement commits through, so the list-per-cell change and the
  through split land in game 1 exactly as they land in the iso grid game.
- **36, 37 and 38 — stairs, falling and ladders — are grid movement in 3D only.** The gate is
  `effective_motion() == GRID` **and** `MapContext.supports_height`, not the space and not the
  profile. Being 3D is not the condition: `FreeMotion` is 3D too and already has *real*
  gravity and jumping ([free_motion.gd](../actors/motion/free_motion.gd) — `gravity`,
  `jump_strength`, `_velocity.y`, landing resolving the jump key). None of 36–38 may reach it.
  The iso **free** demo and the iso **grid** demo sit in the same space and take different
  halves of this cluster, which is precisely the seam that would rot if the rule were
  written as "3D".

  A useful check on that gate: `jump` is free to be the ladder release (38) *because*
  `GridMotion.jump` is dead while `FreeMotion.jump` is the real thing. One action, two
  meanings, split on exactly the same line as the rest of the cluster.

34. ~~How many actors may hold one cell?~~ ✅ **Zero to many. `Occupancy` maps a cell to a
    list, and blocking becomes a predicate over that list.** Built 2026-09-13. `_cells` went
    from `Dictionary[Vector3i, StringName]` to a list per cell, `at()` became **`actors_at`**
    (everyone) beside **`blockers_at`** (only those who stop a step), `is_free` became
    `is_empty` (nobody at all) beside `is_clear` (nobody blocking), and **every actor is
    recorded whether or not it blocks** — which is the point. Before this, a non-blocking
    actor was absent from the table entirely, so "what is at `player.cell() + facing()`"
    could not find it and a through NPC was unaddressable by interact. Presence and blocking
    are now two questions, not one flag.

    **`commit`'s rule survives with one word inserted.** It was "a claim on a cell held by
    an actor that is not taking part is refused"; it becomes "…held by a **blocking** actor
    that is not taking part". Swaps and push chains are unaffected, because the reason they
    work — every participant appears as a claimant — is untouched.

    **Stacked blockers are legal, because they are intentional.** Two non-through actors on
    one tile is what a teleport, a forced spawn or an event placement produces, and the
    model can now represent it, so it is not an error: a *voluntary step* into a blocking
    holder is still refused, but a forced placement stacks and the actors walk off normally.
    `Actor._claim_spawn_cell`'s `push_error` on an occupied spawn is therefore gone, and the
    forced path has its own name: **`place()` cannot be refused and `commit()` can.** A
    teleport (`move_to` with `path: "raw"`) now calls `place`, where it used to call
    `commit_step` and silently fail to move when the destination was held.

35. ~~What does "through" mean?~~ ✅ **Two independent flags, each symmetric.**
    `through_terrain` and `through_actors` replaced `solid`. Built 2026-09-13. Symmetric
    means through-actors ignores others *and* is ignored by them — one flag, both directions,
    no ghost-you-can-bump-into case, and it lives in `Occupancy` as a phasing flag rather
    than being asked of the actor at every check.

    Half of this already existed by accident: `_terrain_allows` runs *before* the occupancy
    check, so the old `solid = false` actor was still stopped by walls — it was already
    through-actors-only. What is genuinely new is `through_terrain`, which game 2 wants and
    game 1 has no use for.

    **`through_terrain` switches off two of `Passability`'s three steps, not one.** Terrain
    is painted in 2D *and* modelled in 3D, and physics (step 3) is the modelled half — so
    skipping only the paint would let `body_test_move` re-impose the wall the flag was told
    to ignore. That was not obvious until the test for it was written.

    **`through_terrain` does not fall** — where falling exists at all, which is grid movement
    in 3D. It skips terrain collision and may walk through a wall, but no floor pulls it down,
    so it is the **one actor for which `y` is an input again**. It needs explicit commands to
    change height, because nothing in the world will change it on its behalf. That makes a vertical-movement
    command a requirement of stage C's registry rather than a nicety (36 otherwise removes
    every reason to have one), and it is the reason a through-terrain actor cannot simply
    reuse the ladder rules.

> **Built 2026-09-14, and 36 was revised while building it.** [core/terrain.gd](../core/terrain.gd)
> implements 36, 37 and 38; `tests/height_test.gd` covers them with 90 assertions across
> three elevations. **Read the two revisions below before the prose in 36**, which is kept
> because its *reasoning* still holds even where its mechanism does not.
>
> - **The floor is a `GridMap`, not a raycast against the mesh.** 36 specified inferring
>   stairs and ramps from surface continuity, sampled at the shared edge. What shipped is
>   `MapContext.floor_node`: a cell's presence says where ground is, its mesh-library item
>   *name* says what kind, and its cell *orientation* says which way it rises. Chosen
>   because it is exact where continuity sampling is approximate — no tolerance to tune, no
>   physics needed, deterministic in a headless test, and authored in the GridMap editor
>   with one rotatable item per kind. The mesh is still consulted for exactly one thing, and
>   it is a presentation question: how high to draw the sprite on a slope.
> - **A ramp's logical cell is its lower end.** Stepping onto a ramp is a level step and the
>   climb happens on the way *off* it, with the sprite lifted half a cell
>   (`Terrain.RAMP_RISE`) so it stands on the slope rather than inside it. This is the one
>   place the logical answer and the visible one disagree on purpose.
>
> The rule set that resulted is in `Terrain.resolve_step`, in the order it is tried. One
> rule was missing from every version of this design until the test found it: **stepping
> down onto a ladder's top rung**, the exact reverse of the dismount — without it a player
> who climbs out at the top and turns around cannot get back on.

36. ~~How does a grid actor change elevation?~~ ✅ **`y` stops being an input to a step, and
    upward movement is authored, never tolerated. There is no climb limit.** The mover asks
    for a cardinal **XZ** step; the map answers what the floor of that column is; the step is
    permitted when the floors **match**. A Δy of +1 is permitted **only where the map
    provides a connection** — a stair, a ramp or a ladder.

    **A one-tile cliff and a one-tile stair are the same height and are not the same thing.**
    No actor scales the cliff, at any stat, ever; the stair is traversable because the
    geometry makes it so. The upward rule is geometry, not a number — which is why there is
    nothing to tune and nothing to get wrong per actor. Downward is the only direction with a
    number on it, and that is 37.

    **Stairs and ramps are inferred from the mesh. Nothing is painted, and 2D needs none of
    this** — game 1 is flat, so this belongs to grid movement in 3D and nothing else (see the
    scope note at the top of this cluster). A modelled ramp simply works.

    **What separates a ramp from a cliff geometrically: the surface is continuous across the
    shared edge.** That is the test `floor_y` has to support — sample the walkable surface at
    the **midpoint of the boundary** between the two cells, not just at their centres. On a
    ramp the edge sample agrees with both cell surfaces; at a cliff it agrees with one and
    differs from the other by the full drop. So "is this step a walk, a rise, or a fall" is
    one query about continuity rather than a classification of tiles.

    Two wrinkles this creates, both worth knowing before the first ramp is modelled:

    - **A decorative slope must not be walkable, and the collision layer is what says so.**
      The query asks the *walkable* layer, so geometry that is scenery is simply not on it.
      This is the authoring discipline that replaces the paint.
    - **Surface heights are continuous; cells are integers.** A two-cell ramp rising one unit
      puts a column's surface at a fractional height. The resolution is the invariant this
      codebase already holds: **the cell stays integer and authoritative, the view takes the
      sampled surface height.** Occupancy, triggers and events never see a fraction; only the
      sprite does. Cell `y` therefore matters only where floors genuinely stack — a bridge
      over ground — and not for a ramp at all.

    **This fixes a silent hole.** `Passability.STEPS` holds four cardinals at `y = 0`, so a
    step with any Δy is not found in it and `allows_step` falls through to its non-cardinal
    branch, which only asks `directions(to) != 0`. The both-cells-must-agree rule is skipped
    entirely. Stairs built on the current code would appear to work while enforcing nothing.

    `floor_y` is also what retires the known gap where `_terrain_allows` treats any occupied
    `GridMap` cell as a wall — right for a walls-only layer, backwards for a floor.

37. ~~What happens at a ledge?~~ ✅ **You fall, as repeated one-cell steps, up to an exposed
    limit.** Each cell of the descent is its own committed step, so triggers fire on the way
    down and monsters see each one. The limit is a number, not a bool:
    **`max_fall_cells` — 0 means ledges are walls** (game 1's answer), 1 permits a one-cell
    drop, and anything over 10 permits any fall at all.

    **The depth is measured before the step off the ledge commits.** A three-cell drop under
    a limit of two is refused *entirely* rather than falling two and stranding the actor in
    mid-air — lookahead for the refusal, stepwise for the execution.

    **This retires the event override `Passability` anticipated.** Its docstring notes that
    the symmetric both-sides rule "cannot express a ledge you may drop off but not climb.
    That is what the event override is for when it arrives." It is not needed, and for a
    better reason than the one first filed here: **up and down are not one rule with two
    numbers.** Up is authored geometry (36) and down is a permitted distance (this). The
    asymmetry is structural, not arithmetic.

38. ~~Are ladders events or terrain?~~ ✅ **Terrain, flagged like everything else, with the
    facing doing the work.** A ladder column carries a facing — the side it is mounted on.
    Walking **into** that direction climbs one cell; walking **away** from it descends one.
    No graph, no per-ladder authoring, and every ladder in the game behaves identically.

    **Release is `jump`.** `GridMotion.jump` currently does nothing but warn that jump needs
    free motion — the action is already bound and dead in a grid game, so letting go costs no
    new binding in either profile. The same trick `turn_in_place` used to play with Shift and
    `run`, before game 1 gained a run of its own on 2026-09-14 and turning moved to Q.

    **Release ignores `max_fall_cells`.** Letting go is a deliberate act, so it drops however
    far the column goes. This keeps the limit meaning exactly one thing — *may this actor
    walk off a ledge* — which is what lets game 1 set it to 0 and still have working ladders.

    **The top dismounts automatically:** climbing into the top cell steps the actor onto the
    floor above in the same motion, so there is no press that appears to do nothing. The
    consequence is an authoring rule — **the top of a ladder must have floor beside it** —
    and that is exactly the kind of thing the map validator should check rather than discover.

    A ladder is therefore the one vertical connection driven by *held direction* rather than
    by crossing geometry, and the only one that is flagged rather than inferred (36).

---


## Cluster 2 — Who owns control?

*This cluster is fully answered as of 2026-09-14 — nothing is left open in
[open-questions.md](open-questions.md).*

> **Questions 6, 7, 8, 9 and 10 are about the round and the step pulse, which were struck
> from the design later the same day** (question 42, [stage-c-plan.md](stage-c-plan.md)).
> They keep their numbers and their reasoning, because a decision record that quietly drops
> the questions it changed its mind about is not a record. Read them as answers to a question
> the project no longer asks.
>
> **The parts that outlived the round**, and are still true: turning in place and bumping a
> wall both **emit an event and change no cell** (6, 7); there is **no watchdog** and
> therefore every command must resolve its completion key on every path out, cancellation
> included (8); `actor_stepped` fires at **commit**, not at visual settle, and cell triggers
> fire with it (10). What is gone is the framing — "opens a round", "pulses" — not those
> behaviours.
>
> "What drives a monster" is now [open question 46](open-questions.md).

5. ~~Camera ownership?~~ ✅ **The recommendation, plus a third mode.** The camera follows
   the player by default; events borrow it and must return it, via `CameraRig.lock()`
   (already built). Confirmed and extended: an event may also **follow something other than
   the player** — `CameraRig.follow()` already takes any actor id, so this was mostly already
   true, and a fixed point (a chest, a cutscene mark) is `CameraRig.move_to()`, listed in
   architecture.md §12.6 as "to implement."

   **The new half: the camera is sometimes locked to a smaller bounds than the map makes
   available.** `RoomCamera2D.bounds` (already built) clamps the camera to the *map's* edges
   — a Rect2, checked once per map. What this decision adds is a **second, narrower bound an
   event can impose temporarily** — a boss arena inside a bigger room, a cutscene that must
   not let the camera drift past a doorway — and it must follow the same borrow-and-return
   shape as `lock()`, not overwrite `bounds` outright: `push_bounds(rect)` /
   `pop_bounds()`, with `bounds` itself as the floor a `pop_bounds()` with an empty stack
   returns to. Not yet built - `RoomCamera2D` has the single map-wide `bounds` field and
   nothing stacked on top of it. When this is built, `CameraRig.lock()` and
   `push_bounds()`/`pop_bounds()` are two independent things an event can hold, not one
   combined "the event owns the camera" flag — a cutscene can narrow the bounds without
   taking control of what the camera looks at, and vice versa.
6. ~~Does turning in place open a round?~~ ✅ **No — but it emits an event** (2026-09-14).
   Turning changes no cell, `actor_stepped` is about cells, and facing stays free: the player
   re-aims before a fight without giving the monsters a move. The rider is the half worth
   recording — **closing no round is not the same as being silent.** `Actor.set_facing`
   publishes `EventBus.actor_turned(actor_id, from_dir, to_dir)`, so a guard's line of sight,
   a statue puzzle or a graph condition can watch a turn without holding a reference to the
   actor. It fires for **every** facing change, the one a step makes on its way out included;
   a listener that means "turned in place" checks the actor is not moving. Emitting it from
   the one choke point rather than from the turn-in-place path was deliberate — "the player is
   now facing me" is the question being asked, and how the facing was acquired is the
   listener's business, not the emitter's.
7. ~~Does bumping a wall open a round?~~ ✅ **No — but it emits an event** (2026-09-14), the
   same shape of answer as 6. Walking into a wall passes no time, so time cannot be passed by
   the trick; the explicit "wait one step" input is how it is passed on purpose, and it stays
   on the stage B list. `Actor.report_blocked` publishes
   `EventBus.actor_blocked(actor_id, from, to)` — a thud, a locked-door bark, a tutorial
   noticing the player shoving at the same wall. **Both refusals come through it**, the
   terrain one and the occupancy one, which is why the two `blocked.emit` sites in
   `GridMotion` were routed through a single method on `Actor` instead: a bump has one
   announcement point, or the two kinds drift apart.

**Revised 2026-09-14, the same day: the whole actor-event set was redesigned around one
rule — every actor event is a trigger, and none is a clock.** The first pass (above) still
had a two-tier system: `actor_stepped` was gated by a per-actor `publishes_pulse` export and
by `ModeStack.suppresses_pulse()`, and a separate always-on `cell_entered` existed only to
give traps an unconditional signal `actor_stepped` didn't provide. Both of those are now
deleted. `EventBus` carries **four** unconditional actor moments — `actor_stepped`,
`actor_settled` (new: the step's visual has caught up, the "land-on-it" half `actor_stepped`
never covered), `actor_blocked`, `actor_turned` — and `cell_entered` is gone, because
`actor_stepped` now does its job.

**The gating question (9, below) did not disappear — it moved from the emitter to the
listener.** `EventBus` stays a dumb hub with no state (architecture.md §7.7), so "should a
cutscene's player steps drive the monsters" is no longer answered by `GridMotion` deciding
whether to emit at all. It is answered by whatever listens *for AI purposes* — a future
`StepResponder` asks `ModeStack.rounds_active()` / `suppresses_pulse()` itself before
reacting to `actor_stepped` — while a HUD, footstep or music cue, which never needed gating
in the first place, is completely unaffected by the change. `decision 10`'s "cell triggers
fire at commit too" now means: a future `EventRunner` checking `MapContext.events_at()` also
listens to the unconditional `actor_stepped`, not to a signal built specifically for it.

**A rider on all four — the `player_*` shorthands** (2026-09-14). `EventBus` carries **four**
of them beside the `actor_*` signals: `player_stepped`, `player_settled`, `player_blocked`
and `player_turned`, each its `actor_*` counterpart with the id dropped. They exist because
**most listeners only ever care about the player** — a HUD, a minimap, a footstep, a music
cue, a been-here-before flag — and written out each of those is the same four lines: connect,
compare the id, drop the argument. Four lines repeated thirty times is thirty chances to get
the player test subtly wrong, so the test itself moved to one place: **`Actor.is_player()`**
(a `PlayerBrain`, or the id `player` as the fallback for a map that places the player without
one). `AreaComponent`'s PLAYER filter, which had its own copy of that expression, now asks
there too. Now that no `actor_*` signal carries gating of its own, **every `player_*` form is
exactly its `actor_*` counterpart filtered** — the divergence the first pass required
(`player_stepped` ignoring pulse suppression that `actor_stepped` obeyed) no longer exists,
because there is no suppression left at this layer to diverge from.

**Four, not five — `player_entered_cell` was written and then deleted the same day**, and
the rule it leaves behind is worth more than the signal was: *one moment, one signal.* It
fired at the same instant as `player_stepped`, under the same conditions, always in the same
pair, and differed only in carrying the destination without the origin. That is a **payload
preference**, and a listener expresses one with an underscore —
`func _on_player_stepped(_from: Vector3i, to: Vector3i)` — since Godot 4 refuses a callable
with fewer parameters than the signal has (verified: it logs
*"Method expected 1 argument(s), but called with 2"* and silently drops the call, so the
underscore is not optional). One unused parameter is a smaller cost than a second name for
the same event. This is the rule the whole redesign above applies at a larger scale: a second
signal earns its place only by covering a genuinely different moment, never a different
subset of the same moment's payload or a different subset of the same moment's listeners.

8. ~~Round watchdog timeout~~ ✅ **Cut, 2026-09-13 — there is no watchdog.** The question was
   "what maximum round duration force-closes the gate", and the answer is that nothing does.
   `RoundGate` closes when its completion keys resolve and that is the only thing that closes
   it; `GameProfile.round_watchdog_seconds` is deleted. What this gives up is the log line a
   never-closing round would have produced — a round that hangs now hangs, and is diagnosed
   by finding the command that never completed rather than by being told which one it was.
   The gate's join is the thing to keep honest.
10. ~~Pulse fires on step commit or visual settle?~~ ✅ **Commit — and cell triggers fire
    there too**, so monsters and traps observe identical state. `fire_on` is deleted rather
    than moved into page settings; the land-on-it case is a `wait_settle` command at the top
    of the trigger's own graph, which is `wait_for` against the step's existing completion
    key. One ordering, one default, one fewer knob to validate.
    **Revised 2026-09-14:** "the step pulse" is no longer a separate thing from "cell
    triggers" — both read as `EventBus.actor_stepped`, unconditional, since `cell_entered`
    is deleted (cluster 2 rider, above). The land-on-it side of this decision now has its
    own signal too: `EventBus.actor_settled` fires when the sprite catches up, which is what
    `wait_settle` was already joining internally and is now also a public moment.
9. ~~Does scripted player movement pulse?~~ ✅ **No by default, and the opt-in is per
   command** (2026-09-14). A cutscene that walks the player past a room of monsters must not
   drive them, so pulses are suppressed outside `Field` mode, with an opt-in `pulse: true`
   argument on a move command, defaulting false, for the rare scripted sequence that wants
   monsters reacting while the player is driven. Opt-in per command rather than a mode: a
   chase sequence usually wants the pulse on two commands out of forty, and a pulsing *mode*
   would make the author remember to leave it.
   **Revised the same day: where this is enforced moved.** The first pass built the
   suppression as a `ModeStack.suppresses_pulse()` check inside `GridMotion._commit_step`,
   gating `EventBus.actor_stepped` itself. That check is gone — `actor_stepped` is
   unconditional now (cluster 2 rider, above) — so the decision here is unchanged but is no
   longer self-enforcing at the emitter. It is stage C's to build: a `StepResponder` (or
   whatever reacts to `actor_stepped` for AI purposes) must itself check
   `ModeStack.suppresses_pulse()`, and a `pulse: true` command needs a way to tell it "react
   anyway" for this one step - an argument the responder reads, not a flag the bus carries.
   `publishes_pulse` - the per-actor export that answered "whose steps count as a pulse at
   all" - is deleted along with the mechanism it belonged to; every grid actor's steps are
   visible on `EventBus` now; whether they *matter* to a responder is that responder's
   question to ask.
27. ~~Who owns "input is locked"?~~ ✅ **`ModeStack`**, built in stage A rather than F. Each
    mode declares whether it pulses, pauses physics, keeps the map loaded and **has rounds**;
    the round gate only holds where `rounds_active()`, so a cutscene entered mid-round no
    longer has a gate running underneath it. (The force-unlock this was also protecting
    against is moot since 8 was cut — there is nothing to force-unlock.) `InputManager`
    gained the `push_target` / `pop_target` stack underneath it.
    See [core/mode_stack.gd](../core/mode_stack.gd).
28. ~~`ActorRegistry` scope.~~ ✅ **On `MapContext`**, beside `Occupancy` — no autoload. Ids
    stay map-unique with no collision, two maps can be resident while battle keeps the field
    map loaded, and teardown disposes both tables for free. Actors already reach their context
    by walking up the tree, so nothing above needed a new parameter.
    See [core/map_context.gd](../core/map_context.gd).

---

## Cluster 3 — How much is data, how much is code?

*This cluster is fully answered as of 2026-09-14 — nothing is left open in
[open-questions.md](open-questions.md).*

11. ~~Is monster AI authored as event graphs?~~ ✅ **Yes** (2026-09-14) — the project's
    central bet, taken. Monster behaviour is data: routes for the common cases, graphs for
    genuinely scripted monsters, and no separate AI component to keep in step with the event
    format. **And routes are reusable**, which is the part this answer added: one route
    definition can be shared by many monsters instead of copied into each.

    **Shared routes, and the one thing that makes them hard.** A route is referenced by name
    from a library — `res://events/routes/<name>.route.json`, one file per route so it diffs
    and the editor can list it — and the reference site may override the scalar fields:

    ```json
    "route": {"use": "patrol_ns", "speed": 50}
    ```

    `mode`, `loop`, `on_blocked` and `speed` override cleanly. **`waypoints` looked like the
    problem, and turned out to have an easier sibling instead of a fix.** §3 of
    [event-pages.md](event-pages.md) makes absolute cells canonical for `waypoints` because
    absolute cells are what a gizmo drags — but a route shared by six guards in six rooms
    cannot hold absolute cells, or all six patrol the same strip.

    **The fix that shipped, the same day, is a second route mode rather than an exception
    bolted onto the first.** `step_n` / `step_s` / `step_e` / `step_w` — a single relative
    step, already the graph's `step` command by another name — turns out to be **the most
    common move command a route will ever use**, because a patrol is naturally authored as
    "two north, one east, wait, two south" and not as a list of world cells. A route in the
    new `steps` mode is a list of exactly those tokens and never mentions a cell, so sharing
    one needs no anchor, no per-instance expansion, nothing beyond the ordinary `use` lookup
    — reuse falls out of the mode, not out of machinery built to enable it. `steps` is now
    the mode a shared patrol reaches for first.

    **`waypoints` keeps the anchor-relative scheme, demoted to the fallback.** A route
    template in `waypoints` mode still stores its cells relative to an anchor, expanded
    against each instance's spawn cell at parse — kept for the organic path too irregular to
    type as steps and worth dragging instead. An inline (non-shared) route in either mode is
    unaffected: `waypoints` stores absolute cells as always, and a `steps` list was already
    relative with nothing to resolve.

    **Most monsters never touch either mode's machinery.** `fixed`, `toward`, `away` and
    `random` have no waypoints or steps at all, so sharing them is nothing but a named
    reference — and those are the modes that carry a large share of an RPG's monsters before
    `steps` is even in play.

    **This is not page inheritance** (question 17, which was answered no). Inheritance there
    meant implicit and positional — a page silently taking fields from the page before it.
    A route reference is explicit, named, and **resolved at parse into a fully expanded
    inline route**, so the in-memory page is still exactly one shape and cluster 4's boundary
    rule holds: *accept shorthand at the boundary, normalise immediately.*

    **Three things the editor owes this**, none of them optional once a route has more than
    one user: a shared route must show **how many users it has** before it is edited, since
    dragging one guard's handle moves six; a **"make local copy"** button, which is how the
    seventh guard stops being the sixth; and a **validator check for a missing `use` target**
    that fails at import rather than at runtime, because a typo'd route name would otherwise
    read in-game as a monster that simply stands still.

    The graph-side equivalent of this is question 12, below, and it lands consistent with
    it: explicit, named, own context.
12. ~~Sub-graphs — does `call` run another `.event.json`, own context or shared?~~ ✅ **Yes,
    and own context — with the caller reachable through it** (2026-09-14). `call` runs a
    whole other `.event.json`, and the callee's `GameState`-adjacent graph context is its
    own, not the caller's — consistent with how a shared route (11, above) gets its own
    resolved data rather than reading the reference site's. What the plain "own context"
    recommendation was missing: a sub-graph is usually called *for* something specific to the
    call site (which NPC asked, what item was involved), so **the callee's context carries a
    `parent_context` key pointing back at the caller's**, rather than the two being sealed off
    from each other. A condition or command inside the callee reaches an argument the caller
    didn't bother re-passing via `parent_context.some_field`, while `GameState` itself — the
    global flags and variables (14, below) — stays visible from anywhere regardless, since
    it was never per-context to begin with. `parent_context` chains if `call` nests, the same
    way a call stack would, so a graph three levels deep can still reach the outermost
    caller's data by walking `parent_context.parent_context...` rather than everything being
    re-passed at each hop.

    **Superseded 2026-09-17 by question 49** while planning segment 4's executor shape in
    detail. "Own context, caller reachable through `parent_context`" turned out to be the
    wrong split once self flags were considered concretely: a self flag is exactly the kind
    of "GameState-adjacent" thing this question called the callee's own, and a shared
    subroutine (`guard_dialogue.event.json`, called from many different guards) needs the
    opposite — every caller's self flags to stay caller-scoped, or every guard using the
    subroutine would read and write the same flag. 49 keeps the identity (`map_id`/
    `event_id`) fixed through a `call` and adds a real call stack instead of a
    `parent_context` back-reference.
13. ~~Can a graph set its own page?~~ ✅ **No** (2026-09-14), as recommended. There is no
    `set_page` command; page selection stays exactly what event-pages.md §2.3 already
    describes — conditions are the single source of truth for which page is active, checked
    (**"conditional validation"**) rather than imperatively assigned. A graph that wants a
    different page active sets the flag or variable a page's `conditions` test and lets page
    selection notice on its own, the same as a player's own actions would. This is what keeps
    condition lists trustworthy: a page can always be identified by reading its
    `conditions` alone, with no `set_page` call elsewhere in the project able to have
    silently overridden that.
14. ~~`GameState` scope — flags and ints, or a manifest?~~ ✅ **The manifest** (2026-09-14),
    as recommended, with the type list settled: **bools and ints are what a common command
    reads and writes** — a flag, a counter, a chapter number — and are the two types every
    condition and command signature (event-pages.md §2.2) should assume by default. Strings,
    floats, arrays and dictionaries are declarable too, for the cases that need them (an NPC's
    remembered name, a percentage, a party roster), but are the exception a manifest entry
    opts into rather than the common shape. The manifest is what event-pages.md §2.2's
    variable picker reads from, and (11, above) is exactly why this got more pressing: a
    shared route or graph template that takes an argument is asking for a declared, typed
    variable, which is unavailable without this.

---

## Cluster 4 — Authoring format details ✅

*Fully answered as of 2026-09-14. Four of the five are the same rule — accept convenient
shorthand at the boundary, normalise immediately, keep exactly one shape in memory — applied
to commands (15), pages (17), and conditions (16).*

15. ~~Keep the terse command string form `{"command": "mov n 2"}`?~~ ✅ **Yes** (2026-09-14),
    as recommended: it stays, but strictly as **parse-time sugar**. `mov n 2` expands to the
    long form the instant it is read, and nothing downstream — the graph editor, the runner,
    the validator — ever sees or has to understand the terse spelling. What this buys is the
    typing speed of the dock's seeded commands without a second command grammar to keep in
    step with the first: there is exactly one command shape in memory, and the terse form is
    a keyboard convenience at the boundary rather than an alternate representation. The cost
    is that a file saved after a round trip comes back long — accepted, since the long form
    is what the editor edits anyway.
16. ~~Structured conditions vs expression strings — keep both, or unify?~~ ✅ **Both
    surfaces, one representation** (2026-09-14). Pages keep structured entries and `if` keeps
    its expression string, but **the string is parsed into the same structured condition the
    pages use** — so the two are authoring surfaces over one shape, not two condition
    systems. This is question 15's rule applied to conditions: `chapter >= 2 and not
    slime_a_dead` is sugar typed at the boundary, expanded on read, and nothing downstream
    sees a string.

    **What it buys, beyond consistency.** One evaluator and **one predicate table** — the
    list of what a condition can test (`flag`, `var`, `self_flag`, `item`, `party_has`, …)
    lives in one place the way `EventCommand.definitions()` does for commands, so a predicate
    cannot exist on the page side and not in `if`. That divergence is the specific failure
    "keep both, fully separate" would have rotted into: add `party_has` next year, add it
    twice or not at all. And because the parsed form is introspectable, an `if` gets the
    same **static validation against question 14's manifest** that pages do — a graph testing
    `chpater` is caught at validate time rather than mid-cutscene, when the player finally
    reaches that branch. That argument did not exist when the "keep both" recommendation was
    written; the manifest is what made it available.

    **The cost, which is the real content of this decision.** Godot's built-in `Expression`
    can no longer be the evaluator: it executes, but it will not hand back a tree, and the
    tree is the entire point. So stage C owes a **real tokenizer and precedence parser**,
    with error positions good enough to show in the dock. That is the largest single piece of
    work this answer creates, and it buys nothing at runtime — only at validate time and for
    later tooling. Accepted knowingly.

    **Two consequences to design around.** The structured form has to express everything a
    string can, so it grows `all` / `any` / `not` nesting; the flat AND list stays the *page*
    authoring convention (the page form offers nothing else) rather than being the limit of
    the format. And a typed string does not survive a round trip — the author's spelling and
    parenthesisation are normalised away, exactly as 15's terse commands are. If arithmetic
    inside a comparison (`gold - cost > 0`) turns out to be wanted, that is a new leaf kind
    to add deliberately, not a reason to keep a second evaluator.

    **Later tooling becomes additive**, which is the point of paying now: a condition builder
    widget for `if`, a rename-this-flag-everywhere refactor, or a "what would make this branch
    take" inspector are all things you can write against a tree and cannot write against a
    string. None are owed in stage C.
17. ~~Do pages inherit?~~ ✅ **No.** Pages are fully explicit and absent means default. The
    repetition inheritance would have saved goes to a "duplicate page" button in the page
    bar instead. What that buys: a page reads in isolation, diffs cleanly, and the in-memory
    page is always exactly the page in the file — no resolution pass between parse and
    `ActorView.apply_art`. That is the same rule cluster 4 states for fields — *accept
    shorthand at the boundary, normalise immediately, keep one shape in memory* — applied to
    whole pages, which is the argument that settled it.
18. ~~Route `wait` units — steps or seconds?~~ ✅ **Seconds** (2026-09-14). Not the
    unit-tagged compromise that was recommended: a `wait` is simply a duration in seconds in
    both games. The recommendation assumed steps were worth keeping because they read
    naturally in game 1, but they are meaningless in game 2, and a tagged unit would have put
    a per-field discriminator into the format to serve exactly one game — the opposite of
    question 15's rule, which wants one shape in memory. Seconds are the unit both games can
    always answer, so the field is a plain number and the parser has nothing to branch on. If
    "wait one step" turns out to be genuinely wanted in game 1, it belongs as its own command
    with its own name, not as a mode of `wait`.
19. ~~One document per event, or a map-level bundle?~~ ✅ **Per-event files, in a per-map
    folder** (2026-09-14) — the recommendation, plus the answer to the objection against it.
    Each event is its own document, so it diffs, moves and renames cleanly and two people
    editing two events never touch the same file; the "dozens of tiny files" cost is paid off
    by **foldering them per map** rather than by bundling, so a map's events are one directory
    listing instead of one document. The dock still opens a map's worth at once — that was
    always a dock feature rather than a storage decision, and the folder is exactly what it
    globs.

---

## Cluster 6 — Editor tooling ✅

*Fully answered as of 2026-09-14. The tooling **wishlist** stays in
[open-questions.md](open-questions.md) — those are not questions, so they do not follow the
cluster heading here.*

22. ~~Gizmo undo strategy — internal snapshot stack, or `EditorUndoRedoManager`?~~ ✅
    **The snapshot stack, for now** (2026-09-14), as recommended, and deliberately recorded
    as provisional. Routes are small enough that snapshotting one whole is cheap, and the
    event dock already treats the file as the source of truth with explicit Save/Reload — so
    the stack keeps **one model of "when does my change hit disk"** rather than two
    overlapping ones. The accepted cost: `Ctrl+Z` does not cross between a gizmo edit and an
    ordinary scene edit, so undoing past a gizmo change means two separate undo histories.
    This was the plan's largest implementation-risk unknown — not because the decision is
    hard but because Godot's editor undo is object-property shaped while the data here is a
    file — and "for now" is the point: **timebox it**, and if the split history proves
    annoying in practice, revisiting means writing an `EditorUndoRedoManager` adapter over a
    working feature rather than choosing blind.

---

## Cluster 7 — Deferred by design ✅

*Fully answered as of 2026-09-14. Answered ahead of stage E, where they were originally
deferred to — both answers are cheap to revisit and neither changes what stage C builds.*

23. ~~Mid-execution page switch — defer, or swap immediately?~~ ✅ **Defer to graph
    completion** (2026-09-14), as recommended, **with an explicit escape hatch**: a graph can
    hit a dedicated **re-validate** command to force page selection to run at that point. The
    default prevents "the chest changed art halfway through its own cutscene" — a running
    graph keeps the page it started under, so the actor it is animating cannot swap sprite,
    collision or page body underneath it. The re-validate command covers the case pure
    deferral would have made impossible: a long background or cutscene graph that *should*
    notice a flag it just set, at a beat the author chooses. Putting the switch behind an
    explicit command keeps it authored and visible in the graph rather than an emergent
    timing surprise, and it does not reintroduce question 13's `set_page` — re-validate
    re-runs the ordinary conditional check, it does not name a page.
24. ~~Does game 1 have a separate battle scene?~~ ✅ **Yes**, as Lufia 2 does, and as
    [slime_a.event.json](events/slime_a.event.json) already assumed with its `start_battle`
    command. **Consequence: `ModeStack` moves from the last stage into stage A**, since a
    Battle mode that keeps the field map resident is now a prerequisite for game 1 being
    playable end to end. It is also the arbiter question 27 needs.
25. ~~Save format: in-flight background runners — captured, or restartable from the top?~~ ✅
    **Record the node they were in** (2026-09-14) — a middle position, not the recommended
    "always restartable". An background runner saves **which graph node it was processing**, and
    resumes there rather than at the top. That costs one identifier per runner and avoids the
    visible failure of pure restart, where a long background patrol or idle loop snaps back to
    its beginning on every load. It stops short of full capture: the command *within* that
    node re-runs from its start, and a `GridMotion` mid-step is not preserved. **"For now" is
    meant literally** — revisit once stage C's runner exists and it is clear how coarse a node
    actually is; the wishlist item in [open-questions.md](open-questions.md) tracks the harder
    mid-command version. Saved regardless, per two-games.md §3.10: self flags, variables,
    monster `credit`, **and route progress** (waypoint index plus `pingpong` direction) — the
    last of which the original envelope omitted.
26. ~~Do the two games share maps?~~ ✅ **No.** Separate map sets — game 1 is `Space2D` and
    game 2 is `Space3D`, and the art styles do not mix in any case. The simplification this
    earns: **a map belongs to exactly one profile**, so no map declares which presentations
    it supports, `MapContext` needs no profile-compatibility field, and no "view two ways"
    mode has to exist.

---

## Cluster 10 — Stage C, the event system ✅

*Decided 2026-09-14 while planning stage C. The plan itself is
[stage-c-plan.md](stage-c-plan.md); this is the record of the decisions inside it.*

39. ~~How savable is "savable at almost any moment"?~~ ✅ **Hybrid, by command.** Movement,
    animation and `wait` resume **mid-command**; dialogue and anything that merely takes a
    frame **restart from the top of their command** on load. Battle saving is refused
    outright rather than left undefined.

    **This is a structural constraint, not a preference.** A GDScript coroutine suspended
    inside `await` keeps its resumption point in the engine's function stack, where nothing
    can enumerate or rebuild it — so the `EventRunner` sketched in architecture.md §7.4 ("a
    blocking command is awaited on its returned key") is *unsaveable as written*, not merely
    awkward to save. The runner is a tick-driven state machine instead, and `to_save()` is a
    straight read of its fields rather than a snapshot mechanism bolted on.

    The asymmetry is deliberate and one-directional: **restart is always a legal downgrade.**
    A command's base `restore()` calls `start()`, so if a command stops being resumable in a
    later version, an old save's state is ignored and it simply re-runs. Shrinking the
    resumable set can never break a save.
40. ~~How are actors and other live things named in a command's args?~~ ✅ **`@` marks a
    resolvable term.** `@player`, `@self`, `@npc_scout` are references resolved at runtime;
    a bare string is a literal string and never an actor id. So `"actor": "npc_scout"` in the
    old examples was wrong and becomes `"@npc_scout"`, and a bare string in an actor-typed
    arg is a validator error that suggests the `@` form. One sigil, one rule, and a glance at
    any arg says whether it is data or a reference.
41. ~~What does `face` take?~~ ✅ **It splits into two commands.** `face_direction` takes a
    compass direction (`n`/`s`/`e`/`w`, plus diagonals where there are eight), `random`, or a
    relative turn; `face_to` takes a `@` term. The old single `face` was polymorphic — the
    examples used `toward` for an actor and `direction` for a vector, in the same arg slot —
    which is exactly the ambiguity two commands remove.

    **Turns are named by handedness: `turn_cw`, `turn_ccw`, `turn_180`.** Not degrees,
    because a `turn_cw` is 90° in game 1 and 45° in game 2, so any number in the name would
    be wrong in one of the two games.
42. ~~The round and the step pulse.~~ ✅ **Struck from the design**, not deferred. Speed
    classes and `credit` go with them, which leaves **`speed` with exactly one meaning
    everywhere**: world units per second. The `100` / `200` values on pages and routes in the
    examples are therefore not a second unit system, just wrong numbers.

    What this cost in code was nothing, which is itself the argument: `RULES["pulse"]`,
    `RULES["round"]`, `suppresses_pulse()`, `rounds_active()` and
    `GameProfile.Capability.STEP_PULSE` were **all uncalled outside a test**. What survives is
    `EventBus.actor_stepped` and its three siblings — a step is still a published moment, it
    is just no longer a clock — and `InputIntent.lock_step`, whose only caller will be stage
    C's exclusive slot. Questions 6–10 keep their numbers with a superseded note; "what drives
    a monster" is now open question 46.
43. ~~What is a `"//"` key?~~ ✅ **A comment.** Preserved verbatim through a parse/stringify
    round trip and ignored semantically, so the editor cannot eat an author's notes —
    [slime_a.event.json](events/slime_a.event.json) already uses four of them.
44. ~~What can trigger an event?~~ ✅ **Seven triggers.** `player_touch` (the player moves
    into the event's cell, or onto it when the event is through-passable), `event_touch` (the
    event moves into the player), `action` (the interact button, facing it or standing on a
    through event), `auto` (exclusive or parallel), `on_load`, `leave_cell`, `on_flag`.

    The last three were added on top of the first four because each covers a case that would
    otherwise need a workaround: an opening cutscene without `on_load` is an `auto` page that
    immediately sets a self flag to stop repeating; a pressure plate that releases needs
    `leave_cell`; and an event reacting to something happening elsewhere on the map needs
    `on_flag`, which falls out of the condition subscription page selection already requires.
    The old `ActorStepped` trigger is gone with the pulse (42); `"trigger": "touch"` in the
    examples normalises to `player_touch`.
45. ~~Where are routes edited?~~ ✅ **A Routes panel plus a viewport gizmo.** The panel lists
    every `res://events/routes/*.route.json` with its **user count** — dragging one guard's
    handle moves all six, and the author has to know that before the drag, not after — and
    edits the selected route as a step list or a waypoint table. The gizmo drags whichever
    route the selected `GameEvent` is using, inline or shared. One place to browse, one place
    to drag, and it keeps the event dock's file-is-the-truth model rather than adding a second
    source.
47. ~~How does a page's graph say where it begins?~~ ✅ **An explicit `start` node**, decided
    2026-09-15 while building the graph and JSON editors against segment 3's page-wrapped
    documents. Before this, a graph's entry point was an unstated convention — whichever node
    happened to be first in the array, which nothing enforced and nothing could validate.
    **Per-page, not global**: each page's `graph` is already fully self-contained (question 17
    — absent means default, never inherited), so each gets its own `start`, matching that
    independence rather than inventing a new place in the document for one shared entry point.

    `start` is a command like any other (`events/event_command.gd`) — no args, one flow port,
    a `RESTART` resume bucket like `label`/`goto` — so it costs the registry one entry rather
    than a special case bolted onto the schema. `EventCommand.validate_reachability(nodes)` is
    the check it unlocks: exactly one `start` node is expected, and every node not reachable
    from it by following `outputs` targets is reported, grouped into **orphaned chains**
    (connected components of the unreached set, not a flat node count) — a two-node dangling
    sequence is one chain, not two.

    All five worked examples in [docs/events/](events/) now open with a `start` node
    targeting their old first node. `graph_editor_panel.gd` gained a matching **Add Start**
    button, since there is still no general command-editing UI (event-pages.md §4.1) — typing
    `"command": "start"` by hand in the JSON dock was the only alternative. The graph viewer
    also gained a **minimal page selector** (a dropdown, condition summary per entry, no
    reorder/add/duplicate/delete yet) so a page-wrapped document like
    [slime_a.event.json](events/slime_a.event.json) can be opened and switched between pages
    at all — before this it could only open a bare-array file. Both are deliberately thin:
    the full page bar (§4.1) and Routes-panel-style tooling stay deferred, this is only enough
    to see and validate a multi-page graph today.

    **Follow-up, same day: an output's `type` merged into a `flow` name, and the graph
    viewer stopped offering to add or remove ports.** `graph_document`'s output shape used
    to be `{"type": "flow"|"bool"|"int"|"float"|"string", "target": ...}` — a generic,
    multi-primitive graph-editor concept a separate per-node `flows` array had to be kept
    in step with by hand, and every real port in every example was `"flow"` anyway. An
    output is now `{"flow": "next"|"true"|"false"|a choice's own label, "target": ...}`,
    one list instead of two that always had to agree. `EventCommand.flows_of` is
    authoritative for how many ports a node has and what each is named — the graph viewer
    builds a node's ports from it directly rather than from the file's own `outputs`, so a
    node's ports are no longer something an author adds or removes (the `+ Output`/`-`
    buttons and the type dropdown are gone); they follow from the command, the same way its
    arguments do. There is still no UI for choosing a command at all (§4.1), so today that
    still means the file already said one.

    **A `GraphNode` also tints red when [`EventCommand.is_blocking`](../events/event_command.gd)
    says the node blocks** — `self_modulate`, since a `GraphNode` has no simpler
    "colour the background" knob — so a glance at the graph says which nodes hold the
    runner up and which fire and carry on.

    **Second follow-up, same day: the start node stopped being something an author adds at
    all.** The Add Start button lasted one round trip — a graph needs exactly one start
    node, so a button to add one is a button that only ever gets pressed once per graph and
    is otherwise a trap (press it twice and `validate_reachability` now reports two).
    `graph_editor_panel._ensure_start_node()` maintains the invariant instead: called after
    loading a page and after a page gains its first node, it adds a start node exactly when
    one is missing and there is a real graph to belong to — an intentionally empty,
    route-only page (event-pages.md §2) is left empty rather than handed a start node it
    never asked for. Three more things follow from "there is always exactly one, and an
    author never manages it directly":
    - **it cannot be deleted** — `_on_delete_nodes_request` and `_on_duplicate_nodes_request`
      both skip it even when it is part of the current selection;
    - **it has no input slot** — nothing may flow into the node execution begins at, or it
      would be reachable from somewhere else too, the exact ambiguity a named entry point
      exists to remove;
    - **it is always green**, never the blocking red above, so it reads as the graph's one
      fixed landmark rather than as one more command among the others.
48. **Is there a debug fast-forward, and how does it reach every command that needs it?**
    ✅ **Yes — a global read-only flag, `DebugFlags.is_fast_forward()`, held down on
    backtick** (2026-09-17). Held rather than toggled, and read directly off `Input`
    rather than routed through `InputManager`'s owned-input stack, because the entire
    point is that it has to keep working when nobody owns input — mid-cutscene, mid-
    dialogue, exactly when a developer wants to blow through a segment they've already
    seen. `force_fast_forward` is a settable override for `event_runner_test.gd`, since a
    headless test cannot hold a physical key down.

    **One convention, not four special cases.** Every blocking, `RESUME_STATE` command
    (`fade`, `shake`, `camera_to`, `camera_follow`, `play_anim`, plus `say`/`ask`/`close_window`
    already being the reason `RESUME_STATE` exists) checks the flag at the top of its own
    `tick()` and collapses to its end state on that same tick if it is set — a `fade`
    snaps straight to `to`, a `camera_to` snaps straight to the target cell, a `shake`
    simply never displaces anything, and `wait` finishes on its first tick since it has no
    end state to preserve at all. `play_anim` is the one hedge worth naming: "when
    possible" it seeks straight to its last frame, and where a visual cannot seek
    deterministically (a particle effect, say) it just stops blocking the runner and lets
    the effect finish on its own clock in the background, the same way dialogue owns its
    own reveal rather than the command executor owning it.

    `GridMotion` and the dialogue window are not `tick()`-shaped commands, so they read
    the same flag themselves rather than through the executor convention: a route under
    fast-forward still commits and settles every cell — occupancy, `actor_stepped`, a
    monster watching the player still sees every moment — it just does each one in zero
    tween time, which is why "teleport to each position" is the right description rather
    than "skip cells". The dialogue window reveals text instantly and auto-advances
    anything that isn't a real choice; a choice still waits for the player, because there
    is nothing to collapse a decision *to*.
49. **`call`, precisely: clone or shared, one runner or a stack, and whose identity?** ✅
    **Clone the target graph, run it as a new frame on the runner's own call stack, and
    keep the caller's identity throughout** (2026-09-17), refining 12 above with the
    concrete shape segment 4's executor interface needed. "Run another event's graph
    inline" (the registry's own blurb) means *inline*, literally: no second `EventRunner`,
    no second scheduler slot, no second actor lease — `call` pushes a `{nodes, cursor}`
    frame onto the current runner's stack and pops it on that frame's `end`, resuming the
    caller at the call node's own `next` port.

    **The target graph is deep-copied before it runs**, not referenced. Two guards
    sharing one `guard_dialogue.event.json` via `call` each get their own private copy of
    its node array, so nothing about one guard's conversation is observable from or
    mutable by the other's, however the document happens to be cached across callers.

    **`EventContext` — map, event, self — never changes across a `call`.** Self flags
    read and written inside the called graph resolve against whoever originally triggered
    the runner, never the called document's own id, which is what makes a shared
    subroutine's self flags mean "have I done this with *this* NPC" rather than "with
    *some* NPC". This is the piece 12 got backwards by calling the callee's context its
    own.

    **New command, `exit_call`** — no args, no flow ports, pops the most-nested call frame
    and resumes the caller at its `next`. Outside any call frame it behaves like `end`,
    rather than being an error, since a top-level graph has nowhere to exit *to* but still
    has a runner to stop.

    **Consequence for segment 5:** a save captured mid-`call` has to serialise the whole
    frame stack — each frame's document reference, its cloned node array, and its cursor —
    not just the top one, because the clone means a restore cannot just reload the
    document and replay from `start`; the cloned copy *is* what was running. A recursion
    guard for a call cycle (A calls B calls A) is a separate, smaller counter from the
    existing `goto`/node-budget one, so the error names it as a call cycle rather than
    reporting a generic budget overrun many frames later.
50. **Do page conditions get the same string form `if` already has?** ✅ **Yes** (2026-09-17).
    `EventCondition.parse_expression`, built for 16's `if` surface, is reused verbatim: a
    page's `conditions` may now be a bare string as well as the structured array, both
    compiling to the same tree. Nothing new to bind — `GameState` was already a global
    autoload reachable from the parser's `var`/`flag`/`self_flag` resolution, so a string
    condition reads live state exactly the way the structured form always has.
51. **Can an exclusive ("main thread") event survive a `change_map` and keep running on the
    new map?** ✅ **Yes, deliberately, and it changes who owns the runner** (2026-09-17).
    `change_map` gains a `next` port (`"flows": ["next"]`, was `[]`) and stops being a
    terminal node — its executor stays busy across the map load and resolves onto `next`
    once the destination is ready, the same as any other multi-tick blocking command.
    This is a small but real revision to segment 1's already-built registry, not just a
    segment 6 concern, since the schema shape changes even though the behaviour lands in
    the scheduler.

    **The exclusive runner is owned by `EventScheduler` itself the moment it acquires the
    slot, not by the `GameEvent` that spawned it and not by the `Actor` it drives.** A
    `GameEvent` is a child of the map scene it is placed on; if it (or the `Actor`) were
    still the thing holding the runner's only reference, the runner would be destroyed the
    instant its map unloads, `change_map`'s new `next` port notwithstanding. Handing the
    scheduler its own reference — for as long as it holds the exclusive slot — is what
    makes "the locked event continues to process" literally true across the boundary.
    Background/ambient runners are unaffected and keep dying with their map exactly as
    before; this persistence is exclusive-only.

    **`EventContext` splits a field it didn't need to split before.** *Identity*
    (`map_id`, `event_id`, for self-flag scoping) is fixed at the moment the runner first
    acquired the exclusive slot and never changes, including across a `change_map` — the
    same rule 49 gives `call`, since self flags are about which authored graph is running,
    not which map the player is standing on. The *live reference* (the actual
    `MapContext`, for cells and `@`-resolution) is rebound on every `change_map`
    completion. Any `@`-reference the rest of the chain needs is re-resolved fresh by role
    against the new map (`@player` looked up again, not a stale node pointer kept) —
    correct whether the player's `Actor` node turns out to persist across a map load or
    gets respawned fresh each time, which is not yet decided because no map loader exists
    yet to decide it.

    **The arriving map's own initialisation is not gated on the traveling runner** — its
    `on_load` triggers, `GameEvent` registration and background/ambient runners start on
    their own schedule regardless of whether the cross-map exclusive runner has finished
    its chain. Stated explicitly as a guardrail so this is never accidentally wired the
    other way.
52. **How does a background route resume after a lease interrupts it — and where does the
    resume point live?** ✅ **On the `Actor`, not the runner or the scheduler, using the
    same restart-vs-resume rule segment 5a already gives whole documents** (2026-09-17).
    `Actor` gains `suspended_route: Dictionary`. When a lease seizes a patrolling actor,
    whatever currently drives its route (segment 7's compiled-command background runner)
    is asked for its ordinary `capture()`, and the result — plus the route's own identity,
    a hash of its compiled command stream, the same idea as segment 5a's `doc_hash` — is
    written there before that runner is discarded. On lease release, a matching identity
    resumes verbatim at the same waypoint and `pingpong` direction via `restore()`; a
    mismatched one (a different route was assigned, or the route file changed) restarts
    from the route's own beginning instead — restart is always a legal downgrade, same as
    5a. `suspended_route` is cleared either way once consumed. Carried on the actor rather
    than the runner or the scheduler because the actor is already what everything else
    (and the save envelope) treats as authoritative; anything that later drives that
    actor — a fresh `RouteBrain`, a reload from disk — finds its resume point by reading
    the actor, with no back-channel to whatever object used to own the route. This makes
    segment 7's "interruption is the same mechanism as saving" line literal: the field
    that carries a paused route across a lease and the field that carries it across a real
    save are the same one.
