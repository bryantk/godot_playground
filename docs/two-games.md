# Two games, one toolchain — gap analysis

Companion to [architecture.md](architecture.md). That document describes the engine seams
and its §1 decisions are settled. This one is proposals: what the two-game plan needs
that the seams do not yet cover, and which of those settled decisions the game list puts
back in play.

> See also [event-pages.md](event-pages.md) for the multi-page event format and routes, and
> [open-questions.md](open-questions.md) for every unresolved decision in one place, with
> the answered ones in [solved-questions.md](solved-questions.md).

Written 2026-09-07, revised the same day (see §6). The two targets:

1. **JRPG** — pure 2D grid movement. On some maps, monsters and certain map events take a
   step or an action in response to the player stepping. Speed classes: most act once per
   player step, rare fast ones act twice, slow ones every other step. Lufia 2.
2. **Iso-ish** — the same SNES-era pixel art, 3D underneath. Orthographic, pixel perfect,
   free movement, jumping, height. Levels authored in 3D and rotatable live between four
   yaw stops.

Both are real-time. Game 1 is not turn-based; its monsters are ordinary real-time
actors that happen to be driven by a new trigger source rather than by a clock.

---

## 1. Verdict

The seam holds, and it holds better than the first pass of this document assumed. Nothing
in either game requires tearing up the space/motion split, the `Vector3i` cell
vocabulary, the registry-addressed actors, or the graph-as-JSON event format.

With a single time base across both games, the two games are **one runtime** that
differs along four configuration axes. There is no second execution model to build, no
duration units to disambiguate, and no bimodal event runner.

What is genuinely missing:

- **A step pulse and its round gate.** One new trigger source (`player moved`), a signal to
  carry it, per-actor state for speed classes, and an input gate that holds
  `InputIntent.step` until the round's blocking actions complete. A feature, not a layer.
  (The watchdog this bullet used to call for was cut on 2026-09-13 — open-questions 8.) §3.1
- **Transactional occupancy.** Not for turn ordering — for push chains and for the batch of
  monsters that all respond to the same pulse in the same frame. §3.2
- **Presentation as its own axis.** Game 2 is sprites in a 3D world. The plan has no place
  to put "what an actor looks like" independent of what space it lives in. §3.3
- **Camera as a swappable rig.** Two genuinely different cameras, addressed identically
  by events. §3.4
- **Input as intent.** Two control schemes, and game 2's live rotation makes input
  direction *view-relative* for the first time. §3.5
- **The pixel-perfect 3D rig** and the art-pipeline decisions it forces. §3.6
- **Per-game command subsets**, so one editor can serve both games. §3.7
- **A mode stack** for battle, menus and cutscenes. §3.8
- **Repo structure**, which the plan does not address at all. §3.9

---

## 2. Four axes, two profiles

The two axes in architecture.md §2 become four. Each game is a point in that space, and a
`GameProfile` resource is the thing that names it. **Specified 2026-09-08** — see §2.1.

| | **Space** | **Motion** | **Presentation** | **Camera** |
| --- | --- | --- | --- | --- |
| 1. JRPG | `Space2D` | `GridMotion`, 4-way | `SpriteView2D`, 4 facings | `RoomCamera2D` |
| 2. Iso-ish | `Space3D` | `FreeMotion`, sub-pixel | `SpriteView3D`, 8 facings | `OrthoPixelRig`, 4 yaw stops, pitch 30° |

Time is uniform: real-time, `delta`, seconds. It is not an axis.

**Facing counts, decided 2026-09-08.** Game 1 is 4-way and draws 4 directions. Game 2 moves
freely and draws 8. Both games are sprite games, so the presentation axis is entirely a
choice of how many frames and at what pitch they are drawn.

**8 facings against 90° yaw stops is exact**, which is the reason this combination is worth
having. Frames sit 45° apart and each yaw stop is 90°, so
`frame = (facing_index - 2 * yaw_index) mod 8` — integer arithmetic, no rounding, and no yaw
at which some frame has no art. `SpriteView3D.set_facing(dir, camera_yaw)` is that one line.

One thing falls out of the table.

**The two games differ on every axis, and on nothing else.** Same event system, same
actor identity, same cell vocabulary, same time base. They are two configurations of one
runtime rather than two games that happen to share a library, and game 1's monsters are
the only novel *behaviour* between them — behaviour that is one trigger source away from
being ordinary.

The cost of that is now concentrated: with only two profiles, every axis is exercised by
exactly one game, so nothing in the spine is validated by a second caller. That is what
makes the headless harness (§3.10) load-bearing rather than a nicety.

### 2.1 `GameProfile`

Specified 2026-09-08. It was named here, in §3.7 and in stage A without anyone saying what it
carried; this is that. It is a `Resource`, because §3.7's validation runs inside the Godot
editor and must read it without the game running.

```gdscript
class_name GameProfile extends Resource

enum Capability {
    GRID_MOTION, FREE_MOTION, HEIGHT, PATHFINDER,
    STEP_PULSE, ROTATABLE_VIEW, BATTLE_SCENE,
}

@export var id: StringName                      # "jrpg" — save envelope, §3.10
@export var capabilities: Array[Capability]     # §3.7
@export var input_profile: InputProfile         # §3.5
@export var modes: Array[StringName]            # §3.8
@export var default_cell_size: Vector3          # MapContext may override
@export var texels_per_unit: int = 16           # §3.6

# The four axes of §2, named rather than merely documented — decided 2026-09-08.
@export var motion_script: Script               # GridMotion | FreeMotion
@export var view_script: Script                 # SpriteView2D | SpriteView3D
@export var camera_script: Script               # RoomCamera2D | OrthoPixelRig
```

