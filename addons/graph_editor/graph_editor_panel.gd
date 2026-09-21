@tool
extends VBoxContainer

## Bottom-panel node graph editor, saved and loaded as JSON.
##
## The [GraphEdit] on screen is the document: there is no parallel model held in a
## member variable. Saving walks the graph nodes and their connections; loading builds
## them back. That keeps the two from drifting, and it means a [code]@tool[/code]
## script reload - which wipes this instance's variables but leaves its children
## standing - cannot lose the graph.
##
## Shape of the file is [GraphDocumentScript]'s business; this file is the editing of
## it. Three rules from there matter to the UI:
## - an output port names one flow and points at one node, so connecting a port that is
##   already wired replaces the old connection rather than adding to it;
## - a node has exactly one input, so every connection lands on port 0 and any number
##   of ports may point at the same node;
## - a node's ports come from its command ([method EventCommand.flows_of]), not from
##   anything this panel lets an author add or remove directly.
##
## [b]The page inspector, left of the graph[/b], is the exception to "the graph is the
## document": art, speed, route and conditions belong to the page (event-pages.md §2),
## not to any node, so there is nothing on screen to read them back from at save time.
## Each field writes straight into [member _doc]'s current page as it changes instead -
## see [method _build_page_inspector].

const Doc := preload("res://addons/graph_editor/graph_document.gd")
const EventDoc := preload("res://events/event_document.gd")

const METADATA_SECTION := "graph_editor"
const METADATA_PATH_KEY := "last_file"

## Items behind the toolbar's dropdowns, grouped by what they act on rather than left
## as one long row of buttons. The enum values double as [PopupMenu] item ids, so a
## dropdown's [signal PopupMenu.id_pressed] handler can [code]match[/code] on them
## directly instead of comparing against the label text.
enum FileAction { NEW, OPEN, RELOAD, SAVE }
enum GraphAction { ADD_COMMAND, ARRANGE, VALIDATE, VIEW_JSON }
enum ActorAction { LOAD_EVENT, DELETE_ACTOR, FIND_ORPHANS }

## Where a node dropped by the Add button lands, before the offset below spreads
## repeated presses out instead of stacking them.
const ADD_POSITION := Vector2(80, 80)
const ADD_STEP := Vector2(40, 30)

## Where an auto-added start node lands - left of [constant ADD_POSITION], since it is
## conventionally the leftmost node in a graph read left to right.
const _START_POSITION := Vector2(-160, 80)

var _path := ""
var _dirty := false
## How many nodes the Add button has placed, so each lands clear of the last.
var _added := 0

## The whole loaded file, [EventDocument]-shaped even when [member _wrapped] is false -
## a bare array reads as one page the same way [method EventDocument.parse] always
## reads one (event-pages.md §2.1). The [GraphEdit] on screen only ever shows
## [code]_doc.pages[_current_page].graph[/code]; every other page's data sits here
## untouched until its turn.
var _doc: Dictionary = EventDoc.default_document()
## True when the file on disk is the [code]{format, id, pages: []}[/code] wrapper, false
## for a bare array. Decides what [method _save] writes back - saving must not silently
## upgrade one of the four plain-array examples into the wrapper shape.
var _wrapped := false
var _current_page := 0

var _graph: GraphEdit
## The last node an "Add Command" press created, for [method _chain_from_node] to
## fall back on when nothing is selected - cleared whenever the graph is rebuilt from
## data ([method _clear]), since a node from a page or file no longer showing must
## never be auto-wired into a new one.
var _last_spawned: GraphNode = null
var _title: Label
var _page_selector: OptionButton
var _results: ItemList
var _status: Label
## The File dropdown - kept, unlike the others, because [method _refresh_title]
## enables and disables its Save and Reload items.
var _file_menu: MenuButton
## Quick-access save, beside [member _file_menu] rather than buried in it - enabled
## and disabled in step with the dropdown's own Save item, by [method _refresh_title].
var _save_icon_button: Button
var _file_dialog: EditorFileDialog

## The panel to the left of the graph - page data no node carries: art, speed, route
## and conditions. See [method _build_page_inspector] and [method _load_page_inspector].
var _art_picker: EditorResourcePicker
## The page's settings.trigger (decision 44's seven, plus a blank "(none)" for a page
## only ever entered by `call`) - see [constant EventDocument.TRIGGERS].
var _trigger_option: OptionButton
var _speed_spin: SpinBox
## The three actor flags a page carries as siblings of art/conditions - lock_facing,
## through and through_terrain, applied to GameEvent's own actor on activation.
var _lock_facing_check: CheckBox
var _through_check: CheckBox
var _through_terrain_check: CheckBox
## lock_player is a fourth actor flag, but on a different lifecycle from the other
## three - see event_document.gd's own note on it - so it is kept in its own variable
## rather than folded into the comment above about siblings of art/conditions.
var _lock_player_check: CheckBox
var _conditions_list: VBoxContainer
## Toggled between "Edit Route" and "Back to Graph" - see [method _on_route_button_pressed].
var _route_button: Button
## True while [member _graph] is showing the current page's [code]route[/code] instead
## of its [code]graph[/code] - both are node arrays [method _load_page] can point the
## same [GraphEdit] at, so editing a route needs no editor of its own.
var _editing_route := false

## The type-to-search popup [method _open_command_picker] shows - see
## [method _build_command_picker].
var _command_picker: PopupPanel
var _command_search: LineEdit
var _command_list: ItemList

## Where [method _on_command_picked] lands the next node - a real graph position when
## the picker was opened by right-clicking the canvas ([method _on_popup_request]), or
## [constant Vector2.INF] to fall back to [method _spawn_node]'s own incrementing
## default when it was opened from the toolbar instead, which has no click to go by.
var _spawn_position := Vector2.INF

## The confirmation popup [method _on_find_orphaned_events] shows - see
## [method _build_orphan_dialog].
var _orphan_dialog: ConfirmationDialog
var _orphan_list: ItemList
## What [method _on_orphan_dialog_confirmed] archives - set by
## [method _on_find_orphaned_events] just before the dialog pops up, since a
## [ConfirmationDialog]'s [signal confirmed] carries no argument of its own.
var _pending_orphans: Array[String] = []

func _init() -> void:
	name = "Graph"

func _ready() -> void:
	if not _bind():
		# Reloaded into a panel that is already up - its graph is still on screen.
		return

	var last: String = EditorInterface.get_editor_settings().get_project_metadata(
		METADATA_SECTION, METADATA_PATH_KEY, "")
	if last != "" and FileAccess.file_exists(last):
		_load(last)
	else:
		_new_document()

# --- UI -----------------------------------------------------------------------

## Points the references above at this panel's children, building them first if the
## panel is new. Returns true only when it built them.
##
## A [code]@tool[/code] script reloads in place: the node keeps its children and its
## connections - which is why a handler can still fire - but this instance is rebuilt
## with every reference back to null and no promise that [method _ready] runs again.
## Finding the children by name lets the panel pick itself back up.
func _bind() -> bool:
	if get_child_count() == 0:
		_build_ui()
		return true

	_graph = get_node_or_null(^"Body/Graph") as GraphEdit
	_title = get_node_or_null(^"Toolbar/Title") as Label
	_page_selector = get_node_or_null(^"Toolbar/PageSelector") as OptionButton
	_results = get_node_or_null(^"Results") as ItemList
	_status = get_node_or_null(^"Status") as Label
	_file_menu = get_node_or_null(^"Toolbar/File") as MenuButton
	_save_icon_button = get_node_or_null(^"Toolbar/SaveIcon") as Button
	_file_dialog = get_node_or_null(^"FileDialog") as EditorFileDialog

	_art_picker = get_node_or_null(
		^"Body/PageInspector/PageInspectorBox/ArtSheet") as EditorResourcePicker
	_trigger_option = get_node_or_null(
		^"Body/PageInspector/PageInspectorBox/Trigger") as OptionButton
	_speed_spin = get_node_or_null(
		^"Body/PageInspector/PageInspectorBox/Speed") as SpinBox
	_lock_facing_check = get_node_or_null(
		^"Body/PageInspector/PageInspectorBox/LockFacing") as CheckBox
	_through_check = get_node_or_null(
		^"Body/PageInspector/PageInspectorBox/Through") as CheckBox
	_through_terrain_check = get_node_or_null(
		^"Body/PageInspector/PageInspectorBox/ThroughTerrain") as CheckBox
	_lock_player_check = get_node_or_null(
		^"Body/PageInspector/PageInspectorBox/LockPlayer") as CheckBox
	_conditions_list = get_node_or_null(
		^"Body/PageInspector/PageInspectorBox/Conditions") as VBoxContainer
	_route_button = get_node_or_null(
		^"Body/PageInspector/PageInspectorBox/Edit Route") as Button

	_command_picker = get_node_or_null(^"CommandPicker") as PopupPanel
	_command_search = get_node_or_null(^"CommandPicker/Box/CommandSearch") as LineEdit
	_command_list = get_node_or_null(^"CommandPicker/Box/CommandList") as ItemList

	_orphan_dialog = get_node_or_null(^"OrphanDialog") as ConfirmationDialog
	_orphan_list = get_node_or_null(^"OrphanDialog/OrphanList") as ItemList

	if is_instance_valid(_graph):
		# The path lives in project metadata as well as in _path precisely so that it
		# survives this.
		_path = EditorInterface.get_editor_settings().get_project_metadata(
			METADATA_SECTION, METADATA_PATH_KEY, "")
		_refresh_title()
		return false

	# Children, but not the ones expected - left over from a build of this script whose
	# layout differed. Start over rather than binding to nothing and going inert.
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_build_ui()
	return true

