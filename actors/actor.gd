@tool
class_name Actor extends Node

## The identity every system talks to. A [Node], not a body subclass - that is what
## lets the identical script sit under a [CharacterBody2D] in a town and a
## [CharacterBody3D] in a field.
##
## Registers itself with its map's [MapContext] on ready and deregisters on exit.
##
## [b]It decides nothing.[/b] An actor is an id, a facing and a handful of axis children
## - a [SpaceAdapter], a [MotionController], an [ActorView] - none of which choose where
## to go. Choosing is a [Brain]'s job, and the brain is a child added per placement
## rather than baked into the scene. That is what lets the player and every NPC on a map
## be the same prefab: what differs is which brain, if any, is attached.

enum MotionMode { INHERIT, GRID, FREE }

## Map-unique: "player", "npc_guard". Two actors answering to one id makes every
## event that names it ambiguous, so [MapContext] refuses the second.
##
## [b]Changing this in the editor renames the placement node to match[/b], through
## [method ActorNaming.rename_for] - so the scene tree and the inspector cannot disagree
## about which guard is which. The setter knows the id being replaced, which is better
## information than a pattern match: renaming away from a hand-typed id like
## [code]player[/code] still strips cleanly instead of stacking suffixes.
##
## [b]Editor only, and that is load-bearing rather than caution.[/b] Demo scripts reach
## actors by node path - [code]$Upscale/World/Map/Actors/Player/Actor[/code] - so a rename
## at run time would break every [code]@onready[/code] that names one, on the frame the id
## was set. Renaming is an authoring convenience; at run time the id changes and the node
## keeps its name.
@export var actor_id: StringName = &"":
	set(value):
		var previous := actor_id
		actor_id = value
		if previous != value:
			_sync_placement_name(previous)

## Walks through other actors, and is walked through by them.
##
## [b]Symmetric on purpose[/b] (open-questions 35): one flag, both directions. It does
## not mean "absent from [Occupancy]" - a phasing actor is still recorded on its cell, or
## interact could not find it and a through NPC would be unaddressable.

@export var through_actors: bool = false

## Ignores terrain: the painted pathing mask in 2D, the colliders and [GridMap] in 3D.
##
## [b]Nothing moves this actor vertically.[/b] No floor holds it up and no ledge drops it,
## so it is the one actor whose [code]y[/code] is an input rather than a lookup, and the
## only way to change its height is an explicit command. See open-questions 35 and 36.
@export var through_terrain: bool = false

@export var motion_mode: MotionMode = MotionMode.INHERIT

## How many directions this actor's facing quantises to. 4 for game 1, 8 for game 2.
@export_range(4, 8, 4) var facing_count: int = 4

## Ignores every facing command - [method set_facing] itself is the gate, so this holds
## regardless of who is asking: a graph's `face_direction`/`face_to`, a step's own
## implicit turn, a brain, a route. A page's `lock_facing` (event-pages.md) applies this
## to the actor GameEvent owns for as long as that page is active; a statue-like prop
## that must never visually reorient is the case it exists for.
@export var facing_locked: bool = false

## A step has been committed: the body is already on [param to], the sprite is not yet.
## [signal arrived] is the other end of the same step.
##
## The pair exists because for the length of a step the body and the sprite disagree, and
## different things mean different halves of that: a trap fires when the body lands, a
## footfall sound when the sprite does. [AreaZone] is the same distinction with a shape
## around it.
signal step_committed(from: Vector3i, to: Vector3i)

signal arrived(cell: Vector3i)
signal blocked(cell: Vector3i)
signal facing_changed(dir: Vector3i)

## A fall is about to start: the actor is standing on nothing at [param from] and will
## come to rest on [param to]. The depth is [code]from.y - to.y[/code].
##
## [b]Fired before the drop, not during it[/b], and before
## [member GridMotion.fall_delay] is waited out - which is what makes that delay a window
## to do something in. A listener gets told where the actor is, where it is going and how
## long it has, and can play the hang, swing the camera or start a sound over the top of
## the default drop.
##
## It cannot yet [i]replace[/i] the fall - the actor still drops on its own afterwards.
## Taking it over is the next step, and this signature is the one that hook will use.
signal falling(from: Vector3i, to: Vector3i)

## A background route's own paused progress, question 52: written the moment a lease
## seizes this actor away from whatever [EventRunner] was driving its route (stage-c-
## plan.md segment 7), consumed and cleared the next time that route resumes. Carried
## here rather than on the runner or [EventScheduler] because a route's runner is
## discarded the instant it is preempted - there being nothing left to ask - and
## because whatever later drives this actor's route (a fresh [GameEvent] activation, a
## reload from disk) finds its resume point by reading the actor, with no back-channel
## to whoever used to own it. [code]{"hash": String, "frames": Array}[/code] - the same
## shape [method EventRunner.to_save]'s own [code]frames[/code] key already is, plus a
## [method EventCommand.doc_hash] of the route as newly recompiled, so a changed route
## restarts from its own beginning instead of resuming into a graph that no longer
## matches (segment 5a's "restart is always a legal downgrade", at route granularity).
var suspended_route: Dictionary = {}