| Profile | Capabilities |
| --- | --- |
| `jrpg` | `GRID_MOTION, STEP_PULSE, PATHFINDER, BATTLE_SCENE` |
| `isoish` | `FREE_MOTION, HEIGHT, ROTATABLE_VIEW` |

**Capabilities are a closed enum, not the free strings §3.7 sketched.** With a growing
command set, free strings drift into near-duplicates that silently never match a
`requires` entry, and a capability that never matches fails open — the validator simply stops
warning. Seven values is the cheapest possible moment to close it.

`STEP_PULSE` is a capability *only*, with no parallel boolean field, so "does this game
pulse?" has exactly one answer. `HEIGHT` does legitimately coexist with
`SpaceAdapter.supports_height()`: the capability is authoring-time validation, the method is
the runtime warning in architecture.md §4.

**The profile names the axis classes**, so §2's table is executable rather than descriptive
and an actor's children are built from data. Two consequences to hold onto:

- Something has to instantiate them — an `ActorFactory`, which is also what a future `spawn`
  command would use to create a monster from an event graph.
- `MapContext.default_motion` (architecture.md §4) is now a *second* place motion is
  declared. The profile's `motion_script` is the default and a map may override it, which is
  exactly the "grid movement in a 3D scene" case architecture.md §2 wants to keep possible.
  Stating the precedence — map overrides profile — is what stops the two disagreeing.

### 2.2 One profile per executable

**Decided 2026-09-08: each game ships as its own executable, and only one profile exists in
any given build.** There is no runtime profile selection, no launcher scene and no
`--profile` argument; the active profile is fixed when the build is made. The shared code in
`core/`, `events/` and `ui/` is what the two have in common — a library, not a runtime
switch.

What this simplifies, which is more than it looks:

- **Capability tags become purely an authoring-time concern.** Nothing at runtime ever asks
  "is this command available in this profile?", because a build only contains one profile's
  commands' worth of relevance. §3.7's payoff is entirely in the dock's validate pass and the
  graph editor's command dropdown.
- The dock infers which profile it is validating against from the event file's path — an
  event under `games/jrpg/` is authored against `jrpg` — so no profile picker is needed.
- No mode or system has to survive a profile change mid-session, so nothing needs to be
  re-initialised or torn down when one is "swapped". That case does not exist.

