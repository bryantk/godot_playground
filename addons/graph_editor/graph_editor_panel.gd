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

const Doc := preload("res://addons/graph_editor/graph_document.gd")
const EventDoc := preload("res://events/event_document.gd")

const METADATA_SECTION := "graph_editor"
const METADATA_PATH_KEY := "last_file"

## Name of the first row of a graph node - the one carrying the input port and the
## title field. Output rows follow it, so an output's port index is its child index
## minus one, which is what keeps ports and connections lined up.
const HEAD_ROW := "Head"
const OUT_ROW_PREFIX := "Out"

## Where a node dropped by the Add button lands, before the offset below spreads
## repeated presses out instead of stacking them.
const ADD_POSITION := Vector2(80, 80)
const ADD_STEP := Vector2(40, 30)

## Where an auto-added start node lands - left of [constant ADD_POSITION], since it is
## conventionally the leftmost node in a graph read left to right.
const _START_POSITION := Vector2(-160, 80)

## A blocking node's [member GraphNode.self_modulate] - a tint on the whole node, panel
## included, since [GraphNode] has no simpler "colour the background" knob than that.
const _BLOCKING_COLOR := Color(1.0, 0.55, 0.55)

## [constant EventCommand.START_COMMAND]'s colour, always - it overrides
## [constant _BLOCKING_COLOR] rather than combining with it, so the one node every graph
## has exactly one of stays visually distinct from an ordinary blocking command.
const _START_COLOR := Color(0.55, 1.0, 0.55)

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
var _title: Label
var _page_selector: OptionButton
var _results: ItemList
var _status: Label
var _save_button: Button
var _reload_button: Button
var _file_dialog: EditorFileDialog

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

	_graph = get_node_or_null(^"Graph") as GraphEdit
	_title = get_node_or_null(^"Title") as Label
	_page_selector = get_node_or_null(^"Toolbar/PageSelector") as OptionButton
	_results = get_node_or_null(^"Results") as ItemList
	_status = get_node_or_null(^"Status") as Label
	_save_button = get_node_or_null(^"Toolbar/Save") as Button
	_reload_button = get_node_or_null(^"Toolbar/Reload") as Button
	_file_dialog = get_node_or_null(^"FileDialog") as EditorFileDialog

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

	toolbar.add_child(_make_button("New", _new_document))
	toolbar.add_child(_make_button("Open", _open))
	_reload_button = _make_button("Reload", _reload)
	toolbar.add_child(_reload_button)
	_save_button = _make_button("Save", _save)
	toolbar.add_child(_save_button)

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

	toolbar.add_child(_make_button("Add Node", _add_node))
	toolbar.add_child(_make_button("Arrange", _arrange))
	toolbar.add_child(_make_button("Validate", _validate))

	_graph = GraphEdit.new()
	_graph.name = "Graph"
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
	_graph.popup_request.connect(_on_popup_request)
	# Dragging a node is an edit like any other, but it arrives once per drag rather
	# than once per pixel, so it is cheap to mark dirty on.
	_graph.end_node_move.connect(_mark_dirty)

	# Every output may land on an input, which is the only thing type 0 is used for.
	_graph.add_valid_connection_type(Doc.FLOW_SLOT_TYPE, 0)

	add_child(_graph)

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

# --- Graph nodes --------------------------------------------------------------

## Builds the [GraphNode] for one entry of the document. Its wiring is not applied
## here - targets are ids, which cannot be resolved until every node exists - see
## [method _apply_connections].
##
## [b]Output ports come from the command, not from [param node]'s own [code]outputs[/code].[/b]
## [method EventCommand.flows_of] is authoritative for how many ports a node has and what
## each is named - a linear command has one "next", "if" has "true"/"false", "ask" has one
## per choice - so a port is never something this panel offers to add or remove; it
## follows from choosing a command, same as the arguments it takes. There is still no UI
## for choosing a command (event-pages.md §4.1), so today that means whatever the file
## already said, or [constant EventCommand.START_COMMAND] for the one every graph is
## guaranteed to have - see [method _ensure_start_node].
func _make_graph_node(node: Dictionary) -> GraphNode:
	var id: String = node["id"]
	var graph_node := GraphNode.new()
	graph_node.name = _scene_name(id)
	graph_node.title = node.get("title", Doc.DEFAULT_TITLE)
	graph_node.position_offset = node.get("position", Vector2.ZERO)
	# The scene name is sanitised and can collide, so the id travels separately. Every
	# lookup goes through _id_of() rather than reading the name back.
	graph_node.set_meta(&"graph_id", id)
	# Everything this panel has no field for - command, args, blocking, key, and whatever
	# _unknown carries - rides along as meta rather than being dropped. This is the fix
	# for the data-loss bug: a graph opened and saved here used to keep only id, title,
	# position and outputs.
	graph_node.set_meta(&"graph_extra", _extra_of(node))

	var id_label := Label.new()
	id_label.text = id
	id_label.add_theme_color_override(&"font_color", _muted_color())
	id_label.tooltip_text = "Node id - generated, and what other nodes target."
	id_label.mouse_filter = Control.MOUSE_FILTER_PASS
	graph_node.get_titlebar_hbox().add_child(id_label)

	_add_head_row(graph_node)
	for flow in EventCommand.flows_of(node):
		_add_output_row(graph_node, flow)
	_refresh_slots(graph_node)

	# Green for the start node, always - never red, even though "start" blocks by its own
	# registry entry; red for any other blocking command, so a glance at the graph says
	# which nodes hold the runner up and which fire and carry on.
	if str(node.get("command", "")) == EventCommand.START_COMMAND:
		graph_node.self_modulate = _START_COLOR
	elif EventCommand.is_blocking(node):
		graph_node.self_modulate = _BLOCKING_COLOR
	else:
		graph_node.self_modulate = Color.WHITE

	return graph_node

