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
## it. Two rules from there matter to the UI:
## - an output port carries one primitive and points at one node, so connecting a port
##   that is already wired replaces the old connection rather than adding to it;
## - a node has exactly one input, so every connection lands on port 0 and any number
##   of ports may point at the same node.

const Doc := preload("res://addons/graph_editor/graph_document.gd")

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

var _path := ""
var _dirty := false
## How many nodes the Add button has placed, so each lands clear of the last.
var _added := 0

var _graph: GraphEdit
var _title: Label
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

	# Every primitive may land on an input, which is the only thing type 0 is used for.
	for type in Doc.TYPES:
		_graph.add_valid_connection_type(Doc.slot_type(type), 0)

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
func _make_graph_node(node: Dictionary) -> GraphNode:
	var id: String = node["id"]
	var graph_node := GraphNode.new()
	graph_node.name = _scene_name(id)
	graph_node.title = node.get("title", Doc.DEFAULT_TITLE)
	graph_node.position_offset = node.get("position", Vector2.ZERO)
	# The scene name is sanitised and can collide, so the id travels separately. Every
	# lookup goes through _id_of() rather than reading the name back.
	graph_node.set_meta(&"graph_id", id)
	# Everything this panel has no field for - command, args, blocking, key, flows, and
	# whatever _unknown carries - rides along as meta rather than being dropped. This is
	# the fix for the data-loss bug: a graph opened and saved here used to keep only id,
	# title, position and outputs.
	graph_node.set_meta(&"graph_extra", _extra_of(node))

	var id_label := Label.new()
	id_label.text = id
	id_label.add_theme_color_override(&"font_color", _muted_color())
	id_label.tooltip_text = "Node id - generated, and what other nodes target."
	id_label.mouse_filter = Control.MOUSE_FILTER_PASS
	graph_node.get_titlebar_hbox().add_child(id_label)

	_add_head_row(graph_node)
	for output in node.get("outputs", []):
		_add_output_row(graph_node, output["type"])
	_add_footer_row(graph_node)
	_refresh_slots(graph_node)

	return graph_node

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

## One output port: its primitive, and a button to drop it.
func _add_output_row(graph_node: GraphNode, type: String) -> void:
	var row := HBoxContainer.new()
	# Numbered by the ports already present, which is also the port index this row
	# will answer to once _refresh_slots() runs.
	row.name = OUT_ROW_PREFIX + str(_output_rows(graph_node).size())

	var remove := Button.new()
	remove.name = "Remove"
	remove.text = "-"
	remove.tooltip_text = "Remove this output."
	remove.pressed.connect(_on_remove_output.bind(graph_node, row))
	row.add_child(remove)

	var types := OptionButton.new()
	types.name = "Type"
	for i in Doc.TYPES.size():
		types.add_item(Doc.TYPES[i], i)
	types.select(maxi(Doc.TYPES.find(type), 0))
	types.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	types.item_selected.connect(_on_output_type_changed.bind(graph_node))
	row.add_child(types)

	graph_node.add_child(row)

func _add_footer_row(graph_node: GraphNode) -> void:
	var row := HBoxContainer.new()
	row.name = "Footer"

	var add := Button.new()
	add.name = "AddOutput"
	add.text = "+ Output"
	add.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add.pressed.connect(_on_add_output.bind(graph_node))
	row.add_child(add)

	graph_node.add_child(row)

## Re-applies every slot on [param graph_node] from its rows.
##
## [GraphNode] indexes slots by child index, and numbers ports by counting the enabled
## slots before them - so with the head row at index 0 and the footer disabled, an
## output's port index is always its child index minus one. Called after any row is
## added or removed, and after a type changes.
func _refresh_slots(graph_node: GraphNode) -> void:
	for i in graph_node.get_child_count():
		var row := graph_node.get_child(i)
		var is_head: bool = row.name == HEAD_ROW
		var is_output: bool = str(row.name).begins_with(OUT_ROW_PREFIX)
		var type := _row_type(row) if is_output else ""

		graph_node.set_slot(i,
			is_head, 0, Doc.UNTYPED_COLOR,
			is_output, Doc.slot_type(type), Doc.type_color(type))

func _row_type(row: Node) -> String:
	var types := row.get_node_or_null(^"Type") as OptionButton
	if types == null:
		return Doc.TYPES[0]
	return types.get_item_text(types.selected)

