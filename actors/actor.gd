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
@export var actor_id: StringName = &""

## Does this actor take an occupancy slot? Decorations and bodiless region triggers
## do not.
@export var solid: bool = true

@export var motion_mode: MotionMode = MotionMode.INHERIT

## How many directions this actor's facing quantises to. 4 for game 1, 8 for game 2.
@export_range(4, 8, 4) var facing_count: int = 4

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


## A solid grid actor claims the cell it spawned in, so two NPCs authored onto the
## same tile fail loudly at load rather than at first step.
func _claim_spawn_cell() -> void:
	if _ctx == null or not solid or effective_motion() != MotionMode.GRID:
		return
	if not _ctx.occupancy.reserve(actor_id, cell()):
		push_error("Actor '%s' spawned on an occupied cell %s." % [actor_id, cell()])


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
	clear_areas()
	if _ctx != null:
		_ctx.unregister(self)


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


func set_facing(dir: Vector3i) -> void:
	if dir == Vector3i.ZERO or dir == _facing:
		return
	_facing = Space.quantise(Vector3(dir), facing_count)
	var v := view()
	if v != null:
		v.set_facing(_facing)
	facing_changed.emit(_facing)


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
