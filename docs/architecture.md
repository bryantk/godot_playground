# Architecture — dual-space movement and the JSON event system

Status: design, nothing implemented. Written 2026-09-07.

This describes how a tile-based 2D map and a free-movement 3D map can both run the
same events, collisions, dialogue and triggers, and how event scripts are stored as
JSON node graphs that the graph editor already understands.

> **Read the companions first.** This document covers the engine seams for one game;
> two others revise it, and a fourth collects what is still undecided.
>
> - [two-games.md](two-games.md) — the seams against both planned games. Adds a
>   presentation axis, camera rigs, input intent and the step pulse. Reopens two decisions
>   in §1 below and revises the build order in §9.
> - [event-pages.md](event-pages.md) — multi-page events, conditions, and routes.
>   **Supersedes §7.1 and §7.6 below.**
> - [open-questions.md](open-questions.md) — every unresolved decision across all three,
>   grouped by when it is needed, and [solved-questions.md](solved-questions.md) — the
>   answered ones, kept with their reasoning.

---

## 1. Decisions on record

These are settled; the rest of the document follows from them.

| Decision | Choice |
| --- | --- |
| Rendering | Real `Node2D` scenes and real `Node3D` scenes. No SubViewport compositing. |
| Canonical maths | 3D. `Vector3` / `Vector3i` are the shared vocabulary; 2D is that with Y dropped. |
| Projection | Y is up. `as_v2(v3) -> Vector2(v3.x, v3.z)`. A 2D map is a 3D map flattened at `y = 0`. |
| Cell type | `Vector3i`. 2D maps keep `y = 0`; 3D maps use `y` as floor/layer. |
| Mode scope | Per map. A map is grid or free, decided when it loads. Transitions at map boundaries. `MapContext.default_motion` overrides `GameProfile.motion_script`. |
| Event coordinates | Cells. Free-movement maps quantise to cells for event purposes only. |
| Actor addressing | Map-unique string ids through a registry. |
| Concurrency | One exclusive (input-locking) runner at a time, plus any number of background runners. |
| Passability | Tile/geometry data **and** physics, together. |
| Grid feel | The physics body snaps to the destination cell immediately; the visual tweens to catch up. |
| Occupancy writes | Always through `Occupancy.commit(changes)`, never by mutating the dictionary in place — even for a single actor's step. |
| Step timing | Occupancy commit, `actor_stepped` and cell triggers all fire at **step commit**. `wait_settle` covers the land-on-it case. §5 (This row said "the step pulse"; the pulse was struck 2026-09-14, question 42. The signal and its timing are unchanged.) |
| Grid directions | Game 1 steps 4-way. Game 2 uses `FreeMotion`. |
| Script shape | Graph node = one command. Flow ports are the successor links. Renders as JSON. |

---

## 2. The two axes that are usually conflated

Most of the difficulty in "swap 2D for 3D" comes from treating it as one switch. It is
two independent ones:

**Space** — is this scene made of `Node2D`s or `Node3D`s? A property of the *map scene*.

**Motion** — does an actor step cell to cell, or move continuously and jump? A property
of the *actor*.

Splitting them means grid movement in a 3D scene is free (which you will want the moment
a town is modelled in 3D), free movement in a 2D scene is possible later, and neither the
event system nor anything above it ever needs to know which is in play.

```
                          Space2D          Space3D
        GridMotion    classic JRPG    3D town, ortho cam, tile steps
        FreeMotion    (unused, works) 3D field, jumping
```

Three of those four squares have a demo (`demos/demo_launcher.tscn`). The top-right one
costs a `MapContext.default_motion` of `GRID` and a `GridMotion` child instead of a
`FreeMotion` one, with nothing above the actor layer changed — which is the claim this
section makes, now exercised rather than asserted.

Everything above the actor layer speaks `Vector3` world positions and `Vector3i` cells.
The conversion to and from `Vector2` happens in exactly one place: the space adapter.

---

## 3. Layers

```
  ┌─ Event authoring ───────────────────────────────────────────┐
  │  graph_editor (nodes)   event_editor (JSON text + validate)  │
  └──────────────────────────┬──────────────────────────────────┘
                             │  .event.json
  ┌─ Event runtime ──────────▼──────────────────────────────────┐
  │  EventScheduler ─ EventRunner* ─ EventCommand registry       │
  └──────────────────────────┬──────────────────────────────────┘
                             │  commands name actors by id, places by cell
  ┌─ World services ─────────▼──────────────────────────────────┐
  │  MapContext ─ ActorRegistry ─ Occupancy ─ GameState          │
  └──────────────────────────┬──────────────────────────────────┘
                             │  Vector3 / Vector3i only
  ┌─ Actor ──────────────────▼──────────────────────────────────┐
  │  PlayerController (player) ─ Actor (Node)                     │
  │                            ─ MotionController (Grid | Free)   │
  └──────────────────────────┬──────────────────────────────────┘
                             │  the only Vector2 ⇄ Vector3 seam
  ┌─ Space adapter ──────────▼──────────────────────────────────┐
  │  Space2D (CharacterBody2D, TileMapLayer)                     │
  │  Space3D (CharacterBody3D, GridMap / mesh + Camera3D ortho)  │
  └──────────────────────────────────────────────────────────────┘
```

Nothing in an upper layer may reference a `Node2D` or `Node3D` type. That single rule is
what makes the swap work; it is worth enforcing in review.

---

## 4. Space layer

### `Space` — static conversions

No state, all static, mirroring `Anchor_Constants` in style.

```gdscript
class_name Space

static func as_v2(v: Vector3)   -> Vector2   # (x, z)
static func as_v2i(c: Vector3i) -> Vector2i  # (x, z)
static func as_v3(v: Vector2, y: float = 0.0)  -> Vector3
static func as_v3i(c: Vector2i, y: int = 0)    -> Vector3i
static func flatten(v: Vector3) -> Vector3   # y stripped, stays 3D
```