func _output_rows(graph_node: GraphNode) -> Array[Node]:
	var rows: Array[Node] = []
	for child in graph_node.get_children():
		if str(child.name).begins_with(OUT_ROW_PREFIX):
			rows.append(child)
	return rows

## Rebuilds the output rows of [param graph_node] to match [param outputs], preserving
## the wiring by target id.
##
## Adding or removing a port renumbers the ones after it, and [GraphEdit] holds its
## connections by port number - so rather than patch them, every connection out of this
## node is dropped and the surviving targets are reconnected against the new numbering.
func _rebuild_outputs(graph_node: GraphNode, outputs: Array) -> void:
	for row in _output_rows(graph_node):
		graph_node.remove_child(row)
		row.queue_free()

	var footer := graph_node.get_node_or_null(^"Footer")
	for output in outputs:
		_add_output_row(graph_node, output["type"])
	# Keep the add button last: the footer must stay the highest child index or it
	# would take an output's slot.
	if footer != null:
		graph_node.move_child(footer, graph_node.get_child_count() - 1)

	_refresh_slots(graph_node)
	_disconnect_from(graph_node)

	for i in outputs.size():
		var target: String = outputs[i]["target"]
		if target == "":
			continue

		var target_node := _node_by_id(target)
		if target_node != null:
			_graph.connect_node(graph_node.name, i, target_node.name, 0)

func _disconnect_from(graph_node: GraphNode) -> void:
	for connection in _graph.get_connection_list():
		if connection["from_node"] == graph_node.name:
			_graph.disconnect_node(connection["from_node"], connection["from_port"],
				connection["to_node"], connection["to_port"])

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
				"type": _row_type(rows[i]),
				"target": targets.get("%s:%d" % [graph_node.name, i], ""),
			})

		# Start from whatever this node carried that the panel has no field for, so
		# command/args/blocking/key/flows/_unknown ride through untouched, then overwrite
		# the four the UI actually owns.
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
	_mark_dirty()
	_validate()

func _on_add_output(graph_node: GraphNode) -> void:
	if not _live():
		return

	var outputs := _outputs_of(graph_node)
	outputs.append(Doc.default_output())
	_rebuild_outputs(graph_node, outputs)
	_mark_dirty()

func _on_remove_output(graph_node: GraphNode, row: Node) -> void:
	if not _live():
		return

	var index := _output_rows(graph_node).find(row)
	if index < 0:
		return

	var outputs := _outputs_of(graph_node)
	outputs.remove_at(index)
	_rebuild_outputs(graph_node, outputs)
	_mark_dirty()

## This node's ports as [code]{"type", "target"}[/code], with targets as ids - the form
## [method _rebuild_outputs] takes.
func _outputs_of(graph_node: GraphNode) -> Array[Dictionary]:
	for node in _serialize():
		if node["id"] == _id_of(graph_node):
			return node["outputs"]
	return []

func _on_output_type_changed(_selected: int, graph_node: GraphNode) -> void:
	if not _live():
		return

	# A port that changed primitive keeps its connection: the input side accepts
	# everything, so the wire is still legal. Only the slot's colour and type need
	# catching up.
	_refresh_slots(graph_node)
	_mark_dirty()

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
func _on_duplicate_nodes_request() -> void:
	if not _live():
		return

	var ids := _used_ids()
	var copies: Array[GraphNode] = []

	for node in _serialize():
		var source := _node_by_id(node["id"])
		if source == null or not source.selected:
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
	_clear()
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

	var parsed: Dictionary = Doc.parse(file.get_as_text())
	var nodes: Array[Dictionary] = parsed["nodes"]

	_path = path
	_clear()

	for node in nodes:
		_graph.add_child(_make_graph_node(node))
	_apply_connections(nodes)

	_dirty = false
	_refresh_title()
	_remember_path()
	_report(parsed["problems"], "%d node(s) loaded." % nodes.size())

## Wires up a freshly built graph. Separate from node creation because a target may
## name a node that comes later in the file.
func _apply_connections(nodes: Array[Dictionary]) -> void:
	for node in nodes:
		var from := _node_by_id(node["id"])
		if from == null:
			continue

		for i in (node["outputs"] as Array).size():
			var target: String = node["outputs"][i]["target"]
			if target == "":
				continue

			var to := _node_by_id(target)
			if to != null:
				_graph.connect_node(from.name, i, to.name, 0)

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

	file.store_string(Doc.stringify(_serialize()))
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
	_report(Doc.validate(nodes), "%d node(s), %d connection(s), graph is consistent."
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
