@tool
extends EditorPlugin

## Adds the node graph editor to the editor's bottom panel.
##
## The bottom panel rather than a side dock: a [GraphEdit] needs width, and this one
## wants to sit open beside the scene rather than replace the main screen.
##
## Like the event editor next to it, the plugin is only the panel - the .json files on
## disk stay the single source of truth, so hand-editing and other tools can touch the
## same graphs.

const PanelScript := preload("res://addons/graph_editor/graph_editor_panel.gd")

var _panel: Control = null
var _button: Button = null

func _enter_tree() -> void:
	_panel = PanelScript.new()
	_button = add_control_to_bottom_panel(_panel, "Graph")

func _exit_tree() -> void:
	if _panel == null:
		return

	remove_control_from_bottom_panel(_panel)
	_panel.queue_free()
	_panel = null
	_button = null
