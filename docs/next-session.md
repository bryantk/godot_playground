# Next session — where to pick up

Written 2026-09-08 at the end of the stage A session. This is the work queue;
[open-questions.md](open-questions.md) is what is still undecided, and
[solved-questions.md](solved-questions.md) is the decision record.

---

## Where things stand

**Stage A is built, tested and committed** (`9f3c118`), along with Cluster 5's file moves.
160 headless assertions, exit 0:

```
godot --headless --path . res://tests/stage_a_test.tscn
```

Regenerate the two game profiles after changing `GameProfile` or `InputProfile`:

```
godot --headless --path . res://tools/make_profiles.tscn
```

The three demo scenes are **hand-authored `.tscn` files** — edit them in the editor, not
in code. The bootstrap that first generated them (`tools/make_demo_scenes.gd`) is gone as
of 2026-09-12; re-running it would only have clobbered editor work. What guards them now:

```
godot --headless --path . res://tests/demo_scenes_test.tscn
```

It loads each demo, walks the player, and checks the nodes the demo scripts reach by
`@onready` path still exist — which is the failure a rename in the editor causes.

**Areas entered and exited landed 2026-09-13** — `core/areas/`, architecture.md §6.2,
decisions 30–33. An `AreaZone` under an `Area2D`/`Area3D` reports four moments
(entered / arrived / leaving / exited); `AreaComponent` children act on them;
`SpeedModifier` is the first. Grid actors resolve zones by a **synchronous point query at
commit**, not by overlap signals, which is what lets the step *entering* a slow tile be the
slow one.

```
godot --headless --path . res://tests/areas_test.tscn
```

**Each demo carries one example patch**, marked in translucent blue so it can be seen as
well as felt: jrpg cells 11–12 / 5–6 (north+south, ×0.8), and an east–west strip at
x 3–6, z 7 in both iso demos (×0.5). `demo_scenes_test` checks the two ways an authored
zone fails silently — a component that never found its zone, and a shape off the query
layer or not monitorable.

Two things to know before touching movement:

- **The grid step's `Tween` is gone.** `GridMotion._process` walks the sprite offset to
  zero, keeping remaining *distance*, so speed can change mid-cell.
  `ActorView.apply_step_offset` is now `set_step_offset`, and `step_trans` / `step_ease`
  are deleted.
- **`demo_scenes_test` had a phase-dependent assertion** — it sampled the routed NPC's cell
  once, 1.4 s later, against a route whose longest `wait` is 1.5 s, so a working patrol
  could read as broken. It now watches for movement over a window covering a whole cycle.