`Vector3i` cannot carry methods, so the `as_v2` the brief asked for lives here as a free
function rather than on the value. Everything that needs the projection calls
`Space.as_v2(...)`; nothing else is allowed to write `Vector2(v.x, v.z)` by hand, so the
axis choice can be revisited in one file.

### `SpaceAdapter` — the interface

GDScript has no interfaces and `Node2D`/`Node3D` share no useful base, so the adapter is
a plain `Node` child of the actor root that reaches up to its parent. Two implementations
with identical signatures:

```gdscript
class_name SpaceAdapter extends Node

func world_position() -> Vector3
func set_world_position(p: Vector3) -> void
func set_facing(dir: Vector3) -> void
func body_test_move(from: Vector3, motion: Vector3) -> bool
func move_and_slide(velocity: Vector3, delta: float) -> Vector3   # returns applied
func supports_height() -> bool                # false for Space2D
```

The grid-step tween's `visual_offset` is deliberately **not** here — it lives on `ActorView`
(two-games.md §3.3), which is the layer that owns what an actor looks like. Keeping it off
the adapter is §11's "stay thin" rule being applied rather than stated.

`Space2D` truncates on the way out and lifts on the way in, using `Space`. Its
`supports_height()` is `false`, which is how a command carrying a non-zero `y` on a flat
map produces a warning instead of a silent no-op.

### Map layout

Both map roots carry the same `MapContext` child, so map-level code is shared:

```
Town2D (Node2D)                    Field3D (Node3D)
├─ MapContext                      ├─ MapContext
│    map_id, cell_size,            │    map_id, cell_size,
│    default_motion = Grid         │    default_motion = Free
├─ TileMapLayer (ground)           ├─ GridMap / meshes
├─ TileMapLayer (collision/data)   ├─ StaticBody3D collision
├─ Camera2D                        ├─ Camera3D (orthographic)
├─ Actors/                         ├─ Actors/
└─ Events/                         └─ Events/
```

`cell_size` lives on `MapContext` as a `Vector3` so a 2D map can say `(16, 0, 16)` px and
a 3D map `(1, 1, 1)` m without either knowing about the other's units.

---

## 5. Actor layer

### `Actor` — the identity every system talks to

```gdscript
class_name Actor extends Node

@export var actor_id: StringName        # map-unique: "player", "npc_guard"
@export var through_actors: bool        # walks through actors, and is walked through
@export var through_terrain: bool       # ignores the paint, the colliders and gravity
@export var motion_mode: MotionMode     # Inherit | Grid | Free

signal arrived(cell: Vector3i)
signal blocked(cell: Vector3i)
signal facing_changed(dir: Vector3i)

func cell() -> Vector3i
func world_position() -> Vector3
func facing() -> Vector3i
func is_moving() -> bool
```

A `Node`, not a body subclass — that is what lets the identical script sit under a
`CharacterBody2D` in a town and a `CharacterBody3D` in a field. It registers itself with
`ActorRegistry` on `_ready` and deregisters on exit.

An actor decides nothing. It is an id, a facing and its axis children; where it goes is
whichever of the two things below is attached, if either is.

### `PlayerController` — the only thing left that decides every frame

```gdscript
class_name PlayerController extends Node

var intent := InputIntent.new()

func _think(delta: float) -> void     # fills intent from the keyboard
func _apply(delta: float) -> void     # hands it to Grid | Free motion
```

**Player and NPC are the same scene.** One actor prefab per game is instanced for every
actor on the map; what makes one of them the player is a `PlayerController` child on its
`Actor`. An actor with no controller and no `GameEvent` stands there, which is exactly
what scenery wants. The alternative — a `player_x.tscn` beside an `npc_x.tscn` —
duplicated the sprite, the view wiring and the collision shape twice per game and made
every fix to an actor a fix in two files.

`intent` is one currency, `InputIntent`, and this class is what turns it into motion in
the same pass it fills it. That split still matters even with one class doing both:
filling the intent is *reading the keyboard*, applying it is *which controller the actor
has* (`GridMotion` takes a committed step, `FreeMotion` continuous steering), and the
motion controllers never need to know input exists.

**This used to be `Brain`/`PlayerBrain`, a base class built for several kinds of decider
- the player, and a patrolling NPC (`RouteBrain`, stage C through segment 6).**
Segment 7 (2026-09-20) retired `RouteBrain` in favour of `EventRoute.compile()` turning a
page's own `route` field (event-pages.md §3) into the same command stream an event graph
runs, executed by a background `EventRunner` off a sibling `GameEvent` instead - not a
brain of any kind, so a patrolling actor looks exactly like scenery from `Actor`'s own
point of view. That left `PlayerBrain` the only concrete subclass, so the shared base
bought nothing merging back into it didn't already have for free - done since, the
merged class renamed `PlayerController` to drop a name that no longer described more
than one thing.

| Decider | Fills/drives from | Status |
| --- | --- | --- |
| `PlayerController` | the keyboard, through `InputProfile` and the map's camera yaw | stage A, was `InputDriver`, then `Brain`/`PlayerBrain` |
| event graphs | a runner driving the actor through a lease | stage C, §7 |

### `MotionController`

```gdscript
class_name MotionController extends Node

func step(dir: Vector3i) -> bool                        # one cell; false if blocked
func move_to(cell: Vector3i, opts: Dictionary) -> String  # returns a completion key
func move_by(delta: Vector3i, opts: Dictionary) -> String
func face(dir: Vector3i) -> void
func jump(strength: float) -> String                    # Free only; Grid warns
func cancel() -> void
```

`opts` carries `speed`, `path` (`"line"` / `"astar"` / `"raw"`), `through_walls`,
`blocking`. Every long-running call returns a key, matching the pattern `EventBus.say`
already uses — the caller awaits it or ignores it.