## True when the references above are live, re-binding them first if a reload dropped
## them. Every handler passes through here, since one can fire before [method _bind].
func _live() -> bool:
	if not is_instance_valid(_graph):
		_bind()
	return is_instance_valid(_graph)

func _build_ui() -> void:
	add_theme_constant_override("separation", 4)

	var toolbar := HBoxContainer.new()
	toolbar.name = "Toolbar"
	add_child(toolbar)

	_file_menu = _make_menu_button("File", [
		[FileAction.NEW, "New"],
		[FileAction.OPEN, "Open"],
		[FileAction.RELOAD, "Reload"],
		[FileAction.SAVE, "Save"],
	], _on_file_menu_id_pressed)
	toolbar.add_child(_file_menu)

	# A one-click save beside the dropdown rather than only inside it - Save is common
	# enough to earn a permanent spot, the same reasoning the editor's own save icon in
	# its main toolbar follows.
	_save_icon_button = Button.new()
	_save_icon_button.name = "SaveIcon"
	_save_icon_button.flat = true
	_save_icon_button.tooltip_text = "Save"
	_save_icon_button.icon = EditorInterface.get_editor_theme().get_icon(&"Save", &"EditorIcons")
	_save_icon_button.pressed.connect(_save)
	toolbar.add_child(_save_icon_button)

	_title = Label.new()
	_title.name = "Title"
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.mouse_filter = Control.MOUSE_FILTER_PASS
	toolbar.add_child(_title)

	# Hidden until a loaded document has more than one page - the four plain-array
	# examples and any new document never show it at all.
	_page_selector = OptionButton.new()
	_page_selector.name = "PageSelector"
	_page_selector.tooltip_text = "Which page's graph is on screen. Order is priority - event-pages.md §2.3."
	_page_selector.item_selected.connect(_on_page_selected)
	_page_selector.visible = false
	toolbar.add_child(_page_selector)

	toolbar.add_child(_make_menu_button("Graph", [
		[GraphAction.ADD_COMMAND, "Add Command"],
		[GraphAction.ARRANGE, "Arrange"],
		[GraphAction.VALIDATE, "Validate"],
		[GraphAction.VIEW_JSON, "View JSON"],
	], _on_graph_menu_id_pressed))

	toolbar.add_child(_make_menu_button("Actor", [
		[ActorAction.LOAD_EVENT, "Load Actor Event"],
		[ActorAction.DELETE_ACTOR, "Delete Actor"],
		[ActorAction.FIND_ORPHANS, "Find Orphaned Events"],
	], _on_actor_menu_id_pressed))

	var body := HBoxContainer.new()
	body.name = "Body"
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)

	body.add_child(_build_page_inspector())

	_graph = GraphEdit.new()
	_graph.name = "Graph"
	_graph.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_graph.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_graph.custom_minimum_size = Vector2(0, 260)
	_graph.show_grid = true
	_graph.snapping_enabled = true
	_graph.snapping_distance = 20
	_graph.right_disconnects = true
	_graph.connection_request.connect(_on_connection_request)
	_graph.disconnection_request.connect(_on_disconnection_request)
	_graph.delete_nodes_request.connect(_on_delete_nodes_request)
	_graph.duplicate_nodes_request.connect(_on_duplicate_nodes_request)
	# Right-click (or the context-menu key) opens the same command picker "Add
	# Command" does - see _on_popup_request().
	_graph.popup_request.connect(_on_popup_request)
	# Dragging a node is an edit like any other, but it arrives once per drag rather
	# than once per pixel, so it is cheap to mark dirty on.
	_graph.end_node_move.connect(_mark_dirty)

	# Every output may land on an input, which is the only thing type 0 is used for.
	_graph.add_valid_connection_type(Doc.FLOW_SLOT_TYPE, 0)

	body.add_child(_graph)

	add_child(_build_command_picker())
	add_child(_build_orphan_dialog())

	_results = ItemList.new()
	_results.name = "Results"
	_results.custom_minimum_size = Vector2(0, 72)
	_results.auto_height = false
	_results.item_selected.connect(_on_result_selected)
	add_child(_results)

	_status = Label.new()
	_status.name = "Status"
	_status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_status)

	_file_dialog = EditorFileDialog.new()
	_file_dialog.name = "FileDialog"
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.add_filter("*.json", "Node graphs")
	_file_dialog.file_selected.connect(_load)
	add_child(_file_dialog)

func _make_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	# Named as well as labelled so _bind() can find it again after a script reload.
	button.name = text
	button.text = text
	button.pressed.connect(handler)
	return button

## A toolbar dropdown grouping related actions under one label, instead of one button
## each - [param items] is [code][[id, label], ...][/code], [param id] being an entry
## of whichever [code]*Action[/code] enum the dropdown is for. [param handler] receives
## that id from [signal PopupMenu.id_pressed] and dispatches on it, the same shape for
## every dropdown so adding one is copy the call, not write a new pattern.
func _make_menu_button(text: String, items: Array, handler: Callable) -> MenuButton:
	var menu := MenuButton.new()
	# Named as well as labelled so _bind() can find it again after a script reload -
	# only [member _file_menu] actually needs that, but every dropdown gets the same
	# treatment rather than one being the exception.
	menu.name = text
	menu.text = text
	menu.switch_on_hover = true
	# MenuButton defaults to flat - reads as a label, not a control - which is what
	# made these hard to tell apart from the title text next to them.
	menu.flat = false

	var popup := menu.get_popup()
	for entry in items:
		popup.add_item(entry[1], entry[0])
	popup.id_pressed.connect(handler)

	return menu

# --- Page inspector -------------------------------------------------------------
#
# The panel to the left of the graph, for page data no node carries: art, speed, route
# and conditions (event-pages.md §2). Unlike the graph, there is no on-screen copy this
# reads back from at save time - each field writes straight into the current page's
# entry in [member _doc] as it changes, since these are plain values with nothing like
# port wiring to reconcile. [method _load_page_inspector] is the other direction,
# called wherever [method _load_page] is so the panel always matches what page is open.