The one cost is in-editor: `run/main_scene` names one game at a time, so switching which game
`F5` launches means changing that setting (or using `F6` on the game's own main scene). Minor,
and per-developer rather than per-build.

---

## 3. What is missing

### 3.1 The step pulse

Game 1's monsters need to know the player took a step. That is the whole mechanism.

**The signal.** `Actor`/`GridMotion` already knows when a step commits; publish it:

```gdscript
# EventBus
signal actor_stepped(actor_id: StringName, from: Vector3i, to: Vector3i)
```

Fired once per cell entered, at commit time — which is step *start*, since
architecture.md §5 makes the body authoritative and snaps it to the destination
immediately. Firing at commit rather than at visual settle is what makes monsters appear
to move *with* the player rather than a beat behind, which is the Lufia 2 look.

**Decided 2026-09-08: cell triggers fire at commit too**, not at visual settle, so there is
one moment when a step happens and monsters and traps observe identical state. The
land-on-it feel is a `wait_settle` command inside the trigger's own graph rather than a
`fire_on` flag on the trigger; architecture.md §5 has the detail and §7.6 there records
`fire_on` being dropped rather than moved into page settings.

**Revised 2026-09-14: `actor_stepped` is unconditional, and it is the only signal a cell
trigger needs.** The mechanism above once meant "the player's step is gated to a pulse by
`publishes_pulse` and `ModeStack.suppresses_pulse()`, and a separate always-on `cell_entered`
exists for traps that need every actor's step regardless." Both the gate and the second
signal are gone: `actor_stepped` now fires for **every** grid actor, on every step, always.
A trap's `ActorStepped` trigger below reads it the same as ever; a monster's `StepResponder`
below is now the thing responsible for asking `ModeStack` whether *it* should react, since
the bus no longer decides that on any listener's behalf. architecture.md §7.7 has the full
signal set, including `actor_settled` for the land-on-it half `wait_settle` already used
internally.

**The trigger.** A new `ActorStepped` trigger value in a page's `settings`
(event-pages.md §4.3, which renames `EventSource` to `GameEvent`), with an actor filter
defaulting to the player. Then a monster's behaviour is an ordinary event graph:

```
trigger: ActorStepped, filter: "player"
  → if (player within 6 cells)  → step toward player
                                → else wait
```

This is the reuse win worth pointing out: **monster AI is authored in the graph editor you
already built**, with the same commands, the same validator, and the same JSON. The "some
events on some maps" case — a statue that rotates each step, sand that drains, a platform
that advances — is the identical mechanism with no extra machinery. Nothing needs a
bespoke AI system to get game 1 working.

**Speed classes.** Per-actor local state, no global scheduler:

```
StepResponder (a small component, or just fields on the monster's graph context):
    speed: int = 100          # 200 = acts twice per pulse, 50 = every other pulse
    credit: int = 0

on pulse:
    credit += speed
    while credit >= 100:
        take one action
        credit -= 100
```

Because this is local, there is no need for a deterministic global turn order, no energy
queue, and no tick. Haste and slow are `speed` changes and cost nothing extra. A monster
that should act on the *first* of two pulses rather than the second just starts with
`credit = 50`.

**Resolution order within a pulse: actor-at-a-time** (decided 2026-09-08). Each responder
drains its credit fully before the next one acts — one loop over responders in the stable
order of §3.2, with the inner `while credit >= 100` running to completion. Simplest to
implement, and the consequence to know about is that a `speed: 200` monster resolves both of
its steps against a world in which the slower monsters have not moved yet, so it can enter a
cell that a slower monster is about to vacate. That is order-dependence showing up twice per
fast monster rather than once, which is exactly why §3.2's stable order is load-bearing and
why the headless test in §3.10 should assert on a map containing a fast monster.

**Cutscenes need no special case.** During a cutscene the player is not stepping, so no
pulse fires, so monsters stop. The behaviour that would have needed a "does the world tick
pause?" decision falls out for free.

#### The round, and the input gate

**Decided:** the player cannot commit another step until every action this pulse triggered
has finished. Call that span a **round**.

This is not a return to lockstep. The world still runs on `delta` — animations, particles,
dialogue, ambient events all tween in seconds exactly as in game 2. What is gated is
one field of one struct: `InputIntent.step`. The round is an input policy, not a clock.

**A round is a join over completion keys.** Every long-running call in this architecture
already returns a key (`EventBus.say`, `MotionController.move_to`, `ActorView.play`), so a
round is:

```
player commits a step        → open round, collect the player's own step key
publish actor_stepped        → each responder acts, its keys join the round
await all keys               → close round, unlock InputIntent.step
```

**The player's own step is always in the round.** That matters more than it looks: on a map
with no responders the round contains one key and closes when the player's step tween ends —
which is exactly the "cannot start step 2 until step 1 lands" behaviour that makes grid
movement feel gridlike in the first place. `GridMotion`'s "reject a step while already
moving" *is* the degenerate round. There is no separate mechanism for monster maps and
non-monster maps, and no code path that only game 1's dungeons exercise.

**`blocking` already means "participates in the round".** If monster AI is authored as event
graphs (§3.1, Q3), a command with `blocking: true` joins the round and one with
`blocking: false` does not. So a monster's *step* holds the gate while its idle flourish,
its sound effect, or a floating damage number does not — without inventing any new
vocabulary. This is the strongest argument for the graphs-for-AI bet: the gate semantics fall
out of the command format for free.

**Worst case is the slowest blocking responder.** One monster with a long attack animation
holds the whole map hostage. Two mitigations, both worth adopting: mark presentation-only
actions non-blocking as above, and keep a per-action budget in mind when authoring, since the
round duration *is* the game's input latency.

**A round that never closes locks the player out permanently.** Under lockstep this would
have been a frozen tick; here it is a soft-locked game, which is worse because everything
else keeps animating and it looks like a control bug rather than a hang. This section used
to answer that with a **watchdog** — a maximum round duration that force-closes the round,
unlocks input and logs the offending command. ✅ **Cut 2026-09-13 (open-questions 8): there
is no watchdog**, and `GameProfile.round_watchdog_seconds` is deleted. The consequence is
accepted deliberately: a round that never closes stays open, and the diagnosis is finding
the command that never resolved its key rather than being told which one it was. What
replaces the safety net is the join itself — **every command that can hold the gate must
resolve its completion key on every path out, including failure and cancellation** — which
is where the testing effort goes instead.

**Gate the step, not the input.** Locking all input during a round would feel dreadful.
Recommend only `InputIntent.step` is gated; menu, cancel, and interact stay live. This is
precisely why §3.5 separates `step` from the other intent fields — the gate is one boolean on
one field, not a push onto the input target stack.

**Two design levers this exposes**, both genuine gameplay decisions rather than technical
ones. **Both decided 2026-09-14 — no, and both emit an event** (open-questions 6 and 7):

- **Does turning in place open a round?** ✅ **No.** Turning changes no cell and
  `actor_stepped` is about cells, so facing is free and the player re-aims before a fight
  without giving the monsters a move.
- **Does bumping a wall open a round?** ✅ **No**, plus an explicit "wait one step" input, so
  passing time is a choice rather than a wall-bumping trick.

**But neither is silent, and that distinction is the load-bearing half.** A thing that opens
no round is not a thing nothing may observe: `EventBus.actor_turned` and
`EventBus.actor_blocked` publish both moments, unconditionally — every actor event on
`EventBus` is a trigger now, `actor_stepped` included (revised below). A guard's line of
sight, a statue puzzle, a locked-door bark and a tutorial noticing the player shoving at a
wall all want these; none of them wants a round.

**Event-driven player movement should not pulse by default.** A cutscene that walks the
player past monsters would otherwise drive them. ✅ **Decided 2026-09-14:** an opt-in
`pulse: true` argument on move commands, defaulting false, for the rare scripted sequence
that wants monsters reacting. Per command rather than per mode — a chase sequence wants the
pulse on two commands out of forty, and a pulsing mode is the kind of thing an author forgets
to leave.

**Revised the same day: `actor_stepped` no longer gates itself, so this suppression is no
longer built where §3.1 first put it.** The original mechanism was a
`ModeStack.suppresses_pulse()` check inside `GridMotion._commit_step`, which made
`actor_stepped` fire only for the player, only outside a suppressing mode. That check, and
the per-actor `publishes_pulse` export beside it, are both deleted: `actor_stepped` now fires
for every grid actor on every step, always (§3.1 below). Nothing about the *decision* here
changed — a cutscene still must not drive the monsters, and `pulse: true` is still the
escape hatch — but the enforcement moves to whatever consumes `actor_stepped` for AI purposes
(a future `StepResponder`), which checks `ModeStack` itself rather than relying on the bus to
have already decided on its behalf.

**Animation duration is now load-bearing, not cosmetic.** A fast monster taking two steps
per pulse must fit both inside roughly one player step duration — otherwise being fast makes
the *player* wait longer, which is backwards: the scariest monster in the game would make the
game feel sluggish rather than tense. Derive each action's animation time from the player's
step duration divided by the actions taken this pulse, not from the monster's configured
speed. This was a polish note under the queue-one model; under the gate it is a correctness
requirement.

### 3.2 Transactional occupancy

The occupancy design in architecture.md §6 reserves cells first-come-first-served. Two
cases still stress it, both independent of the time base:

**Push chains.** Pushing a block is a multi-cell, multi-actor transaction: a chain of
blocks either all move or none do, and a block pushed onto a plate or over a hole triggers
something. Reserve-as-you-go cannot express "all or nothing" — a half-committed chain
leaves the world inconsistent. `Occupancy` needs a commit that takes a *set* of cell
changes and either applies all of them or none.

**The pulse batch.** All monsters on a map respond to the same signal in the same frame, so
they all claim cells in the same frame. First-come-first-served is fine here *provided the
iteration order is deterministic* — otherwise two monsters contending for the cell the
player just vacated will resolve differently between runs, which is miserable to debug and
worse to speedrun. Recommend a stable order (registry insertion, or distance to the pulsing
actor) rather than whatever order signal connections happen to fire in.

Full two-phase propose/resolve is not needed. Deterministic order plus a transactional
multi-cell commit covers both cases, and it is much less machinery. The thing to avoid is
writing `Occupancy` as a bare `Dictionary` mutated in place by each mover — give it a
`commit(changes) -> bool` from the start and the push case never requires a rewrite.

**Push is the test case.** If block chains, a block shoved into a monster, and a block
pushed over a hole all work, the design is right. Recommend building `push` early in game 1
for exactly that reason, well before a real puzzle needs it.

### 3.3 Presentation layer (`ActorView`)

Missing entirely. Add it as a sibling of `MotionController` under `Actor`:

```gdscript
class_name ActorView extends Node

func set_facing(dir: Vector3i, camera_yaw: float) -> void
func play(anim: StringName) -> String             # returns a completion key
func set_visible(v: bool) -> void
func set_step_offset(offset: Vector3) -> void     # the grid step offset lands here
```

- `SpriteView2D` — `AnimatedSprite2D`, 4 directions (§2), Y-sorted by the 2D engine.
- `SpriteView3D` — billboarded `Sprite3D`/quad in a 3D world, 8 directions. Needs
  `camera_yaw` to pick its frame, which is what makes game 2's live rotation work; with 90°
  yaw stops that reduces to integer frame arithmetic (§2). Also the layer that rounds the
  transform to whole texels (§3.6).
`visual_offset` from `SpaceAdapter` belongs here rather than on the adapter, as
`set_step_offset` (renamed from `apply_step_offset` when the step tween became a
`GridMotion`-driven clock — architecture.md §4, open-questions 31). **Decided** — architecture.md §4 records the adapter no longer carrying
it, which makes the adapter thinner, the goal architecture.md §11 already names.

### 3.4 Camera rigs

The plan has `camera_to` / `camera_follow` commands but nothing to implement them against.

```gdscript
class_name CameraRig extends Node

func follow(actor_id: StringName, seconds: float) -> String
func move_to(cell: Vector3i, seconds: float) -> String
func rotate_to(yaw: float, seconds: float) -> String   # game 2
func zoom_to(z: float, seconds: float) -> String
func shake(amount: float, seconds: float) -> String
func lock(locked: bool) -> void                        # player control on/off
```

- `RoomCamera2D` (game 1) — follows with a deadzone, clamps to map bounds, or snaps per
  screen for the classic room-scroll. `rotate_to` warns.
- `OrthoPixelRig` (game 2) — fixed pitch, yaw snapped to stops, pixel-quantised. §3.6.

The point is that `camera_to` in an event graph means the same thing in both, and the
rig decides what it can honour. `rotate_to` is the one verb only game 2 honours, which is
what the `ROTATABLE_VIEW` capability is for.

### 3.5 Input as intent

`input_manager.gd` forwards raw named actions to one target. Two schemes need more:

```gdscript
class_name InputIntent    # produced per frame, consumed by MotionController
    move: Vector3         # WORLD space, already basis-corrected
    jump: bool
    run: bool
    interact: bool
    step: Vector3i        # game 1: a discrete committed step, or ZERO
```

Two things this must handle that nothing currently does:

**View-relative input.** The moment game 2's camera rotates, "up" on the stick is no longer
`-Z`. Input direction has to be resolved through the camera basis and then re-quantised —
to 4 world directions for game 1's grid, 8 for game 2's sprites. One `InputProfile` per
game, one basis resolver shared. Get this wrong and rotation feels broken in a way that is
hard to diagnose later.

**Held-direction repeat.** The round gate (§3.1) simplifies this: the cadence is set by
round completion, not by a repeat timer, so holding a direction means "step again the moment
the round closes, if still held". Turning in place is not a policy in the profile but a held
modifier — Shift, the `turn_in_place` action — decided on the frame the direction arrives;
a tap-versus-hold grace made the first frames of every press ambiguous. Note that the round
duration therefore *is* game 1's input latency and its difficulty pacing, which is a good
reason to keep blocking responder actions short.

**"The moment" is literal, and it is the whole difference between stepping and walking.**
The driver hands `GridMotion` a step intent rather than re-testing the key next frame, so
the next step commits inside the settle instead of one `_process` later — see
architecture.md §5. Combined with a linear step tween, a held direction produces genuinely
continuous motion; with either one missing it reads as step-pause-step-pause. The gate
holds the chained step too, or a locked round would leak exactly one step.

The target-stack idea in architecture.md §7.8 still stands; it sits under this, and §3.8
folds it in.

### 3.6 Pixel-perfect 3D and live rotation (game 2)

Not covered at all, and it is the hardest *rendering* problem in the project.

**The rig.** Render the 3D scene into a low-resolution `SubViewport` at the pixel-art
resolution, then scale it up with nearest-neighbour filtering. This is the standard approach
and it is what makes 3D geometry read as pixel art.

This partially revisits the "no SubViewport compositing" line in architecture.md §1. That
decision was about compositing *2D actors into a 3D scene*; a whole-scene low-res viewport
is a different technique, and game 2 likely needs it. Worth stating plainly rather than
pretending the decision is untouched.

**Constraints that follow. Decided 2026-09-08 except where noted:**

- **Texel density: 16 px per tile.** One world unit is one tile is 16 px. Every mesh UV and
  every sprite is built to it, or 3D geometry and sprites visibly disagree about pixel size.
  This is the earliest irreversible art decision and it is independent of pitch and yaw.
- **Yaw: 4 stops at 90°.** "Rotatable live" means an animated snap between the four
  cardinal views. Free rotation and pixel-perfect are close to incompatible: off-axis edges
  break the pixel grid, and directional sprites have no frame to show at 30°.

  The reason 90° is worth the constraint, rather than 45°: **all four views are congruent.**
  Ground tiles stay axis-aligned at every stop, so there is exactly **one tile geometry** to
  draw. With 8 stops at 45° the odd stops render tiles as diamonds and the even stops render
  them axis-aligned, and those are not congruent at any pitch — so 8 stops costs two
  distinct tile presentations, not merely twice the sprite art. That cost is easy to miss.
- **Pitch is a projection choice, and it no longer gates tiles.** Because the four views are
  congruent, pitch does not have to agree with any tile grid — game 2's tiles are real 3D
  meshes and carry no implied camera angle at all. It still gates *sprites*, which have a
  pitch baked into how they are drawn: mismatch it and characters look like they are leaning
  or floating.

  **Decided 2026-09-08: `pitch_degrees = 30.0`** — a 16 × 8 px ground tile, exactly 2:1.

  **Why the pitch has to be one of a short list.** At 90° yaw stops a ground tile projects to
  16 × 16·sin θ px, and if that height is not a whole number the tile grid drifts against the
  pixel grid — rows come out 11 px in some places and 12 px in others. So only the angles
  where `16·sin θ` is an integer are usable at all: 30.00°, 34.23°, 38.68°, 43.43°, 48.59°,
  54.34°, 61.04°, 69.64°, for tile depths 8 through 15. Every "nice" round number — 45°, 60° —
  is fractional and therefore wrong.

  **Correcting this document's first pass**, which conflated two different angles: at a 45°
  yaw a unit ground square projects to a diamond of width √2 and height √2·sin θ, so a 2:1
  diamond needs sin θ = 0.5 and hence **pitch 30°**. `atan(0.5)` ≈ 26.57° is the *screen*
  angle of the resulting tile edge, not a camera pitch; used as one it yields a ~2.24:1
  diamond with no clean pixel stair-step. True isometric is `atan(1/√2)` ≈ 35.26° and 45°
  gives 1:1.

  **What 30° gives, at 16 px per tile:**

  | | Value |
  | --- | --- |
  | Ground tile | 16 × 8 px, exact |
  | Vertical face | 13.856 px per tile of height (`√(256 − 64)`) |
  | Character, 1.75 tiles | 24 px tall (`28·cos 30°`) |

  It is the shallowest of the usable angles, which means it shows height better than any
  other — and game 2 is the game with jumping, ledges and floors (§1), so the pitch that
  reads height best is the one that suits it. A one-tile step stands 13.9 px tall against an
  8 px-deep tile.

  **The cost, and it is a real art-pipeline consequence.** Floors and walls cannot both be
  pixel-clean: a vertical face is `√(256 − n²)` px per tile of height, and 256 has no
  Pythagorean pair, so an integer floor guarantees a fractional wall. Floors tile across the
  whole screen while walls tile once per structure, which is why the floor gets the integer —
  but 30° maximises `cos θ` and therefore has the *tallest* vertical faces of any candidate,
  so it also has the most wall to resample. A wall texture authored at 16 texels per world
  unit of height is squashed to 13.856 px on screen, dropping ~14% of its rows unevenly.

  **Recommended fix, for stage E:** author vertical-face art at **14 texels per world unit of
  height** rather than 16, so it maps to 13.856 px — a 1% squash instead of 14%. Texel density
  stays 16 for everything horizontal. Worth deciding before wall art, not after.
- **Camera quantisation, and sub-pixel actors.** The ortho camera must snap to whole texels
  each frame or everything shimmers as it moves. The logical position stays a continuous
  `Vector3` and only the *render* rounds — quantising the logical position instead would
  silently turn sub-pixel movement into 16 px stepping.

  **Everything that rounds must round the same quantity on the same grid**, and this is the
  part that is easy to get subtly wrong. The camera snaps along its own basis — screen right
  and screen up, which at pitch 30 is not world Y — so a sprite rounding on world X/Y/Z is
  snapping to a grid the camera does not share. The remainders never cancel and the followed
  actor wobbles by up to a texel. `Space.snap_to_basis` is the one place that rounding
  happens, the rig snaps *the followed actor's position* (not the camera's) and hangs the
  camera off the result at a fixed offset, and it pushes its basis to every `SpriteView3D`
  each frame so they round identically. Get that right and the followed actor sits on one
  pixel and stays there.

  **The viewport offset does not do what it looks like it does.** Spending the snap
  remainder by sliding the upscaled image halves the size of the world's scroll steps — but
  it slides the *whole* image, and the followed actor is in that image. So it buys a
  smoother world by making the one thing the eye is locked onto jitter. Measured over a
  second of walking at 4 cells/s:

  | | followed actor | world scroll step |
  | --- | --- | --- |
  | offset off | still, 0 px | 0–2 px per frame |
  | offset on | 2 px, 47 frames in 60 | 0–1 px per frame |

  So `OrthoPixelRig.subtexel_smoothing` defaults **off**. Whole-texel scrolling is what
  every game of this look did, and at any ordinary walk speed the world already advances
  about a texel a frame, so there is very little to win and a visibly unsteady player to
  lose. It is worth turning on only for something moving far slower than a texel per frame.
