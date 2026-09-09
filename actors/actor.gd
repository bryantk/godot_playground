class_name Actor extends Node

## The identity every system talks to. A [Node], not a body subclass - that is what
## lets the identical script sit under a [CharacterBody2D] in a town and a
## [CharacterBody3D] in a field.
##
## Registers itself with its map's [MapContext] on ready and deregisters on exit.

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

signal arrived(cell: Vector3i)
signal blocked(cell: Vector3i)
signal facing_changed(dir: Vector3i)

var _ctx: MapContext = null
var _adapter: SpaceAdapter = null
var _motion: MotionController = null
var _view: ActorView = null
var _facing: Vector3i = Vector3i(0, 0, 1)


func _ready() -> void:
	_ctx = MapContext.of(self)
	_resolve_parts()

	if _ctx != null and _ctx.register(self):
		# Deferred, because the parts may not exist yet. A scene-authored actor has
		# its children before _ready, but one built in code - by hand or by
		# [ActorFactory] - gets them added after it is already in the tree, and
		# reserving a cell before the adapter exists would claim the origin.
		_claim_spawn_cell.call_deferred()


## Cache the axis children. Safe to call repeatedly; the getters call it when
## something is still missing, so the order children are added in does not matter.
func _resolve_parts() -> void:
	if _adapter == null:
		_adapter = _find_child_of_type("SpaceAdapter") as SpaceAdapter
	if _motion == null:
		_motion = _find_child_of_type("MotionController") as MotionController
	if _view == null:
		_view = _find_child_of_type("ActorView") as ActorView


## A solid grid actor claims the cell it spawned in, so two NPCs authored onto the
## same tile fail loudly at load rather than at first step.
func _claim_spawn_cell() -> void:
	if _ctx == null or not solid or effective_motion() != MotionMode.GRID:
		return
	if not _ctx.occupancy.reserve(actor_id, cell()):
		push_error("Actor '%s' spawned on an occupied cell %s." % [actor_id, cell()])


func _exit_tree() -> void:
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