## True for a [GraphNode] built from a [constant EventCommand.START_COMMAND] node - read
## from meta, since the command lives there rather than in any field this panel edits.
func _is_start_node(graph_node: GraphNode) -> bool:
	return str(_extra_of_node(graph_node).get("command", "")) == EventCommand.START_COMMAND

## The input row. Also holds the title field, so the row that has no output port is
## the one carrying the only per-node value worth editing.
func _add_head_row(graph_node: GraphNode) -> void:
	var row := HBoxContainer.new()
	row.name = HEAD_ROW

	var field := LineEdit.new()
	field.name = "TitleField"
	field.text = graph_node.title
	field.placeholder_text = Doc.DEFAULT_TITLE
	field.custom_minimum_size = Vector2(120, 0)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_changed.connect(_on_node_title_changed.bind(graph_node))
	row.add_child(field)

	graph_node.add_child(row)

## One output port: a label naming its flow, and nothing else. No type to pick, no
## button to remove it - [method _make_graph_node]'s docstring says why.
func _add_output_row(graph_node: GraphNode, flow: String) -> void:
	var row := HBoxContainer.new()
	# Numbered by the ports already present, which is also the port index this row
	# will answer to once _refresh_slots() runs.
	row.name = OUT_ROW_PREFIX + str(_output_rows(graph_node).size())
	row.set_meta(&"flow", flow)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var label := Label.new()
	label.name = "Flow"
	label.text = flow if flow != "" else "(unnamed)"
	label.add_theme_color_override(&"font_color", _muted_color())
	row.add_child(label)

	graph_node.add_child(row)

## Re-applies every slot on [param graph_node] from its rows.
##
## [GraphNode] indexes slots by child index, and numbers ports by counting the enabled
## slots before them - so with the head row at index 0, an output's port index is always
## its child index minus one. Every output is a flow port now, so there is one slot type
## and one colour rather than a per-row choice.
##
## [b]The start node has no input slot.[/b] Nothing may flow into the node execution
## begins at - that would make it reachable from somewhere else too, which is exactly
## the ambiguity a single named entry point exists to remove.
func _refresh_slots(graph_node: GraphNode) -> void:
	var has_input := not _is_start_node(graph_node)
	for i in graph_node.get_child_count():
		var row := graph_node.get_child(i)
		var is_head: bool = row.name == HEAD_ROW
		var is_output: bool = str(row.name).begins_with(OUT_ROW_PREFIX)

		graph_node.set_slot(i,
			is_head and has_input, 0, Doc.UNTYPED_COLOR,
			is_output, Doc.FLOW_SLOT_TYPE, Doc.FLOW_COLOR)

## The flow name [method _add_output_row] gave this row, for [method _serialize] to read
## back - see [method _make_graph_node]'s docstring for why a port's identity is its flow
## name rather than a stored type.
func _row_flow(row: Node) -> String:
	return row.get_meta(&"flow", "")

func _output_rows(graph_node: GraphNode) -> Array[Node]:
	var rows: Array[Node] = []
	for child in graph_node.get_children():
		if str(child.name).begins_with(OUT_ROW_PREFIX):
			rows.append(child)
	return rows

# --- Reading the graph back ---------------------------------------------------