- **Sprites in a rotating 3D world** need a billboard mode that yaws to the camera but keeps
  its own pitch, plus a depth-sorting decision — a slight tilt writing to the depth buffer
  is usually cleanest; pure billboards intersect geometry badly.

**Consequence for events: none**, and that is the useful part. Cells are world-space
`Vector3i`, so a rotated view never touches event JSON. Only input basis and sprite facing
care about yaw.

### 3.7 Per-game command subsets

`EventCommand` is one global registry, but the two games support different subsets. The
`space: "any" | "grid" | "free"` field in architecture.md §7.2 is too narrow.

**Proposal: capability tags.** Commands declare what they need; profiles and maps declare
what they provide.

```
"jump":         {"requires": ["height", "free_motion"]}
"push":         {"requires": ["grid_motion"]}
"camera_rotate":{"requires": ["rotatable_view"]}
"start_battle": {"requires": ["battle_scene"]}
"say":          {"requires": []}
```

The event dock's validate pass then reports "`jump` is not available in profile `jrpg`"
instead of the command failing silently at runtime, and the graph editor's command dropdown
offers only what the current profile supports. This is the single change that makes one
editor genuinely serve both games.

### 3.8 A mode stack

**Decided 2026-09-08: game 1 has a separate battle scene**, as Lufia 2 does, and as
[slime_a.event.json](events/slime_a.event.json) already assumes with its `start_battle`
command. Game 2 may still want in-world combat. Both need menus and cutscenes.
The plan handles cutscenes via the exclusive runner and nothing else.

