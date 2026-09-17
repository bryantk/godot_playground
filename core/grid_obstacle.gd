class_name GridObstacle extends Node3D

## A static or rigid, non-actor obstacle that claims its cells in the map's [Occupancy]
## table.
##
## [method Passability.can_enter] only falls back to physics when [method Terrain.governs]
## is false - on a height map the floor [GridMap] already answers for physics, so a bare
## [StaticBody3D] or [RigidBody3D] prop is invisible to grid movement (its own doc names
## exactly this case: "a pushable crate... has to be an actor in Occupancy instead of a
## bare body"). This registers a prop as that occupant, the same way
## [method Actor._claim_spawn_cell] does for a mover.
##
## [b]The footprint is read from collision shapes, not just the origin cell.[/b] A prop
## bigger than one cell, or one straddling a cell boundary, occupies every cell its
## [CollisionShape3D] descendants overlap - see [method _footprint_cells]. Only
## [BoxShape3D] is measured precisely; anything else falls back to its own origin, which
## is exactly right for the props this was built for and a deliberate simplification
## rather than a general collision-to-cells solver.
##
## [b]A [RigidBody3D] rechecks while it is awake[/b], because physics can move it after
## spawn - a static prop's footprint never changes once placed, so it is computed once.
## A rigid body that has settled is [i]asleep[/i] (Godot's own physics stops simulating
## it), so this listens for [signal RigidBody3D.sleeping_state_changed] rather than
## polling forever: physics processing turns on only while it is actually moving, and one
## last check runs the moment it comes to rest to catch its final cells. Read dynamically
## ([method Object.is_class], [method Object.get], a string-named [method Object.connect])
## because the script's declared base is [Node3D] - GDScript's static checker refuses
## [code]self is RigidBody3D[/code] here, since [RigidBody3D] is not an ancestor or
## descendant of [Node3D] in the script's own declared type.
##
## [b]Passable obstacles still occupy their cells[/b] - present to [method Occupancy.actors_at]
## - they just do not block a step, mirroring [member Actor.through_actors]. That is the
## "through" option: a bush an actor can walk into but a monster's line of sight could still
## find, rather than the prop simply not registering at all.

@export var through: bool = false

var _ctx: MapContext = null
var _id: StringName = &""
var _last_cells: Array[Vector3i] = []


func _ready() -> void:
	_ctx = MapContext.of(self)
	if _ctx == null:
		return
	_id = StringName("obstacle:%d" % get_instance_id())
	_ctx.occupancy.set_phasing(_id, through)
	_claim_footprint()
	set_physics_process(false)


func _exit_tree() -> void:
	if _ctx != null:
		_ctx.occupancy.release_actor(_id)


func _claim_footprint() -> void:
	var cells := _footprint_cells()
	if cells == _last_cells:
		return
	_last_cells = cells
	_ctx.occupancy.place_many(_id, cells)


## Every cell this prop's colliders overlap, in world space.
func _footprint_cells() -> Array[Vector3i]:
	var shapes: Array[CollisionShape3D] = []
	_find_collision_shapes(self, shapes)
	if shapes.is_empty():
		return [_ctx.cell_of(global_position)]

	var world_aabb := AABB(shapes[0].global_transform.origin, Vector3.ZERO)
	for cs: CollisionShape3D in shapes:
		for corner: Vector3 in _box_corners(cs):
			world_aabb = world_aabb.expand(corner)

	# A hair inside the far edge, so a face sitting exactly on a cell boundary does not
	# pull in one extra, empty-overlap row of cells beyond it.
	var epsilon := Vector3.ONE * 0.001
	var lo := _ctx.cell_of(world_aabb.position + epsilon)
	var hi := _ctx.cell_of(world_aabb.position + world_aabb.size - epsilon)

	var cells: Array[Vector3i] = []
	for x in range(lo.x, hi.x + 1):
		for y in range(lo.y, hi.y + 1):
			for z in range(lo.z, hi.z + 1):
				cells.append(Vector3i(x, y, z))
	return cells


func _find_collision_shapes(node: Node, out: Array[CollisionShape3D]) -> void:
	for child in node.get_children():
		if child is CollisionShape3D and (child as CollisionShape3D).shape != null:
			out.append(child)
		_find_collision_shapes(child, out)


## The eight world-space corners of [param cs]'s shape. Exact for [BoxShape3D]; anything
## else is treated as a point at the shape's own origin, which just means a footprint no
## bigger than one cell rather than a wrong one.
func _box_corners(cs: CollisionShape3D) -> Array[Vector3]:
	var half := Vector3.ZERO
	if cs.shape is BoxShape3D:
		half = (cs.shape as BoxShape3D).size * 0.5

	var corners: Array[Vector3] = []
	for sx in [-1.0, 1.0]:
		for sy in [-1.0, 1.0]:
			for sz in [-1.0, 1.0]:
				corners.append(cs.global_transform * Vector3(sx * half.x, sy * half.y, sz * half.z))
	return corners
