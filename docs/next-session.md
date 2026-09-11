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

- **`Passability._terrain_allows` treats any occupied `GridMap` cell as impassable.** That is
  backwards for a `GridMap` used as a floor. Needs real cell metadata once a 3D map exists —
  fine until then, because no 3D map does.
- **`ActorFactory` is written but never exercised.** Nothing constructs actors from a profile
  yet; the test builds them by hand. First real map will be its first caller.
- **The camera rigs are unexercised** apart from `OrthoPixelRig`'s pitch arithmetic. No rig
  has been attached to an actual camera in a scene.
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