**Consequence: `ModeStack` moves from the last stage into stage A.** A Battle mode that keeps the
field map resident is now a prerequisite for game 1 being playable end to end, so it can no
longer be the last thing built. §4.3's order is revised accordingly.

**Proposal:** a small `ModeStack` autoload — `Field`, `Cutscene`, `Battle`, `Menu` — where
each mode declares whether it pauses physics, whether it suppresses the step pulse, whether
the map stays loaded, and who owns input. Battle becomes "push a mode that keeps the map in
memory and hands input to the battle scene", not a bespoke lifecycle.

The input target stack (§3.5, architecture.md §7.8) and the event scheduler's exclusive slot
should both become consumers of this rather than parallel mechanisms. Two overlapping
"who has control" systems is a predictable source of bugs, and it is much cheaper to unify
them before either exists.

**And the round gate is a third one.** §3.1 gates `InputIntent.step` independently of both.
As originally filed this was a live defect: the player steps onto a cell, the round opens, an
`EnterCell` trigger takes the exclusive slot and puts up dialogue, and two seconds later the
round watchdog force-closes the round, unlocks `InputIntent.step` and logs an error naming a
command that is legitimately waiting on the player. ✅ Resolved twice over —
`ModeStack.rounds_active()` means no gate runs under a cutscene (open-questions 27), and the
watchdog half no longer exists at all (open-questions 8, cut 2026-09-13).