**`GridMotion`** — works in either space.

1. Compute the destination cell.
2. Ask `Passability.can_enter(dest, actor)` (§6).
3. On success, build a change set — release `from`, reserve `dest` — and apply it with a
   single `Occupancy.commit(changes)`. Then **set the body's world position to the
   destination cell centre immediately**.
4. Ask the physics server which `AreaZone`s cover the destination and hand them to the
   actor (§6.2). Synchronous, so a zone that changes the actor's speed has changed it
   before step 5 spends a single frame.
5. Push the visual child back by `-delta` via `ActorView.set_step_offset`, and walk that
   offset to zero in `GridMotion._process` at the actor's **current** speed.
6. Emit `arrived` when the offset reaches zero, resolving the step's completion key.

Step 5 is a hand-rolled clock rather than a `Tween`, and **the state it keeps is the
remaining distance, not the elapsed time**. A tween's duration is fixed when it starts, so
an actor stepping onto mud would have finished that step at its old speed and only slowed
on the next one — which is precisely the case `SpeedModifier` exists to serve. Re-reading
the speed every frame also means a modifier that arrives or leaves mid-cell takes effect
mid-cell. `ActorView` therefore no longer owns the interpolation, and its
`step_trans`/`step_ease` exports are gone with it.

Nothing is interpolated, which was already the only defensible choice: an eased step
decelerates the sprite to a dead stop in the middle of every cell, so a held direction
reads as step-pause-step-pause even when the steps are back to back in time — the velocity
hits zero at each boundary and the eye reads that as a stop, not as walking. Constant
velocity is what joins consecutive steps into continuous motion.

Step 5 has a matching constraint: the next step has to commit **inside** the settle, not a
frame later. Whatever drives the actor hands `GridMotion` a `set_step_intent(dir)` each
frame and withdraws it when it stops asking, and `_settle` consumes it after the route
queue gets its turn. Re-testing the input in the driver's own `_process` instead would
drop one frame per cell, which at a 167–250 ms step is a visible hitch at every boundary.
It is an intent rather than a queue so that a released key cannot buy one more step, and a
`cancel()` — a cutscene taking over — drops it.

Step 3 goes through `commit` even though a single step is only two cell changes and could be
written as two dictionary writes. That is the point: `push` needs an all-or-nothing multi-cell
commit (two-games.md §3.2), and if the ordinary step does not already use that path, push
arrives as a rewrite rather than a caller.

The body is authoritative and always exactly on a cell; the sprite is a lie that catches
up. Physics queries, occupancy, and event triggers therefore never see a half-cell state,
and a cutscene that teleports an actor mid-step just cancels the tween.

**Decided: everything fires at commit.** The body snapping to the destination cell is the
one moment a step happens, and the occupancy commit, `actor_stepped` and any cell trigger on
the destination all fire there, in that order. (This named "the step pulse"; the pulse was
struck on 2026-09-14, question 42, and the signal outlived it unchanged.) Monsters and traps therefore observe identical world state, and there is exactly
one ordering to specify and test.

RPG Maker fires on-enter triggers at visual arrival instead, and that reads better for some
traps. That case is a `wait_settle` command at the top of the trigger's own graph rather than
a `fire_on` flag on the trigger: the step already returns a completion key that resolves when
the tween ends (step 5), so `wait_settle` is `wait_for` against the triggering actor's step
key, which the runner supplies in `context`. No new mechanism, one fewer knob, and nothing
for the validator to check — which is why `fire_on` is dropped from page settings entirely
(event-pages.md §4.3).

**`FreeMotion`** — 3D only. Ordinary `move_and_slide` + gravity + jump through the
adapter. Its `cell()` is `floor(world_position / cell_size)`, computed on demand — no
occupancy reservation, because free actors do not own cells. `move_to(cell)` steers
toward the cell centre and completes inside a tolerance radius.

---

## 6. Collision and passability

Two sources, both consulted, in cost order:

```gdscript
class_name Passability

static func can_enter(ctx: MapContext, cell: Vector3i, actor: Actor) -> bool:
    # 1. Static terrain: a hand-painted direction mask in 2D; GridMap cells or
    #    colliders in 3D.                                    — skipped by through_terrain
    # 2. Occupancy: is a *blocking* actor already standing here?
    #                                                        — skipped by through_actors
    # 3. Physics: SpaceAdapter.body_test_move for anything neither of the above knows
    #    about — a pushed crate, a door body, a temporary barrier.
    #                                                        — skipped by through_terrain
```

Steps 1 and 2 are cheap dictionary/tile lookups and reject most moves. Step 3 is the
escape hatch that keeps physics-driven objects honest without making them author tile
data. Free-movement actors skip 1 and 2 entirely and let physics do its job.

**`through_terrain` skips 1 and 3, not just 1.** Both are terrain — one painted, one
modelled — so switching off only the first leaves physics to re-impose the wall the flag
was told to ignore. **`through_actors` is not tested here at all**: blocking is symmetric,
so both halves of it live in `Occupancy` (open-questions 35).

**A cell holds zero to many actors.** `Occupancy` maps a cell to a *list*, and blocking is
a predicate over it — `actors_at` is what an interact or a trigger reads, `blockers_at` is
what a step reads. A through actor is still recorded, which is exactly why: absent from the
table it could not be found at all. Forced placement (`place`) stacks and cannot be
refused; only a voluntary step consults `is_free_for` (open-questions 34).

### 2D terrain is painted; 3D terrain is modelled

The two spaces answer step 1 differently, and deliberately.

**2D**: a `Pathing` `TileMapLayer` sits beside the art layers, one tile per cell, drawn
from `resources/Pathing.png` — a 4×4 atlas of every combination of open sides. Each tile
carries its combination as an int in the `pathing` custom data layer:

