@tool
class_name DebugArea2D extends Node2D

## Draws an outlined rectangle - nothing else, on purpose (no label, no icon): a
## placement's own name in the Scene dock already says what it is, and text drawn in
## world space fights the camera's zoom instead of reading cleanly at every one.
##
## A scene-authored sibling of [GameEvent] (and of [Actor]/[Sprite2D]/a collider,
## where any exist), parented directly under the placement root - the actual
## [Node2D] a placement's own instanced scene positions. A bodiless region trigger or
## a no-art actor's own [GameEvent] gets one of these added under that same root by
## hand.
##
## [b]Why it must sit there and nowhere deeper[/b]: a [CanvasItem] parented under
## [GameEvent] or [Actor] instead - both plain [Node]s - becomes its own transform
## root (draws at the world origin, ignoring the placement entirely) - the trap
## [method ActorView._warn_if_detached] exists to catch for a [Sprite2D] visual, and
## exactly the one a debug box parented one level too deep walks straight into.
## Parented at the placement root itself, [member Node2D.position]/[member
## Node2D.global_position] are inherited through the ordinary transform chain like
## any other sibling under it - no per-frame copy needed to track a moving actor.
##
## [b]Sized from whichever sibling has something to measure.[/b] [member target]
## names the source by hand; left unset, [method _sync_target] searches this node's
## own parent (the placement root) for a sibling [CollisionShape2D] first, then a
## sibling [CollisionPolygon2D], then a sibling [Actor] - and writes whichever it finds
## back into [member target], so the choice is visible afterward in the inspector
## rather than re-decided silently every load. A placement carrying more than one of
## these (an actor with its own physics body, say) picks in that same order by
## default; [member target] is the escape hatch for pointing this at another one
## instead.
##
## [b]Reading a collider[/b] ([method _size_from_collider]) covers [RectangleShape2D],
## [CircleShape2D] and [CapsuleShape2D] as a bounding box - anything else uncommon is
## read as "nothing found" rather than computing a real hull, the same "not worth it
## for a rare shape" call this project already makes elsewhere (see
## [code]selection_highlight.gd[/code]'s own doc on quad-view).
##
## [b]A [CollisionPolygon2D] target is different[/b]: an irregular polygon is exactly
## what [AreaZone] itself is queried against at a cell centre ([method
## AreaZone.zones_at]), so drawing its smooth outline would show a shape the zone query
## never actually sees. [method _sync_polygon_footprint] instead tests every candidate
## cell's own centre against the polygon with the same [method
## Geometry2D.is_point_in_polygon] logic a physics point query resolves to, and [method
## _draw] outlines the covered cells themselves - a rough, blocky area that matches what
## crossing the zone actually feels like, rather than the polygon's own drawn edge.
##
## [b]Reading an actor[/b] is the original behaviour: [member area_size] becomes
## [code]footprint.x/z * cell_size[/code] - "show the footprint" - sized to wrap it
## rather than centred through it, since [method Actor.cell] is the footprint's own
## anchor *corner*, not its centre ([method GameEvent._footprint_visual_offset] is the
## same correction applied to the sprite instead).
##
## [b]Neither resolves[/b] (a bodiless region trigger authored with no collider and no
## [Actor] beside it) keeps [member area_size] exactly as authored, centred on
## [member offset] as it always was.
##
## [b]While editing[/b], [method _sync_visibility] leaves [member Node2D.visible]
## alone - toggling a box off with the Scene dock's own eye icon sticks, instead of
## snapping back on every frame. [b]At runtime, [member Node2D.visible] instead
## follows [method DebugFlags.is_box_type_visible][/b] for [member type] - one of six
## categories the debug menu ([code]~[/code], then keys 1-6) toggles independently,
## rather than every debug overlay in the game sharing a single on/off flag.

## The sibling this sizes itself from - a [CollisionShape2D], a [CollisionPolygon2D]
## or an [Actor]. Set by hand to resolve a conflict, or by [method _sync_target] the
## first time this node with none picks one automatically.
@export var target: Node = null

