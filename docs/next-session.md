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

**Areas entered and exited landed 2026-09-13** — `core/areas/`, architecture.md §6.1,
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

**Turning in place is Shift**, not a tap, as of 2026-09-12. `InputProfile` lost
`tap_turns_in_place` and `turn_grace`; the `turn_in_place` action (Shift, sharing the key
with `run` — a grid game never runs and a free game never turns) decides on the frame the
direction arrives. A tap-versus-hold grace made the first frames of every press ambiguous:
the step had to be delayed by the grace or retroactively cancelled by a turn.

**2D collision is hand-painted** as of 2026-09-12. `TileSet` custom data went from a
`passable` bool to a `pathing` int: the direction mask painted from
`resources/Pathing.png`, one tile per cell, N/E/S/W as 1/10/100/1000. A step asks both
cells — the one being left and the one being entered — so painting either side of a
boundary is enough. Unpainted reads as open, which is why `jrpg_demo` currently has no
blocking at all. architecture.md §6 has the rule; `stage_a_test` covers it.

Nothing 🔴 is outstanding. Questions 20, 21, 27 and 28 were answered by building.

**Cluster 9 was decided on 2026-09-13** — questions 34–38, now in
[solved-questions.md](solved-questions.md) with the rest of the answers.
**34 and 35 are built and green** (205 stage A assertions); 36–38 are not written.

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

- [ ] **`Passability.floor_y()`, sampled at the shared edge** (36) — `y` stops being an input
      to a step. **No climb tolerance:** a one-tile cliff is impassable upward. Stairs and
      ramps are **inferred from the mesh**, nothing is painted, and the discriminator is that
      a ramp's surface is *continuous across the boundary* while a cliff's is not — so the
      query samples the edge midpoint, not just the two cell centres. Closes the hole where
      any Δy step skips the both-cells-agree rule, and retires the "occupied `GridMap` cell
      is a wall" gap listed in §3 below.
- [ ] **Falling, as repeated one-cell steps, under `max_fall_cells`** (37) — 0 makes ledges
      walls, >10 permits anything. Depth is measured *before* the step off commits, so an
      over-limit drop is refused rather than stranding the actor mid-air.
- [ ] **Ladders as terrain** (38) — a column flagged with the side it is mounted on. Walking
      into that side climbs a cell, walking away descends one. **`jump` is the release**
      (dead in a grid game today) and it **ignores `max_fall_cells`**, because letting go is
      deliberate. The top dismounts automatically, so a ladder top must have floor beside it
      — a validator check, not a discovery.

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

- **`Passability._terrain_allows` treats any occupied `GridMap` cell as impassable.** Right
  for a walls-only data layer, which is what the iso-ish grid demo uses and the first thing
  to exercise this branch at all. Still backwards for a `GridMap` used as a *floor*, where
  occupied means walkable — that case needs real cell metadata and no map has it yet.
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
