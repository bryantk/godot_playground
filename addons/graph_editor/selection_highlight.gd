@tool
extends RefCounted

## Draws a highlight around whichever [Actor]s or [GameEvent]s are selected in the Scene
## dock, in the 2D or 3D editor viewport - [method draw_2d]/[method draw_3d], called
## every frame by [code]plugin.gd[/code]'s own [method
## EditorPlugin._forward_canvas_force_draw_over_viewport]/[method
## EditorPlugin._forward_3d_force_draw_over_viewport]. The "force" pair, not the plain
## one: those only fire for whichever plugin currently owns the edited object (the
## machinery a custom gizmo uses), and a selection highlight should show up the instant
## either kind of node is picked, with no "become the active plugin for this object"
## dance first.
##
## [b]Neither [Actor] nor [GameEvent] is a [Node2D]/[Node3D] of its own[/b] - both are
## plain [Node]s parented under the real placement root ([DebugArea2D]/[DebugArea3D]'s
## own sibling spot - see either class's doc for why a debug box lives there and
## nowhere deeper). [method _anchor_of] walks up from the selected node to find that
## root, landing on the same [Node2D]/[Node3D] either debug node already sits beside.
##
## [b]Sized like [DebugArea2D]/[DebugArea3D], without depending on either existing.[/b]
## A placement with no [DebugArea2D]/[DebugArea3D] child at all (most of them, day to
## day) still gets an accurately-sized highlight: [method _footprint_rect_2d]/[method
## _footprint_corners_3d] reread the sibling [Actor]'s own [member Actor.footprint] and
## [member MapContext.cell_size] directly - the same two numbers those debug nodes
## already turn into a box - rather than requiring one to be placed just so this has
## something to measure.
##
## [b]No footprint to measure[/b] (a bodiless region trigger's [GameEvent] with no
## [Actor] beside it, or an [Actor] not yet under a [MapContext]) falls back to a small,
## fixed-screen-size marker centred on the anchor's own projected position instead of
## drawing nothing - still enough to say "this is where the selected node lives."
##
## [b]Known limit:[/b] the 3D half reads its camera from [method
## EditorInterface.get_editor_viewport_3d]'s pane 0 only - correct for the ordinary
## single-viewport 3D editor, but a highlight drawn in a quad-view pane other than the
## first will project against the wrong camera. Not worth the bookkeeping a fully
## per-pane-correct version would need until someone actually edits in quad view.
##
## [b]The 2D half reads [member Viewport.global_canvas_transform] off [method
## EditorInterface.get_editor_viewport_2d] directly[/b] - the 2D editor's own pan/zoom,
## not anything derived from the selected node. Both [method
## CanvasItem.get_viewport_transform] and [method CanvasItem.get_canvas_transform] on the
## anchor were tried first and both drew the highlight off from the actual item (in
## opposite directions from each other) - the points being transformed ([member
## Actor.footprint]'s rect corners, [member Node2D.global_position]) are already global,
## so a transform pulled off the anchor itself is the wrong tool no matter which of the
## two is picked; the editor viewport's own transform is what actually matches what's on
## screen.

const HIGHLIGHT_COLOR := Color(1.0, 0.85, 0.1, 0.95)
const LINE_WIDTH := 2.0
const MARKER_SCREEN_SIZE := 18.0

## [DebugArea3D._build_wire_box]'s own corners and edges, copied rather than shared -
## see that method's own doc on why its twin in [code]debug_passability_view.gd[/code]
## already lives as its own small copy instead of a shared static helper.
const _BOX_CORNERS: Array[Vector3] = [
	Vector3(-1, -1, -1), Vector3(1, -1, -1), Vector3(1, -1, 1), Vector3(-1, -1, 1),
	Vector3(-1, 1, -1), Vector3(1, 1, -1), Vector3(1, 1, 1), Vector3(-1, 1, 1),
]
const _BOX_EDGES: Array[Vector2i] = [
	Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
	Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
	Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
]


## Every [Actor]/[GameEvent] in the current Scene dock selection - the set [method
## draw_2d]/[method draw_3d] each walk, filtering to whichever half resolves to a
## [Node2D] or [Node3D] anchor.
static func _targets() -> Array[Node]:
	var out: Array[Node] = []
	for node in EditorInterface.get_selection().get_selected_nodes():
		if node is Actor or node is GameEvent:
			out.append(node)
	return out


## The nearest [Node2D]/[Node3D] ancestor - walks up from the selected node itself to
## the placement root [DebugArea2D]/[DebugArea3D] already sit beside as a direct child
## of the same root.
static func _anchor_of(node: Node) -> Node:
	var n: Node = node
	while n != null:
		if n is Node2D or n is Node3D:
			return n
		n = n.get_parent()
	return null


## The [Actor] beside [param anchor], if any - [method DebugArea2D._sync_target]'s own
## search, read straight off the placement root rather than a debug node's cached one.
static func _actor_under(anchor: Node) -> Actor:
	for child in anchor.get_children():
		if child is Actor:
			return child as Actor
	return null


