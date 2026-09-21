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
## [b]Always visible while editing.[/b] [b]At runtime, only while [method
## DebugFlags.show_debug_view] is on[/b] - the same flag [DebugPassabilityView] reads,
## so every debug overlay in the game turns on and off together.

@export var area_size: Vector2 = Vector2(16, 16)
@export var offset: Vector2 = Vector2.ZERO
@export var color: Color = Color(0.35, 0.55, 1.0, 0.9)
@export var line_width: float = 2.0

var _anchor: Node2D = null


func _ready() -> void:
	_anchor = _find_anchor()
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


func _sync_position() -> void:
	if _anchor != null and is_instance_valid(_anchor):
		global_position = _anchor.global_position


func _sync_visibility() -> void:
	visible = true if Engine.is_editor_hint() else DebugFlags.show_debug_view()


func _draw() -> void:
	draw_rect(Rect2(offset - area_size * 0.5, area_size), color, false, line_width)