func _build_page_inspector() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "PageInspector"
	scroll.custom_minimum_size = Vector2(220, 0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED

	var box := VBoxContainer.new()
	box.name = "PageInspectorBox"
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(box)

	box.add_child(_section_label("Art"))
	_art_picker = EditorResourcePicker.new()
	_art_picker.name = "ArtSheet"
	_art_picker.base_type = "Texture2D"
	_art_picker.tooltip_text = "The page's art.sheet - what the actor looks like while this page is active."
	_art_picker.resource_changed.connect(_on_art_sheet_changed)
	box.add_child(_art_picker)

	box.add_child(_section_label("Trigger"))
	_trigger_option = OptionButton.new()
	_trigger_option.name = "Trigger"
	_trigger_option.tooltip_text = "The page's settings.trigger - which of decision 44's seven moments runs this page's graph. (none) leaves the page reachable only by \"call\"."
	_trigger_option.add_item("(none)")
	for trigger in EventDoc.TRIGGERS:
		_trigger_option.add_item(str(trigger))
	_trigger_option.item_selected.connect(_on_trigger_selected)
	box.add_child(_trigger_option)

	box.add_child(_section_label("Speed"))
	_speed_spin = SpinBox.new()
	_speed_spin.name = "Speed"
	_speed_spin.min_value = 0
	_speed_spin.max_value = 1000
	_speed_spin.step = 1
	_speed_spin.tooltip_text = "The page's settings.speed. 0 means absent - the page does not set one."
	_speed_spin.value_changed.connect(_on_speed_changed)
	box.add_child(_speed_spin)

	box.add_child(_section_label("Actor"))

	_lock_facing_check = CheckBox.new()
	_lock_facing_check.name = "LockFacing"
	_lock_facing_check.text = "Lock facing"
	_lock_facing_check.tooltip_text = "The page's lock_facing - ignores every facing command while this page is active, including looking at whoever started the interaction."
	_lock_facing_check.toggled.connect(_on_lock_facing_toggled)
	box.add_child(_lock_facing_check)

	_through_check = CheckBox.new()
	_through_check.name = "Through"
	_through_check.text = "Through"
	_through_check.tooltip_text = "The page's through - other actors do not block this actor's pathing (and vice versa), and the action trigger switches from \"adjacent and facing\" to \"on the same cell\"."
	_through_check.toggled.connect(_on_through_toggled)
	box.add_child(_through_check)

	_through_terrain_check = CheckBox.new()
	_through_terrain_check.name = "ThroughTerrain"
	_through_terrain_check.text = "Through terrain"
	_through_terrain_check.tooltip_text = "The page's through_terrain - ignores the painted pathing mask / colliders and GridMap, the same as Actor.through_terrain."
	_through_terrain_check.toggled.connect(_on_through_terrain_toggled)
	box.add_child(_through_terrain_check)

	_lock_player_check = CheckBox.new()
	_lock_player_check.name = "LockPlayer"
	_lock_player_check.text = "Lock player"
	_lock_player_check.tooltip_text = "The page's lock_player - disables player input for exactly the run this page's trigger starts, released the moment that run ends. See halt_control/return_control to hold the lock past that."
	_lock_player_check.toggled.connect(_on_lock_player_toggled)
	box.add_child(_lock_player_check)

	box.add_child(HSeparator.new())

	# The route gizmo event-pages.md §4.2 describes is a separate, larger effort; this
	# is the stopgap until then - the same node graph editor as the page's own command
	# graph, pointed at "route" instead of "graph" (see the class docstring's note on
	# a route being a node array too).
	_route_button = _make_button("Edit Route", _on_route_button_pressed)
	box.add_child(_route_button)

	box.add_child(HSeparator.new())

	box.add_child(_section_label("Conditions"))
	_conditions_list = VBoxContainer.new()
	_conditions_list.name = "Conditions"
	box.add_child(_conditions_list)

	box.add_child(_make_button("+ Condition", _on_add_condition))

	return scroll

func _section_label(text: String) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_color_override(&"font_color", _muted_color())
	return label

## The current page's dictionary in [member _doc], or [code]{}[/code] if there is none -
## every field this section touches is read and written through this, since the page
## dictionaries in [member _doc.pages] are always the live ones (Dictionary is a
## reference type here), never copies.
func _current_page_dict() -> Dictionary:
	var pages: Array = _doc.get("pages", [])
	if _current_page < 0 or _current_page >= pages.size():
		return {}
	return pages[_current_page]

## Refreshes every field in the page inspector from page [param index] - the inverse of
## the handlers below, called wherever [method _load_page] is so the panel to the left
## never shows the previous page's data.
func _load_page_inspector(index: int) -> void:
	if not is_instance_valid(_art_picker):
		return

	var pages: Array = _doc.get("pages", [])
	var page: Dictionary = pages[index] if index >= 0 and index < pages.size() else {}

	var art: Dictionary = page.get("art", {})
	var sheet := str(art.get("sheet", ""))
	_art_picker.edited_resource = load(sheet) if sheet != "" and ResourceLoader.exists(sheet) else null

	var settings: Dictionary = page.get("settings", {})
	# Index 0 is "(none)"; a trigger absent or not one of the seven (an older file, a
	# typo fixed by hand) also lands there rather than silently picking the first real
	# entry, which would rewrite the file's trigger the moment anything else changed.
	var trigger := str(settings.get("trigger", ""))
	_trigger_option.select(EventDoc.TRIGGERS.find(trigger) + 1)
	_speed_spin.set_value_no_signal(float(settings.get("speed", 0)))

	_lock_facing_check.set_pressed_no_signal(bool(page.get("lock_facing", false)))
	_through_check.set_pressed_no_signal(bool(page.get("through", false)))
	_through_terrain_check.set_pressed_no_signal(bool(page.get("through_terrain", false)))
	_lock_player_check.set_pressed_no_signal(bool(page.get("lock_player", false)))

	_refresh_conditions()

## [param index] is into the dropdown (0 is "(none)"), not into
## [constant EventDocument.TRIGGERS] - offset by one to get the real list.
func _on_trigger_selected(index: int) -> void:
	if not _live():
		return

	var settings: Dictionary = _current_page_dict().get("settings", {})
	if index <= 0:
		settings.erase("trigger")
	else:
		settings["trigger"] = EventDoc.TRIGGERS[index - 1]
	_mark_dirty()

func _on_art_sheet_changed(resource: Resource) -> void:
	if not _live():
		return

	var art: Dictionary = _current_page_dict().get("art", {})
	if resource != null and resource.resource_path != "":
		art["sheet"] = resource.resource_path
	else:
		art.erase("sheet")
	_mark_dirty()

func _on_speed_changed(value: float) -> void:
	if not _live():
		return

	var settings: Dictionary = _current_page_dict().get("settings", {})
	if value > 0:
		settings["speed"] = value
	else:
		settings.erase("speed")
	_mark_dirty()

## The four below write straight into the page dictionary, not settings - lock_facing/
## through/through_terrain/lock_player are siblings of art and conditions, not settings,
## even though lock_player (unlike the other three) describes one triggered run rather
## than the whole time the page is active - see event_document.gd's own note on it.
func _on_lock_facing_toggled(pressed: bool) -> void:
	if not _live():
		return
	_current_page_dict()["lock_facing"] = pressed
	_mark_dirty()

func _on_through_toggled(pressed: bool) -> void:
	if not _live():
		return
	_current_page_dict()["through"] = pressed
	_mark_dirty()

func _on_through_terrain_toggled(pressed: bool) -> void:
	if not _live():
		return
	_current_page_dict()["through_terrain"] = pressed
	_mark_dirty()

func _on_lock_player_toggled(pressed: bool) -> void:
	if not _live():
		return
	_current_page_dict()["lock_player"] = pressed
	_mark_dirty()

## Toggles [member _editing_route] and reloads the current page, which is all that is
## needed: [method _load_page] and [method _commit_current_page] already read and
## write whichever of "route" or "graph" [member _editing_route] names, so this button
## does not touch the graph itself - the same node editor, command picker, Arrange
## and Validate all keep working unchanged, just aimed at a different array.
func _on_route_button_pressed() -> void:
	if not _live():
		return

	_commit_current_page()
	_set_editing_route(not _editing_route)
	if _load_page(_current_page):
		_mark_dirty()
	else:
		_refresh_title()

	# Explicit, checkable feedback on what actually loaded - an empty route with only
	# its forced start node looks identical to "nothing happened" at a glance, so this
	# says in words what the canvas alone might not get across.
	if _editing_route:
		_set_status("Editing route for page %d: %d node(s)."
			% [_current_page + 1, _graph_nodes().size()], _status_color(true))
	else:
		_set_status("Back to the command graph for page %d." % [_current_page + 1],
			_status_color(true))

## A lighter, bluer version of the editor's own dark panel colour, for
## [method _set_editing_route] to tint [member _route_button] and [member _graph]'s
## background with - close in tone to the surrounding dark theme rather than a bright
## colour that would clash with it, "lighter" and "blue" both read relative to it.
func _route_tint() -> Color:
	var theme := EditorInterface.get_editor_theme()
	var base := theme.get_color(&"dark_color_2", &"Editor") if theme.has_color(&"dark_color_2", &"Editor") \
		else Color(0.14, 0.15, 0.18)
	return base.lightened(0.2).lerp(Color(0.3, 0.45, 0.75), 0.4)

## Sets [member _editing_route] and keeps the on-screen state that flag alone does not
## update in step with it: [member _route_button]'s label and tint, and a lighter blue
## background on [member _graph] itself - so which array is on screen is obvious at a
## glance, not just from the button text.
func _set_editing_route(editing: bool) -> void:
	_editing_route = editing
	var tint := _route_tint()

	if is_instance_valid(_route_button):
		_route_button.text = "Back to Graph" if editing else "Edit Route"
		_route_button.modulate = tint if editing else Color.WHITE

	if is_instance_valid(_graph):
		if editing:
			var panel := StyleBoxFlat.new()
			panel.bg_color = tint
			_graph.add_theme_stylebox_override(&"panel", panel)
		else:
			_graph.remove_theme_stylebox_override(&"panel")

# --- Conditions -----------------------------------------------------------------
#
# The flat AND list event-pages.md §2.2 calls the page convention - leaves only, no
# all/any/not nesting, which is what a typed `if` expression is for instead. A page
# hand-typed with a branch in it still round-trips (nothing here rewrites what it does
# not understand); it just shows read-only, since this form has no widgets for it.

## Rebuilds every row in [member _conditions_list] from the current page.
func _refresh_conditions() -> void:
	if not is_instance_valid(_conditions_list):
		return

	for child in _conditions_list.get_children():
		_conditions_list.remove_child(child)
		child.queue_free()

	var conditions: Array = _current_page_dict().get("conditions", [])
	for i in conditions.size():
		_conditions_list.add_child(_build_condition_row(conditions[i], i))

func _build_condition_row(entry: Variant, index: int) -> Control:
	var row := HBoxContainer.new()

	var kind := _condition_kind(entry) if typeof(entry) == TYPE_DICTIONARY else ""
	if kind == "":
		var label := Label.new()
		label.text = "(complex condition)"
		label.tooltip_text = JSON.stringify(entry)
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_color_override(&"font_color", _muted_color())
		row.add_child(label)
		row.add_child(_make_remove_condition_button(index))
		return row

	var leaf: Dictionary = entry

	var kind_option := OptionButton.new()
	for candidate in EventCondition.LEAVES:
		kind_option.add_item(str(candidate))
	kind_option.select(EventCondition.LEAVES.keys().find(kind))
	kind_option.item_selected.connect(_on_condition_kind_selected.bind(index))
	row.add_child(kind_option)

	var name_field := LineEdit.new()
	name_field.placeholder_text = "name"
	name_field.text = str(leaf.get(kind, ""))
	name_field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_field.text_changed.connect(_on_condition_name_changed.bind(index))
	row.add_child(name_field)

	if kind == "var":
		var op_option := OptionButton.new()
		for op in EventCondition.OPERATORS:
			op_option.add_item(op)
		op_option.select(EventCondition.OPERATORS.find(str(leaf.get("op", "=="))))
		op_option.item_selected.connect(_on_condition_op_selected.bind(index))
		row.add_child(op_option)

		var value_field := LineEdit.new()
		value_field.placeholder_text = "value"
		value_field.text = str(leaf.get("value", ""))
		value_field.custom_minimum_size = Vector2(56, 0)
		value_field.text_changed.connect(_on_condition_value_changed.bind(index))
		row.add_child(value_field)
	else:
		var is_check := CheckBox.new()
		is_check.text = "is"
		is_check.button_pressed = bool(leaf.get("is", true))
		is_check.toggled.connect(_on_condition_is_toggled.bind(index))
		row.add_child(is_check)

	row.add_child(_make_remove_condition_button(index))
	return row

func _make_remove_condition_button(index: int) -> Button:
	var button := Button.new()
	button.text = "x"
	button.tooltip_text = "Remove this condition."
	button.pressed.connect(_on_remove_condition.bind(index))
	return button

## The one leaf key [param entry] tests, or "" if it is not a single-leaf entry this
## form can edit - a branch ([code]all[/code]/[code]any[/code]/[code]not[/code]) or a
## leaf naming more than one test.
func _condition_kind(entry: Dictionary) -> String:
	var kind := ""
	for key in EventCondition.LEAVES:
		if entry.has(key):
			if kind != "":
				return ""
			kind = str(key)
	return kind

func _on_condition_kind_selected(selected: int, index: int) -> void:
	if not _live():
		return

	var conditions: Array = _current_page_dict().get("conditions", [])
	if index < 0 or index >= conditions.size():
		return

	var old_leaf: Dictionary = conditions[index]
	var old_kind := _condition_kind(old_leaf)
	var new_kind := str(EventCondition.LEAVES.keys()[selected])
	conditions[index] = {new_kind: old_leaf.get(old_kind, "")}
	_mark_dirty()
	_refresh_conditions()

func _on_condition_name_changed(text: String, index: int) -> void:
	if not _live():
		return

	var conditions: Array = _current_page_dict().get("conditions", [])
	if index < 0 or index >= conditions.size():
		return

	var leaf: Dictionary = conditions[index]
	var kind := _condition_kind(leaf)
	if kind == "":
		return

	leaf[kind] = text
	_mark_dirty()

func _on_condition_op_selected(selected: int, index: int) -> void:
	if not _live():
		return

	var conditions: Array = _current_page_dict().get("conditions", [])
	if index < 0 or index >= conditions.size():
		return

	(conditions[index] as Dictionary)["op"] = EventCondition.OPERATORS[selected]
	_mark_dirty()

func _on_condition_value_changed(text: String, index: int) -> void:
	if not _live():
		return

	var conditions: Array = _current_page_dict().get("conditions", [])
	if index < 0 or index >= conditions.size():
		return

	(conditions[index] as Dictionary)["value"] = _coerce_condition_value(text)
	_mark_dirty()

## A [LineEdit] only ever hands back a string, but [code]value[/code] wants whatever
## type the variable actually holds - the same coercion [method GraphDocument._read_args]
## already does for a node's own arguments, done here for a condition's.
func _coerce_condition_value(text: String) -> Variant:
	if text == "true":
		return true
	if text == "false":
		return false
	if text.is_valid_float():
		return float(text) if text.contains(".") else int(text)
	return text

func _on_condition_is_toggled(pressed: bool, index: int) -> void:
	if not _live():
		return

	var conditions: Array = _current_page_dict().get("conditions", [])
	if index < 0 or index >= conditions.size():
		return

	(conditions[index] as Dictionary)["is"] = pressed
	_mark_dirty()

func _on_add_condition() -> void:
	if not _live():
		return

	var conditions: Array = _current_page_dict().get("conditions", [])
	conditions.append({"flag": ""})
	_refresh_conditions()
	_refresh_page_selector()
	_mark_dirty()

func _on_remove_condition(index: int) -> void:
	if not _live():
		return

	var conditions: Array = _current_page_dict().get("conditions", [])
	if index < 0 or index >= conditions.size():
		return

	conditions.remove_at(index)
	_refresh_conditions()
	_refresh_page_selector()
	_mark_dirty()

# --- Add-command picker ---------------------------------------------------------
#
# The type-to-search replacement for a plain "Add Node" button (event-pages.md §4.1:
# "no UI for choosing a command"). [constant EventCommand.COMMANDS] is the one list -
# nothing here names a command twice - filtered live as the search box changes and
# read back into a new node the same way [method _spawn_node] always placed one.

## Builds [member _command_picker] once, at panel construction - see [method _bind]
## for how it is found again after a script reload.
func _build_command_picker() -> PopupPanel:
	_command_picker = PopupPanel.new()
	_command_picker.name = "CommandPicker"

	var box := VBoxContainer.new()
	box.name = "Box"
	_command_picker.add_child(box)

	_command_search = LineEdit.new()
	_command_search.name = "CommandSearch"
	_command_search.placeholder_text = "Search commands..."
	_command_search.custom_minimum_size = Vector2(280, 0)
	_command_search.text_changed.connect(_on_command_search_changed)
	_command_search.gui_input.connect(_on_command_search_gui_input)
	box.add_child(_command_search)

	_command_list = ItemList.new()
	_command_list.name = "CommandList"
	_command_list.custom_minimum_size = Vector2(280, 240)
	_command_list.item_activated.connect(_on_command_picked)
	box.add_child(_command_list)

	return _command_picker

## The list-and-confirm popup [method _on_find_orphaned_events] pops up, naming what it
## found before anything is moved - the same "show, then ask" shape [ConfirmationDialog]
## exists for, since archiving is a file move an author cannot undo from inside the
## editor.
func _build_orphan_dialog() -> ConfirmationDialog:
	_orphan_dialog = ConfirmationDialog.new()
	_orphan_dialog.name = "OrphanDialog"
	_orphan_dialog.title = "Archive Orphaned Events"
	_orphan_dialog.min_size = Vector2(360, 260)
	_orphan_dialog.confirmed.connect(_on_orphan_dialog_confirmed)

	_orphan_list = ItemList.new()
	_orphan_list.name = "OrphanList"
	_orphan_list.custom_minimum_size = Vector2(340, 200)
	_orphan_dialog.add_child(_orphan_list)

	return _orphan_dialog

func _open_command_picker() -> void:
	if not _live():
		return

	_spawn_position = Vector2.INF
	_command_search.text = ""
	_refresh_command_list()
	_command_picker.popup_centered(Vector2i(320, 320))
	_command_search.grab_focus.call_deferred()

## Every command the picker offers, blank-command placeholder first, alphabetical
## after. [constant EventCommand.START_COMMAND] never appears - it is not something an
## author adds; [method _ensure_start_node] is the only thing that ever places one.
func _command_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = [
		{"name": "", "label": "(no command)", "blurb": "A blank node, command chosen later."},
	]

	var names := EventCommand.definitions().keys()
	names.sort()
	for name: Variant in names:
		if str(name) == EventCommand.START_COMMAND:
			continue
		entries.append({"name": str(name), "label": str(name),
			"blurb": EventCommand.description(str(name))})

	return entries

## [param query]'s matches, ranked name-prefix first, then name-contains, then
## blurb-contains, alphabetical within each tier - so typing "mov" surfaces "move_to"
## and "move_by" before a command that only mentions moving in its blurb.
func _filtered_command_entries(query: String) -> Array[Dictionary]:
	var trimmed := query.strip_edges()
	if trimmed == "":
		return _command_entries()

	var q := trimmed.to_lower()
	var prefix: Array[Dictionary] = []
	var name_hit: Array[Dictionary] = []
	var blurb_hit: Array[Dictionary] = []

	for entry in _command_entries():
		var name: String = entry["name"]
		if name == "":
			continue
		var lname := name.to_lower()
		if lname.begins_with(q):
			prefix.append(entry)
		elif lname.contains(q):
			name_hit.append(entry)
		elif str(entry["blurb"]).to_lower().contains(q):
			blurb_hit.append(entry)

	var by_name := func(a: Dictionary, b: Dictionary) -> bool:
		return str(a["name"]) < str(b["name"])
	prefix.sort_custom(by_name)
	name_hit.sort_custom(by_name)
	blurb_hit.sort_custom(by_name)

	var out: Array[Dictionary] = []
	out.append_array(prefix)
	out.append_array(name_hit)
	out.append_array(blurb_hit)
	return out

func _refresh_command_list(query: String = "") -> void:
	_command_list.clear()
	for entry in _filtered_command_entries(query):
		var index := _command_list.add_item("%s - %s" % [entry["label"], entry["blurb"]])
		_command_list.set_item_metadata(index, entry["name"])
		_command_list.set_item_tooltip(index, str(entry["blurb"]))

	if _command_list.item_count > 0:
		_command_list.select(0)

func _on_command_search_changed(text: String) -> void:
	_refresh_command_list(text)

## Arrow keys and Enter reach [member _command_list] from here rather than from the
## list itself, since focus stays in the search field the whole time an author types -
## moving it to the list on every keystroke would fight the text cursor.
func _on_command_search_gui_input(event: InputEvent) -> void:
	if not (event is InputEventKey) or not (event as InputEventKey).pressed:
		return

	var key := (event as InputEventKey).keycode
	match key:
		KEY_DOWN:
			_move_command_selection(1)
			_command_search.accept_event()
		KEY_UP:
			_move_command_selection(-1)
			_command_search.accept_event()
		KEY_ENTER, KEY_KP_ENTER:
			_activate_selected_command()
			_command_search.accept_event()
		KEY_ESCAPE:
			_command_picker.hide()
			_command_search.accept_event()

func _move_command_selection(delta: int) -> void:
	if _command_list.item_count == 0:
		return

	var selected := _command_list.get_selected_items()
	var current := selected[0] if not selected.is_empty() else -1
	var next := clampi(current + delta, 0, _command_list.item_count - 1)
	_command_list.select(next)
	_command_list.ensure_current_is_visible()

func _activate_selected_command() -> void:
	var selected := _command_list.get_selected_items()
	if not selected.is_empty():
		_on_command_picked(selected[0])

func _on_command_picked(index: int) -> void:
	if index < 0 or index >= _command_list.item_count:
		return

	var command := str(_command_list.get_item_metadata(index))
	_command_picker.hide()
	_spawn_node(command, _spawn_position)
	_spawn_position = Vector2.INF

# --- Graph nodes --------------------------------------------------------------

## Builds an [EventGraphNode] for [param node] and wires its
## [signal EventGraphNode.changed] to mark this document dirty - the one thing every
## construction site needs done alongside creating the node. Everything about what a
## node looks like and how its fields are edited lives on that class now; this panel
## only owns the document (which page, which array) and the canvas (wiring,
## selection, layout) - see [method _ensure_start_node] for the one node every graph
## is guaranteed to have.
func _make_graph_node(node: Dictionary) -> EventGraphNode:
	var graph_node := EventGraphNode.create(node)
	graph_node.changed.connect(_mark_dirty)
	return graph_node

# --- Reading the graph back ---------------------------------------------------

## The document as it stands on screen, start node first and the rest in the order
## they were created - see [method EventGraphNode.create]'s docstring on why the
## start node is never something an author reorders by hand.
func _serialize() -> Array[Dictionary]:
	# Connections are held by node name and port; targets are written as ids. Building
	# the map once keeps _serialize() linear rather than rescanning per port.
	var targets := {}
	for connection in _graph.get_connection_list():
		targets["%s:%d" % [connection["from_node"], connection["from_port"]]] = \
			_id_of(_graph.get_node_or_null(NodePath(connection["to_node"])))

	var nodes: Array[Dictionary] = []
	for graph_node in _graph_nodes():
		var outputs: Array[Dictionary] = []
		var rows := graph_node.output_rows()
		for i in rows.size():
			outputs.append({
				"flow": graph_node.row_flow(rows[i]),
				"target": targets.get("%s:%d" % [graph_node.name, i], ""),
			})

		var entry := graph_node.to_entry(outputs)

		if graph_node.is_start():
			nodes.push_front(entry)
		else:
			nodes.append(entry)

	return nodes

func _graph_nodes() -> Array[EventGraphNode]:
	var nodes: Array[EventGraphNode] = []
	for child in _graph.get_children():
		if child is EventGraphNode:
			nodes.append(child)
	return nodes

func _id_of(graph_node: Node) -> String:
	return (graph_node as EventGraphNode).id if graph_node is EventGraphNode else ""

## True for a [GraphNode] built from a [constant EventCommand.START_COMMAND] node.
func _is_start_node(graph_node: GraphNode) -> bool:
	return graph_node is EventGraphNode and (graph_node as EventGraphNode).is_start()

func _node_by_id(id: String) -> GraphNode:
	for graph_node in _graph_nodes():
		if _id_of(graph_node) == id:
			return graph_node
	return null

func _used_ids() -> Dictionary:
	var ids := {}
	for graph_node in _graph_nodes():
		ids[_id_of(graph_node)] = true
	return ids

# --- Editing ------------------------------------------------------------------

## Starting args for a freshly spawned node, command by command - just enough to open
## on something an author would plausibly want rather than a wall of blank fields.
## Every command not named here still opens to [method Doc.default_node]'s plain
## [code]{}[/code], same as always.
func _default_args_for(command: String) -> Dictionary:
	match command:
		"move_by":
			# North, one step, at EventGraphNode's own "Normal" speed preset - a step
			# in some direction at some speed is the whole shape of this command, so
			# it opens already saying one instead of empty.
			return {"cells": [0, 0, -1], "speed": EventGraphNode.normal_speed()}
		_:
			return {}

## Places a new node with [param command] - "" for the blank node the picker also
## offers - at [param at], or [constant ADD_POSITION]'s own incrementing default when
## [param at] is [constant Vector2.INF] (the toolbar's "Add Command", which has no
## click position to land on). [method _on_popup_request] passes a real one. Then the
## same tail every edit that can leave a graph without a start node runs:
## [method _ensure_start_node] repairs it, then dirty and re-validate.
func _spawn_node(command: String, at: Vector2 = Vector2.INF) -> void:
	if not _live():
		return

	var id := Doc.generate_id(_used_ids())
	var position := at
	if position == Vector2.INF:
		position = ADD_POSITION + ADD_STEP * _added + _graph.scroll_offset / _graph.zoom
		_added += 1

	var node := Doc.default_node(id, position)
	node["command"] = command
	node["args"] = _default_args_for(command)

	# Found before the new node exists, so it is never a candidate for its own source.
	var chain_from := _chain_from_node()

	var graph_node := _make_graph_node(node)
	_graph.add_child(graph_node)

	if chain_from != null:
		_auto_connect(chain_from, graph_node)

	# Selected so the next "Add Command" chains from this one in turn - clicking an
	# earlier node first overrides that, which is what lets an author branch instead
	# of only ever extending the last thing they added.
	for other in _graph_nodes():
		other.selected = other == graph_node
	_last_spawned = graph_node

	# The first node in what was an empty (route-only) page's graph turns it into a real
	# graph, which needs its start node - see _ensure_start_node()'s force parameter.
	_ensure_start_node()
	_mark_dirty()
	_validate()

## The node a new one should chain from: the graph's own single selected node if
## exactly one is selected, otherwise [member _last_spawned], otherwise the start
## node - the only node "most recent" can mean before a first command exists.
func _chain_from_node() -> EventGraphNode:
	var selected := _selected_graph_node()
	if selected != null:
		return selected
	if is_instance_valid(_last_spawned):
		return _last_spawned
	for graph_node in _graph_nodes():
		if graph_node.is_start():
			return graph_node
	return null

## The graph's own selected node, if exactly one is. Two or more selected reads as
## none: which one a chain should follow from is genuinely ambiguous then, so nothing
## is auto-wired rather than guessing.
func _selected_graph_node() -> EventGraphNode:
	var found: EventGraphNode = null
	for graph_node in _graph_nodes():
		if graph_node.selected:
			if found != null:
				return null
			found = graph_node
	return found

## Connects [param from]'s first output with nothing already wired from it to
## [param to]'s input - so a chain of "Add Command" presses reads as the chain of
## steps it usually is, the same shape every hand-typed demo file already chains its
## nodes in, without an author dragging a wire for each one. Does nothing if every
## output [param from] has is already spoken for.
func _auto_connect(from: EventGraphNode, to: EventGraphNode) -> void:
	var rows := from.output_rows()
	if rows.is_empty():
		return

	var wired := {}
	for connection in _graph.get_connection_list():
		if connection["from_node"] == from.name:
			wired[int(connection["from_port"])] = true

	for i in rows.size():
		if not wired.has(i):
			_graph.connect_node(from.name, i, to.name, 0)
			return

## Adds a [constant EventCommand.START_COMMAND] node if [member _graph] does not already
## have one. Every graph with anything in it has exactly one - not a button an author
## presses, a fact this panel maintains - so a graph that loaded without one (a hand-typed
## file, an older one from before question 47) is given one here instead of being left to
## fail validation until someone notices.
##
## [b]An empty graph stays empty unless [param force] is true.[/b] A page may legitimately
## have no graph at all - event-pages.md §2's route-only decoration, logic-free by design -
## and loading one should not hand it a start node it never asked for. [param force] is
## for [method _new_document]: a brand new document is presumed to be about to become a
## real graph, so it gets its start node up front rather than waiting for a first "Add
## Node" to trigger the repair.
##
## Returns whether it had to add one, so callers that run this against a freshly loaded
## page know whether that page now differs from what is on disk.
func _ensure_start_node(force: bool = false) -> bool:
	var existing := _graph_nodes()
	for graph_node in existing:
		if _is_start_node(graph_node):
			return false
	if existing.is_empty() and not force:
		return false

	# "" always - the start node is the one node allowed a blank id (question 47
	# follow-up), so it never needs one generated.
	var node := Doc.default_node("", _START_POSITION)
	node["command"] = EventCommand.START_COMMAND

	_graph.add_child(_make_graph_node(node))
	return true

func _on_node_title_changed(text: String, graph_node: GraphNode) -> void:
	if not _live():
		return

	graph_node.title = text if text != "" else Doc.DEFAULT_TITLE
	_mark_dirty()

func _on_connection_request(from_node: StringName, from_port: int, to_node: StringName,
		to_port: int) -> void:
	if not _live():
		return

	# One target per port: re-wiring a port replaces what was there rather than
	# fanning out, which the file has no way to express.
	for connection in _graph.get_connection_list():
		if connection["from_node"] == from_node and connection["from_port"] == from_port:
			_graph.disconnect_node(from_node, from_port, connection["to_node"],
				connection["to_port"])

	_graph.connect_node(from_node, from_port, to_node, to_port)
	_mark_dirty()
	_validate()

func _on_disconnection_request(from_node: StringName, from_port: int,
		to_node: StringName, to_port: int) -> void:
	if not _live():
		return

	_graph.disconnect_node(from_node, from_port, to_node, to_port)
	_mark_dirty()
	_validate()

func _on_delete_nodes_request(names: Array[StringName]) -> void:
	if not _live():
		return

	for node_name in names:
		var graph_node := _graph.get_node_or_null(NodePath(node_name)) as GraphNode
		if graph_node == null:
			continue

		# The start node is not deletable: every graph has exactly one, and Delete/Select
		# All + Delete should not be able to leave a graph without it. Selecting it alongside
		# other nodes still deletes the rest - only the start node itself is skipped.
		if _is_start_node(graph_node):
			continue

		# Ports pointing at it go slack rather than disappearing: the port is part of
		# the owning node's shape, and dropping it would renumber its siblings.
		for connection in _graph.get_connection_list():
			if connection["from_node"] == node_name or connection["to_node"] == node_name:
				_graph.disconnect_node(connection["from_node"], connection["from_port"],
					connection["to_node"], connection["to_port"])

		_graph.remove_child(graph_node)
		graph_node.queue_free()

	_mark_dirty()
	_validate()

## Copies the selected nodes, ports and all. Their targets are dropped: a duplicate
## that inherited them would silently double every path leading out of the original.
##
## The start node is excluded even when selected: a graph has exactly one, so duplicating
## it would immediately fail validation with two rather than do anything useful.
func _on_duplicate_nodes_request() -> void:
	if not _live():
		return

	var ids := _used_ids()
	var copies: Array[GraphNode] = []

	for node in _serialize():
		var source := _node_by_id(node["id"])
		if source == null or not source.selected or _is_start_node(source):
			continue

		var id := Doc.generate_id(ids)
		ids[id] = true

		node["id"] = id
		node["position"] = source.position_offset + ADD_STEP
		for output in node["outputs"]:
			output["target"] = ""

		copies.append(_make_graph_node(node))

	for graph_node in _graph.get_children():
		if graph_node is GraphNode:
			graph_node.selected = false

	for copy in copies:
		_graph.add_child(copy)
		copy.selected = true

	if not copies.is_empty():
		_mark_dirty()

## Right-click (or the context-menu key) on the canvas - opens the same picker "Add
## Command" does, rather than dropping a bare node the way this used to, since a
## command still has to be chosen from the picker or the search either way.
func _on_popup_request(at_position: Vector2) -> void:
	if not _live():
		return

	# at_position is in the control's own space; the offset and zoom turn it back
	# into graph coordinates, same conversion [method _spawn_node]'s own default
	# position already does for [constant ADD_POSITION].
	_spawn_position = (at_position + _graph.scroll_offset) / _graph.zoom

	_command_search.text = ""
	_refresh_command_list()
	_command_picker.popup(Rect2i(Vector2i(get_global_mouse_position()), Vector2i(320, 320)))
	_command_search.grab_focus.call_deferred()

## Lays the nodes out in a grid, in document order. A way back from a graph that has
## been dragged into a pile, or from a hand-written file where nothing has a position.
func _arrange() -> void:
	if not _live():
		return

	var columns := maxi(1, int(ceil(sqrt(float(_graph_nodes().size())))))
	var index := 0
	for graph_node in _graph_nodes():
		graph_node.position_offset = ADD_POSITION + Vector2(
			(index % columns) * 260.0, (index / columns) * 180.0)
		index += 1

	_mark_dirty()

# --- Document -----------------------------------------------------------------

func _new_document() -> void:
	if not _live():
		return

	_path = ""
	_wrapped = false
	_doc = EventDoc.default_document()
	_current_page = 0
	_set_editing_route(false)
	_clear()
	_ensure_start_node(true)
	_refresh_page_selector()
	_load_page_inspector(0)
	_dirty = false
	_results.clear()
	_set_status("New graph - Save to choose a path.", _status_color(true))
	_refresh_title()

func _clear() -> void:
	for graph_node in _graph_nodes():
		_graph.remove_child(graph_node)
		graph_node.queue_free()

	_graph.clear_connections()
	_added = 0
	_last_spawned = null

func _open() -> void:
	if not _live():
		return

	if _path != "":
		_file_dialog.current_path = _path
	_file_dialog.popup_file_dialog()

func _load(path: String) -> void:
	if not _live():
		return

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		_set_status("Could not read %s: %s" % [
			path, error_string(FileAccess.get_open_error())], _status_color(false))
		return

	var text := file.get_as_text()
	_wrapped = typeof(JSON.parse_string(text)) == TYPE_DICTIONARY
	_doc = EventDoc.parse(text)

	_path = path
	_set_editing_route(false)
	# A repair - the file loaded without a start node and this added one - leaves the
	# buffer differing from disk, so it must not be reported clean.
	var repaired := _load_page(0)
	_refresh_page_selector()

	_dirty = repaired
	_refresh_title()
	_remember_path()

	var pages: Array = _doc["pages"]
	var total := 0
	for page in pages:
		total += ((page as Dictionary)["graph"] as Array).size()
	_report(_doc["problems"], "%d page(s), %d node(s) loaded." % [pages.size(), total])

## Wires up a freshly built graph. Separate from node creation because a target may
## name a node that comes later in the file.
##
## Matched by flow name, not by position in [param node]'s authored [code]outputs[/code]
## array - [method _make_graph_node] built this node's ports from
## [method EventCommand.flows_of], in that order, which need not be the order (or even
## the count) [code]outputs[/code] happened to list them in. A flow the node's ports
## don't have is simply not wired, which is what an [code]if[/code] missing a
## [code]"false"[/code] entry should do rather than silently wiring the wrong port.
func _apply_connections(nodes: Array[Dictionary]) -> void:
	for node in nodes:
		var from := _node_by_id(node["id"])
		if from == null:
			continue

		var target_by_flow := {}
		for output in (node.get("outputs", []) as Array):
			var entry: Dictionary = output
			target_by_flow[str(entry.get("flow", ""))] = str(entry.get("target", ""))

		var flows := EventCommand.flows_of(node)
		for i in flows.size():
			var target: String = target_by_flow.get(flows[i], "")
			if target == "":
				continue

			var to := _node_by_id(target)
			if to != null:
				_graph.connect_node(from.name, i, to.name, 0)

## "route" while [member _editing_route], otherwise "graph" - the key
## [method _load_page] and [method _commit_current_page] read and write, so a route
## and a graph are the same kind of array read and written through the same code, just
## under a different name.
func _target_key() -> String:
	return "route" if _editing_route else "graph"

## [param page]'s [param key] as a list of nodes this panel can build a graph from.
##
## [b]Copied entry by entry into a typed array rather than assigned across.[/b]
## GDScript refuses an untyped [Array] assigned to an [code]Array[Dictionary][/code]
## at run time, and the pages reaching here do not all carry a typed one:
## [method EventDocument.default_page]'s literal is untyped, and the bare-array
## document path only ever replaces that default's [code]graph[/code] - so every
## single-page file (which is most of them) has an untyped [code]route[/code] sitting
## there waiting to abort the load half way through, after the button has already
## recoloured and before the graph is cleared.
##
## Anything that is not a list of nodes reads as no nodes: a page whose route is still
## event-pages.md §3's [code]{mode, loop, waypoints}[/code] object opens as an empty
## route to author rather than erroring, which is the same "repair, never reject" rule
## [method EventDocument.parse] follows.
func _nodes_of(page: Variant, key: String) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	if typeof(page) != TYPE_DICTIONARY:
		return nodes

	var raw: Variant = (page as Dictionary).get(key, [])
	if typeof(raw) != TYPE_ARRAY:
		return nodes

	for entry in raw as Array:
		if entry is Dictionary:
			nodes.append(entry)
	return nodes

## Replaces whatever the [GraphEdit] shows with page [param index]'s [method _target_key]
## array. Does not touch [member _dirty] itself - opening a page you are not editing is
## not an edit - but returns whether [method _ensure_start_node] had to add one, which is.
func _load_page(index: int) -> bool:
	var pages: Array = _doc.get("pages", [])
	var nodes: Array[Dictionary] = []
	if index >= 0 and index < pages.size():
		nodes = _nodes_of(pages[index], _target_key())

	_current_page = index
	_clear()
	for node in nodes:
		_graph.add_child(_make_graph_node(node))
	_apply_connections(nodes)
	_load_page_inspector(index)

	# Back to the origin regardless of where the view was left - loading a different
	# array (a different page, or the graph/route swap) with the scroll position of
	# whatever was on screen before is how a reload can look like nothing happened:
	# the new content is there, just off screen.
	_graph.scroll_offset = Vector2.ZERO

	# Forced while editing a route: an author who just pressed "Edit Route" asked to
	# see and edit it, so an empty one should show up as a graph with a start node
	# ready to build on, not a blank canvas indistinguishable from the switch having
	# done nothing. A graph, unforced, may still legitimately have no start node at
	# all - event-pages.md §2's route-only decoration - see this method's docstring.
	return _ensure_start_node(_editing_route)

## Writes the graph on screen back into [member _doc] before it is abandoned for
## another page, another view of the same page, or for saving - the file (here,
## [member _doc]) stays the source of truth, and the [GraphEdit] is a view onto one
## array of one page at a time.
func _commit_current_page() -> void:
	var pages: Array = _doc.get("pages", [])
	if _current_page < 0 or _current_page >= pages.size():
		return
	(pages[_current_page] as Dictionary)[_target_key()] = _serialize()

## Rebuilds the dropdown from [member _doc]'s pages, with a one-line condition summary
## per entry (event-pages.md §4.1's page bar, minus reorder/add/duplicate/delete - those
## stay deferred). Hidden for the ordinary one-page case so the four plain-array examples
## and any new document do not show a selector with nothing to select.
func _refresh_page_selector() -> void:
	if not is_instance_valid(_page_selector):
		return

	_page_selector.clear()
	var pages: Array = _doc.get("pages", [])
	for i in pages.size():
		var conditions: Array = (pages[i] as Dictionary).get("conditions", [])
		var summary := "no conditions" if conditions.is_empty() \
			else "%d condition(s)" % conditions.size()
		_page_selector.add_item("Page %d (%s)" % [i + 1, summary], i)

	_page_selector.visible = pages.size() > 1
	if _current_page < pages.size():
		_page_selector.select(_current_page)

func _on_page_selected(index: int) -> void:
	if not _live() or index == _current_page:
		return

	_commit_current_page()
	# A repair here means this page loaded without a start node and now has one, which the
	# saved file does not - true dirt, not just "looked at a different page".
	if _load_page(index):
		_mark_dirty()
	_page_selector.select(index)
	_validate()

func _reload() -> void:
	if _path == "" or not _live():
		return
	_load(_path)

func _save() -> void:
	if not _live():
		return

	if _path == "":
		# Nowhere to write yet - reuse the open dialog in save mode for one round.
		_file_dialog.file_mode = EditorFileDialog.FILE_MODE_SAVE_FILE
		_file_dialog.file_selected.disconnect(_load)
		_file_dialog.file_selected.connect(_save_as, CONNECT_ONE_SHOT)
		_file_dialog.popup_file_dialog()
		return

	var file := FileAccess.open(_path, FileAccess.WRITE)
	if file == null:
		_set_status("Could not write %s: %s" % [
			_path, error_string(FileAccess.get_open_error())], _status_color(false))
		return

	_commit_current_page()

	# A bare-array file stays a bare array: EventDoc.stringify() always writes the
	# {format, id, pages: []} wrapper, and saving through it would silently upgrade every
	# plain-array example the moment someone opened it here and hit Save.
	var text: String = EventDoc.stringify(_doc) if _wrapped \
		else Doc.stringify((_doc["pages"][0] as Dictionary).get("graph", []))

	file.store_string(text)
	file.close()

	_dirty = false
	_refresh_title()
	# Let the FileSystem dock notice the write instead of showing a stale file.
	EditorInterface.get_resource_filesystem().update_file(_path)
	_validate()

func _save_as(path: String) -> void:
	if not _live():
		return

	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.file_selected.connect(_load)

	_path = path
	_remember_path()
	_save()

func _remember_path() -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		METADATA_SECTION, METADATA_PATH_KEY, _path)

