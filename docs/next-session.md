# Next session — where to pick up

Written 2026-09-08 at the end of the stage A session. This is the work queue;
[open-questions.md](open-questions.md) is still the decision record.

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

Nothing 🔴 is outstanding. Questions 20, 21, 27 and 28 were answered by building.

---

## 1. Answer five questions first

Stage B needs these, and answering them first makes it one pass instead of two. Every one
has a recommendation on file, so "yes" to all five is a complete answer.

| # | Question | Recommendation |
| --- | --- | --- |
| 11 | Is monster AI authored as event graphs? | Yes, with routes carrying the common cases |
| 6 | Does turning in place open a round? | No — it changes no cell |
| 7 | Does bumping a wall open a round? | No, plus an explicit "wait one step" input |
| 8 | Round watchdog timeout | 2s. Safe to add now that 27 is answered |
| 9 | Does scripted player movement pulse? | No — opt-in `pulse: true` on move commands |

11 is the one worth actual thought: it sets how much of stage C must be right before game 1
is playable. The other four are gameplay levers.

---

## 2. Stage B — game 1 vertical slice

In order, because each puts the one before it under load:

- [ ] **`StepResponder`** — per-actor `speed`/`credit`, driven by `EventBus.actor_stepped`.
      Resolution is **actor-at-a-time**: each responder drains its credit fully before the
      next acts, iterating `MapContext.actors()` for the stable order.
- [ ] **`RoundGate`** — opens on a committed step, joins over completion keys, closes when
      all resolve, holds `InputIntent.step` only. Consults `ModeStack.rounds_active()`; the
      watchdog must not run outside it (that is question 27's whole point).
- [ ] **The watchdog** — force-close, unlock, and log the actor and command that failed to
      complete. Converts the most likely "my game froze" bug into a log line.
- [ ] **`push`** — the test case for transactional occupancy. Block chains, a block shoved
      into a monster, and a block pushed over a hole. `Occupancy.commit` already takes the
      multi-cell set; this is the caller it was built for.
- [ ] **A real 2D map** — `TileMapLayer` with a `passable` custom data layer, wired to
      `MapContext.collision_node`, so `Passability` step 1 is exercised against real data
      rather than the open-ground fallback.
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
