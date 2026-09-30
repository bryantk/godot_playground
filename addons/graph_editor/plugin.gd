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
const FramePickerScript := preload("res://addons/graph_editor/frame_picker_panel.gd")
const RouteOverlayScript := preload("res://addons/graph_editor/route_overlay.gd")

var _panel: Control = null
var _button: Button = null
var _inspector: EditorInspectorPlugin = null
var _frame_picker: Control = null

func _enter_tree() -> void:
	_panel = PanelScript.new()
	_button = add_control_to_bottom_panel(_panel, "Graph")

	_inspector = InspectorScript.new()
	_inspector.setup(_panel, func() -> void: make_bottom_panel_item_visible(_panel))
	add_inspector_plugin(_inspector)

	_frame_picker = FramePickerScript.new()
	add_control_to_bottom_panel(_frame_picker, "Frames")
	_panel.setup_frame_picker(
		_frame_picker, func() -> void: make_bottom_panel_item_visible(_frame_picker))

	# Without this, the two overrides below never fire at all: the plain (non-"force")
	# draw-over hooks only run for whichever plugin currently owns the edited object -
	# the machinery a custom gizmo uses - and this plugin never claims that (no
	# _handles override), since a selection highlight has no business being the thing
	# that decides which plugin edits an [Actor] or [GameEvent].
	set_force_draw_over_forwarding_enabled()

	# Likewise for the viewport input hooks below: without this they only fire for a
	# selected object this plugin _handles, and it handles nothing. Needed so a "Pick"
	# button's next click in the scene viewport reaches _forward_*_gui_input.
	set_input_event_forwarding_always_enabled()

func _exit_tree() -> void:
	if _inspector != null:
		remove_inspector_plugin(_inspector)
		_inspector = null

	if _frame_picker != null:
		remove_control_from_bottom_panel(_frame_picker)
		_frame_picker.queue_free()
		_frame_picker = null

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
	RouteOverlayScript.draw_2d(overlay)

func _forward_3d_force_draw_over_viewport(overlay: Control) -> void:
	HighlightScript.draw_3d(overlay)
	RouteOverlayScript.draw_3d(overlay)

## While a node's "Pick" button is waiting (see [method GraphEditorPanel.is_picking]), a
## left click in the 2D viewport fills the cell argument in with the cell under the mouse,
## and Esc cancels. Every mouse button event is swallowed meanwhile so the click does not
## also select or drag whatever is underneath.
func _forward_canvas_gui_input(event: InputEvent) -> bool:
	if _panel == null or not _panel.is_picking():
		return false
	if _is_escape(event):
		_panel.cancel_pick()
		return true

	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return false
	if click.pressed:
		var viewport := EditorInterface.get_editor_viewport_2d()
		var world: Vector2 = viewport.global_canvas_transform.affine_inverse() * click.position
		_panel.complete_pick(Vector3(world.x, 0.0, world.y))
	return true

## The 3D half: the click is cast from the viewport camera onto the ground plane (y = 0).
## A map with height still picks the column under the click, at floor level.
func _forward_3d_gui_input(camera: Camera3D, event: InputEvent) -> int:
	if _panel == null or not _panel.is_picking():
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if _is_escape(event):
		_panel.cancel_pick()
		return EditorPlugin.AFTER_GUI_INPUT_STOP

	var click := event as InputEventMouseButton
	if click == null or click.button_index != MOUSE_BUTTON_LEFT:
		return EditorPlugin.AFTER_GUI_INPUT_PASS
	if click.pressed:
		var origin := camera.project_ray_origin(click.position)
		var normal := camera.project_ray_normal(click.position)
		var hit: Variant = Plane(Vector3.UP, 0.0).intersects_ray(origin, normal)
		if hit is Vector3:
			_panel.complete_pick(hit)
		else:
			_panel.cancel_pick()
	return EditorPlugin.AFTER_GUI_INPUT_STOP

func _is_escape(event: InputEvent) -> bool:
	var key := event as InputEventKey
	return key != null and key.pressed and key.keycode == KEY_ESCAPE