## The document as it stands on screen, in the order the nodes were created.
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
		var rows := _output_rows(graph_node)
		for i in rows.size():
			outputs.append({
				"flow": _row_flow(rows[i]),
				"target": targets.get("%s:%d" % [graph_node.name, i], ""),
			})

		# Start from whatever this node carried that the panel has no field for, so
		# command/args/blocking/key/_unknown ride through untouched, then overwrite the
		# four the UI actually owns.
		var entry: Dictionary = _extra_of_node(graph_node).duplicate(true)
		entry["id"] = _id_of(graph_node)
		entry["title"] = graph_node.title
		entry["position"] = graph_node.position_offset
		entry["outputs"] = outputs
		nodes.append(entry)

	return nodes

func _graph_nodes() -> Array[GraphNode]:
	var nodes: Array[GraphNode] = []
	for child in _graph.get_children():
		if child is GraphNode:
			nodes.append(child)
	return nodes

func _id_of(graph_node: Node) -> String:
	if graph_node == null:
		return ""
	return graph_node.get_meta(&"graph_id", "")

## Everything in [param node] this panel has no UI for - every key besides id, title,
## position and outputs, which are the ones a [GraphNode] can actually show and edit.
func _extra_of(node: Dictionary) -> Dictionary:
	var extra: Dictionary = node.duplicate(true)
	extra.erase("id")
	extra.erase("title")
	extra.erase("position")
	extra.erase("outputs")
	return extra

func _extra_of_node(graph_node: Node) -> Dictionary:
	if graph_node == null:
		return {}
	return graph_node.get_meta(&"graph_extra", {})

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

## A scene name for [param id]. Node names cannot hold [code]. : @ / " %[/code], and
## two different ids could sanitise to the same string, so the name is for the scene
## tree and [GraphEdit] only - the id itself lives in metadata.
func _scene_name(id: String) -> String:
	var name_hint := id.validate_node_name()
	return name_hint if name_hint != "" else "Node"

# --- Editing ------------------------------------------------------------------

func _add_node() -> void:
	if not _live():
		return

	var id := Doc.generate_id(_used_ids())
	var position := ADD_POSITION + ADD_STEP * _added + _graph.scroll_offset / _graph.zoom
	_added += 1

	var graph_node := _make_graph_node(Doc.default_node(id, position))
	_graph.add_child(graph_node)
	# The first node in what was an empty (route-only) page's graph turns it into a real
	# graph, which needs its start node - see _ensure_start_node()'s force parameter.
	_ensure_start_node()
	_mark_dirty()
	_validate()

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

	# "start" when it is free, matching the worked examples, otherwise a generated id -
	# the name is cosmetic either way, since the command is what makes it the start node.
	var used := _used_ids()
	var id := "start" if not used.has("start") else Doc.generate_id(used)

	var node := Doc.default_node(id, _START_POSITION)
	node["title"] = "Start"
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

func _on_popup_request(at_position: Vector2) -> void:
	if not _live():
		return

	# Right-click drops a node where the pointer is. at_position is in the control's
	# own space, which the offset and zoom turn back into graph coordinates.
	var id := Doc.generate_id(_used_ids())
	var position := (at_position + _graph.scroll_offset) / _graph.zoom

	_graph.add_child(_make_graph_node(Doc.default_node(id, position)))
	_ensure_start_node()
	_mark_dirty()
	_validate()

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
	_clear()
	_ensure_start_node(true)
	_refresh_page_selector()
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

## Replaces whatever the [GraphEdit] shows with page [param index]'s graph. Does not
## touch [member _dirty] itself - opening a page you are not editing is not an edit -
## but returns whether [method _ensure_start_node] had to add one, which is.
func _load_page(index: int) -> bool:
	var pages: Array = _doc.get("pages", [])
	var nodes: Array[Dictionary] = []
	if index >= 0 and index < pages.size():
		nodes = (pages[index] as Dictionary).get("graph", [])

	_current_page = index
	_clear()
	for node in nodes:
		_graph.add_child(_make_graph_node(node))
	_apply_connections(nodes)
	return _ensure_start_node()

## Writes the graph on screen back into [member _doc] before it is abandoned for another
## page, or for saving - the file (here, [member _doc]) stays the source of truth, and
## the [GraphEdit] is a view onto one page of it at a time.
func _commit_current_page() -> void:
	var pages: Array = _doc.get("pages", [])
	if _current_page < 0 or _current_page >= pages.size():
		return
	(pages[_current_page] as Dictionary)["graph"] = _serialize()

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
	_title.text = ("* " if _dirty else "") + label
	_title.tooltip_text = label
	_save_button.disabled = not _dirty and _path != ""
	_reload_button.disabled = _path == ""

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