var _ctx: MapContext = null
var _adapter: SpaceAdapter = null
var _motion: MotionController = null
var _view: ActorView = null
var _brain: Brain = null
var _facing: Vector3i = Vector3i(0, 0, 1)

## The zones this actor is standing in, and the subset it has stepped out of but not yet
## visually left. The actor owns the list; each zone owns its own per-actor state, so
## neither is a copy of the other.
var _areas: Array[AreaZone] = []
var _areas_leaving: Array[AreaZone] = []


func _ready() -> void:
	# @tool, for the actor_id setter alone (see the export above). Nothing else here
	# should run in the editor: registering with a MapContext, reserving a cell and
	# querying zones are all run-time acts, and doing them while a scene is merely open
	# would put occupancy and the registry into a state no game session produced.
	if Engine.is_editor_hint():
		return

	_ctx = MapContext.of(self)
	_resolve_parts()

	if _ctx != null and _ctx.register(self):
		# Deferred, because the parts may not exist yet. A scene-authored actor has
		# its children before _ready, but one built in code - by hand or by
		# [ActorFactory] - gets them added after it is already in the tree, and
		# reserving a cell before the adapter exists would claim the origin.
		_claim_spawn_cell.call_deferred()
		_claim_spawn_zones.call_deferred()


## Cache the axis children. Safe to call repeatedly; the getters call it when
## something is still missing, so the order children are added in does not matter.
func _resolve_parts() -> void:
	if _adapter == null:
		_adapter = _find_child_of_type("SpaceAdapter") as SpaceAdapter
	if _motion == null:
		_motion = _find_child_of_type("MotionController") as MotionController
	if _view == null:
		_view = _find_child_of_type("ActorView") as ActorView
	if _brain == null:
		_brain = _find_child_of_type("Brain") as Brain


## A grid actor takes its spawn cell, and declares how it blocks while it is there.
##
## Free actors own no cells, so they are absent from [Occupancy] entirely - that is what
## [member through_actors] is [i]not[/i] for, and why the flag is registered here rather
## than standing in for "is in the table".
##
## A spawn is a [method Occupancy.place]: it cannot fail. Two blockers authored onto one
## tile used to be an error, and is now presumed intentional (open-questions 34) - the
## same thing a teleport or an event placement produces, and they walk off normally
## because only a voluntary step is refused.
func _claim_spawn_cell() -> void:
	if _ctx == null or effective_motion() != MotionMode.GRID:
		return
	_ctx.occupancy.set_phasing(actor_id, through_actors)
	_ctx.occupancy.place(actor_id, cell())


## The zones an actor is standing in the moment it spawns.
##
## Grid crossings are resolved at step commit, so an actor authored on top of a zone would
## not be in it until it stepped out and back again - it would start in the mud and not be
## slowed by it. Free motion needs none of this: an [Area3D] reports a body that appears
## inside it, so this is grid movement's gap alone.
##
## A further physics frame past [method _claim_spawn_cell], because a collider added in the
## same frame as the actor has not reached the physics server yet and the query would come
## back empty.
func _claim_spawn_zones() -> void:
	if effective_motion() != MotionMode.GRID or not is_inside_tree():
		return
	await get_tree().physics_frame
	if not is_inside_tree():
		return

	update_areas(AreaZone.zones_at(self, cell()))
	settle_areas()


func _exit_tree() -> void:
	# Nothing was claimed in the editor, so there is nothing to give back.
	if Engine.is_editor_hint():
		return

	clear_areas()
	if _ctx != null:
		_ctx.unregister(self)


## Keeps the placement node's name in step with [member actor_id], in the editor.
##
## Three guards, each for a different way this would otherwise misfire:
##
## - [b]Editor only.[/b] A rename at run time breaks every [code]@onready[/code] that
##   reaches an actor by path, which is how all three demo scripts find theirs.
## - [b]In the tree only.[/b] Godot applies exported properties before a node is in the
##   tree, so on scene load this fires with no parent to rename and, worse, would rename
##   the node while the scene is being read back.
## - [b]The id it is replacing, not a pattern.[/b] [method ActorNaming.rename_for] strips
##   the previous id exactly, so moving away from a hand-typed [code]player[/code] leaves
##   [code]Guard[/code] rather than [code]Guard__player__event_2[/code].
func _sync_placement_name(previous: StringName) -> void:
	if not Engine.is_editor_hint() or not is_inside_tree():
		return
	ActorNaming.rename_for(ActorNaming.placement_root(self), actor_id, previous)