## What this box is marking, purely to pick a starting [member color] from [constant
## DebugFlags.BOX_TYPE_COLORS] - nothing else reads it. Changing it overwrites [member
## color]; changing [member color] afterward (by hand, or a second [member type]
## change) is what wins from then on, the same one-shot-default relationship [member
## area_size]'s own setter note describes for the mesh. Also which of [DebugFlags]'s
## six debug-menu categories [method _sync_visibility] follows at runtime.
##
## A plain [code]@export_enum[/code] int, not [enum DebugFlags.BoxType] by static type
## - see that enum's own doc for why - kept in the exact same order by hand: None,
## Event, Area, Transfer Marker, Actor.
@export_enum("None", "Event", "Area", "Transfer Marker", "Actor") var type: int = 0:
	set(value):
		type = value
		color = DebugFlags.BOX_TYPE_COLORS[value]

@export var area_size: Vector2 = Vector2(16, 16)
@export var offset: Vector2 = Vector2.ZERO
@export var color: Color = Color(0.35, 0.55, 1.0, 0.9)
@export var line_width: float = 2.0

## Also fills the rect, in [member color] at a quarter of its own alpha - see [method
## _fill_color]. Off by default: the outline alone is enough for most placements, and
## a filled rect reads as a stronger claim ("this whole area does something") than an
## outline does.
@export var fill: bool = false

## Top-left corner of the drawn rect, relative to [member offset] - [code]-area_size *
## 0.5[/code] (centred) with nothing resolved, or the collider's/footprint's own
## anchor once [method _sync_footprint] finds one.
var _rect_pos: Vector2 = Vector2.ZERO

## Grid cells (this node's own local grid, [code]world / _cell_size[/code]) a sibling
## [CollisionPolygon2D] target covers - empty whenever [member target] is anything
## else, which is what tells [method _draw] to fall back to the plain rect it has
## always drawn. Filled by [method _sync_polygon_footprint].
var _covered_cells: Array[Vector2i] = []

## [member MapContext.cell_size] read down to X/Z, cached alongside [member
## _covered_cells] so [method _draw] does not have to walk up to [MapContext] again
## every frame just to turn a cell back into a rect.
var _cell_size: Vector2 = Vector2.ZERO


func _ready() -> void:
	refresh()


## Re-derives everything from [member target] (resolving it first if unset), then
## redraws - [method _ready]'s own body, pulled out so [method
## MapContext.refresh_debug_areas] can re-run it on demand for a box already sized at
## whatever it was when the scene loaded.
func refresh() -> void:
	_sync_target()
	_sync_footprint()
	_sync_visibility()
	queue_redraw()


func _process(_delta: float) -> void:
	_sync_visibility()
	queue_redraw()


## Leaves [member target] alone if it already names something live; otherwise looks
## for a sibling [CollisionShape2D] first, then a sibling [CollisionPolygon2D], then a
## sibling [Actor], among this node's own parent's children (the placement root, the
## same sibling shape [GameEvent] and [Sprite2D] already share with it) - and writes
## whichever it finds back into [member target].
func _sync_target() -> void:
	if target != null and is_instance_valid(target):
		return

	var parent := get_parent()
	if parent == null:
		return

	for child in parent.get_children():
		if child is CollisionShape2D:
			target = child
			return
	for child in parent.get_children():
		if child is CollisionPolygon2D:
			target = child
			return
	for child in parent.get_children():
		if child is Actor:
			target = child
			return


## Derives [member area_size] and [member _rect_pos] from [member target] - a
## collider's own shape, a [CollisionPolygon2D]'s own covered cells, an actor's own
## footprint, or (with none of those) [member area_size] centred on [member offset]
## exactly as authored.
func _sync_footprint() -> void:
	_covered_cells.clear()

	if target is CollisionShape2D:
		var collider := target as CollisionShape2D
		var size: Variant = _size_from_collider(collider)
		if size != null:
			area_size = size
			_rect_pos = collider.position - area_size * 0.5
			return
		_rect_pos = -area_size * 0.5
		return

	if target is CollisionPolygon2D:
		_sync_polygon_footprint(target as CollisionPolygon2D)
		return

	var actor := target as Actor if target is Actor else null
	var ctx := MapContext.of(self) if actor != null else null
	if actor == null or ctx == null:
		_rect_pos = -area_size * 0.5
		return

	var cell := Vector2(ctx.cell_size.x, ctx.cell_size.z)
	area_size = Vector2(actor.footprint.x, actor.footprint.z) * cell
	_rect_pos = -cell * 0.5


