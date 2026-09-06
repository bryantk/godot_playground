class_name Dialogue
extends Control

signal finished

@export var max_lines:= 4
@export_group("References")
@export var text_block: RichTextBlock = null
@export var cursor: Control
@export var window: Control
@export var locations: Control

enum Location { TOP, MIDDLE, BOTTOM }

func _ready() -> void:
	text_block.on_finished.connect(_finished)
	text_block.on_page_displayed.connect(_on_page_displayed)

func set_window_location(index: int) -> void:
	if index < 0 or index >= locations.get_child_count():
		push_error("set_window_location: no location at index %d" % index)
		return

	var location: Control = locations.get_child(index)
	# Control.global_position folds in the window's own pivot-scale offset, so writing
	# it while the window sits collapsed (a zoom animation parked closed) shoves
	# position pivot_offset * (1 - scale) the other way to compensate - hundreds of
	# pixels offscreen once the intro scales back up. Zeroing the pivot makes this a
	# plain parent-space move; the animation rebuilds its own pivot in _layout().
	var pivot: Vector2 = window.pivot_offset
	window.pivot_offset = Vector2.ZERO
	window.global_position = location.global_position
	window.pivot_offset = pivot

func display(text: String) -> void:
	cursor.visible = false
	text_block.reset()

	await _animate_window(&"intro", true)

	text_block.display(text)

func _finished() -> void:
	cursor.visible = false

	await _animate_window(&"outro", false)

	text_block.reset()
	finished.emit()

## Runs the window's [param method] animation if it has one, otherwise falls back to
## toggling visibility to [param shown]. Always awaitable.
func _animate_window(method: StringName, shown: bool) -> void:
	if not window.has_method(method):
		window.visible = shown
		return

	var tween: Tween = window.call(method)
	if tween != null:
		text_block.pause()
		await tween.finished

func _on_page_displayed(_page: int, _ratio: float) -> void:
	cursor.visible = true

func action(pressed: bool) -> void:
	_speed_up()
	if not pressed:
		return

	if text_block.advance():
		cursor.visible = false

func cancel(_pressed: bool) -> void:
	_speed_up()

func _speed_up() -> void:
	var input = InputManager.is_down(&"action") or InputManager.is_down(&"cancel")
	text_block.request_speed_up = input

func debug2(pressed: bool) -> void:
	if not pressed:
		return
	_finished()

func debug(pressed: bool) -> void:
	if not pressed:
		return

	display(
"""Line 1
Line 2
Line 3
Line 4
2 Line 5
2 Line 6
2 Line 7
2 Line 8""")
