@tool
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

## The grid this map's tile art/pathing mask is actually painted at - independent of
## [member cell_size], the grid actors move and occupy. [constant Vector3.ZERO] (the
## default) reads as "same as [member cell_size]", the 1:1 ratio every map that
## predates this one has, so a map that never sets this is untouched.
##
## [b]What this buys[/b]: an actor can move and be occupied at a finer grid than the
## art was painted at, with nothing repainted. [method Passability.allows_step] only
## ever consults the painted mask at a crossed *map* cell boundary ([method
## map_cell_of]) - a step that lands inside the same map cell it started in is
## unconstrained by the mask, because the mask has nothing to say about a subdivision
## it does not know exists. Set this to the map's old [member cell_size] the moment
## [member cell_size] itself is made finer, and every existing [TileMapLayer] keeps
## meaning exactly what it always painted.
@export var map_cell_size: Vector3 = Vector3.ZERO

## A map-wide pixel nudge, applied to every actor's sprite on this map ([method
## Actor._ready] pushes it, alongside that actor's own per-footprint [method
## Actor.footprint_visual_offset] correction) - the player included, not only an
## actor with a [GameEvent] beside it. Lives here rather than per-actor because a
## mismatch between [member cell_size] and [member map_cell_size] shifts every
## actor's sprite by the same amount - a per-map fact, not a per-placement one - and
## one number here fixes every actor on the map at once instead of copying the same
## value onto each of them by hand.
@export var actor_visual_offset: Vector2 = Vector2.ZERO

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

## Inspector-only: re-snaps every grid [Actor] under this map onto its own cell's
## centre at [member cell_size]'s current value, then re-derives every
## [DebugArea2D]/[DebugArea3D] from the (possibly now-different) result and redraws
## it. Nothing does either automatically after the first [method Node._ready] - an
## authored placement is a hand-dragged pixel position, snapped to whatever grid the
## editor happened to be showing at the time (see [method Actor._ready]'s own
## spawn-time snap for the run-time half of this), and a [member cell_size] changed
## afterward leaves every existing placement sitting on the *old* grid until this is
## pressed.
@export_tool_button("Update Map Size") var update_map_size_action: Callable = update_map_size

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


## [member map_cell_size], defaulting to [member cell_size] when unset - see that
## member's own doc for why [constant Vector3.ZERO] is the sentinel rather than a real
## value to fall back to.
func effective_map_cell_size() -> Vector3:
	return map_cell_size if map_cell_size != Vector3.ZERO else cell_size


## The coarse map/tile cell [param cell] - an actor-grid cell, [method cell_of]'s own
## unit - falls within. Identity ([code]== cell[/code]) whenever [method
## effective_map_cell_size] equals [member cell_size], which is every map that has
## never set [member map_cell_size] to anything else.
##
## X/Z only, ground-plane, same scope [Actor.footprint] keeps to: [param cell]'s own Y
## passes through untouched rather than being divided by a ratio, since a height map's
## vertical cells are not this feature's concern yet.
func map_cell_of(cell: Vector3i) -> Vector3i:
	var map_size := effective_map_cell_size()
	return Vector3i(
		floori(float(cell.x) / _ratio(map_size.x, cell_size.x)),
		cell.y,
		floori(float(cell.z) / _ratio(map_size.z, cell_size.z)),
	)


func _ratio(map_axis: float, cell_axis: float) -> float:
	return map_axis / cell_axis if cell_axis > 0.0 else 1.0


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


## Called by [CameraRig] on ready. One rig per map: a [PlayerController] inside an actor
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


## Every cell at least one [GameEvent] is registered on - [DebugPassabilityView]'s own
## reader, so an event with no [Actor] in [Occupancy] (any free-motion one; a bodiless
## region trigger) still shows up somewhere, not just the walls and ladders the other
## two tables already cover.
func registered_event_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cell: Vector3i in _events_by_cell:
		out.append(cell)
	return out


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


# -- Update map size ------------------------------------------------------------

## Walks this map's own root (its parent, the town/field scene both map roots sit
## under), re-snaps every grid [Actor] found onto its own cell's centre, then
## re-syncs and redraws every [DebugArea2D]/[DebugArea3D] - see [member
## update_map_size_action]'s own doc for why either is needed at all.
func update_map_size() -> void:
	var root := get_parent()
	if root == null:
		return
	_reposition_actors_under(root)
	_refresh_debug_areas_under(root)


## [member Actor.motion_mode] resolved against this map's [member default_motion] -
## the same rule [method Actor.effective_motion] applies, duplicated rather than
## called because that method reads [member Actor._ctx], which is only ever set by
## [method Actor._ready] and this runs from the editor, where an [Actor] is never
## ready.
func _effective_motion(who: Actor) -> Actor.MotionMode:
	return who.motion_mode if who.motion_mode != Actor.MotionMode.INHERIT else default_motion


func _reposition_actors_under(node: Node) -> void:
	if node is Actor:
		_snap_actor_to_grid(node as Actor)
	for child in node.get_children():
		_reposition_actors_under(child)


## Snaps [param who]'s placement body directly, rather than through [method
## Actor.world_position]/[method Actor.adapter] - both read a [SpaceAdapter] that only
## binds to its body in [method Node._ready], which never runs for a plain (non-
## [@tool]) script while a scene is merely open for editing.
func _snap_actor_to_grid(who: Actor) -> void:
	if _effective_motion(who) != Actor.MotionMode.GRID:
		return

	var body := who.get_parent()
	if body is Node2D:
		var b2 := body as Node2D
		b2.position = Space.as_v2(cell_centre(cell_of(Space.as_v3(b2.position))))
	elif body is Node3D:
		var b3 := body as Node3D
		b3.position = cell_centre(cell_of(b3.position))


func _refresh_debug_areas_under(node: Node) -> void:
	if node is DebugArea2D or node is DebugArea3D:
		node.refresh()
	for child in node.get_children():
		_refresh_debug_areas_under(child)