## Fills [member _covered_cells] with every grid cell (in [member MapContext.cell_size]
## units, on this node's own local grid) whose centre falls inside [param poly] -
## [param poly]'s own [member CollisionPolygon2D.transform] carries it into that same
## local space first, since an authored polygon is free to sit off its own node's
## origin. With no [MapContext] above this node, or an empty polygon, falls back to
## [member area_size] centred on [member offset], exactly like no collider at all.
##
## [b]Why a cell's centre and not its corners or the polygon's own vertices[/b]: this
## is deliberately the same question [method AreaZone.zones_at] asks the physics
## server at a grid actor's commit - see that method's own doc. Testing centres keeps
## this box in lock-step with what the zone the polygon belongs to actually reacts to,
## the way [method _sync_footprint]'s collider branch already keys off a shape rather
## than redrawing it from scratch.
func _sync_polygon_footprint(poly: CollisionPolygon2D) -> void:
	var ctx := MapContext.of(self)
	if ctx == null or poly.polygon.is_empty():
		_rect_pos = -area_size * 0.5
		return

	_cell_size = Vector2(ctx.cell_size.x, ctx.cell_size.z)
	if _cell_size.x <= 0.0 or _cell_size.y <= 0.0:
		_rect_pos = -area_size * 0.5
		return

	var xform := poly.transform
	var bounds := Rect2(xform * poly.polygon[0], Vector2.ZERO)
	for point in poly.polygon:
		bounds = bounds.expand(xform * point)

	var inv := xform.affine_inverse()
	var min_cell := Vector2i(floori(bounds.position.x / _cell_size.x),
		floori(bounds.position.y / _cell_size.y))
	var max_cell := Vector2i(floori(bounds.end.x / _cell_size.x),
		floori(bounds.end.y / _cell_size.y))

	for y in range(min_cell.y, max_cell.y + 1):
		for x in range(min_cell.x, max_cell.x + 1):
			var centre := (Vector2(x, y) + Vector2(0.5, 0.5)) * _cell_size
			if Geometry2D.is_point_in_polygon(inv * centre, poly.polygon):
				_covered_cells.append(Vector2i(x, y))


## A bounding size for [param collider]'s own [member CollisionShape2D.shape], or
## [code]null[/code] for no shape, a disabled collider, or a shape this does not
## bother reading ([ConvexPolygonShape2D] and anything else uncommon) - read the same
## as no collider at all.
func _size_from_collider(collider: CollisionShape2D) -> Variant:
	if collider.disabled:
		return null

	var shape := collider.shape
	if shape is RectangleShape2D:
		return (shape as RectangleShape2D).size
	if shape is CircleShape2D:
		var d: float = (shape as CircleShape2D).radius * 2.0
		return Vector2(d, d)
	if shape is CapsuleShape2D:
		var c := shape as CapsuleShape2D
		return Vector2(c.radius * 2.0, c.height)
	return null


## Leaves [member Node2D.visible] alone while editing - the Scene dock's own eye icon
## (or the Inspector's "Visible" checkbox) is the only thing that should touch it
## there, so toggling a box off sticks instead of snapping back on next frame/[method
## refresh]. At runtime, [member Node2D.visible] never was hand-authored, so this
## drives it from [method DebugFlags.is_box_type_visible] for [member type] instead.
func _sync_visibility() -> void:
	if Engine.is_editor_hint():
		return
	visible = DebugFlags.is_box_type_visible(type)


func _draw() -> void:
	if not _covered_cells.is_empty():
		_draw_covered_cells()
		return

	var rect := Rect2(offset + _rect_pos, area_size)
	if fill:
		draw_rect(rect, _fill_color(), true)
	draw_rect(rect, color, false, line_width)


## The [CollisionPolygon2D] branch of [method _draw]: one rect per [member
## _covered_cells] entry, rather than the polygon's own smooth outline - see the class
## doc and [method _sync_polygon_footprint] for why "rough, and cell-aligned" is the
## point rather than a shortcut.
func _draw_covered_cells() -> void:
	for cell in _covered_cells:
		var rect := Rect2(offset + Vector2(cell) * _cell_size, _cell_size)
		if fill:
			draw_rect(rect, _fill_color(), true)
		draw_rect(rect, color, false, line_width)


## [member color] at a quarter of its own alpha - a fill reads as a wash under the
## outline rather than a second, equally-loud shape competing with it.
func _fill_color() -> Color:
	return Color(color.r, color.g, color.b, color.a * 0.25)