Battle *itself* is a subsystem neither document touches. Flagging the boundary is enough for
now; the thing to avoid is letting battle reach into map internals.

### 3.9 Repo and tooling structure

The biggest practical question, and one the plan does not address at all.

Godot constraints that matter: `class_name` globals are project-wide, so a shared script
library works cleanly — but editor plugins must live in each project's own `res://addons/`,
and `.godot/` caches, project settings, input maps and import settings are per project.

**Recommend one repository, two game folders:**

```
core/            space, actors, motion, occupancy, passability, step pulse
events/          registry, runner, scheduler, commands
ui/              TextBox/dialogue, menus, windows
addons/          graph_editor, event_editor  (one copy, both games)
games/
  jrpg/          profile, maps, art, monsters, push/puzzle commands
  isoish/        profile, maps, art, ortho pixel rig
```

One `project.godot`, two export presets, two executables — one per profile (§2.2). Each
preset carries a custom feature tag (`jrpg`, `isoish`) and overrides `run/main_scene` for
it, so each build boots straight into its own game with no selection code anywhere.

The alternative — two separate projects sharing `core/` as a git submodule — keeps
shipping clean but duplicates or symlinks the two editor plugins, drifts two sets of
project settings, and needs a submodule bump per core change. For a solo project where
the shared tooling *is* the point, one repository is the better trade. Shipping as separate
executables does **not** require splitting the repo; that is what the feature tags are for.

