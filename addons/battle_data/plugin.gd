@tool
extends EditorPlugin

## Adds the Battle Data dock: a tab per kind of battle data (heroes, enemies, troops,
## items, abilities, effects) with New / Duplicate / Save / Delete, and a validator for
## broken references. The fields themselves are edited in Godot's own inspector, which
## already gives a typed picker for every linked resource (abilities on a hero, enemies in
## a troop, an effect on an ability) - the dock is the list, the file handling and the
## checking around it.

const PanelScript := preload("res://addons/battle_data/battle_data_panel.gd")

var _panel: Control = null


func _enter_tree() -> void:
	_panel = PanelScript.new()
	add_control_to_dock(EditorPlugin.DOCK_SLOT_LEFT_BR, _panel)


func _exit_tree() -> void:
	if _panel == null:
		return
	remove_control_from_docks(_panel)
	_panel.queue_free()
	_panel = null