func _mark_dirty() -> void:
	_dirty = true
	_refresh_title()

func _refresh_title() -> void:
	if not is_instance_valid(_title):
		return

	var label := _path if _path != "" else "(unsaved)"
	if _editing_route:
		label += " (route)"
	_title.text = ("* " if _dirty else "") + label
	_title.tooltip_text = label

	var save_disabled := not _dirty and _path != ""
	if is_instance_valid(_file_menu):
		var popup := _file_menu.get_popup()
		popup.set_item_disabled(popup.get_item_index(FileAction.SAVE), save_disabled)
		popup.set_item_disabled(popup.get_item_index(FileAction.RELOAD), _path == "")
	if is_instance_valid(_save_icon_button):
		_save_icon_button.disabled = save_disabled

# --- Validation ---------------------------------------------------------------

func _validate() -> void:
	if not _live():
		return

	var nodes := _serialize()
	var problems := Doc.validate(nodes)
	problems.append_array(EventCommand.validate_reachability(nodes))
	_report(problems, "%d node(s), %d connection(s), graph is consistent."
		% [nodes.size(), _graph.get_connection_list().size()])

## Fills the result list from [param problems], or reports [param clean] when there are
## none. Each problem naming a node in quotes becomes clickable - see
## [method _on_result_selected].
func _report(problems: Array, clean: String) -> void:
	_results.clear()

	for problem in problems:
		var text := str(problem)
		var index := _results.add_item(text)
		_results.set_item_tooltip(index, text)
		_results.set_item_metadata(index, _referenced_id(text))

	if problems.is_empty():
		_set_status(clean, _status_color(true))
		return

	_set_status("%d problem%s." % [problems.size(), "" if problems.size() == 1 else "s"],
		_status_color(false))

