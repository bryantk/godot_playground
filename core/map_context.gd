class_name MapContext extends Node

## Everything that is true of one loaded map. Both map roots carry one of these as a
## child, so map-level code is shared between a [Node2D] town and a [Node3D] field.
##
## It owns the [Occupancy] table and the actor registry. The registry lives here
## rather than in an autoload because game 1's battle keeps the field map resident
## while a battle scene runs, so two maps' worth of map-unique ids can be live at
## once - a global table would collide. Scoping it here means ids stay map-unique with
## no collision, two maps can be resident, and teardown disposes both tables for free.

signal actor_registered(actor_id: StringName)
signal actor_unregistered(actor_id: StringName)

@export var map_id: StringName = &"map"

## Pixels for a 2D map, metres for a 3D one. Nothing compares a distance across maps -
## only cells travel between them - so the two never need to agree.
@export var cell_size: Vector3 = Vector3.ONE

## The motion this map's actors use unless the actor overrides it. This takes
## precedence over [member GameProfile.motion_script], which is what keeps
## "grid movement in a 3D town" possible.
@export var default_motion: Actor.MotionMode = Actor.MotionMode.GRID

## Which space this map is. Exported so a headless test can declare it without
## building a real scene.
@export var supports_height: bool = false

## The [TileMapLayer] or [GridMap] carrying passability data, relative to this node.
## Empty means the map has no data layer, which reads as open ground - that is what
## makes a bare test scene usable.
@export var collision_node: NodePath = NodePath()

## The [GridMap] of walkable cells, for a 3D map with stairs, ramps or ladders. Its
## cells are actor cells one for one: a cell at grid Y means ground whose surface is
## exactly that Y, which is the same thing [method cell_centre] returns.
##
## [b]Distinct from [member collision_node], which is the walls.[/b] One says where you
## may not go, the other says where the ground is, and a map can have either, both or
## neither. Empty - which is every 2D map and every flat 3D one - means [Terrain] does
## not govern and a step keeps its own Y, exactly as it did before height existed.
##
## Only meaningful with [member supports_height]. See [Terrain].
@export var floor_node: NodePath = NodePath()

## The [GridMap] of ladder cells, if the map has any.
##
## [b]Its own layer because a ladder is an overlay, not a kind of ground.[/b] A GridMap
## cell holds exactly one item, so a ladder sharing [member floor_node] would evict
## whatever was there - the floor at its foot, most obviously, leaving the player
## standing on a rung where a tile should be. On its own layer a cell can be floor
## [i]and[/i] ladder, or wall and ladder, and the ladder is drawn over both.
##
## Climbing rules key off this layer; standing, walking and falling still key off
## [member floor_node]. See [method Terrain.resolve_step].
@export var ladder_node: NodePath = NodePath()

## How far a grid actor may fall from one step, in cells. **0 makes every ledge a wall**
## and a large value permits anything.
##
## The default is deliberately small. A map that has not thought about falling should
## not silently let the player walk off a four-storey drop, and one cell is the height
## a person steps down without it reading as a fall at all. Deeper drops are a design
## choice a map makes on purpose.
##
## Releasing a ladder ignores this entirely (open-questions 38) - the limit is there to
## stop accidents, and letting go is not one.
@export var max_fall_cells: int = 1

var occupancy := Occupancy.new()

## The rig looking at this map, registered by [CameraRig] on ready.
var _camera_rig: CameraRig = null

## Membership in [code]&"map_context"[/code] is how global, scene-independent systems -
## [DebugPassabilityView] today - find whichever map is currently loaded without a
## [NodePath] into it. See [method of] for the other lookup, which walks up from a node
## already inside the map instead.
func _enter_tree() -> void:
	add_to_group(&"map_context")


func _exit_tree() -> void:
	remove_from_group(&"map_context")

## actor_id -> Actor
var _actors: Dictionary[StringName, Actor] = {}

## cell -> Array[Node] of GameEvents sitting there, for the interact lookup. Filled
## by GameEvent in stage C; the table exists now so nothing has to be retrofitted.
var _events_by_cell: Dictionary[Vector3i, Array] = {}


# -- Cells and world ----------------------------------------------------------