| | | |
| --- | --- | --- |
| `N = 1` | `E = 10` | binary, so a painted tile reads as a nibble |
| `S = 100` | `W = 1000` | |

A step from `a` to `b` is allowed when **`a` is open on the side it leaves by and `b` is
open on the side it is entered by**. Both cells are asked, so a boundary painted from
either side holds — a map can be walled by painting only the wall tiles or only the floor
tiles, whichever is fewer, and the two agree where they meet. The rule is symmetric by
construction and so cannot express a one-way ledge; that is what the event override is
for. An unpainted cell, a missing tile and a missing layer all read as open, which makes
painting subtractive and a half-painted map walkable rather than sealed.

**3D**: Godot's own colliders, plus the `GridMap`'s occupied cells while that is still
the walls layer. No painting.

The layer is hidden at runtime; the JRPG demo toggles it on `1` so what was painted can
be read back off the map.

`Occupancy` is a per-map `Dictionary[Vector3i, StringName]` on `MapContext`. It is
reserved at step start (see above), which is what stops two NPCs walking into the same
tile on the same frame.

### 6.1 Height — ramps, stairs, ladders and falling

**3D grid only** (open-questions 36–38, built 2026-09-14). A map that sets
`MapContext.floor_node` — a `GridMap` of walkable cells, distinct from `collision_node`'s
walls — hands its step resolution to [`Terrain`](../core/terrain.gd). A map that does not,
which is every 2D map and every flat 3D one, behaves exactly as it did before any of this
existed: `to = from + dir`, Y untouched. `FreeMotion` never asks; it has real gravity
already and none of this may reach it.

**The GridMap is the authority on levels, the mesh on looks.** A cell's presence says where
the ground is, its mesh-library **item name** says what kind (`ramp`, `stairs`, anything else
is flat floor), and its **cell orientation** says which way it rises. One rotatable item per
kind is the whole authoring story, and it is exact where raycasting a mesh for surface
continuity would need a tolerance to tune. Godot 4's `MeshLibrary` has no custom-data table
the way `TileSet` does, which is why the name carries the kind.

**Ladders get their own layer** (`MapContext.ladder_node`), because a ladder is an *overlay*
on a cell rather than a kind of ground. A GridMap cell holds exactly one item, so a ladder
sharing the floor layer evicts whatever was there — most visibly the tile at its own foot,
leaving the player standing on a rung where a floor should be. On its own layer a cell can be
floor **and** ladder, or wall and ladder, and the ladder is drawn over both. Climbing keys off
that layer; standing, walking and falling still key off the floor. So an actor at the foot of
a ladder is on solid ground and walks off in any direction normally — pressing into the wall
is the one move the ladder *adds*. Only an actor hanging on a rung over air is restricted to
the ladder's own moves.

**A ladder is mounted and dismounted from either end of its axis, at either height.** Both
halves of that matter, and getting either wrong strands the player:

- **Either end.** Walking into a ladder from the ground below goes the way it is climbed;
  stepping onto it from the ledge above goes the opposite way. Only accepting the first
  worked for a ladder tucked under its ledge and dropped the player straight past one that
  was not. Perpendicular is still refused — you cannot walk onto the side of a ladder.
- **Either height.** The floor beside the last rung may be one cell *up* from it (the rungs
  stop under the ledge) or *level* with it (the rungs run up flush with the top surface).
  Both are how someone would build it, so both dismount.

**A `ladder` item found on the floor layer reads as `VOID`, not floor.** It belongs on the
ladder layer and a cell there is a leftover from before that layer existed — but "anything
that is not a ramp is floor" turned such a leftover into an invisible platform. The rung then
counted as ground, which switched off the guard keeping a hanging actor on its ladder, and
pressing a perpendicular direction walked the actor off the rung into open air. VOID is both
the safe answer and the true one: there is no ground there.

`Terrain.resolve_step()` is the entire rule set, in the order it is tried:

| From → into | Result |
| --- | --- |
| on a ladder | climb (into the wall), descend (away), or dismount at either end |
| off a ramp, the way it rises | up one |
| into a ladder, from its mounted side | mount it |
| ground straight ahead | across, no change of Y |
| onto a ramp rising back at us | down one |
| onto a ladder's top rung, over its edge | down one, on the ladder |
| nothing there | fall, if the floor below is within `max_fall_cells` |

**There is no climb tolerance.** The only way up is a ramp or a ladder, so a bare one-cell
lip is a wall from below and a drop from above — the asymmetry §6's painted 2D mask is
structurally unable to express, since it consults the same two flags in both directions.

**A ramp's logical cell is its lower end**, so stepping on is a level step and the climb
happens on the way off. The sprite is lifted half a cell (`Terrain.RAMP_RISE`) to stand on
the slope instead of inside it — the one place the logical and visible answers disagree by
design, and the reason `GridMotion` interpolates between *surfaces* rather than cell centres.

**Falling is repeated one-cell steps**, literally: each cell of a drop goes through
`_commit_step` like any other step and publishes its own `actor_stepped` / `actor_settled`,
so a monster watching the player fall sees every cell of it. The depth is measured **before
the step off the ledge commits**, which is what lets an over-limit drop be refused instead of
stranding the actor mid-air. `MapContext.max_fall_cells` defaults to 1; 0 makes every ledge a
wall. Releasing a ladder (`jump`) ignores the limit **and the delay below** — both exist for
a fall nobody asked for, and letting go is the one fall that was asked for.

