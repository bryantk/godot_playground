extends Node

## One wireframe box per cell a step is refused on right now, for whichever grid-movement
## map is currently loaded, plus a second colour over every ladder cell. Walls, prop
## footprints and standing actors already answer to the same two systems - [Passability]'s
## terrain data and [Occupancy] - so one overlay reads both instead of needing a separate
## view per kind of blocker; ladders are a third, independent layer
## ([member MapContext.ladder_node]).
##
## Autoloaded as [code]DebugPassabilityView[/code] - one instance for the whole game
## rather than one per map scene, since every demo wants the same overlay and none of
## them should have to remember to add it. It finds the current map itself, by group
## membership ([method MapContext._enter_tree]) rather than a [NodePath] handed to it,
## which is what lets the same instance follow whichever map is loaded.
##
## [b]No map, or one with no collision layer to speak of, means doing nothing[/b] - not
## freeing itself the way a scene-local instance used to. A global can't queue_free over
## a demo it doesn't like; it just skips drawing until a map with something to show up
## shows up, exactly as it does while [method DebugFlags.show_debug_view] is off.
##
## [b]Not gated on [member MapContext.default_motion] any more.[/b] It used to draw only
## for a GRID-default map, back when a free-motion demo's blockers were assumed
## uninteresting - but a free player still walks into the same [member
## MapContext.collision_node] walls, a page can still put a GRID-motion actor on a
## free-default map (the iso free demo's own Wanderer), and [Occupancy] still tracks
## whichever of those does claim cells. What actually decides whether there is anything
## worth drawing is [member MapContext.collision_node] being set, not which motion the
## map defaults to.
##
## [b]"Impassable" means fully walled, not one-sided.[/b] [method Passability.directions]
## can refuse only one side of a cell - a one-way ledge, a door painted shut from the
## north - and this overlay does not attempt to show that nuance; it flags a 2D cell only
## when every side is closed. A 3D wall cell has no such nuance ([GridMap] presence is
## binary), so it always shows.
##
## [b]Ladders are 3D-only.[/b] [member MapContext.ladder_node] is only ever a [GridMap]
## (event-pages.md's height rules); a 2D map has no such layer, so the 2D half of this
## view draws impassable cells alone.

const WALL_COLOR := Color(0.95, 0.2, 0.2, 0.9)
const LADDER_COLOR := Color(0.25, 0.95, 0.35, 0.9)

## The map this instance is currently drawing for, or null between maps. Compared
## against every physics frame so a map switch tears down the old visuals and builds
## fresh ones instead of drawing last map's boxes in this map's space.
var _ctx: MapContext = null
var _root: Node = null
var _is_3d := false

## 2D only: what the last rebuild found, read back by [method _on_draw_2d] - drawing only
## happens inside that callback, so the cells have to be cached rather than recomputed.
var _cells_2d: Array[Vector3i] = []

## 3D only: one wireframe box shape, reused by every instance regardless of colour - a
## box is just a transform and a material against a shared line mesh. Rebuilt whenever
## the map changes, since [member MapContext.cell_size] can differ between maps.
var _wire_mesh: ArrayMesh
var _wall_material: StandardMaterial3D
var _ladder_material: StandardMaterial3D


func _physics_process(_delta: float) -> void:
	var ctx := _current_context()
	if ctx != _ctx:
		_teardown()
		_ctx = ctx
		if _ctx != null:
			_setup()

	if _ctx == null:
		return

	_root.visible = DebugFlags.show_debug_view()
	if not _root.visible:
		return

	if _is_3d:
		_rebuild_3d()
	else:
		_cells_2d = _blocked_cells()
		(_root as Node2D).queue_redraw()