## The first quoted id in [param message] that names a node in the graph, or "".
## Cheaper than threading an id through every message, and the ids are what the
## messages quote anyway.
func _referenced_id(message: String) -> String:
	var parts := message.split("\"")
	# Odd indices are the quoted runs.
	var i := 1
	while i < parts.size():
		if _node_by_id(parts[i]) != null:
			return parts[i]
		i += 2
	return ""

func _on_result_selected(index: int) -> void:
	if not _live():
		return

	var id := str(_results.get_item_metadata(index))
	if id == "":
		# A problem with no node behind it - a parse error, or a top-level shape
		# complaint. Nothing on the canvas to jump to.
		return

	var graph_node := _node_by_id(id)
	if graph_node == null:
		return

	for other in _graph_nodes():
		other.selected = other == graph_node

	# Centre the offending node rather than only highlighting it - on a graph wider
	# than the panel it may well be off screen.
	_graph.scroll_offset = graph_node.position_offset * _graph.zoom \
		- (_graph.size - graph_node.size * _graph.zoom) * 0.5

# --- Toolbar dropdowns ---------------------------------------------------------

func _on_file_menu_id_pressed(id: int) -> void:
	match id:
		FileAction.NEW: _new_document()
		FileAction.OPEN: _open()
		FileAction.RELOAD: _reload()
		FileAction.SAVE: _save()

