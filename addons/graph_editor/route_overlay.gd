@tool
extends RefCounted

## Draws where the selected actor's or event's first page would walk it, in the 2D or 3D
## editor viewport - the movement commands of its [code]route[/code] (patrol, cyan) and
## its [code]graph[/code] (orange) traced by [RouteTracer], from the placement's own cell.
## Called from the plugin's force-draw-over hooks next to [SelectionHighlight], and like
## it only ever draws what is selected in the Scene dock, so a busy map is not covered in
## lines.
##
## [b]One path, marked where it cannot know[/b] - see [RouteTracer]. A random or wander
## step is drawn as a large X with a compass tick on each side, an unknowable step
## (towards/away the player, route_seek) as "?", and a loop is closed with a small ring.
## Solid lines are walks; dashed ones are a jump or a [code]move_route[/code] (what lies
## between is decided at run time).

const ROUTE_COLOR := Color(0.3, 0.9, 1.0, 0.95)
const GRAPH_COLOR := Color(1.0, 0.55, 0.15, 0.95)
const LINE_WIDTH := 2.0
const MARK_RADIUS := 11.0
const ARROW_SIZE := 9.0


static func draw_2d(overlay: Control) -> void:
	var viewport := EditorInterface.get_editor_viewport_2d()
	if viewport == null:
		return
	var xform := viewport.global_canvas_transform

	for node in EditorInterface.get_selection().get_selected_nodes():
		var anchor := _anchor_of(node)
		if not (anchor is Node2D):
			continue
		var map := MapContext.of(anchor)
		if map == null:
			continue
		var project := func(cell: Vector3i) -> Variant:
			return xform * Space.as_v2(map.cell_centre(cell))
		var start := map.cell_of(Space.as_v3((anchor as Node2D).global_position))
		_draw_placement(overlay, anchor, start, project)


static func draw_3d(overlay: Control) -> void:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		return

	for node in EditorInterface.get_selection().get_selected_nodes():
		var anchor := _anchor_of(node)
		if not (anchor is Node3D):
			continue
		var map := MapContext.of(anchor)
		if map == null:
			continue
		var project := func(cell: Vector3i) -> Variant:
			var world := map.cell_centre(cell) + Vector3(0.0, 0.05, 0.0)
			return null if camera.is_position_behind(world) else camera.unproject_position(world)
		var start := map.cell_of((anchor as Node3D).global_position)
		_draw_placement(overlay, anchor, start, project)


## [param project] turns a cell into a screen position, or null when it cannot be shown
## (behind the 3D camera).
static func _draw_placement(overlay: Control, anchor: Node, start: Vector3i,
		project: Callable) -> void:
	var event := _event_under(anchor)
	if event == null or event.document_path == "" or not FileAccess.file_exists(event.document_path):
		return

	var document := EventDocument.parse(FileAccess.get_file_as_string(event.document_path))
	var pages: Array = document.get("pages", [])
	if pages.is_empty():
		return
	var page: Dictionary = pages[0]

	for entry in [["route", ROUTE_COLOR], ["graph", GRAPH_COLOR]]:
		var nodes: Array = page.get(entry[0], [])
		if nodes.is_empty():
			continue
		var facing := Vector3i(0, 0, 1)
		_draw_segments(overlay, RouteTracer.trace(nodes, start, facing), project, entry[1])


static func _draw_segments(overlay: Control, segments: Array[Dictionary], project: Callable,
		color: Color) -> void:
	for segment in segments:
		match segment["kind"]:
			"line":
				var a: Variant = project.call(segment["from"])
				var b: Variant = project.call(segment["to"])
				if a == null or b == null:
					continue
				if bool(segment.get("dashed", false)):
					overlay.draw_dashed_line(a, b, color, LINE_WIDTH, 6.0)
				else:
					overlay.draw_line(a, b, color, LINE_WIDTH, true)
				_arrowhead(overlay, a, b, color)
			"random":
				var at: Variant = project.call(segment["at"])
				if at != null:
					_compass(overlay, at, color)
			"unknown":
				var at: Variant = project.call(segment["at"])
				if at != null:
					overlay.draw_string(ThemeDB.fallback_font, (at as Vector2) + Vector2(-5, 7), "?",
						HORIZONTAL_ALIGNMENT_LEFT, -1, 22, color)
			"loop":
				var at: Variant = project.call(segment["at"])
				if at != null:
					overlay.draw_arc(at, MARK_RADIUS * 0.6, 0.0, TAU, 20, color, LINE_WIDTH)


static func _arrowhead(overlay: Control, from: Vector2, to: Vector2, color: Color) -> void:
	var direction := (to - from).normalized()
	if direction == Vector2.ZERO:
		return
	var side := direction.orthogonal() * ARROW_SIZE * 0.5
	var base := to - direction * ARROW_SIZE
	overlay.draw_polyline(PackedVector2Array([base + side, to, base - side]), color, LINE_WIDTH, true)


## The "anything could happen here" mark: a big X, with a short tick out of each side for
## the four compass directions a random step can take.
static func _compass(overlay: Control, at: Vector2, color: Color) -> void:
	var r := MARK_RADIUS
	overlay.draw_line(at + Vector2(-r, -r), at + Vector2(r, r), color, LINE_WIDTH, true)
	overlay.draw_line(at + Vector2(-r, r), at + Vector2(r, -r), color, LINE_WIDTH, true)
	for tick in [Vector2.UP, Vector2.RIGHT, Vector2.DOWN, Vector2.LEFT]:
		overlay.draw_line(at + tick * r * 1.15, at + tick * r * 1.7, color, LINE_WIDTH, true)


static func _anchor_of(node: Node) -> Node:
	var n: Node = node
	while n != null:
		if n is Node2D or n is Node3D:
			return n
		n = n.get_parent()
	return null


## The placement's [GameEvent] - under the anchor itself, or (for a selected Actor or other
## child) a sibling reached through its parent.
static func _event_under(anchor: Node) -> GameEvent:
	for child in anchor.get_children():
		if child is GameEvent:
			return child as GameEvent
	return null
