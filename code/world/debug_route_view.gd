extends Node

## Draws the path each actor's last [code]move_route[/code] computed ([member
## Actor.move_route]), from the cell the actor is on now to the end of it, for whichever
## map is loaded - the debug menu's "Route" category (key 7). The part already walked
## drops away as the actor advances, so the line is what is left to do.
##
## Autoloaded as [code]DebugRouteView[/code], the same way [DebugPassabilityView] is: one
## instance for the whole game that finds the current map by group, rebuilds its drawing
## node when the map changes, and does nothing with no map or with the category off. 2D
## maps draw through a [Node2D]'s [signal CanvasItem.draw]; 3D ones through an
## [ImmediateMesh] of unshaded lines.
##
## Only the stored path is drawn here - it is exact. The editor's route overlay
## (addons/graph_editor/route_overlay.gd) is what traces a graph's movement commands,
## with its random/unknown markers, for the selected placement.

const COLOR := Color(0.3, 1.0, 0.6, 0.95)
const ARROW_CELLS := 0.3

var _ctx: MapContext = null
var _root: Node = null
var _is_3d := false

## What [method _on_draw_2d] draws - recomputed every physics frame and cached, since
## 2D drawing only happens inside that callback. Each entry is the world points of one
## actor's remaining route.
var _lines: Array[PackedVector3Array] = []

var _mesh: ImmediateMesh = null


func _physics_process(_delta: float) -> void:
	var found := get_tree().get_first_node_in_group(&"map_context") as MapContext
	if found != _ctx:
		_teardown()
		_ctx = found
		if _ctx != null:
			_setup()

	if _ctx == null:
		return

	_root.visible = DebugFlags.is_category_visible(&"route")
	if not _root.visible:
		return

	_lines = route_lines(_ctx)
	if _is_3d:
		_rebuild_3d()
	else:
		(_root as Node2D).queue_redraw()


## Every actor's remaining stored route as world points, cell centres from the actor's
## own cell onward. Empty entries (no route, or already at its end) are left out. Public
## and map-only so a test can ask it directly.
static func route_lines(ctx: MapContext) -> Array[PackedVector3Array]:
	var out: Array[PackedVector3Array] = []
	for id in ctx.actor_ids():
		var actor := ctx.actor(id)
		if actor == null or actor.move_route.is_empty():
			continue

		var cells: Array[Vector3i] = []
		for step: Variant in actor.move_route:
			var cell: Variant = ((step as Dictionary).get("args", {}) as Dictionary).get("cell")
			if cell is Array and (cell as Array).size() >= 3:
				cells.append(Vector3i(int(cell[0]), int(cell[1]), int(cell[2])))

		# Drop whatever the actor has already walked: from its current cell, if that is
		# on the route, else the whole thing.
		var at := cells.find(actor.cell())
		var remaining := cells.slice(at + 1) if at >= 0 else cells
		if remaining.is_empty():
			continue

		var points := PackedVector3Array([ctx.cell_centre(actor.cell())])
		for cell in remaining:
			points.append(ctx.cell_centre(cell))
		out.append(points)
	return out


func _setup() -> void:
	_is_3d = _ctx.get_parent() is Node3D
	if _is_3d:
		var instance := MeshInstance3D.new()
		_mesh = ImmediateMesh.new()
		instance.mesh = _mesh
		var material := StandardMaterial3D.new()
		material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		material.albedo_color = COLOR
		material.no_depth_test = true
		instance.material_override = material
		_root = instance
	else:
		_root = Node2D.new()
		(_root as Node2D).draw.connect(_on_draw_2d)

	_root.name = "DebugRouteLines"
	_ctx.get_parent().add_child(_root)


func _teardown() -> void:
	if _root != null and is_instance_valid(_root):
		_root.queue_free()
	_root = null
	_mesh = null
	_lines.clear()


func _on_draw_2d() -> void:
	var draw := _root as Node2D
	for points in _lines:
		var flat := PackedVector2Array()
		for p in points:
			flat.append(Space.as_v2(p))
		draw.draw_polyline(flat, COLOR, 2.0, true)
		draw.draw_circle(flat[flat.size() - 1], maxf(2.0, _ctx.cell_size.x * 0.15), COLOR)


func _rebuild_3d() -> void:
	_mesh.clear_surfaces()
	if _lines.is_empty():
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_LINES)
	for points in _lines:
		for i in range(points.size() - 1):
			_mesh.surface_add_vertex(points[i] + Vector3(0.0, 0.1, 0.0))
			_mesh.surface_add_vertex(points[i + 1] + Vector3(0.0, 0.1, 0.0))
	_mesh.surface_end()