func _on_graph_menu_id_pressed(id: int) -> void:
	match id:
		GraphAction.ADD_COMMAND: _open_command_picker()
		GraphAction.ARRANGE: _arrange()
		GraphAction.VALIDATE: _validate()
		GraphAction.VIEW_JSON: _view_json()

func _on_actor_menu_id_pressed(id: int) -> void:
	match id:
		ActorAction.LOAD_EVENT: _on_load_actor_event()
		ActorAction.DELETE_ACTOR: _on_delete_actor()
		ActorAction.FIND_ORPHANS: _on_find_orphaned_events()

# --- Actor wiring ---------------------------------------------------------------
#
# The graph editor has no scene tree of its own - these read the Godot editor's
# selection instead, so "the actor" always means whatever is selected in the Scene
# dock, the same way [method EditorInterface.get_selection] drives the inspector.

## The [Actor] the selection means: the selected node itself, or the first [Actor]
## found under it. The "under it" half is what lets an author select an actor's
## placement root - [method ActorNaming.placement_root], the node the Scene dock
## actually shows a name for - and have it mean the [Actor] inside, the same node
## [member Actor.actor_id] and this file's other actor-facing tools already agree on.
func _selected_actor() -> Actor:
	var selection := EditorInterface.get_selection().get_selected_nodes()
	if selection.is_empty():
		return null

	var node: Node = selection[0]
	if node is Actor:
		return node as Actor

	var found := ActorNaming.actors_under(node)
	return found[0] if not found.is_empty() else null