**A fall announces itself before it happens**, which is the hook for choreographing one.
`Actor.falling(from, to)` — with `EventBus.actor_falling` / `player_falling` beside it —
fires once per fall, naming the cell the actor is standing on nothing in and the cell it will
land on, *before* anything drops. `GridMotion.fall_delay` is the window that opens after it:
seconds this actor hangs before the drop begins, **per actor** because it is characterisation
rather than physics — how far anything may fall is the map's business, how long *this* actor
dangles first is the actor's. It defaults to 0, which is the same-frame behaviour falling had
before the hook existed. A hanging actor is still `is_busy()` - which said "no round closes
underneath one" before the round was struck (question 42), and now means no command joined on
that actor resolves early - and `cancel()` clears the hang along with the fall.

The signal announces; it cannot yet **replace** the fall — the default drop still follows.
Taking it over is the next step, and this signature is the one that hook will use.

**Physics stands down on a height map.** `Passability` skips its step 3 wherever `Terrain`
governs, because the floor slabs and the ramp meshes are themselves colliders and would read
a legitimate climb as walking into a wall. The cost: a pushable crate on such a map has to be
an actor in `Occupancy`, not a bare body.

### 6.2 Areas — entered and exited

Passability answers *may I*; an area answers *where am I*. An `AreaZone` is a `Node` under
an `Area2D` or an `Area3D` — the same arrangement `Actor` uses under a body, so one script
serves both spaces — and it reports actors crossing its collider.

**The collider is the authored shape; it is not always what detects the crossing.** Which
path is used follows the **motion, not the space**:

| Motion | How a crossing is detected |
| --- | --- |
| `FreeMotion` | the area's own `body_entered` / `body_exited` |
| `GridMotion`, in either space | a point query at the destination cell centre, at commit |

A grid actor never travels through a shape — it snaps from cell centre to cell centre — so
there is nothing for an overlap signal to observe at the right moment. Worse, an overlap
signal arrives on the *next* physics frame, which is after the step it was supposed to
change has already been given its speed. The query is synchronous and lands inside the
commit, which is what makes "slow the step that is entering" expressible at all. In 3D the
query carries the cell's Y, so a zone on an upper storey does not answer for the floor
below.

**Four moments**, because for the length of a step the body and the sprite disagree:

```
actor_entered   commit of the step that lands inside     body in
actor_arrived   that step's sprite settles inside        visually in
actor_leaving   commit of the step that lands outside    body out
actor_exited    that step's sprite settles outside       visually out
```

`actor_exited` is the one that means *wholly* out, and a zone keeps an actor until then —
which is also what lets a modifier apply to the step carrying the actor out of it. Under
free motion there is no lagging sprite, so entered/arrived fire together, as do
leaving/exited.

**The zone decides nothing.** `AreaComponent` children are what act: one component per
behaviour, so a tile that slows you, plays a sound and fires an event is three components
on one shape. Every actor gets the zone's signals; each component carries its own
`affects` filter (all / player / a named target).

`SpeedModifier` is the first one, and it is a **provider, not a value**: entering registers
it with the actor's `MotionController`, leaving unregisters it, and in between the
controller asks it for a scale every frame, handing it the direction being travelled.
Nothing writes `speed`, so there is no base value to restore and a route's own speed change
cannot be clobbered by a zone ending. Scales from overlapping zones **multiply**. Direction
is the actor's heading resolved to cardinals by `Passability.cardinals` — one or two flags,
so a diagonal or an analog stick asks the same question a grid step does — and leaving all
four unchecked means every direction, the same way an unpainted pathing cell is open.

```
godot --headless --path . res://tests/areas_test.tscn
```

---

## 7. Event system

### 7.1 The document

> **Superseded by [event-pages.md §2](event-pages.md).** An event document is a page
> wrapper, not a bare node array; a top-level array is still accepted as a single-page
> document, so what follows remains the format of *one page's* graph.

An event script is the graph document `graph_document.gd` already reads and writes, with
two fields added per node:

```json
{
  "id": "n2",
  "title": "Guard greets",
  "position": {"x": 240, "y": 0},
  "command": "say",
  "args": {"text": "Halt.", "location": 2},
  "blocking": true,
  "outputs": [{"flow": "next", "target": "n3"}]
}
```

- `command` — a name in the `EventCommand` registry.
- `args` — the command's parameters, shape defined by its registry entry.
- `blocking` — optional; defaults to the command's own default.
- `key` — optional, non-blocking commands only: names the completion key so a later
  `wait_for` in the same graph can join it. Without one the command is fire-and-forget.
- `outputs` — flow ports are successors. A linear command has one; a branch has one per
  branch, in the order the command declares. `"target": ""` ends that path. `flow` names
  the port — `"next"` for a linear command, `"true"`/`"false"` for a branch, a choice's
  own label for `ask` — and is authoritative from `EventCommand.flows_of`, not something
  an author picks; a separate `flows` array used to carry this per node until question
  47's follow-up merged it into each port, since the two always had to agree anyway.

Control flow needs no special mechanism: `if`, `choice`, `goto` and `loop` are ordinary
commands that pick *which* flow port to continue from. That is exactly the "point at the
id of the node to go to" the brief asked for, and it stays valid JSON with no nesting.

`graph_document.parse` keeps repairing what it can and reporting the rest; the new fields
follow the same rule (unknown command → reported, node becomes a no-op, graph still opens).

### 7.2 `EventCommand` — the registry

`event_editor_dock.gd` already looks up a global class named `EventCommand` with a static
`parse_route`, so that is the name to build.

```gdscript
class_name EventCommand

# name -> {
#   "args":     {"cell": "cell", "speed": "float?"},   # ? = optional
#   "blocking": true,                                  # default
#   "flows":    ["next"],                              # flow port labels
#   "space":    "any" | "grid" | "free",               # where it is meaningful
# }
static func definitions() -> Dictionary

static func parse_route(data: Variant) -> Dictionary   # {"commands": [...], "problems": [...]}
static func validate_node(node: Dictionary) -> Array[String]
```

Keeping the schema as data, not as one class per command, means the dock's validate pass,
the graph editor's node inspector, and the runtime all read the same table — and adding a
command is one dictionary entry plus one executor function.

**Terse form.** The dock currently seeds new commands as `{"command": "mov n 2"}`. Worth
keeping as sugar: `parse_route` expands a space-separated string through an alias table
into the structured form, so hand-typing a move route stays fast while the graph editor
always writes the long form. ✅ **Decided 2026-09-14: kept** (§12.1).

**`if` conditions work the same way** (question 16). The `if` command takes an expression
string — `chapter >= 2 and not slime_a_dead` — and `parse_route` expands it into the same
structured condition an event page's `conditions` list holds (event-pages.md §2.2), so there
is one evaluator and one predicate table rather than two condition systems. This means a
real tokenizer and precedence parser, with error positions the dock can show: Godot's
built-in `Expression` executes but returns no tree, and the tree is what makes an `if`
statically checkable against §12.3's manifest.

### 7.3 Command set (first pass)

| Category | Commands |
| --- | --- |
| Flow | `wait`, `goto`, `if`, `choice`, `label`, `end`, `call` (sub-graph) |
| Actor | `move_to`, `move_by`, `step`, `face`, `jump`, `follow`, `set_speed`, `teleport`, `wait_for`, `wait_settle` |
| Dialogue | `say`, `append_say`, `ask` (menu → flow ports), `close_window` |
| State | `set_flag`, `set_var`, `add_var` |
| Map | `change_map`, `fade`, `shake`, `camera_to`, `camera_follow` |
| Presentation | `play_anim`, `play_sound`, `play_music`, `set_visible` |

`space: "free"` on `jump` means the validator warns when a grid map's event uses it,
rather than the command silently doing nothing at runtime.

### 7.4 `EventRunner`

One instance per running script.

```gdscript
class_name EventRunner extends Node

func run(graph: Array[Dictionary], entry_id: String, context: Dictionary) -> void
func stop() -> void
signal finished(runner_id: String)
```

The loop: look up the node, look up the command, execute it. A blocking command is
awaited on its returned key; a non-blocking one has its key filed in the runner's
`_pending` table so a later `wait_for` can join it. Then follow the flow port the command
chose (index 0 unless it says otherwise) and repeat. A visited-count guard on each node
turns a runaway `goto` loop into an error with the node id instead of a frozen editor.

`context` carries `map`, `self_actor` (the event's own actor, so a shared graph can say
`"actor": "@self"`), and the trigger that fired it.

### 7.5 `EventScheduler` (autoload)

- **Exclusive slot** — at most one runner. Locks player input, queues or drops competing
  requests by policy. Cutscenes, NPC conversations, doors.
- **Background runners** — any number, no input lock. NPC patrol routines, fountains,
  weather.
- **Actor leases** — a runner takes a lease on each actor it drives. A second runner
  asking for a leased actor waits or is refused, which is what prevents a patrol routine
  and a cutscene fighting over the same guard's position.
- Background runners are suspended while the exclusive slot is occupied (configurable per
  runner, so a background waterfall keeps going).

### 7.6 Triggers

> **Superseded by [event-pages.md §4.3](event-pages.md).** `EventSource` becomes
> `GameEvent`, and `trigger`, `condition`, `once` and `pulse_filter` all move into per-page
> `settings` — a chest needs a different trigger on each page. `fire_on` is **removed**, not
> moved: everything fires at commit and `wait_settle` covers the alternative (§5).

```gdscript
class_name EventSource extends Node   # a Node again, so it works in both spaces

@export_file("*.event.json") var graph_path: String
@export var entry: String = ""                 # "" = first node
@export var trigger: Trigger                   # Interact | EnterCell | ActorStepped
                                               #  | Autorun | Parallel
@export var pulse_filter: StringName = &"player"   # ActorStepped: whose steps count
@export var cells: Array[Vector3i] = []        # for EnterCell; empty = the parent's cell
@export var condition: String = ""             # flag/var expression, empty = always
@export var once: bool = false
```

Interact triggers are resolved by asking the map "what is at
`player.cell() + player.facing()`?" — a dictionary lookup on `MapContext`, identical in
both spaces. `EnterCell` is checked by `Occupancy` when a reservation lands.

> **Two corrections, 2026-09-13.** This section used to say "no raycast or `Area`
> involved", and to speak of *the* event at a cell.
>
> - **Raycasts are used in 2D**, and by grid movement generally. A point query at the
>   destination cell centre is how `AreaZone` membership is resolved at commit (§6.2); it
>   is synchronous, which an overlap signal is not, and that is the whole reason it is a
>   query rather than a signal. The original rule was written as though colliders were a
>   3D-only affordance.
> - **A cell holds many things, not one.** Many events and many zones may sit on one tile
>   and all of them fire. `MapContext._events_by_cell` was already an `Array` per cell, so
>   the table was right and only the prose was wrong.

### 7.7 What `EventBus` gains

It stays a dumb signal hub with no state. Additions:

```gdscript
signal command_finished(key: String)     # generic completion, mirrors dialogue_finished
signal event_started(runner_id: String, exclusive: bool)
signal event_finished(runner_id: String)
signal map_changing(from_id: StringName, to_id: StringName)
signal input_lock_changed(locked: bool)

# What a grid actor did. All triggers, all unconditional. actor_falling is the only one
# that fires *before* the thing it names, which is what makes it a hook (§6.1).
signal actor_stepped(actor_id: StringName, from: Vector3i, to: Vector3i)
signal actor_settled(actor_id: StringName, cell: Vector3i)
signal actor_blocked(actor_id: StringName, from: Vector3i, to: Vector3i)
signal actor_turned(actor_id: StringName, from_dir: Vector3i, to_dir: Vector3i)
signal actor_falling(actor_id: StringName, from: Vector3i, to: Vector3i)

# The same moments for the player alone, with no id to compare.
signal player_stepped(from: Vector3i, to: Vector3i)
signal player_settled(cell: Vector3i)
signal player_blocked(from: Vector3i, to: Vector3i)
signal player_turned(from_dir: Vector3i, to_dir: Vector3i)
signal player_falling(from: Vector3i, to: Vector3i)

func wait_for_command(key: String) -> void   # same shape as the existing wait_for
```

`dialogue_finished` stays as is; `say` already returns a key, so the `say` command needs
no adapter.

**Revised 2026-09-14: all four are triggers, and none is a clock.** The first version of
this section had `actor_stepped` gated by a per-actor `publishes_pulse` flag and by
`ModeStack.suppresses_pulse()` — the mechanism by which "does event-driven movement drive
the monsters" (question 9) was enforced, at the emitter. Both are gone. `actor_stepped` now
fires unconditionally, for every grid actor, on every step, and `cell_entered` — which used
to exist purely to give traps an unconditional signal `actor_stepped` didn't provide — is
deleted along with it, because `actor_stepped` now does that job itself.

**The gating question did not disappear; it moved.** `EventBus` stays a dumb hub with no
state, so it is no longer where "should this actually act" gets decided. That decision now
belongs to whatever listens *for AI purposes* — a future `StepResponder` asks
`ModeStack.rounds_active()` / `suppresses_pulse()` itself before reacting to a step, the same
way a HUD, a footstep or a music cue was never gated in the first place and needed no change
at all. One signal per moment; the consumer decides what the moment means to it, rather than
the emitter deciding for every consumer at once.

**The four, and what each is for:**

- **`actor_stepped`** — the step committed. Fired once per cell entered, at commit, before
  the visual has caught up. What lets a monster move *with* the player rather than a beat
  behind, for whichever listener chooses to act on it.
- **`actor_settled`** — the step's visual has caught up to the body: the sprite is on the
  cell, any zone the actor stepped out of is now visually left too (`Actor.settle_areas`).
  The "land-on-it" moment — a footfall, a camera nudge, the far side of a `wait_settle` join.
- **`actor_blocked`** — the actor wanted a step and could not have it: the wall bump, from
  either passability or occupancy. Opens no round (open-questions 7).
- **`actor_turned`** — facing changed, whether as part of a step or a turn in place with no
  step at all. Opens no round either way (open-questions 6).

**The `player_*` half is shorthand, not a second mechanism** — the identical four moments
with the id dropped, because most listeners only ever want the player and hand-rolling that
filter thirty times means thirty copies of the player test. There is one copy:
`Actor.is_player()`. Connect to the `actor_*` form or the `player_*` form for a given moment,
never both, or a listener handles the player twice. Now that `actor_stepped` carries no
gating of its own, `player_stepped` is exactly `actor_stepped` filtered — no divergence
between the two forms is left to remember.

**There are four shorthands, not five, and the missing one is the rule.** A
`player_entered_cell` existed for an afternoon and was deleted: it fired at the same instant
as `player_stepped`, under the same conditions, and differed only in carrying the destination
without the origin. That is a payload preference, and a listener expresses one with an
underscore — `func _on_player_stepped(_from: Vector3i, to: Vector3i)`, since Godot 4 refuses
a callable with fewer parameters than the signal and drops the call at emit time. **One
moment, one signal** — the rule this project applies to every one of these eight, including
the ones added after this paragraph was written.

### 7.8 Input during events

`input_manager.gd` currently forwards to a single `target`. Give it a small stack:
`push_target` / `pop_target`, so the exclusive runner pushes a null-ish target (or a
"skip cutscene" handler) and pops it on finish, and the dialogue window pushes itself
while open. No system has to know what the previous owner was.

---

## 8. File layout

```
core/
  space.gd                 Space  (static projections)
  space_adapter.gd         SpaceAdapter (base)
  space_2d.gd              Space2D
  space_3d.gd              Space3D
  map_context.gd           MapContext, occupancy, cell/world conversion
  passability.gd           Passability (static) — terrain, and cardinals()
  areas/
    area_zone.gd           AreaZone — entered/arrived/leaving/exited (§6.2)
    area_component.gd      AreaComponent base — what a zone actually does
    speed_modifier.gd      SpeedModifier — per-direction speed scaling
  game_state.gd            autoload: flags, variables, party
  game_profile.gd          GameProfile Resource — spec in two-games.md §2.1
  mode_stack.gd            autoload: Field | Cutscene | Battle | Menu  (stage A, §12.7)
actors/
  actor.gd                 Actor
  actor_registry.gd        autoload — scope unresolved, see §11 and §12.7
  actor_factory.gd         builds motion/view/camera children from GameProfile
  actor_view.gd            ActorView base (+ sprite_view_2d, sprite_view_3d)
  player_controller.gd     PlayerController — the keyboard, intent in, motion out
                           (was core/input_driver.gd, then brain/brain.gd +
                           brain/player_brain.gd)
  motion/
    motion_controller.gd   base
    grid_motion.gd
    free_motion.gd
events/
  event_command.gd         EventCommand: registry, parse_route, validate
  event_runner.gd
  event_scheduler.gd       autoload
  event_document.gd        EventDocument: page wrapper (event-pages.md §2.1)
  game_event.gd            GameEvent — replaces EventSource (event-pages.md §4.3)
  commands/                one file per category, executors only
    flow_commands.gd
    actor_commands.gd
    dialogue_commands.gd
    ...
addons/graph_editor/       existing — extend graph_document with command/args
addons/event_editor/       existing — its validate hook lights up once EventCommand exists
docs/events/               example graphs (this branch)
```

---

## 9. Build order

Each stage is independently runnable, which matters because the interesting failures are
all at the seams.

1. **Space + projection.** `Space`, `SpaceAdapter`, `Space2D`, `Space3D`. Prove it with a
   throwaway scene that prints the same `Vector3` from a 2D and a 3D actor.
2. **Actor + GridMotion in 2D.** Player steps around a TileMapLayer, snap-and-tween, tile
   custom data passability, occupancy. This is the whole classic-JRPG feel; get it right
   before anything depends on it.
3. **Actor + FreeMotion in 3D**, orthographic camera, jumping. Same `Actor` script, same
   `actor_id`, different controller. The proof that the seam holds.
4. **GridMotion in the 3D scene.** Should be a one-line change of `motion_mode`. If it is
   not, the abstraction is wrong and now is when to fix it.
5. **`EventCommand` registry + `parse_route`.** No runtime yet — the payoff is that the
   event dock's validate button starts working against real definitions.
6. **`EventRunner`** with `wait`, `say`, `move_to`, `face`, `end`. Trigger one graph from
   an `EventSource` on interact. First real cutscene.
7. **Branching:** `if`, `choice`, `goto`, plus `GameState` flags. Multiple flow ports in
   the graph editor.
8. **`EventScheduler`:** exclusive vs background, actor leases, input stack. Background NPC
   patrol running while the player walks.
9. **`change_map`** across the 2D↔3D boundary, carrying party state and spawn cell.
10. **Graph editor command UI** — a command dropdown and an args form per node, driven by
    `EventCommand.definitions()`, so authoring stops being raw JSON.

Stages 1–4 are the risky ones; 5–10 are additive.

---

## 10. Worked examples

See [docs/events/](events/):

- `greet_guard.event.json` — linear: face, say, wait, move.
- `locked_door.event.json` — branch on a flag, with a choice menu.
- `patrol_guard.event.json` — background, non-blocking, loops via `goto`.
- `cliff_jump.event.json` — free-motion map: jump, camera work, blocking vs non-blocking
  running in parallel.

---

## 11. Consequences worth accepting up front

- **Two sets of art tooling.** Real 2D means TileMap editing, 2D lights and Y-sorting;
  real 3D means meshes and an ortho rig. That is the cost of the choice in §1 and it does
  not go away.
- **`SpaceAdapter` must stay thin.** Every method added to it is a method that has to be
  implemented twice and can drift. When something can be computed above the adapter from
  `Vector3`s, compute it there.
- **Cell size mismatch.** A 2D map's cells are pixels, a 3D map's are metres. Nothing
  should compare a distance across maps; only cells travel between them.
- **Y on a flat map.** `Space2D.supports_height()` exists so this is a warning, not a
  mystery. Keep it wired into the validator too, per-map, once maps declare their space.
- **`ActorRegistry` as an autoload has a collision problem.** Game 1's battle is a separate
  scene with the field map still resident (two-games.md §3.8), so two maps' worth of
  map-unique ids can be live at once. Unresolved — see §12.7.

---

## 12. Open questions

Resolved 2026-09-08 and folded in above: **step timing** (both on commit, plus
`wait_settle` — §5), **occupancy commits** (always transactional — §1, §5), **grid
directions** (game 1 is 4-way — §1), and `visual_offset`'s home (`ActorView` — §4).

1. ~~**Terse command strings.**~~ ✅ **Kept, strictly as parse-time sugar** (2026-09-14).
   `mov n 2` expands to the long form the instant it is read, so the alias table is the only
   cost and nothing downstream — graph editor, runner, validator — ever sees the terse
   spelling. One command shape in memory; a file saved after a round trip comes back long.
   solved-questions cluster 4, question 15. The same rule now governs `if` conditions
   (question 16): typed expression in, structured condition in memory.
2. ~~**Sub-graphs.**~~ ✅ **Yes, own context, reachable through `parent_context`**
   (2026-09-14). `call` runs a whole other `.event.json`; the callee gets its own context
   rather than the caller's, but that context carries a `parent_context` key back to the
   caller's, chaining across nested calls. solved-questions cluster 3, question 12.
3. ~~**`GameState` scope.**~~ ✅ **The manifest** (2026-09-14), with bools and ints as the
   common case a condition or command signature should assume by default; strings, floats,
   arrays and dictionaries are declarable for the cases that need them. solved-questions
   cluster 3, question 14.
4. ~~**Save format.**~~ ✅ **An in-flight background runner records the node it was in**
   (2026-09-14) — a middle position, not the simpler "always restartable from the top",
   which would visibly snap a long patrol or idle loop back to its beginning on every load.
   One identifier per runner. It stops short of full capture: the command *within* that node
   re-runs from its start, and a `GridMotion` mid-step is not preserved. **Revisit once an
   `EventRunner` exists** and it is clear how coarse a node really is — the mid-step,
   mid-command version is on open-questions.md's wishlist. solved-questions cluster 7,
   question 25.
5. **`move_to` pathing.** Straight-line-then-stop, or A\* from the start? Recommend the
   former, with `path: "astar"` already in the schema so adding it later is not a format
   change. (The four-versus-eight half of this question is now settled — see §1.)
6. ~~**Camera ownership.**~~ ✅ **Follows the player by default; events borrow and return
   via `CameraRig.lock()`** (2026-09-14) — plus a second, independent borrow: a temporary
   bounds narrower than the map's own, via a `push_bounds()` / `pop_bounds()` not yet built
   (`RoomCamera2D.bounds` is the map-wide floor it returns to). solved-questions cluster 2,
   question 5.
7. ~~**Who owns "input is locked", and what scope does `ActorRegistry` have?**~~ ✅ **Both
   answered in stage A** (open-questions 27 and 28): `ModeStack` arbitrates, and the registry
   lives on `MapContext`. The round gate runs only where `ModeStack.rounds_active()`, so a
   cutscene triggered mid-round has no gate underneath it. The round watchdog that framed
   this question was cut on 2026-09-13 (open-questions 8) — nothing force-closes a round.