**On project-global settings — no longer a cost at all.** The renderer and
`textures/canvas_textures/default_texture_filter` are project-global, and they looked like
the sharp cost of one repo when a third game wanted filtered mipmapped textures and
Forward+. Both remaining games are pixel-art games: `gl_compatibility` with
nearest-neighbour filtering is correct for each of them, and the two never disagree. The
one-repo case no longer leans on a feature-tag override for the renderer.

Feature tags are still doing real work for `run/main_scene`, which is a per-preset string
rather than a rendering mode — the mechanism is the same
(`renderer/rendering_method.mobile` is in `project.godot` today), but nothing now depends
on it behaving for a *custom* tag, so there is no verification blocking the layout.

**Corollary:** `TextBox/`, `constants.gd`, `event_bus.gd` and `input_manager.gd` are
currently at the repository root. They are all shared infrastructure and should move into
`core/` / `ui/` as part of stage A, while it is cheap.

### 3.10 Two smaller ones

**Save framework.** Two games, one format: a shared envelope (profile id, map id, spawn
cell, flags, variables, party) plus a per-game payload blob. Worth defining early, because
retrofitting serialisation onto actors and occupancy is miserable.

Occupancy is derivable from actor cells and need not be stored. These are not, and are all
in the "small, easy to forget, visible if lost" category:

- Monster `credit` values (§3.1).
- **Route progress** — the current waypoint index, and the `pingpong` direction
  (event-pages.md §3). A patrol reloading at waypoint 0 heading forward instead of waypoint
  3 heading back is exactly the kind of bug found weeks later.
- **Self flags** (event-pages.md §2.2). Active page is derivable from conditions; self flags
  are not derivable from anything.

**Headless tests.** The shared core is about to be depended on by both games, which is
exactly when silent regressions get expensive — and with only two profiles, each axis has
exactly one caller, so nothing is validated by a second game merely existing. A headless
scene that loads a map, fires a sequence of step pulses, runs an event graph, and asserts
on final actor cells and flags would cover the pulse batch, the occupancy commit and the
event runner — the three places where bugs will actually live.

The round gate makes game 1 unusually cheap to test this way: a round is a discrete,
awaitable unit with a defined end, so a test can drive "step north, step north, step east"
and assert exact final cells without sampling frames or guessing at timing. Worth exploiting
early, since the pulse batch and the push resolver are the two systems where a regression
would otherwise only show up as a puzzle that quietly stopped being solvable.

---

## 4. Settled decisions the game list reopens

1. **Is `Space2D` worth building for one game?** Game 2 is the proof that "looks 2D, is 3D"
   works. If it succeeds, game 1 could run on `Space3D` too and the 2D adapter is dead
   weight. But game 1 is the game where authentic 2D tooling pays most — `TileMapLayer`
   editing, Y-sort, 2D lights, no texel-density discipline, no billboard sorting — and it
   has no height at all. **Recommend: keep the adapter seam and build game 1 in `Space2D`.**
   If game 2's rig turns out better than expected, game 1 migrates by swapping the adapter,
   with nothing above it touched. That migration being cheap is the entire reason the seam
   exists — this is it earning its keep, not a hedge.

2. **"No SubViewport compositing"** stands for actors, but game 2 needs a whole-scene
   low-res viewport. §3.6.