## The [GameEvent] the selection means, for a bodiless region trigger - one with no
## [Actor] at all, so [method _selected_actor] finds nothing and [method
## find_or_create_game_event_for_actor] has no actor to seek a sibling beside. Only
## consulted when [method _selected_actor] comes back null: an actor's own sibling
## [GameEvent] stays reached through that path, which is also where a missing one gets
## created, so a placement with both is not ambiguous about which this returns.
func _selected_game_event() -> GameEvent:
	var selection := EditorInterface.get_selection().get_selected_nodes()
	if selection.is_empty():
		return null

	var node: Node = selection[0]
	return _first_game_event_under(node)

static func _first_game_event_under(node: Node) -> GameEvent:
	if node is GameEvent:
		return node as GameEvent
	for child in node.get_children():
		var found := _first_game_event_under(child)
		if found != null:
			return found
	return null

## The folder a map's event files live in: one per map, named for the edited scene's
## own file - stage-c-plan.md's [code]res://events/<map_id>/<event_id>.event.json[/code]
## layout. Falls back to "map" for a scene with no file yet, so the helpers built on
## this still have somewhere to point rather than failing outright.
func _map_event_dir(map_root: Node) -> String:
	var scene_path := map_root.scene_file_path if map_root != null else ""
	var map_id := scene_path.get_file().get_basename() if scene_path != "" else "map"
	return "res://events/%s" % map_id

## Where a newly-linked actor's or event's file goes, under [method _map_event_dir].
## [param event_id] names the file - [member Actor.actor_id] (falling back to the node
## name) for an actor, [method GameEvent.event_id] for an event.
func _default_event_path(event_id: String) -> String:
	var map_root := EditorInterface.get_edited_scene_root()
	return "%s/%s.event.json" % [_map_event_dir(map_root), event_id]

## Loads the selected actor's (or bodiless event's) file into the graph - the toolbar's
## own "Load Actor Event" menu item, which reads the editor's current selection rather
## than taking a node directly (see [method _selected_actor]). An [Actor] carries no
## document path of its own (that is [GameEvent]'s business); this finds the
## [GameEvent] sibling [method GameEvent._find_actor]'s own fallback expects, creating
## one there first if none exists yet.
##
## [b]No [Actor] in the selection at all is not a failure[/b] - a region trigger, a
## chest, anything [method GameEvent] class doc calls "a bodiless region trigger" is
## exactly a [GameEvent] with none, and [method _selected_game_event] is this button's
## way of still finding one to open.
func _on_load_actor_event() -> void:
	if not _live():
		return

	var actor := _selected_actor()
	if actor != null:
		open_or_create_game_event(find_or_create_game_event_for_actor(actor))
		return

	var event := _selected_game_event()
	if event != null:
		open_or_create_game_event(event)
		return

	_set_status(
		"Select an Actor or a GameEvent, or a node containing one, to load its event file.",
		_status_color(false))