# -- Identity -----------------------------------------------------------------

func context() -> MapContext:
	return _ctx


func adapter() -> SpaceAdapter:
	if _adapter == null:
		_resolve_parts()
	return _adapter


func motion() -> MotionController:
	if _motion == null:
		_resolve_parts()
	return _motion


func view() -> ActorView:
	if _view == null:
		_resolve_parts()
	return _view


## What is driving this actor, if anything. A [PlayerBrain] makes it the player, a
## [RouteBrain] makes it a patrol, and null is an actor that stands there - which is
## the difference between two placements of the same prefab.
func brain() -> Brain:
	if _brain == null:
		_resolve_parts()
	return _brain


## Is this the player? A [PlayerBrain] is the real test; the id is the fallback for a
## map where the player is placed without one (a cutscene-only scene, a test rig).
##
## [b]One definition, used everywhere[/b] - the [code]player_*[/code] signals on
## [EventBus] and [AreaComponent]'s PLAYER filter both ask here. Two copies of this test
## is how "the trap fires for the player but the music cue does not" happens.
func is_player() -> bool:
	return brain() is PlayerBrain or actor_id == &"player"


## [member motion_mode] with INHERIT resolved against the map's default.
func effective_motion() -> MotionMode:
	if motion_mode != MotionMode.INHERIT:
		return motion_mode
	if _ctx != null:
		return _ctx.default_motion
	return MotionMode.GRID


# -- Position -----------------------------------------------------------------

func world_position() -> Vector3:
	var adapt := adapter()
	return adapt.world_position() if adapt != null else Vector3.ZERO


## The cell this actor is in. A grid actor's body is always exactly on a cell - the
## sprite is the thing that lags - so this never reports a half-cell state.
func cell() -> Vector3i:
	if _ctx == null:
		return Vector3i.ZERO
	return _ctx.cell_of(world_position())


func facing() -> Vector3i:
	return _facing


## Segment E's own save/load action: enough to place this actor back where it was on a
## freshly reloaded map - cell and facing for a grid actor, world position for a free
## one (the same split [method effective_motion] already draws everywhere else).
## Deliberately not everything [GridMotion.to_save]/[method FreeMotion] might one day
## capture - a mid-command resume is [EventRunner]'s own business (segment 5b), reached
## through [EventScheduler]/[EventRunner]'s own save, not this. This is just "where was
## this actor standing".
func to_save() -> Dictionary:
	var c := cell()
	var w := world_position()
	var f := facing()
	var out := {
		"cell": [c.x, c.y, c.z],
		"world": [w.x, w.y, w.z],
		"facing": [f.x, f.y, f.z],
	}
	if not suspended_route.is_empty():
		out["suspended_route"] = suspended_route
	return out


## The inverse of [method to_save]. Placed via [method Occupancy.place], never
## [method Occupancy.commit_step] - no step happened, so there is nothing to publish
## [signal EventBus.actor_stepped] for.
func from_save(state: Dictionary) -> void:
	set_facing(_v3i_of(state.get("facing", [0, 0, 0])))
	suspended_route = (state.get("suspended_route", {}) as Dictionary).duplicate(true)

	var adapt := adapter()
	if adapt == null:
		return

	if effective_motion() == MotionMode.GRID and _ctx != null:
		var c := _v3i_of(state.get("cell", [0, 0, 0]))
		_ctx.occupancy.place(actor_id, c)
		adapt.set_world_position(_ctx.cell_centre(c))
	else:
		adapt.set_world_position(_v3_of(state.get("world", [0.0, 0.0, 0.0])))


static func _v3i_of(raw: Variant) -> Vector3i:
	if raw is Array and (raw as Array).size() >= 3:
		var a := raw as Array
		return Vector3i(int(a[0]), int(a[1]), int(a[2]))
	return Vector3i.ZERO


static func _v3_of(raw: Variant) -> Vector3:
	if raw is Array and (raw as Array).size() >= 3:
		var a := raw as Array
		return Vector3(float(a[0]), float(a[1]), float(a[2]))
	return Vector3.ZERO


func set_facing(dir: Vector3i) -> void:
	if facing_locked or dir == Vector3i.ZERO or dir == _facing:
		return
	var was := _facing
	_facing = Space.quantise(Vector3(dir), facing_count)
	if _facing == was:
		return
	var v := view()
	if v != null:
		v.set_facing(_facing)
	facing_changed.emit(_facing)
	EventBus.actor_turned.emit(actor_id, was, _facing)
	if is_player():
		EventBus.player_turned.emit(was, _facing)


