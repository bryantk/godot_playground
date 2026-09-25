@tool
class_name DebugArea2D extends Node2D

## Draws an outlined rectangle - nothing else, on purpose (no label, no icon): a
## placement's own name in the Scene dock already says what it is, and text drawn in
## world space fights the camera's zoom instead of reading cleanly at every one.
##
## A scene-authored child of [GameEvent] - [GameEvent] stays a plain [Node] with no
## [@tool] of its own, so a bodiless region trigger or a no-art actor's own
## [GameEvent] gets one of these added under it by hand.
##
## [b]Why this follows its anchor by hand[/b]: a [CanvasItem] whose parent is a plain
## [Node] becomes its own transform root (draws at the world origin, ignoring the
## placement entirely) - the trap [method ActorView._warn_if_detached] exists to catch
## for a [Sprite2D] visual, and exactly the one being [GameEvent]'s own child walks
## straight into. [method _find_anchor] walks back up past [GameEvent] to the nearest
## real [Node2D] - the placement root - and [method _process] copies its
## [member Node2D.global_position] every frame, so the rectangle tracks a moving actor
## the same as if the transform chain had done it for free.
##
## [b]Sized from the sibling [Actor]'s own footprint, when there is one.[/b]
## [member area_size] is overwritten to [code]footprint.x/z * cell_size[/code] the
## moment an [Actor] is found beside this node - "show the footprint" - and the box is
## positioned to actually wrap it, not centred through it: [method Actor.cell] is the
## footprint's anchor *corner*, not its centre ([method GameEvent._footprint_visual_offset]
## is the same correction applied to the sprite instead), so the rect starts half a
## cell up/left of the anchor and extends the whole footprint's width/depth from
## there. A bodiless event (no [Actor] beside it) keeps [member area_size] exactly as
## authored, centred on [member offset] as it always was.
##
## [b]Always visible while editing.[/b] [b]At runtime, only while [method
## DebugFlags.show_debug_view] is on[/b] - the same flag [DebugPassabilityView] reads,
## so every debug overlay in the game turns on and off together.

@export var area_size: Vector2 = Vector2(16, 16)
@export var offset: Vector2 = Vector2.ZERO
@export var color: Color = Color(0.35, 0.55, 1.0, 0.9)
@export var line_width: float = 2.0

var _anchor: Node2D = null

## Top-left corner of the drawn rect, relative to [member offset] - [code]-area_size *
## 0.5[/code] (centred) for a bodiless event, or the footprint's own anchor corner
## once [method _sync_footprint] finds an [Actor].
var _rect_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	_anchor = _find_anchor()
	refresh()


## Re-derives everything from the sibling [Actor]'s current footprint and the map's
## current [member MapContext.cell_size], then redraws - [method _ready]'s own body,
## pulled out so [method MapContext.refresh_debug_areas] can re-run it on demand for a
## box already sized at whatever it was when the scene loaded.
func refresh() -> void:
	_sync_footprint()
	_sync_visibility()
	_sync_position()
	queue_redraw()


func _process(_delta: float) -> void:
	_sync_visibility()
	_sync_position()
	queue_redraw()


## The nearest [Node2D] above this node's own parent - skipping [member
## Node.get_parent] itself (typically [GameEvent], a plain [Node]) rather than starting
## there, since a [Node2D] parent placed directly under one would otherwise anchor to
## itself and read as correct by coincidence.
func _find_anchor() -> Node2D:
	var n := get_parent()
	n = n.get_parent() if n != null else null
	while n != null:
		if n is Node2D:
			return n as Node2D
		n = n.get_parent()
	return null


## The [Actor] beside this node, if any - a direct child of [member _anchor] (the
## placement root), the same sibling shape [GameEvent] and [Sprite2D] already share
## with it.
func _find_actor() -> Actor:
	if _anchor == null:
		return null
	for child in _anchor.get_children():
		if child is Actor:
			return child as Actor
	return null


## Derives [member area_size] and [member _rect_pos] from the sibling [Actor]'s own
## footprint and the map's [member MapContext.cell_size], or falls back to
## [member area_size] centred on [member offset] with no [Actor] to read.
func _sync_footprint() -> void:
	var actor := _find_actor()
	var ctx := MapContext.of(self) if actor != null else null
	if actor == null or ctx == null:
		_rect_pos = -area_size * 0.5
		return

	var cell := Vector2(ctx.cell_size.x, ctx.cell_size.z)
	area_size = Vector2(actor.footprint.x, actor.footprint.z) * cell
	_rect_pos = -cell * 0.5


func _sync_position() -> void:
	if _anchor != null and is_instance_valid(_anchor):
		global_position = _anchor.global_position


func _sync_visibility() -> void:
	visible = true if Engine.is_editor_hint() else DebugFlags.show_debug_view()


func _draw() -> void:
	draw_rect(Rect2(offset + _rect_pos, area_size), color, false, line_width)