## The [GameEvent] already sitting beside [param actor] - a sibling under the same
## parent, which is the shape [method GameEvent._find_actor]'s own fallback checks for
## an actor prefab that predates having one - or null if there is none yet.
func _sibling_game_event(actor: Actor) -> GameEvent:
	var parent := actor.get_parent() if actor != null else null
	if parent == null:
		return null
	for child in parent.get_children():
		if child is GameEvent:
			return child
	return null

## [method _sibling_game_event], creating one there if none exists yet. Named after the
## actor's own identity ([member Actor.actor_id], falling back to its node name) so its
## default event file ([method open_or_create_game_event]) keeps the name an author
## already associates with this actor, rather than every auto-created GameEvent
## defaulting to the same generic filename. Never returns null for a non-null
## [param actor]: a fresh GameEvent always lands as a sibling in the same parent.
func find_or_create_game_event_for_actor(actor: Actor) -> GameEvent:
	var existing := _sibling_game_event(actor)
	if existing != null:
		return existing

	var event := GameEvent.new()
	event.name = "GameEvent"

	var parent := actor.get_parent()
	if parent != null:
		parent.add_child(event)
		event.owner = EditorInterface.get_edited_scene_root()
		if EditorInterface.has_method("mark_scene_as_unsaved"):
			EditorInterface.mark_scene_as_unsaved()

	return event

## Opens [param event]'s document in the graph, wiring [member GameEvent.document_path]
## to a default location first if it has none, and creating an empty-but-valid file if
## nothing is there yet - so a brand new event opens straight into an empty graph
## instead of a file-not-found error.
func open_or_create_game_event(event: GameEvent) -> void:
	if not _live() or event == null:
		return

	if event.document_path == "":
		event.document_path = _default_event_path(String(event.event_id()))
		if EditorInterface.has_method("mark_scene_as_unsaved"):
			EditorInterface.mark_scene_as_unsaved()

	_open_or_create(event.document_path)

## Shared tail of both methods above: create an empty-but-valid file there if nothing
## exists yet, then load it into the graph.
func _open_or_create(path: String) -> void:
	if not FileAccess.file_exists(path):
		if not _create_empty_event_file(path):
			return
	_load(path)

## An empty [code][][/code] - the bare-array shorthand [method _load] already accepts
## for a one-page graph - written to [param path], making its parent folder first.
## Returns whether it succeeded.
func _create_empty_event_file(path: String) -> bool:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())

	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		_set_status("Could not create %s: %s" % [
			path, error_string(FileAccess.get_open_error())], _status_color(false))
		return false

	file.store_string("[]\n")
	file.close()
	EditorInterface.get_resource_filesystem().update_file(path)
	return true

## Archives the selected actor's event file (if it has one) and removes the actor's
## placement node from the edited scene.
##
## [b]A button, not a delete-notification hook.[/b] Godot gives a tool script no
## reliable "a node was deleted" signal - only [constant NOTIFICATION_PREDELETE], which
## also fires for a script reload's own teardown and for undo/redo churn, none of which
## should archive anything. An explicit button is the same trade [ActorNaming.assign_all]
## already makes for the same reason (see its docstring): predictable over automatic.
func _on_delete_actor() -> void:
	if not _live():
		return

	var actor := _selected_actor()
	if actor == null:
		_set_status("Select an Actor, or a node containing one, to delete it.",
			_status_color(false))
		return

	var archived_path := ""
	var sibling_event := _sibling_game_event(actor)
	if sibling_event != null and sibling_event.document_path != "" \
			and FileAccess.file_exists(sibling_event.document_path):
		archived_path = _archive_event_file(sibling_event.document_path)

	var node := ActorNaming.placement_root(actor)
	var node_name := node.name
	node.get_parent().remove_child(node)
	node.queue_free()

	if EditorInterface.has_method("mark_scene_as_unsaved"):
		EditorInterface.mark_scene_as_unsaved()

	var note := " Archived event to %s." % archived_path if archived_path != "" else ""
	_set_status("Deleted %s.%s" % [node_name, note], _status_color(true))

## Moves [param path] into a "removed" folder beside it - within the same map folder
## [method _default_event_path] would have written it under - named with the moment it
## was moved so a second deletion of a same-named actor never collides with the first.
## Returns where the file ended up, or "" if the move failed.
func _archive_event_file(path: String) -> String:
	var map_dir := path.get_base_dir()
	var removed_dir := map_dir.path_join("removed")
	DirAccess.make_dir_recursive_absolute(removed_dir)

	var filename := path.get_file()
	var stem := filename.trim_suffix(".event.json")
	if stem == filename:
		# Not the conventional name - still archive it, just without assuming the
		# ".event.json" suffix is there to strip.
		stem = filename.get_basename()

	var stamp := Time.get_datetime_string_from_system(false, true).replace(":", "-")
	var archived_path := removed_dir.path_join("%s_%s.event.json" % [stem, stamp])

	var error := DirAccess.rename_absolute(path, archived_path)
	if error != OK:
		_set_status("Could not archive %s: %s" % [path, error_string(error)], _status_color(false))
		return ""

	EditorInterface.get_resource_filesystem().update_file(path)
	EditorInterface.get_resource_filesystem().update_file(archived_path)
	return archived_path

## Every [code]*.event.json[/code] directly under [param dir_path] - not its "removed"
## subfolder, which holds files already dealt with, not candidates. Returns empty for a
## map with no event folder yet rather than erroring, since that is simply a map with
## nothing to orphan.
func _event_files_in(dir_path: String) -> Array[String]:
	var found: Array[String] = []
	var dir := DirAccess.open(dir_path)
	if dir == null:
		return found

	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and entry_name.ends_with(".event.json"):
			found.append(dir_path.path_join(entry_name))
		entry_name = dir.get_next()
	dir.list_dir_end()
	return found

## Every [GameEvent] under [param root], recursively - the [method
## ActorNaming.actors_under] equivalent for events, since nothing else in the project
## needs one yet.
func _game_events_under(root: Node) -> Array[GameEvent]:
	var found: Array[GameEvent] = []
	if root != null:
		_collect_game_events(root, found)
	return found

func _collect_game_events(node: Node, into: Array[GameEvent]) -> void:
	if node is GameEvent:
		into.append(node as GameEvent)
	for child in node.get_children():
		_collect_game_events(child, into)

## Finds every event file under the edited scene's map folder that no [GameEvent] in
## the scene points at, and asks - through [member _orphan_dialog] - whether to archive
## them. Nothing is moved here; [method _on_orphan_dialog_confirmed] does that, only if
## the author confirms.
func _on_find_orphaned_events() -> void:
	if not _live():
		return

	var map_root := EditorInterface.get_edited_scene_root()
	if map_root == null:
		_set_status("Open a scene to search its map for orphaned events.", _status_color(false))
		return

	var used := {}
	for event in _game_events_under(map_root):
		if event.document_path != "":
			used[event.document_path] = true

	var map_dir := _map_event_dir(map_root)
	var orphans: Array[String] = []
	for path in _event_files_in(map_dir):
		if not used.has(path):
			orphans.append(path)

	if orphans.is_empty():
		_set_status("No orphaned events under %s." % map_dir, _status_color(true))
		return

	_pending_orphans = orphans
	_orphan_list.clear()
	for path in orphans:
		_orphan_list.add_item(path.get_file())

	_orphan_dialog.dialog_text = "%d event file(s) under %s have no actor pointing at them. Archive them?" \
		% [orphans.size(), map_dir]
	_orphan_dialog.popup_centered()

## Archives every file [method _on_find_orphaned_events] listed, once the author
## confirms.
func _on_orphan_dialog_confirmed() -> void:
	var archived := 0
	for path in _pending_orphans:
		if FileAccess.file_exists(path) and _archive_event_file(path) != "":
			archived += 1

	_pending_orphans.clear()
	_set_status("Archived %d orphaned event file(s)." % archived, _status_color(true))

# --- Cross-panel navigation ---------------------------------------------------

## Preloaded rather than looked up by name: the Events dock is a fixed addon file,
## same reasoning as [constant Doc] and [constant EventDoc] above.
const EventDockScript := preload("res://addons/event_editor/event_editor_dock.gd")

func _view_json() -> void:
	if not _live() or _path == "":
		return

	var dock := _find_by_script(get_tree().root, EventDockScript)
	if dock != null:
		dock._load(_path)

## Walks the whole scene tree for a node running [param script] exactly - not by
## name, since the panel's own name ("Graph") collides with the [GraphEdit] child
## inside it, and editor dock layout is otherwise unversioned internal structure
## not worth depending on.
func _find_by_script(node: Node, script: Script) -> Node:
	if node.get_script() == script:
		return node
	for child in node.get_children():
		var found := _find_by_script(child, script)
		if found != null:
			return found
	return null

# --- Theme --------------------------------------------------------------------

func _status_color(ok: bool) -> Color:
	var theme := EditorInterface.get_editor_theme()
	return theme.get_color(&"success_color" if ok else &"error_color", &"Editor")

func _muted_color() -> Color:
	var theme := EditorInterface.get_editor_theme()
	var color := Color.WHITE
	if theme.has_color(&"font_color", &"Editor"):
		color = theme.get_color(&"font_color", &"Editor")

	color.a *= 0.6
	return color

func _set_status(text: String, color: Color) -> void:
	_status.text = text
	_status.tooltip_text = text
	_status.add_theme_color_override(&"font_color", color)