**Player and NPC are one prefab** as of 2026-09-12. Each game has a single actor scene —
`actor_jrpg.tscn`, `actor_isoish.tscn`, `actor_isoish_grid.tscn` — and every placement of
it is a data container with no opinion about what it does. A `Brain` child supplies that:
`PlayerBrain` (the keyboard, formerly `core/input_driver.gd`), `RouteBrain` (a looping
`move_to` / `step` / `face` / `wait` list in the event format's vocabulary), or nothing at
all for scenery. See architecture.md §5. Two consequences worth remembering:

- Stage C's event runner is the third brain, not a second system bolted beside one. A
  route authored today is a route graph later.
- `MapContext.camera_rig()` exists so a `PlayerBrain` inside a prefab can find the yaw
  that resolves "up on the stick" without a `NodePath` reaching up out of the prefab.

**Turning in place is a held modifier**, not a tap, as of 2026-09-12. `InputProfile` lost
`tap_turns_in_place` and `turn_grace`; the `turn_in_place` action decides on the frame the
direction arrives. A tap-versus-hold grace made the first frames of every press ambiguous:
the step had to be delayed by the grace or retroactively cancelled by a turn.

**That modifier is X, not Shift, as of 2026-09-14.** It shared Shift with `run` on the
reasoning that a grid game never runs and a free game never turns in place — and the first
half stopped being true the day `GridMotion` learned to shorten a step, so **Shift now runs
in both games** and turning moved off it. It went to Q first and then to X the same day,
because Q is `yaw_ccw`: in `isoish_grid_demo` — the only scene that is both a grid map and a
rotatable camera — Q would have turned the actor *and* swung the view. X contends with
nothing in either game.

**2D collision is hand-painted** as of 2026-09-12. `TileSet` custom data went from a
`passable` bool to a `pathing` int: the direction mask painted from
`resources/Pathing.png`, one tile per cell, N/E/S/W as 1/10/100/1000. A step asks both
cells — the one being left and the one being entered — so painting either side of a
boundary is enough. Unpainted reads as open, which is why `jrpg_demo` currently has no
blocking at all. architecture.md §6 has the rule; `stage_a_test` covers it.

Nothing 🔴 is outstanding. Questions 20, 21, 27 and 28 were answered by building.

**Cluster 9 was decided on 2026-09-13** — questions 34–38, now in
[solved-questions.md](solved-questions.md) with the rest of the answers.
**All five are built and green** as of 2026-09-14: 34 and 35 in `stage_a_test` (232
assertions), 36–38 in `height_test` (90).

**Two scopes, and they split the list in half.** 34 and 35 are **every grid game, in either
space** — `Occupancy` is what all grid movement commits through. 36, 37 and 38 are **grid
movement in 3D only**, gated on `effective_motion() == GRID` *and*
`MapContext.supports_height`. Not "3D": `FreeMotion` is 3D and already has real gravity and
jumping, and none of the vertical half may reach it.

### Every grid game — done 2026-09-13

- [x] **`Occupancy` holds a list per cell**, and blocking is a predicate over it (34).
      `at()` became `actors_at` / `blockers_at`, `is_free` became `is_empty` / `is_clear`,
      and `place()` is the forced path that `commit()` is not — a teleport used to call
      `commit_step` and silently fail to move onto a held cell.
- [x] **`solid` split into `through_terrain` and `through_actors`** (35). Note
      `through_terrain` switches off **two** of `Passability`'s three steps: physics is the
      modelled half of terrain, so skipping only the paint lets `body_test_move` put the
      wall back. A through-terrain actor **does not fall** and owns its own `y`, so it needs
      explicit height commands — the one actor the rest of this block does not govern.

### Grid movement in 3D only

**Built 2026-09-14** — [core/terrain.gd](../core/terrain.gd), with 90 assertions in
`tests/height_test.gd`:

```
godot --headless --path . res://tests/height_test.tscn
```

- [x] **Ramps and stairs** (36) — `Y` stops being an input to a step:
      `Terrain.resolve_step()` decides where a direction actually lands. **No climb
      tolerance** — the only way up is a ramp or a ladder, so a bare one-cell lip is a wall
      from below and a drop from above, which is the asymmetry 2D's painted mask could never
      express. **Stairs and ramps are the same rule and differ only in art**; the item name
      picks which mesh, `Terrain` reads both as `RAMP`.
- [x] **Falling** (37) — literally repeated one-cell steps, paid out from `_settle()`, each
      publishing its own `actor_stepped` / `actor_settled`. Depth is measured *before* the
      step off the ledge commits, so an over-limit drop is refused rather than stranding the
      actor. `MapContext.max_fall_cells` defaults to **1**, and 0 makes every ledge a wall.
- [x] **The fall hook** — `Actor.falling(from, to)` (plus `EventBus.actor_falling` /
      `player_falling`) fires **once per fall, before anything drops**, naming where the
      actor is and where it will land. `GridMotion.fall_delay` is the window it opens:
      per-actor seconds of hang before the drop starts, defaulting to 0 so nothing changes
      until it is set. A hanging actor is still `is_busy()`, and `cancel()` clears the hang
      with the fall. **A ladder release skips the delay** — the hang is for a fall nobody
      asked for. **It announces, it does not yet intercept** — the default drop still
      follows. Taking the fall over is the next step and will reuse this signature.
- [x] **Ladders** (38) — a column of `ladder` cells **on their own GridMap layer**
      (`MapContext.ladder_node`), oriented toward the wall they are mounted against. Pressing
      into the wall climbs, away descends, both ends dismount, and sideways off a rung is
      refused. **`jump` is the release** and ignores `max_fall_cells`.
      **The separate layer is load-bearing, not tidiness**: a GridMap cell holds one item, so
      a ladder on the floor layer evicts the tile at its own foot. On its own layer a cell is
      floor *and* ladder — an actor at the foot stands on solid ground and walks off in any
      direction, and the ladder only *adds* the move into the wall. Only an actor hanging on
      a rung over air is restricted to the ladder's moves.
      **Both ways a ladder gets built are supported**, and the first pass only handled one:
      the top rung may sit a cell *under* the ledge or *level* with the top surface, and the
      ladder is mounted from either end of its axis. Assuming the tucked-under layout meant
      a flush ladder matched no rule at all — walking off the ledge toward it fell past it,
      and climbing it stranded the actor on the top rung with no way off.

**Ladders took three passes to work in a real map, and the third bug is the one to remember**
— all three looked identical from inside the game ("the player falls instead of grabbing the
ladder") and had nothing to do with each other:

1. **The ladder shared the floor layer**, so it evicted the tile at its own foot. Fixed by
   giving ladders their own GridMap (`ladder_node`).
2. **Only one build of a ladder was understood** — top rung tucked under the ledge, mounted
   from below. Fixed by accepting either height and either end of the axis.
3. **A leftover `ladder` cell in the *floor* layer read as solid ground.** This is the
   subtle one, and it is what was actually wrong with `isoish_grid_demo`. After moving a
   ladder onto its own layer, the original cell stays behind in the floor layer unless it is
   deleted, and `_kind_of_item`'s "anything that is not a ramp is floor" turned that leftover
   into an invisible platform. The rung then counted as ground, which switched off the guard
   keeping a hanging actor on its ladder — so pressing a perpendicular direction walked the
   actor off the rung into open air, and `max_fall_cells = 5` let it fall.
   `Terrain._kind_of_item` now reads a `ladder`-named item on the floor layer as **VOID**.

- [ ] **A validator for the leftover case.** VOID is the right runtime answer but a silent
      one. A ladder cell sitting in the floor layer is always a mistake and the author should
      be told, alongside the ladder-top check below.

**Two revisions to 36 worth knowing, both decided with Kyle on 2026-09-14:**

- **The floor is a `GridMap`, not a raycast.** 36 said stairs and ramps would be *inferred
  from the mesh* with a continuity test at the shared edge. They are not: `MapContext`
  gained a **`floor_node`**, and a cell's presence says where the ground is while its item
  name says what kind. Deterministic, cheap, needs no physics, works headless, and it means
  no continuity tolerance to tune. The mesh is still consulted for one thing — how high to
  draw the sprite on a slope.
- **A ramp's cell is its lower end.** Stepping onto a ramp is a level step; the climb happens
  on the way *off* it. The sprite is lifted `Terrain.RAMP_RISE` (half a cell) so it stands on
  the slope rather than in it, which is the one place the visual and the logical answer
  deliberately disagree.

**Still open from this work:**

- [ ] **A ladder-top validator** (38 called for it) — a ladder whose top has no floor beside
      it reads in-game as a ladder you cannot leave. The dismount rule handles it correctly;
      nothing warns the author.
- [ ] **Intercepting a fall, not just watching one.** `Actor.falling` and `fall_delay` give a
      listener the news and a window; they do not let it *take over*. The shape this wants is
      a listener claiming the fall — the default drop stands down, the listener moves the
      actor and says when it has landed. Needs a way to hand back "I've got this" that a
      signal alone cannot carry, which is the design question, not the plumbing.
- [ ] **Demo geometry.** `tools/make_height_items.tscn` has written placeholder `ramp`,
      `stairs` and `ladder` items (6, 7, 8) into `pixel_blocks.tres`, and
      `tools/make_block_variants.tscn` three capped-off `block_1` variants (9, 10, 11) with
      no top and one, two or three wall faces. Placing them, pointing
      `MapContext.floor_node` at the Floor GridMap and adding a **Ladders** GridMap for
      `ladder_node` is editor work. The art is placeholder primitives until real meshes
      exist — they borrow existing materials so they are textured, but the UV mapping is
      arbitrary and ignores §3.6's texel density.

**Two things worth knowing if you regenerate the placeholders:**

- **Winding decides which way a face points**, and Godot reads it as
  `(v0 - v2).cross(v0 - v1)`. The first ramp had every face inverted — the slope rendered
  from underneath — and was missing both triangular sides, because the two it called sides
  were both the tall north end.
- **`SurfaceTool` smooths by default.** It welds matching vertices on commit and averages
  their normals, which lit the wedge as if it were rounded and turned the stairs into one
  soft lump. `set_smooth_group(-1)` before adding vertices is what makes them flat.

---

## 1. The four questions — answered 2026-09-14

All four are decided and in [solved-questions.md](solved-questions.md). **Stage B is
unblocked.**

| # | Question | Answer |
| --- | --- | --- |
| 6 | Does turning in place open a round? | **No** — but it emits `EventBus.actor_turned` |
| 7 | Does bumping a wall open a round? | **No** — but it emits `EventBus.actor_blocked`, plus a "wait one step" input |
| 9 | Does scripted player movement pulse? | **No** — opt-in `pulse: true` per move command |
| 11 | Is monster AI authored as event graphs? | **Yes**, plus reusable named routes |

**The common thread in 6 and 7 is worth carrying into stage B:** *opening no round is not the
same as being silent.* `actor_turned` and `actor_blocked` are triggers — published always, so
they can be observed but nothing depends on them to drive anything.

**Revised the same day, and worth reading before touching any of this: the whole actor-event
set was redesigned around one rule.** *Every* actor event is now a trigger, not just 6 and
7's two. `actor_stepped` was gated by a per-actor `publishes_pulse` export and by
`ModeStack.suppresses_pulse()`; there was also a separate always-on `cell_entered` for
listeners that needed every actor's step regardless. Both are deleted. `EventBus` now
publishes **four** unconditional actor moments and their `player_*` shorthands:

| Signal | Fires when |
| --- | --- |
| `actor_stepped` / `player_stepped` | A step commits — body on the new cell, sprite not yet |
| `actor_settled` / `player_settled` | The sprite has caught up — the land-on-it moment |
| `actor_blocked` / `player_blocked` | A step was refused (7) |
| `actor_turned` / `player_turned` | Facing changed, with or without a step (6) |

**Built with the answers, and green** — 232 stage A assertions, up from 205
(`core/event_bus.gd`, `actors/actor.gd`, `actors/motion/grid_motion.gd`):

- `Actor.set_facing` publishes `actor_turned` for every facing change — a listener meaning
  "turned in place" checks the actor is not moving — and re-facing the way it already faces
  publishes nothing, or the signal would fire every frame a brain re-asserts its direction.
- The two `blocked.emit` sites in `GridMotion` now go through **`Actor.report_blocked`**, and
  `_settle()` now goes through the new **`Actor.report_settled`**, so terrain refusals,
  occupancy refusals and the settle moment each have one announcement point instead of one
  per call site that can drift.
- `actor_stepped` is unconditional: `publishes_pulse` and the `suppresses_pulse()` check
  inside `_commit_step` are both deleted, and so is `cell_entered` — `actor_stepped` now does
  its job. **What this means for question 9** (does scripted movement pulse — still no by
  default): the answer is unchanged, but the enforcement is no longer built. It moves to
  whatever consumes `actor_stepped` for AI purposes — `StepResponder`, below, must ask
  `ModeStack.suppresses_pulse()` itself before reacting, and a `pulse: true` command needs a
  way to tell it "react anyway" for that one step.
- **`EventBus` carries four `player_*` shorthands** — one the `actor_*` signal without the id,
  because most listeners only ever care about the player. Who the player is, is
  **`Actor.is_player()`**, one definition; `AreaComponent`'s PLAYER filter had a second copy
  of that test and now calls it. None of the four diverges from its `actor_*` counterpart any
  more — there is no gating left at this layer for `player_stepped` to disagree with.
- **One moment, one signal.** A `player_entered_cell` was written and deleted the same day: it
  fired with `player_stepped`, always, and differed only in dropping `from`. Want just the
  cell, take `(_from, to)` — Godot 4 will not connect a shorter callable, so the underscore is
  required, and it is still cheaper than a second name for one event. This is the rule the
  whole redesign applies at scale: a signal earns its place by covering a different *moment*,
  never a different payload subset or listener subset of an existing one.

**Still to build from these answers**, none of it stage A:

- The **"wait one step" input** that 7 promises — an `InputIntent` field and an action, on the
  stage B list below, not a stage C command.
- `StepResponder` must gate itself against `ModeStack` — see above. This did not exist as a
  requirement until the pulse gate moved out of `GridMotion`; it belongs to the
  `StepResponder` bullet below rather than being treated as already covered.
- `pulse: true` on move commands, and the responder-side hook it needs to reach — stage C,
  when `EventCommand` exists.
- **Shared routes** — stage C. `res://events/routes/<name>.route.json`, referenced as
  `{"use": "patrol_ns"}`. **Two route modes now, not one**: `steps` is a list of relative
  moves (`step_n`/`step_s`/`step_e`/`step_w`, plus `wait`/`face`) and is expected to be the
  common case, since a patrol is naturally authored that way and a `steps` route needs no
  anchor to be shared — reuse is free once the mode is relative. `waypoints` stays absolute
  cells for the gizmo-dragged case and is the one that needs the anchor trick: a shared
  `waypoints` template stores cells **relative to a spawn anchor**, not absolutely, or six
  guards using one template all patrol the same strip. event-pages.md §3 and §3.2 have the
  whole shape, including the three things the gizmo owes a shared `waypoints` route.

**Question 8 — the round watchdog — was cut on 2026-09-13.** Nothing force-closes a round;
the gate closes on its completion keys alone. Do not build one back in.

---

## 2. Stage B — game 1 vertical slice

In order, because each puts the one before it under load:

- [ ] **`StepResponder`** — per-actor `speed`/`credit`, driven by `EventBus.actor_stepped`.
      Resolution is **actor-at-a-time**: each responder drains its credit fully before the
      next acts, iterating `MapContext.actors()` for the stable order. **Must check
      `ModeStack.suppresses_pulse()` itself before reacting** — `actor_stepped` no longer
      gates that at the emitter (§1 above), so a responder that skips this check reacts to
      the player's cutscene steps exactly the bug question 9 was answered to prevent.
- [ ] **`RoundGate`** — opens on a committed step, joins over completion keys, closes when
      all resolve, holds `InputIntent.step` only, and runs only where
      `ModeStack.rounds_active()`. With question 8 cut there is no timeout underneath it, so
      **the join is the only thing that closes a round**: every command that can take the
      gate must resolve its key on every path out, including the ones that fail or get
      cancelled. That is the invariant to test hardest.
- [ ] **`push`** — the test case for transactional occupancy. Block chains, a block shoved
      into a monster, and a block pushed over a hole. `Occupancy.commit` already takes the
      multi-cell set; this is the caller it was built for.
- [ ] **Wire the "wait one step" input** — what question 7 promised in exchange for a wall
      bump not passing time. `InputIntent.wait` already exists and nothing produces it: it
      needs an action in `InputProfile` and a `GridMotion` path that opens a round and
      resolves its key without moving. Cheap, and it belongs **before** `RoundGate` is called
      done, because a round opened by a command that commits no step is the degenerate case
      the join has to survive.
- [ ] **Paint the JRPG map** — the `Pathing` layer exists, is wired to
      `MapContext.collision_node` and is empty, so that map is open ground and its walls are
      currently scenery. Painting it is a job for the tile editor; `1` in the demo shows the
      overlay. Until then `Passability` step 1 is exercised only by the headless tests.
- [ ] **Extend the headless harness** — drive "step north, step north, step east" through the
      round gate and assert exact final cells. A round is a discrete awaitable unit, which is
      what makes this cheap; `tests/stage_a_test.gd` has the `_step` / `_settled` helpers
      already.

---

## 3. Known gaps in what was built

Honest list of what stage A stubs or simplifies, so none of it is discovered instead of
decided:

- ~~**`Passability._terrain_allows` treats any occupied `GridMap` cell as impassable.**~~
  **Retired 2026-09-14** by separating the two questions rather than teaching one node to
  answer both. `collision_node` is the *wall* layer and occupied still means impassable
  there, which is correct; ground is `floor_node`, read by `Terrain`, where occupied means
  walkable. Neither has to guess which kind of layer it is looking at.
- **Physics is not consulted on a map with a `floor_node`.** `Passability` skips step 3
  there, because the floor slabs and the ramp and stair meshes are themselves colliders and
  a legitimate climb onto a ramp otherwise reads as walking into it. The cost is real: a
  pushable crate or a swinging door on a height map has to be an actor in `Occupancy`
  rather than a bare body.
- **A fall onto an occupied cell stops in the air above it.** The landing is refused by
  occupancy like any other step, the remaining depth is cleared, and the actor is left
  standing on nothing. Deliberate — the alternative is a pending fall nothing will ever pay
  out, which counts as busy and would hang a round forever. Visible and recoverable beats
  unclosable, but nothing re-triggers the fall when the blocker moves away.
- **Nothing falls except by stepping.** An actor spawned or teleported into mid-air stays
  there; gravity is a consequence of a step, not a background force. Fine today, worth
  knowing before an event drops someone down a shaft.
- **`ActorFactory` is written but never exercised.** Nothing constructs actors from a profile
  yet; the test builds them by hand. First real map will be its first caller.
- **`CameraRig.focus_of` is what a rig must follow, not `Actor.world_position`.** The body is
  authoritative and teleports a whole cell at grid commit, so a rig reading the body lurches
  once per step; `focus_of` adds the view's step offset so the camera tracks the sprite, which
  is what the eye tracks. Free motion leaves that offset at zero, so it is one expression for
  both. Both rigs use it. Anything that adds a third rig has to remember to.
- **`RoomCamera2D`'s deadzone was hiding that bug.** A 32×24 px deadzone against a 16 px cell
  absorbs a one-cell jump, so game 1 never showed it and the iso demo showed it immediately.
  Worth remembering when a demo "looks fine" — it may only mean the tolerance is wider than
  the defect.
- **Pixel alignment is a whole-system property, not a per-node one.** The camera, and every
  `SpriteView3D`, must round the same quantity through `Space.snap_to_basis` on the same
  basis-aligned grid, and only the rig may write a followed sprite's transform (see
  `SpriteView3D._set_offset`) so the sprite is never a tween step ahead of the camera. Four
  separate defects here each produced "the camera is jittery" and each needed a different
  fix; if a new view or rig appears, this is the invariant to hold. two-games.md §3.6 has
  the measurements.
- **`is_busy` and `is_travelling` are different questions.** `is_busy` means "still working
  through a command" — what a round joins on, and what stops a second step mid-step.
  `is_travelling` means "physically moving", which is what presentation wants. They only
  diverge for free motion, where steering with the stick moves the actor with no command in
  flight: `FreeMotion.is_busy()` is false the entire time it walks, so anything gated on it
  (a walk cycle, a footstep sound, a dust puff) silently never fires.
- **Demo spawns need clearance in every direction.** The JRPG player used to spawn one tile
  above the bottom wall, so pressing down did nothing and the demo read as broken rather than
  blocked; one of its NPCs was also spawned inside a wall tile, reserving a cell nothing could
  reach. Both fixed, and both are the kind of thing only walking the demo finds.
- **`ActorView` binds once.** `_ready` no longer re-runs `_after_bind` when the visual was
  already bound in code, because a subclass caches the visual's resting position there and a
  second capture folds in whatever correction had since been written — a drift that grows
  every frame once anything writes the transform per frame.
- **`InputManager`'s target stack is untested**, and nothing produces an `InputIntent` yet —
  there is no per-frame producer wiring `InputProfile` to a controller. Stage B needs one.
  `InputIntent.wait` is the field most obviously waiting on it: it is declared, documented,
  and set by nothing.
- **`SpriteView2D` has a loose fallback** hunting for an `AnimatedSprite2D` child; it should
  take the visual explicitly once a real actor scene exists.
- **`move_to` is straight-line-then-stop**, and stops rather than repathing when blocked.
  `path: "astar"` is accepted in the schema and not implemented (architecture.md §12.5).

---

## 4. Loose ends outside the stages

- [ ] **`run/main_scene` points at `res://demos/demo_launcher.tscn`** — the development
      launcher. Should become game 1's main scene when one exists.
- [ ] **Vertical-face art at 14 texels per world unit**, not 16 — needed before wall art, not
      after (two-games.md §3.6).
- [ ] **Editor tooling wishlist** (open-questions.md Cluster 6, added 2026-09-14) — scaling
      area gizmos, a snap-to-cell shortcut on the root actor/event node, a static (non-
      animated) route preview that flags wall hits, and mid-step/mid-command save resume.
      None block a stage; noted so they aren't lost before the gizmo work starts.

---

## 5. After B

- **C** — `EventCommand` registry with capability tags, `EventRunner`, `EventScheduler`,
  `EventDocument`/`GameEvent`. Wants Cluster 4 (15, 16, 18, 19) settled first.
- **D** — game 2, in two passes (two-games.md §4.3). First `FreeMotion`, jumping and height
  against untextured boxes and a plain ortho camera, so a spine bug is diagnosable on its
  own; then the pixel rig, yaw stops and sprites, which is art pipeline rather than
  architecture.
- **E** — saves and the battle scene. The save envelope must carry self flags, monster
  `credit` and **route progress** (waypoint index plus pingpong direction).
