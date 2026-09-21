extends Node

var _parent : Node

func _ready() -> void:
	_parent = get_parent()
	_sync_visibility()

func _process(_delta: float) -> void:
	_sync_visibility()

func _sync_visibility() -> void:
	var v = true if Engine.is_editor_hint() else DebugFlags.show_debug_view()
	_parent.set("visible", v)