## The cell containing [param world]. Floor division, so cell boundaries land where
## you would draw them and negative coordinates do not fold toward zero.
func cell_of(world: Vector3) -> Vector3i:
	return Vector3i(
		floori(world.x / cell_size.x),
		floori(world.y / cell_size.y) if cell_size.y > 0.0 else 0,
		floori(world.z / cell_size.z),
	)


## The centre of [param cell] in world units - where a grid actor's body sits.
func cell_centre(cell: Vector3i) -> Vector3:
	return Vector3(
		(float(cell.x) + 0.5) * cell_size.x,
		float(cell.y) * cell_size.y,
		(float(cell.z) + 0.5) * cell_size.z,
	)


## [param cell] as a world offset, for turning a cell delta into a motion vector.
func cell_vector(cell: Vector3i) -> Vector3:
	return Vector3(cell) * cell_size


# -- Actor registry -----------------------------------------------------------

## Returns false if [param actor_id] is already taken, which is a real authoring
## mistake rather than something to paper over - two actors answering to one id makes
## every event that names it ambiguous.
func register(who: Actor) -> bool:
	var id: StringName = who.actor_id
	if id == &"":
		push_error("MapContext(%s): actor with no actor_id cannot register." % map_id)
		return false
	if _actors.has(id) and _actors[id] != who:
		push_error("MapContext(%s): duplicate actor_id '%s'." % [map_id, id])
		return false

	_actors[id] = who
	actor_registered.emit(id)
	return true


func unregister(who: Actor) -> void:
	var id: StringName = who.actor_id
	if not _actors.has(id) or _actors[id] != who:
		return
	_actors.erase(id)
	occupancy.release_actor(id)
	actor_unregistered.emit(id)


## Called by [CameraRig] on ready. One rig per map: a [PlayerBrain] inside an actor
## prefab needs the yaw that resolves "up on the stick", and the one thing a shared
## prefab must not carry is a [NodePath] up out of itself into whichever map instanced
## it. Asking the map is how it finds the rig instead.
func register_camera(rig: CameraRig) -> void:
	if _camera_rig != null and _camera_rig != rig and is_instance_valid(_camera_rig):
		push_warning("MapContext(%s): a second camera rig registered; keeping the first."
			% map_id)
		return
	_camera_rig = rig


func camera_rig() -> CameraRig:
	return _camera_rig if is_instance_valid(_camera_rig) else null


func actor(actor_id: StringName) -> Actor:
	return _actors.get(actor_id, null)


func has_actor(actor_id: StringName) -> bool:
	return _actors.has(actor_id)


func actor_ids() -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _actors:
		out.append(id)
	return out


## Every registered actor, in registration order.
##
## Registration order is the stable order the step pulse resolves in. Iterating
## whatever order signal connections happen to fire in would make two monsters
## contending for the cell the player just vacated resolve differently between runs,
## which is miserable to debug and worse to speedrun.
func actors() -> Array[Actor]:
	var out: Array[Actor] = []
	for id: StringName in _actors:
		out.append(_actors[id])
	return out


# -- Events by cell -----------------------------------------------------------

## What sits at [param cell]. The interact lookup is
## [code]events_at(player.cell() + player.facing())[/code] - a dictionary lookup,
## identical in both spaces, with no raycast or Area involved.
func events_at(cell: Vector3i) -> Array:
	return _events_by_cell.get(cell, [])


func add_event_at(cell: Vector3i, event: Node) -> void:
	if not _events_by_cell.has(cell):
		_events_by_cell[cell] = []
	if not _events_by_cell[cell].has(event):
		_events_by_cell[cell].append(event)


func remove_event_at(cell: Vector3i, event: Node) -> void:
	if not _events_by_cell.has(cell):
		return
	_events_by_cell[cell].erase(event)
	if _events_by_cell[cell].is_empty():
		_events_by_cell.erase(cell)


# -- Lookup -------------------------------------------------------------------

## The [MapContext] governing [param node], found by walking up to the map root. Every
## system that needs map state gets it this way, so nothing needs it passed in.
static func of(node: Node) -> MapContext:
	var n := node
	while n != null:
		for child in n.get_children():
			if child is MapContext:
				return child
		n = n.get_parent()
	return null