3. **Build order.** The order in architecture.md §9 was written for one game. Revised:

   - **A. Shared spine** — `GameProfile` first, since everything else here reads it; then
     `Space`, adapters, `Actor`, `ActorView`, registry, `MapContext`, `Occupancy` with
     transactional commit, `InputIntent`, `CameraRig` base, and **`ModeStack`** (moved
     forward from F — §3.8: game 1's separate battle scene needs it, and it is the arbiter
     the round gate, the input target stack and the exclusive slot should all consult).
     Plus the file moves in §3.9.
   - **B. Game 1 vertical slice** — `GridMotion`, passability, the step pulse, one monster
     with a speed class, `push`. Puts the most novel behaviour and the occupancy commit
     under load first.
   - **C. Event system** — registry with capability tags, runner, scheduler, `EventDocument`
     and `GameEvent` including the `ActorStepped` trigger. Author a monster's AI as a graph; that is the test that the
     format is expressive enough.
   - **D. Game 2** — `FreeMotion`, `OrthoPixelRig`, `SpriteView3D`, yaw stops,
     view-relative input. Most of the remaining risk here is art pipeline, not
     architecture.
   - **E. Saves, battle scene, remaining modes.** (The mode stack itself is now in A.)

   The headless harness of §3.10 should land at the end of **B**, not be left as a good idea:
   the round is the awaitable unit that makes it cheap, and B is where the pulse batch and the
   occupancy commit first come under load.

   **Build stage D in two passes**, because it carries two unrelated risks at once and a
   bug in either presents the same way. First `FreeMotion`, jumping and height against
   untextured boxes and a plain ortho camera — that is the shared spine under load in 3D,
   diagnosable on its own. Only then the pixel rig, the yaw stops and the sprites, which is
   an art-pipeline problem rather than an architectural one. Doing both in one pass means a
   spine bug and a texel bug are indistinguishable.

---

## 5. Open questions

1. ~~Mid-step pulse policy~~ — **decided:** input is gated until every blocking action in the
   round completes. See §3.1. Of its four follow-ons, the resolution order within a pulse is
   now decided (actor-at-a-time, §3.1), and so, on 2026-09-14, are the last three of them:
   turning in place and wall-bumping open **no** round but publish an event each, and
   scripted movement does **not** pulse unless a command opts in. §3.1, solved-questions
   6, 7 and 9. Cluster 2 is down to camera ownership alone.
2. ~~Does the pulse fire on step commit or on visual settle?~~ — **decided:** commit, and
   cell triggers fire there too. `fire_on` is dropped and `wait_settle` replaces it. §3.1,
   architecture.md §5.
3. ~~Is monster AI authored as event graphs?~~ — **decided 2026-09-14: yes.** Routes carry
   the common cases and graphs carry the scripted ones; there is no separate AI component.
   The answer added a requirement: **routes are reusable** — a named route in a library, used
   by many monsters, with scalar overrides at the reference site. Reuse turned out to want a
   second route mode: **`steps`**, a list of relative moves (`step_n`/`step_s`/`step_e`/
   `step_w`) that is expected to be the common way a patrol gets authored and needs no anchor
   to share, because it never mentions a cell. `waypoints` (absolute, gizmo-dragged) is the
   fallback, and *that* mode's shared form stores cells **relative to a spawn anchor** rather
   than absolutely, or every monster using it patrols the same strip. solved-questions 11 and
   event-pages.md §3, §3.2.
4. ~~Yaw stops and pitch for game 2~~ — **decided:** 4 stops at 90° and **pitch 30°**, giving
   a 16 × 8 px ground tile. Texel density is 16 px per tile horizontally, and §3.6 recommends
   14 texels per world unit on vertical faces so wall art is not resampled 14%. §3.6.
5. ~~How many sprite directions?~~ — **decided:** 4 for game 1, 8 for game 2. §2.
6. **One repo or two?** (§3.9) Recommend one. Both games want the same renderer and the same
   texture filter, so the project-global settings that would have argued for splitting do
   not conflict.
7. ~~Does game 1 have a separate battle scene?~~ — **decided:** yes, as Lufia 2 does. This
   moves `ModeStack` into stage A. §3.8.
8. ~~Do the games share maps?~~ — **decided 2026-09-08: no.** Game 1 is `Space2D` and game 2
   is `Space3D`, so there is no shared map format to argue about, and the art styles do not
   mix in any case. The simplification this buys — no map declares which presentations it
   supports, `MapContext` needs no profile-compatibility field, and no "view two ways" mode
   has to exist. **A map belongs to exactly one profile.**
9. ~~**Who owns "input is locked"?**~~ ✅ **`ModeStack`** — built in stage A; this is
   open-questions 27. The round gate (§3.1), the input target stack (§3.5) and the exclusive
   slot (architecture.md §7.5) were three independent control mechanisms; `ModeStack`
   arbitrates, and the gate runs only where `rounds_active()`. The watchdog that made this
   urgent is itself cut (open-questions 8). `ActorRegistry` went to `MapContext`
   (open-questions 28).

---

## 6. Revision note

The first version of this document read game 1 as turn-based and proposed a global
`TurnScheduler` with energy-based ordering, a dual time base (ticks vs seconds), unit-tagged
durations on every duration-taking command, a bimodal `EventRunner` for ambient events, and
full two-phase propose/resolve on every move.

All of that is deleted. Game 1 is real-time like game 2; its monsters respond to a
step-pulse trigger. What survived, in much smaller form, is the energy idea — now per-actor
local `credit` for speed classes with no global ordering — and the transactional part of
occupancy, which push chains need regardless of how time works.
