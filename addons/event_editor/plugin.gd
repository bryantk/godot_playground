@tool
extends EditorPlugin

## Adds the event JSON dock to the editor. The dock is the whole plugin - there is
## no importer or custom Resource behind it, so the .json files on disk stay the
## single source of truth that hand-editing and other tools can also touch.

const DockScript := preload("res://addons/event_editor/event_editor_dock.gd")

var _dock: Control = null

func _enter_tree() -> void:
	_dock = DockScript.new()
	add_control_to_dock(DOCK_SLOT_RIGHT_BL, _dock)

func _exit_tree() -> void:
	if _dock == null:
		return

	remove_control_from_docks(_dock)
	_dock.queue_free()
	_dock = null