## The map this overlay should be drawing for right now, or null when there isn't one
## worth drawing - no map loaded (the demo launcher), or one with no
## [member MapContext.collision_node] to read blocked cells off at all.
##
## A battle scene that keeps its field map resident behind it (map_context.gd's own
## doc) would leave two [MapContext]s in the group at once; this does not try to pick
## the "right" one between them; there is no battle scene yet for that to matter.
func _current_context() -> MapContext:
	var found := get_tree().get_first_node_in_group(&"map_context")
	if found == null or (found as MapContext).collision_node.is_empty():
		return null
	return found as MapContext


func _setup() -> void:
	_is_3d = _ctx.get_node_or_null(_ctx.collision_node) is GridMap

	if _is_3d:
		_wire_mesh = _build_wire_box(Vector3(_ctx.cell_size.x, 1.0, _ctx.cell_size.z))
		_wall_material = _unshaded_material(WALL_COLOR)
		_ladder_material = _unshaded_material(LADDER_COLOR)
		_root = Node3D.new()
	else:
		_root = Node2D.new()
		(_root as Node2D).draw.connect(_on_draw_2d)

	_root.name = "DebugPassabilityBoxes"
	_ctx.get_parent().add_child(_root)


func _teardown() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_cells_2d.clear()


func _rebuild_3d() -> void:
	for child in _root.get_children():
		child.queue_free()

	for cell: Vector3i in _blocked_cells():
		_root.add_child(_wire_box_instance(cell, _wall_material))
	for cell: Vector3i in _ladder_cells():
		_root.add_child(_wire_box_instance(cell, _ladder_material))


func _wire_box_instance(cell: Vector3i, material: StandardMaterial3D) -> MeshInstance3D:
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _wire_mesh
	mesh_instance.material_override = material
	mesh_instance.position = _ctx.cell_centre(cell) + Vector3(0.0, 0.5, 0.0)
	return mesh_instance


func _on_draw_2d() -> void:
	var size := Vector2(_ctx.cell_size.x, _ctx.cell_size.z)
	for cell: Vector3i in _cells_2d:
		var centre := Space.as_v2(_ctx.cell_centre(cell))
		(_root as Node2D).draw_rect(Rect2(centre - size * 0.5, size), WALL_COLOR, false)


## The union of every terrain-walled cell and every cell [Occupancy] currently blocks -
## a prop's footprint, an actor standing there - deduplicated, since a monster parked on
## a painted wall tile would otherwise draw twice.
func _blocked_cells() -> Array[Vector3i]:
	var seen: Dictionary[Vector3i, bool] = {}

	var layer := _ctx.get_node_or_null(_ctx.collision_node)
	if layer is GridMap:
		for cell: Vector3i in (layer as GridMap).get_used_cells():
			seen[cell] = true
	elif layer is TileMapLayer:
		var rect: Rect2i = (layer as TileMapLayer).get_used_rect()
		for x in range(rect.position.x, rect.end.x):
			for y in range(rect.position.y, rect.end.y):
				var cell := Vector3i(x, 0, y)
				if Passability.directions(_ctx, cell) == 0:
					seen[cell] = true

	for cell: Vector3i in _ctx.occupancy.blocking_cells():
		seen[cell] = true

	var out: Array[Vector3i] = []
	for cell: Vector3i in seen:
		out.append(cell)
	return out


## Every cell [member MapContext.ladder_node] carries - 3D only, see the class doc.
func _ladder_cells() -> Array[Vector3i]:
	var layer := _ctx.get_node_or_null(_ctx.ladder_node)
	var out: Array[Vector3i] = []
	if layer is GridMap:
		for cell: Vector3i in (layer as GridMap).get_used_cells():
			out.append(cell)
	return out


## The 12 edges of a [param size] box, centred on the origin, as line-primitive geometry -
## a wireframe [BoxMesh] is not a thing Godot 4 ships, so this is the shortest path to one.
func _build_wire_box(size: Vector3) -> ArrayMesh:
	var h := size * 0.5
	var corners: Array[Vector3] = [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var edges: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]

	var points := PackedVector3Array()
	for edge in edges:
		points.append(corners[edge.x])
		points.append(corners[edge.y])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh


func _unshaded_material(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat
