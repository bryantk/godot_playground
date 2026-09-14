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
| Concurrency | One exclusive (input-locking) runner at a time, plus any number of ambient runners. |
| Passability | Tile/geometry data **and** physics, together. |
| Grid feel | The physics body snaps to the destination cell immediately; the visual tweens to catch up. |
| Occupancy writes | Always through `Occupancy.commit(changes)`, never by mutating the dictionary in place — even for a single actor's step. |
| Step timing | Occupancy commit, the step pulse and cell triggers all fire at **step commit**. `wait_settle` covers the land-on-it case. §5 |
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
  │  Brain (Player | Route | …) ─ Actor (Node)                   │
  │                              ─ MotionController (Grid | Free)│
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

An actor decides nothing. It is an id, a facing and its axis children; where it goes is a
`Brain`'s call.

### `Brain` — the one thing that decides

```gdscript
class_name Brain extends Node

var intent := InputIntent.new()

func _think(delta: float) -> void     # subclass fills intent
func _apply(delta: float) -> void     # base hands it to Grid | Free motion
```

**Player and NPC are the same scene.** One actor prefab per game is instanced for every
actor on the map; what makes one of them the player is a `PlayerBrain` child on its
`Actor`, and what makes another a patrol is a `RouteBrain`. An actor with no brain stands
there, which is exactly what scenery wants. The alternative — a `player_x.tscn` beside an
`npc_x.tscn` — duplicated the sprite, the view wiring and the collision shape twice per
game and made every fix to an actor a fix in two files.

Brains speak one currency, `InputIntent`, and the base class is what turns an intent into
motion. That split matters: filling the intent varies by *who is asking* (a keyboard, a
command list, an event graph), applying it varies by *which controller the actor has*
(`GridMotion` takes a committed step, `FreeMotion` continuous steering), and neither side
needs to know the other's answer.

| Brain | Fills the intent from | Status |
| --- | --- | --- |
| `PlayerBrain` | the keyboard, through `InputProfile` and the map's camera yaw | stage A, was `InputDriver` |
| `RouteBrain` | a fixed list of `move_to` / `step` / `face` / `wait` commands, looping | stage A |
| event graphs | a runner driving the actor through a lease | stage C, §7 |

`RouteBrain`'s command list is the event format's — the same names and argument keys
event-pages.md specifies — so stage C's runner executes what a route already holds rather
than a format anyone has to migrate. What a route deliberately has not got is branching
or any way to notice the player: an actor that should react wants an event graph, and
`RouteBrain` growing conditions would be that system built twice.

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
   actor (§6.1). Synchronous, so a zone that changes the actor's speed has changed it
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
one moment a step happens, and the occupancy commit, the step pulse
(two-games.md §3.1) and any `EnterCell` trigger on the destination all fire there, in
that order. Monsters and traps therefore observe identical world state, and there is exactly
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

### 6.1 Areas — entered and exited

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
  "outputs": [{"type": "flow", "target": "n3"}]
}
```

- `command` — a name in the `EventCommand` registry.
- `args` — the command's parameters, shape defined by its registry entry.
- `blocking` — optional; defaults to the command's own default.
- `key` — optional, non-blocking commands only: names the completion key so a later
  `wait_for` in the same graph can join it. Without one the command is fire-and-forget.
- `flows` — optional editor hint listing the flow port labels a branch command produced,
  so a graph reopens with its ports named. The runtime trusts the command definition, not
  this field.
- `outputs` — unchanged. Flow ports are successors. A linear command has one; a branch has
  one per branch, in the order the command declares. `"target": ""` ends that path.

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
always writes the long form. *Decision needed — see §12.*

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
- **Ambient runners** — any number, no input lock. NPC patrol routines, fountains,
  weather.
- **Actor leases** — a runner takes a lease on each actor it drives. A second runner
  asking for a leased actor waits or is refused, which is what prevents a patrol routine
  and a cutscene fighting over the same guard's position.
- Ambient runners are suspended while the exclusive slot is occupied (configurable per
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
>   destination cell centre is how `AreaZone` membership is resolved at commit (§6.1); it
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
signal actor_stepped(actor_id: StringName, from: Vector3i, to: Vector3i)
signal event_started(runner_id: String, exclusive: bool)
signal event_finished(runner_id: String)
signal map_changing(from_id: StringName, to_id: StringName)
signal input_lock_changed(locked: bool)

func wait_for_command(key: String) -> void   # same shape as the existing wait_for
```

`dialogue_finished` stays as is; `say` already returns a key, so the `say` command needs
no adapter.

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
    area_zone.gd           AreaZone — entered/arrived/leaving/exited (§6.1)
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
  brain/
    brain.gd               Brain base — intent in, motion out
    player_brain.gd        PlayerBrain — the keyboard (was core/input_driver.gd)
    route_brain.gd         RouteBrain — a looping command list
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
8. **`EventScheduler`:** exclusive vs ambient, actor leases, input stack. Ambient NPC
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
- `patrol_guard.event.json` — ambient, non-blocking, loops via `goto`.
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

1. **Terse command strings.** Keep `{"command": "mov n 2"}` as an accepted sugar form
   (§7.2), or drop it now that the graph editor is the primary authoring surface? Keeping
   it means an alias table and a second parse path to maintain.
2. **Sub-graphs.** Should `call` run a whole other `.event.json` (common cutscene
   fragments, shared shop logic), and if so, does the callee share the caller's context or
   get its own?
3. **`GameState` scope.** Flags and integer variables only, or typed variables with a
   declared manifest so the graph editor can offer a dropdown instead of a text field?
4. **Save format.** Does a save capture in-flight ambient runners, or are ambient events
   always restartable from the top? The second is much simpler and almost always enough.
5. **`move_to` pathing.** Straight-line-then-stop, or A\* from the start? Recommend the
   former, with `path: "astar"` already in the schema so adding it later is not a format
   change. (The four-versus-eight half of this question is now settled — see §1.)
6. **Camera ownership.** Does the camera follow the player by default with events
   borrowing it, or is it always driven by whatever holds the exclusive slot?
7. ~~**Who owns "input is locked", and what scope does `ActorRegistry` have?**~~ ✅ **Both
   answered in stage A** (open-questions 27 and 28): `ModeStack` arbitrates, and the registry
   lives on `MapContext`. The round gate runs only where `ModeStack.rounds_active()`, so a
   cutscene triggered mid-round has no gate underneath it. The round watchdog that framed
   this question was cut on 2026-09-13 (open-questions 8) — nothing force-closes a round.
