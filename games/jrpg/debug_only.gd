extends Node

var _parent : Node

func _ready() -> void:
	_parent = get_parent()
	_parent.set("visible", false)
	# Hide or remove the marker if this is not a debug build
	if OS.is_debug_build():
		_parent.set("visible", true)

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if event.is_action("debug_toggle"):
		_parent.set("visible", !_parent.get("visible"))