# -- 2D ------------------------------------------------------------------------------

static func draw_2d(overlay: Control) -> void:
	var viewport := EditorInterface.get_editor_viewport_2d()
	if viewport == null:
		return
	var xform := viewport.global_canvas_transform

	for node in _targets():
		var anchor := _anchor_of(node)
		if anchor is Node2D:
			_draw_2d_for(overlay, xform, anchor as Node2D)


static func _draw_2d_for(overlay: Control, xform: Transform2D, anchor: Node2D) -> void:
	var rect: Variant = _footprint_rect_2d(anchor)
	if rect == null:
		_draw_marker(overlay, xform * anchor.global_position)
		return

	var r: Rect2 = rect
	var corners := PackedVector2Array([
		xform * r.position,
		xform * (r.position + Vector2(r.size.x, 0)),
		xform * (r.position + r.size),
		xform * (r.position + Vector2(0, r.size.y)),
	])
	corners.append(corners[0])
	overlay.draw_polyline(corners, HIGHLIGHT_COLOR, LINE_WIDTH, true)


## World-space rect - [method DebugArea2D._sync_footprint]'s own math, read straight off
## the sibling [Actor] and its [MapContext] instead of a debug node's own fields. [code]
## null[/code] with no [Actor] beside [param anchor] or no [MapContext] above it yet,
## which [method _draw_2d_for] reads as "draw the marker instead."
static func _footprint_rect_2d(anchor: Node2D) -> Variant:
	var actor := _actor_under(anchor)
	var ctx := MapContext.of(anchor) if actor != null else null
	if actor == null or ctx == null:
		return null

	var cell := Vector2(ctx.cell_size.x, ctx.cell_size.z)
	var size := Vector2(actor.footprint.x, actor.footprint.z) * cell
	return Rect2(anchor.global_position - cell * 0.5, size)


# -- 3D ------------------------------------------------------------------------------

static func draw_3d(overlay: Control) -> void:
	var viewport := EditorInterface.get_editor_viewport_3d(0)
	var camera := viewport.get_camera_3d() if viewport != null else null
	if camera == null:
		return

	for node in _targets():
		var anchor := _anchor_of(node)
		if anchor is Node3D:
			_draw_3d_for(overlay, camera, anchor as Node3D)


static func _draw_3d_for(overlay: Control, camera: Camera3D, anchor: Node3D) -> void:
	var corners := _footprint_corners_3d(anchor)
	if corners.is_empty():
		if not camera.is_position_behind(anchor.global_position):
			_draw_marker(overlay, camera.unproject_position(anchor.global_position))
		return

	for edge in _BOX_EDGES:
		var a: Vector3 = corners[edge.x]
		var b: Vector3 = corners[edge.y]
		if camera.is_position_behind(a) or camera.is_position_behind(b):
			continue
		overlay.draw_line(camera.unproject_position(a), camera.unproject_position(b),
			HIGHLIGHT_COLOR, LINE_WIDTH)


## The 8 world-space corners of [DebugArea3D]'s own wire box - [method
## DebugArea3D._sync_footprint]/[method DebugArea3D._box_position]'s math, read straight
## off the sibling [Actor] and its [MapContext]. Empty with no [Actor] beside
## [param anchor] or no [MapContext] above it, matching [method _footprint_rect_2d].
static func _footprint_corners_3d(anchor: Node3D) -> Array[Vector3]:
	var actor := _actor_under(anchor)
	var ctx := MapContext.of(anchor) if actor != null else null
	if actor == null or ctx == null:
		return []

	var cell := Vector2(ctx.cell_size.x, ctx.cell_size.z)
	var footprint_xz := Vector2(actor.footprint.x, actor.footprint.z)
	var size := Vector3(footprint_xz.x * cell.x, 1.0, footprint_xz.y * cell.y)
	var footprint_offset := (footprint_xz - Vector2.ONE) * cell * 0.5
	var center := anchor.global_position \
		+ Vector3(footprint_offset.x, size.y * 0.5, footprint_offset.y)

	var h := size * 0.5
	var out: Array[Vector3] = []
	for local in _BOX_CORNERS:
		out.append(center + local * h)
	return out


# -- Shared marker ---------------------------------------------------------------

## A small screen-space diamond at [param screen_pos] - fixed pixel size regardless of
## zoom or camera distance, since there is no world-space footprint to size it against.
static func _draw_marker(overlay: Control, screen_pos: Vector2) -> void:
	var h := MARKER_SCREEN_SIZE * 0.5
	var points := PackedVector2Array([
		screen_pos + Vector2(0, -h), screen_pos + Vector2(h, 0),
		screen_pos + Vector2(0, h), screen_pos + Vector2(-h, 0),
		screen_pos + Vector2(0, -h),
	])
	overlay.draw_polyline(points, HIGHLIGHT_COLOR, LINE_WIDTH, true)