## A step was refused, on [param to]. The actor has not moved and is still on its own
## cell. Both refusals - terrain and occupancy - come through here so there is one
## place a bump is announced; see [signal EventBus.actor_blocked] for why a bump is
## published but opens no round.
func report_blocked(to: Vector3i) -> void:
	var from := cell()
	blocked.emit(to)
	EventBus.actor_blocked.emit(actor_id, from, to)
	if is_player():
		EventBus.player_blocked.emit(from, to)


## A step has settled: the sprite has caught up to the body on [param at]. The other
## half of [signal step_committed] - see [signal EventBus.actor_settled].
func report_settled(at: Vector3i) -> void:
	arrived.emit(at)
	EventBus.actor_settled.emit(actor_id, at)
	if is_player():
		EventBus.player_settled.emit(at)


## A fall is about to start, ending on [param to]. See [signal falling] for what a
## listener can do with it and when it arrives.
func report_falling(to: Vector3i) -> void:
	var from := cell()
	falling.emit(from, to)
	EventBus.actor_falling.emit(actor_id, from, to)
	if is_player():
		EventBus.player_falling.emit(from, to)


func is_moving() -> bool:
	var m := motion()
	return m != null and m.is_busy()


## Physically translating, as opposed to [method is_moving]'s "busy with a command".
## The distinction only bites for free motion, where steering with the stick moves the
## actor with nothing in flight - see [method MotionController.is_travelling].
func is_travelling() -> bool:
	var m := motion()
	return m != null and m.is_travelling()


# -- Areas --------------------------------------------------------------------
#
# Membership lives here rather than on the zones because it is the actor that carries it
# around: the zones an actor is in are the ones it has to be taken out of when it leaves
# the map, and keeping the list means the exit does not need a second query - the first
# one already said which zones stopped covering it.

func areas() -> Array[AreaZone]:
	return _areas


func in_area(zone: AreaZone) -> bool:
	return _areas.has(zone)


## Enter [param zone] now. The free-motion path, called by the zone's own overlap signal,
## where there is no lagging sprite - so the actor is in it and has arrived in it at the
## same moment.
func enter_area(zone: AreaZone) -> void:
	if zone == null or _areas.has(zone):
		return
	_areas.append(zone)
	zone.mark_entered(self)
	if effective_motion() == MotionMode.FREE:
		zone.mark_arrived(self)


## Leave [param zone] now, the other half of [method enter_area].
func exit_area(zone: AreaZone) -> void:
	if zone == null or not _areas.has(zone):
		return
	_areas.erase(zone)
	_areas_leaving.erase(zone)
	zone.mark_leaving(self)
	zone.mark_exited(self)


## The zones covering the cell just committed to, from [GridMotion].
##
## Entering is reported at once; leaving is only announced here and finished in
## [method settle_areas], because the body being out is not the same as being out - the
## sprite is still inside the shape for the length of the step. Keeping the zone in the
## list until then is also what lets a modifier apply to the step that is leaving.
func update_areas(found: Array[AreaZone]) -> void:
	_drop_invalid_areas()

	for zone in found:
		if _areas.has(zone):
			# Stepped out and back in before the exit landed - a cancelled step, or a
			# teleport that finished where it started.
			if _areas_leaving.has(zone):
				_areas_leaving.erase(zone)
				zone.mark_inside(self)
		else:
			_areas.append(zone)
			zone.mark_entered(self)

	for zone in _areas:
		if not found.has(zone) and not _areas_leaving.has(zone):
			_areas_leaving.append(zone)
			zone.mark_leaving(self)


## The sprite has caught up with the body, which is the moment an exit is complete and an
## arrival has happened. Called by [GridMotion] at settle.
func settle_areas() -> void:
	_drop_invalid_areas()

	for zone in _areas_leaving:
		_areas.erase(zone)
		zone.mark_exited(self)
	_areas_leaving.clear()

	for zone in _areas:
		zone.mark_arrived(self)


## Leave everything, without the zones being told twice. For teardown: an actor that is
## freed inside a zone must not leave itself in that zone's occupant table.
func clear_areas() -> void:
	for zone in _areas:
		if is_instance_valid(zone):
			zone.mark_exited(self)
	_areas.clear()
	_areas_leaving.clear()


## A zone can be freed - a map torn down, an event removing its own trigger - while an
## actor is standing in it.
func _drop_invalid_areas() -> void:
	_areas = _areas.filter(is_instance_valid)
	_areas_leaving = _areas_leaving.filter(is_instance_valid)


# -- Internals ----------------------------------------------------------------

## Children are found by class rather than by name so a scene author can name the
## nodes anything and the factory can add them without agreeing on a convention.
func _find_child_of_type(type_name: String) -> Node:
	for child in get_children():
		if child.is_class(type_name) or _script_is(child, type_name):
			return child
	return null


func _script_is(node: Node, type_name: String) -> bool:
	var script: Script = node.get_script()
	while script != null:
		if script.get_global_name() == StringName(type_name):
			return true
		script = script.get_base_script()
	return false
