extends Node

@export var target: Node = null

var _is_down:= {}

func attach(node: Node) -> void:
	target = node

func is_down(action: String) -> bool:
	return _is_down.get(action, false)

func _input(event: InputEvent) -> void:
	# Ignore mouse movement
	if event is InputEventMouseMotion:
		return
	# Held keys emit repeat events; they are neither a press nor a release.
	if event.is_echo():
		return

	print("  ->%s %s" % [event.as_text(), "down" if event.is_pressed() else "up"])

	if event.is_action_pressed(&"quit"):
		get_tree().quit()
	elif event.is_action(&"action"):
		_send(&"action", event.is_pressed())
	elif event.is_action(&"cancel"):
		_send(&"cancel", event.is_pressed())
	elif event.keycode == KEY_R:
		_send(&"debug", event.is_pressed())
	elif event.keycode == KEY_T:
		_send(&"debug2", event.is_pressed())


func _send(method: StringName, pressed: bool) -> void:
	if target == null or not target.has_method(method):
		return

	_is_down[method] = pressed
	target.call(method, pressed)
