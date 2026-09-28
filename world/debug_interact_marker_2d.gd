class_name DebugInteractMarker2D extends Node2D

## A transient X, spawned by [DebugInteractView] at the cell the player's last interact
## attempt resolved to. Fades out and frees itself over [member lifetime]; nothing else
## ever removes one.

@export var size: Vector2 = Vector2(16, 16)
@export var color: Color = Color.WHITE
@export var line_width: float = 3.0
@export var lifetime: float = 3.0

var _age := 0.0


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	modulate.a = 1.0 - _age / lifetime
	queue_redraw()


func _draw() -> void:
	var h := size * 0.5
	draw_line(Vector2(-h.x, -h.y), Vector2(h.x, h.y), color, line_width)
	draw_line(Vector2(-h.x, h.y), Vector2(h.x, -h.y), color, line_width)
