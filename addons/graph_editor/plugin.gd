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
const InspectorScript := preload("res://addons/graph_editor/actor_event_inspector.gd")
const HighlightScript := preload("res://addons/graph_editor/selection_highlight.gd")

var _panel: Control = null
var _button: Button = null
var _inspector: EditorInspectorPlugin = null

func _enter_tree() -> void:
	_panel = PanelScript.new()
	_button = add_control_to_bottom_panel(_panel, "Graph")

	_inspector = InspectorScript.new()
	_inspector.setup(_panel, func() -> void: make_bottom_panel_item_visible(_panel))
	add_inspector_plugin(_inspector)

	# Without this, the two overrides below never fire at all: the plain (non-"force")
	# draw-over hooks only run for whichever plugin currently owns the edited object -
	# the machinery a custom gizmo uses - and this plugin never claims that (no
	# _handles override), since a selection highlight has no business being the thing
	# that decides which plugin edits an [Actor] or [GameEvent].
	set_force_draw_over_forwarding_enabled()

func _exit_tree() -> void:
	if _inspector != null:
		remove_inspector_plugin(_inspector)
		_inspector = null

	if _panel == null:
		return

	remove_control_from_bottom_panel(_panel)
	_panel.queue_free()
	_panel = null
	_button = null

## Highlights whichever [Actor]s/[GameEvent]s are selected in the Scene dock - see
## [code]selection_highlight.gd[/code]'s own class doc for why this is the "force"
## variant and how the highlight is sized.
func _forward_canvas_force_draw_over_viewport(overlay: Control) -> void:
	HighlightScript.draw_2d(overlay)

func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	HighlightScript.draw_3d(overlay)
