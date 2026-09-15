@tool
extends VBoxContainer

## Editor dock for the event command JSON files.
##
## Deliberately a text editor and not a form: the file on disk stays the source of
## truth, so anything this dock cannot express is still reachable by typing. What it
## adds over opening the .json in a text editor is line numbers, folding, JSON
## highlighting, pretty-printing, and a [b]Validate[/b] pass that runs the parsed
## commands through [method EventCommand.parse_route] and lists what came back -
## click a result to jump to the command that caused it.
##
## The route parser is looked up by name at validate time rather than preloaded, so
## the dock keeps working (JSON syntax and shape only) before that class exists and
## picks the schema check up on its own once it does.

## Global class holding the command schema, and its static entry point. Both are
## resolved by name - see [method _route_parser].
const ROUTE_PARSER_CLASS := "EventCommand"
const ROUTE_PARSER_METHOD := "parse_route"

## The document-shape readers - a bare array is graph_document's, a page-wrapped object
## is event_document's. Preloaded rather than looked up by name like the route parser
## above: both are addon/project files that exist from the start, unlike EventCommand,
## which this dock predates.
const GraphDoc := preload("res://addons/graph_editor/graph_document.gd")
const EventDoc := preload("res://events/event_document.gd")

const EMPTY_DOCUMENT := "[\n]\n"
## The command the Add button seeds - a starting point to edit, not a meaningful one.
const NEW_COMMAND := "mov n 2"
## Where the last opened path is remembered between editor sessions.
const METADATA_SECTION := "event_editor"
const METADATA_PATH_KEY := "last_file"

var _path := ""
var _dirty := false
## Where the mouse last sat in the text, as
## [code]{"line": int, "column": int, "index": int, "depth": int}[/code], or empty
## while the pointer is not over any character. See [method _on_hover_changed].
var _hovered: Dictionary = {}

var _title: Label
var _edit: CodeEdit
var _results: ItemList
var _hover_label: Label
var _status: Label
var _save_button: Button
var _reload_button: Button
var _file_dialog: EditorFileDialog

func _init() -> void:
	name = "Events"

func _ready() -> void:
	if not _bind():
		# Reloaded into a dock that is already up: its text, results and dirty flag
		# are still on screen, so take the references back and leave them alone.
		return

	_new_document()

	var last: String = EditorInterface.get_editor_settings().get_project_metadata(
		METADATA_SECTION, METADATA_PATH_KEY, "")
	if last != "" and FileAccess.file_exists(last):
		_load(last)

# --- UI -----------------------------------------------------------------------

## Points the references above at the dock's children, building them first if this
## dock is new. Returns true only when it built them.
##
## A @tool script reloads in place while the editor is running: the node keeps its
## children and its signal connections - which is why a handler can still fire - but
## this instance is rebuilt and every node reference on it comes back null, with no
## guarantee [method _ready] runs again to refill them. Finding the children by name
## rather than trusting the references to survive lets the dock pick itself back up
## instead of erroring on the next mouse move.
func _bind() -> bool:
	if get_child_count() == 0:
		_build_ui()
		return true

	_title = get_node_or_null(^"Title") as Label
	_edit = get_node_or_null(^"Edit") as CodeEdit
	_results = get_node_or_null(^"Results") as ItemList
	_hover_label = get_node_or_null(^"Hover") as Label
	_status = get_node_or_null(^"Status") as Label
	_save_button = get_node_or_null(^"ToolbarFile/Save") as Button
	_reload_button = get_node_or_null(^"ToolbarFile/Reload") as Button
	_file_dialog = get_node_or_null(^"FileDialog") as EditorFileDialog

	if is_instance_valid(_hover_label):
		return false

	# Children, but not the ones we expect - a dock left over from a build of this
	# script whose layout differed. Start it over rather than binding to nothing and
	# going quietly inert. Anything unsaved in the old buffer is gone either way,
	# since there is no telling which child was the editor.
	for child in get_children():
		remove_child(child)
		child.queue_free()

	_build_ui()
	return true

## True when the references above are live, re-binding them first if a reload
## dropped them. Every signal handler passes through here before touching the UI,
## since one can fire in the window between the reload and [method _bind].
func _live() -> bool:
	if not is_instance_valid(_hover_label):
		_bind()
	return is_instance_valid(_hover_label)

func _build_ui() -> void:
	add_theme_constant_override("separation", 4)

	# Two rows: file operations, which act on the whole document, above editing
	# operations, which act on the buffer's contents. Growing list of the latter is
	# what made one crowded row worth splitting.
	var files := HBoxContainer.new()
	files.name = "ToolbarFile"
	add_child(files)

	files.add_child(_make_button("New", _new_document))
	files.add_child(_make_button("Open", _open))
	_reload_button = _make_button("Reload", _reload)
	files.add_child(_reload_button)
	_save_button = _make_button("Save", _save)
	files.add_child(_save_button)

	var editing := HBoxContainer.new()
	editing.name = "ToolbarEdit"
	add_child(editing)

	editing.add_child(_make_button("Add", _add_command))
	editing.add_child(_make_button("Unknown", _show_unknown))
	editing.add_child(_make_button("Strip Unknown", _strip_unknown))

	# Format and Validate get their own row: both re-read the whole buffer rather than
	# make one targeted edit like the row above, which made them worth setting apart.
	var running := HBoxContainer.new()
	running.name = "ToolbarRun"
	add_child(running)

	running.add_child(_make_button("Format", _format))
	running.add_child(_make_button("Validate", _validate))

	_title = Label.new()
	_title.name = "Title"
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_title.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_title)

	_edit = CodeEdit.new()
	_edit.name = "Edit"
	_edit.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_edit.custom_minimum_size = Vector2(0, 160)
	_edit.gutters_draw_line_numbers = true
	_edit.gutters_draw_fold_gutter = true
	_edit.line_folding = true
	_edit.draw_tabs = false
	_edit.indent_use_spaces = false
	_edit.indent_automatic = true
	_edit.auto_brace_completion_enabled = true
	_edit.syntax_highlighter = _make_highlighter()
	_edit.text_changed.connect(_on_text_changed)
	_edit.gui_input.connect(_on_edit_gui_input)
	# gui_input stops arriving the moment the pointer leaves, so without this the
	# last hovered command would stay latched as though the mouse never moved off.
	_edit.mouse_exited.connect(_clear_hover)
	add_child(_edit)

	_results = ItemList.new()
	_results.name = "Results"
	_results.custom_minimum_size = Vector2(0, 96)
	_results.auto_height = false
	_results.item_selected.connect(_on_result_selected)
	add_child(_results)

	_hover_label = Label.new()
	_hover_label.name = "Hover"
	_hover_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_hover_label.mouse_filter = Control.MOUSE_FILTER_PASS
	# Muted, and sat above the status line: it changes constantly as the mouse moves,
	# so it should not read as loudly as a validation result.
	_hover_label.add_theme_color_override(&"font_color", _muted_color())
	add_child(_hover_label)

	_status = Label.new()
	_status.name = "Status"
	# Wraps rather than trims: a validation message naming several node ids, or a long
	# repair message, used to run off the edge of the dock and be readable only from its
	# tooltip. Autowrap grows the label to as many lines as it needs instead.
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.clip_text = false
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	add_child(_status)

	_file_dialog = EditorFileDialog.new()
	_file_dialog.name = "FileDialog"
	_file_dialog.file_mode = EditorFileDialog.FILE_MODE_OPEN_FILE
	_file_dialog.access = EditorFileDialog.ACCESS_RESOURCES
	_file_dialog.add_filter("*.json", "Event commands")
	_file_dialog.file_selected.connect(_load)
	add_child(_file_dialog)

func _make_button(text: String, handler: Callable) -> Button:
	var button := Button.new()
	# Named as well as labelled so _bind() can find it again after a script reload.
	button.name = text
	button.text = text
	button.pressed.connect(handler)
	return button

## A JSON highlighter coloured from the user's script editor theme, so the dock
## matches the editor they already tuned rather than inventing its own palette.
func _make_highlighter() -> CodeHighlighter:
	var highlighter := CodeHighlighter.new()
	var strings := _theme_color("string_color", Color("ffeda1"))
	var numbers := _theme_color("number_color", Color("a1ffe0"))

	highlighter.number_color = numbers
	highlighter.symbol_color = _theme_color("symbol_color", Color("abc9ff"))
	highlighter.add_color_region("\"", "\"", strings)

	# JSON has no keywords, but its three literals read better in the theme's
	# keyword colour than as bare symbols.
	var keyword := _theme_color("keyword_color", Color("ff7085"))
	for literal in ["true", "false", "null"]:
		highlighter.add_keyword_color(literal, keyword)

	return highlighter

func _theme_color(key: String, fallback: Color) -> Color:
	var setting := "text_editor/theme/highlighting/" + key
	var settings := EditorInterface.get_editor_settings()
	if not settings.has_setting(setting):
		return fallback
	return settings.get_setting(setting)

# --- Document -----------------------------------------------------------------

func _new_document() -> void:
	if not _live():
		return

	_path = ""
	_set_text(EMPTY_DOCUMENT)
	_dirty = false
	_results.clear()
	_set_status("New file - Save to choose a path.", _status_color(true))
	_refresh_title()

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

	_path = path
	_set_text(file.get_as_text())
	_dirty = false
	_results.clear()
	_refresh_title()
	_remember_path()
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

	file.store_string(_edit.text)
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

## Appends a fresh [constant NEW_COMMAND] to the end of the array.
##
## Splices the text in rather than re-serialising the parsed document, so the rest
## of the file keeps whatever formatting it was given. The insert goes through
## [method TextEdit.insert_text], so it lands on the undo stack like any typing.
func _add_command() -> void:
	if not _live():
		return

	var scan := _scan(_edit.text)
	var line: int = scan["end_line"]
	var column: int = scan["end_column"]
	# Follow the last command, or the opening bracket when there is not one yet -
	# only the former needs a comma ahead of it.
	var separator := ",\n\t"

	if line < 0:
		line = scan["open_line"]
		column = scan["open_column"]
		separator = "\n\t"

	if line < 0:
		_set_status("No array to add to - fix the JSON first.", _status_color(false))
		_validate()
		return

	# Every command in this project's files is a graph node - id and a wired output
	# included - so a seeded one should already look like its neighbours rather than
	# needing both filled in by hand before Validate stops complaining.
	var seed := {
		"id": GraphDoc.generate_id(_used_ids()),
		"title": GraphDoc.DEFAULT_TITLE,
		"command": NEW_COMMAND,
		"outputs": [{"type": "flow", "target": ""}],
	}
	_edit.insert_text(separator + JSON.stringify(seed), line, column)

	# Leave the caret on the command that was just added, ready to be edited.
	_go_to_line(line + 1)
	_validate()

## Every [code]"id"[/code] already used by a top-level array element, for
## [method GraphDoc.generate_id] to dodge. Empty when the buffer is not an array at all -
## [method _add_command] has already refused by the time this would matter.
func _used_ids() -> Dictionary:
	var used := {}
	var json := JSON.new()
	if json.parse(_edit.text) != OK or typeof(json.data) != TYPE_ARRAY:
		return used

	for entry in json.data as Array:
		if entry is Dictionary and (entry as Dictionary).has("id"):
			used[str((entry as Dictionary)["id"])] = true
	return used

func _format() -> void:
	if not _live():
		return

	var data: Variant = JSON.parse_string(_edit.text)
	if data == null:
		_set_status("Nothing to format - fix the JSON first.", _status_color(false))
		_validate()
		return

	# sort_keys off: the order keys were authored in is part of how the file reads.
	var line := _edit.get_caret_line()
	_set_text(JSON.stringify(data, "\t", false) + "\n")
	_go_to_line(mini(line, _edit.get_line_count() - 1))
	_on_text_changed()

## Lists every key neither reader recognises - a "//" comment included - without
## touching the buffer. Segment 3 preserves these silently on every parse/save; this is
## the surface that lets an author see what is riding along.
func _show_unknown() -> void:
	if not _live():
		return

	var lines := _unknown_lines()
	_results.clear()
	for line in lines:
		_add_result(line, -1)

	if lines.is_empty():
		_set_status("No unknown keys.", _status_color(true))
	else:
		_set_status("%d unknown key(s)." % lines.size(), _status_color(true))

## Rewrites the buffer with every unrecognised key removed, at every level - document,
## page and node. A one-way edit like Format: it lands on the undo stack, but it is not
## undoing itself automatically, so a comment stripped this way is gone until Ctrl+Z.
func _strip_unknown() -> void:
	if not _live():
		return

	var json := JSON.new()
	if json.parse(_edit.text) != OK:
		_set_status("Nothing to strip - fix the JSON first.", _status_color(false))
		_validate()
		return

	var data: Variant = json.data
	var line := _edit.get_caret_line()

	if typeof(data) != TYPE_ARRAY and typeof(data) != TYPE_DICTIONARY:
		_set_status("Nothing to strip.", _status_color(false))
		return

	# strip_unknown_raw() only, never EventDoc.parse()/stringify(): that pair repairs as
	# it round-trips - a missing id generated, a missing title defaulted - which is right
	# for a graph about to be shown, but wrong here. A plain command list that never had
	# an id or a position should not gain four fields because its comment got removed.
	_edit.text = JSON.stringify(EventDoc.strip_unknown_raw(data), "\t", false) + "\n"

	_edit.clear_undo_history()
	_go_to_line(mini(line, _edit.get_line_count() - 1))
	_on_text_changed()
	_show_unknown()

## The unknown-key messages for whichever document shape the buffer currently holds, or
## an empty list while it does not parse at all.
func _unknown_lines() -> Array[String]:
	var json := JSON.new()
	if json.parse(_edit.text) != OK:
		return []

	var data: Variant = json.data
	if typeof(data) == TYPE_ARRAY:
		return GraphDoc.unknown_report(GraphDoc.parse_nodes(data as Array)["nodes"])
	if typeof(data) == TYPE_DICTIONARY:
		return EventDoc.unknown_report(EventDoc.parse(_edit.text))
	return []

func _set_text(text: String) -> void:
	# Assigning text resets the undo history, which is what we want for a load or a
	# reformat - neither is an edit the user should be able to type their way back
	# through half of.
	_edit.text = text
	_edit.clear_undo_history()

func _remember_path() -> void:
	EditorInterface.get_editor_settings().set_project_metadata(
		METADATA_SECTION, METADATA_PATH_KEY, _path)

func _refresh_title() -> void:
	var label := _path if _path != "" else "(unsaved)"
	_title.text = ("* " if _dirty else "") + label
	_title.tooltip_text = label
	_save_button.disabled = not _dirty and _path != ""
	_reload_button.disabled = _path == ""

func _on_text_changed() -> void:
	if not _live():
		return

	_dirty = true
	_refresh_title()

	# The same line and column can mean a different command after an edit, so drop
	# the cached position that _update_hover() skips its rescan on. The reported
	# values are left alone: blanking them here would flicker the readout off on
	# every keystroke, and the next mouse move refreshes them anyway.
	if not _hovered.is_empty():
		_hovered["line"] = -1

func _on_edit_gui_input(event: InputEvent) -> void:
	if not _live():
		return

	if event is InputEventKey and event.pressed and not event.is_echo() \
			and event.ctrl_pressed and event.keycode == KEY_S:
		get_viewport().set_input_as_handled()
		_save()
		return

	if event is InputEventMouseMotion:
		_update_hover(event.position)

# --- Hover --------------------------------------------------------------------

## Works out which command the pointer sits in from its position over the text.
## [param position] is local to [member _edit].
func _update_hover(position: Vector2) -> void:
	# Clamping off: past the end of a line, or below the last one, comes back as
	# (-1, -1) instead of snapping to the nearest real character, so a miss stays
	# distinguishable from a hit. Note the axes - x is the column, y is the line.
	var at := _edit.get_line_column_at_pos(Vector2i(position), false, false)
	if at.x < 0 or at.y < 0:
		_clear_hover()
		return

	# The scan below walks the source from the top, so skip it while the pointer is
	# still over the character it was over last frame - which is most of them.
	if _hovered.get("line", -1) == at.y and _hovered.get("column", -1) == at.x:
		return

	var scan := _scan(_edit.text, at.y, at.x)
	_set_hover({
		"line": at.y,
		"column": at.x,
		"index": scan["index"],
		"depth": scan["depth"],
	})

func _set_hover(info: Dictionary) -> void:
	# Report on the command and nesting rather than on the raw position, so moving
	# along a line does not fire the hook once per character.
	var changed: bool = _hovered.is_empty() \
		or _hovered["index"] != info["index"] \
		or _hovered["depth"] != info["depth"]

	_hovered = info
	if changed:
		_on_hover_changed(_hovered)

func _clear_hover() -> void:
	if _hovered.is_empty() or not _live():
		return

	_hovered = {}
	_on_hover_changed(_hovered)

## Called when the pointer moves into a different command or nesting level, and
## once with an empty [param info] when it leaves the text entirely. The hook to
## build on - for now it just reports where the pointer landed.
func _on_hover_changed(info: Dictionary) -> void:
	if info.is_empty():
		_hover_label.text = ""
		_hover_label.tooltip_text = ""
		return

	var where := "no command" if info["index"] < 0 else "command %d" % info["index"]
	var text := "%s, depth %d - line %d, column %d" % [
		where, info["depth"], int(info["line"]) + 1, info["column"]]

	_hover_label.text = text
	_hover_label.tooltip_text = text

# --- Validation ---------------------------------------------------------------

## Re-checks the buffer and fills the result list. Passes, each only reached when the
## one before it was clean: JSON syntax, the shape the file has to have, the graph's
## wiring (dangling targets, and every node "start" cannot reach), and finally the
## per-command schema via the route parser.
##
## A page-wrapped document ([EventDocument]'s [code]{format, id, pages: []}[/code])
## and a bare array both reach here - see [method _validate_wrapped] and
## [method _validate_bare_array]. Only the bare-array path can point a result at a line:
## the wrapped one has no per-page line tracking yet, so its results carry no line and
## are not clickable, the same as the Unknown button's.
func _validate() -> void:
	if not _live():
		return

	_results.clear()

	var json := JSON.new()
	if json.parse(_edit.text) != OK:
		# get_error_line() is 1-based; the caret is not.
		_add_result("%s" % json.get_error_message(), json.get_error_line() - 1)
		_set_status("Invalid JSON.", _status_color(false))
		return

	var data: Variant = json.data

	if typeof(data) == TYPE_ARRAY:
		_validate_bare_array(data as Array)
		return
	if typeof(data) == TYPE_DICTIONARY:
		_validate_wrapped(data as Dictionary)
		return

	_add_result("Top level must be an array of commands or a page-wrapped object, found %s."
		% type_string(typeof(data)), 0)
	_set_status("1 problem.", _status_color(false))

func _validate_bare_array(data: Array) -> void:
	var lines := _element_lines(_edit.text)

	for i in data.size():
		if typeof(data[i]) != TYPE_DICTIONARY:
			_add_result("Command %d must be an object, found %s."
				% [i, type_string(typeof(data[i]))], _line_of(lines, i))

	if _results.item_count > 0:
		_set_status(_problem_count(), _status_color(false))
		return

	var parsed := GraphDoc.parse_nodes(data)
	var nodes: Array = parsed["nodes"]

	for message in (parsed["problems"] as Array):
		_add_result(str(message), -1)

	for message in _wiring_problems(nodes):
		_add_result(message, _line_for_id(nodes, lines, message))

	if _results.item_count > 0:
		_set_status(_problem_count(), _status_color(false))
		return

	_validate_route(data, lines)

## The dangling-target/duplicate-id checks [method GraphDoc.validate] already has, plus
## the start-node and orphan-chain checks [method EventCommand.validate_reachability]
## adds - one call for both wiring concerns, kept together because a caller wanting one
## almost always wants the other.
func _wiring_problems(nodes: Array) -> Array[String]:
	var problems: Array[String] = GraphDoc.validate(nodes)
	problems.append_array(EventCommand.validate_reachability(nodes))
	return problems

## The line of the top-level array element named by the first quoted id in [param message],
## or -1 when none of [param nodes] is named. [param nodes] is in file order, so its index
## lines up with [param lines] the same way [method _line_of] already assumes elsewhere.
func _line_for_id(nodes: Array, lines: PackedInt32Array, message: String) -> int:
	var parts := message.split("\"")
	var i := 1
	while i < parts.size():
		for j in nodes.size():
			if str((nodes[j] as Dictionary).get("id", "")) == parts[i]:
				return _line_of(lines, j)
		i += 2
	return -1

## A page-wrapped document has no per-page line tracking, so every result here carries no
## line - not clickable, same as the Unknown button's results.
func _validate_wrapped(data: Dictionary) -> void:
	var doc := EventDoc.parse(_edit.text)

	for message in (doc["problems"] as Array):
		_add_result(str(message), -1)

	var pages: Array = doc["pages"]
	for i in pages.size():
		var nodes: Array = (pages[i] as Dictionary).get("graph", [])
		for message in _wiring_problems(nodes):
			_add_result("Page %d: %s" % [i + 1, message], -1)

	for message in EventDoc.validate_pages(pages):
		_add_result(str(message), -1)

	if _results.item_count > 0:
		_set_status(_problem_count(), _status_color(false))
		return

	var total := 0
	for page in pages:
		var nodes: Array = (page as Dictionary).get("graph", [])
		total += nodes.size()
		var parser := _route_parser()
		if parser == null:
			continue
		for problem in _route_problems(parser.call(ROUTE_PARSER_METHOD, nodes)):
			_add_result(str(problem["message"]), -1)

	if _results.item_count > 0:
		_set_status(_problem_count(), _status_color(false))
		return

	if _route_parser() == null:
		_set_status("%d page(s), %d command(s), valid JSON. %s.%s not found, schema unchecked."
			% [pages.size(), total, ROUTE_PARSER_CLASS, ROUTE_PARSER_METHOD], _status_color(true))
		return

	_set_status("%d page(s), %d command(s), every route parses clean." % [pages.size(), total],
		_status_color(true))

## Hands the parsed commands to the route parser, if the project has one yet.
func _validate_route(commands: Array, lines: PackedInt32Array) -> void:
	var parser := _route_parser()
	if parser == null:
		_set_status("%d command(s), valid JSON. %s.%s not found, schema unchecked."
			% [commands.size(), ROUTE_PARSER_CLASS, ROUTE_PARSER_METHOD],
			_status_color(true))
		return

	for problem in _route_problems(parser.call(ROUTE_PARSER_METHOD, commands)):
		_add_result(problem["message"], _line_of(lines, problem["index"]))

	if _results.item_count > 0:
		_set_status(_problem_count(), _status_color(false))
		return

	_set_status("%d command(s), route parses clean." % commands.size(),
		_status_color(true))

## The script declaring [constant ROUTE_PARSER_CLASS], or null when the project has
## no such global class or it has no static [constant ROUTE_PARSER_METHOD] to call.
## Looked up rather than preloaded so the dock does not hard-depend on a class that
## may not be written yet.
func _route_parser() -> Script:
	for entry in ProjectSettings.get_global_class_list():
		if entry.get("class", "") != ROUTE_PARSER_CLASS:
			continue

		var script := load(entry.get("path", "")) as Script
		if script == null:
			return null

		for method in script.get_script_method_list():
			if method.get("name", "") == ROUTE_PARSER_METHOD:
				return script
		return null

	return null

## Normalises whatever the route parser hands back into
## [code]{"message": String, "index": int}[/code] entries, with an index of -1 when
## the problem does not point at one command.
##
## The parser is not written yet, so this stays deliberately loose about the return
## value: [code]null[/code] and [code]false[/code] read as a failure with nothing to
## say, a String as a single message, an Array as a list of them, and a Dictionary
## is searched for an [code]errors[/code] or [code]error[/code] key. Anything else -
## including the parsed route itself coming back on success - counts as clean.
func _route_problems(result: Variant) -> Array[Dictionary]:
	var problems: Array[Dictionary] = []

	match typeof(result):
		TYPE_NIL:
			problems.append(_rejected())
		TYPE_BOOL:
			if not result:
				problems.append(_rejected())
		TYPE_STRING, TYPE_STRING_NAME:
			problems.append(_problem(String(result), -1))
		TYPE_ARRAY:
			for entry in result:
				problems.append_array(_route_problems(entry))
		TYPE_DICTIONARY:
			var errors: Variant = result.get("errors", result.get("error"))
			if errors == null:
				return problems

			problems = _route_problems(errors)
			# An index on the wrapper applies to every message it carried, but only
			# where the message did not name a command of its own.
			var index: int = result.get("index", result.get("command", -1))
			for problem in problems:
				if problem["index"] < 0:
					problem["index"] = index

	return problems

func _rejected() -> Dictionary:
	return _problem("%s.%s rejected the route." % [
		ROUTE_PARSER_CLASS, ROUTE_PARSER_METHOD], -1)

func _problem(message: String, index: int) -> Dictionary:
	return {"message": message, "index": index}

func _problem_count() -> String:
	var count := _results.item_count
	return "%d problem%s." % [count, "" if count == 1 else "s"]

# --- Results ------------------------------------------------------------------

## Adds a line to the result list. [param line] is 0-based, or negative for a
## problem with no place in the file to jump to.
func _add_result(message: String, line: int) -> void:
	var text := message if line < 0 else "Line %d: %s" % [line + 1, message]
	var index := _results.add_item(text)
	_results.set_item_metadata(index, line)
	_results.set_item_tooltip(index, text)

func _on_result_selected(index: int) -> void:
	if not _live():
		return

	_go_to_line(_results.get_item_metadata(index))

func _go_to_line(line: int) -> void:
	if line < 0 or line >= _edit.get_line_count():
		return

	_edit.set_caret_line(line)
	_edit.set_caret_column(0)
	_edit.center_viewport_to_caret()
	_edit.grab_focus()

func _status_color(ok: bool) -> Color:
	var theme := EditorInterface.get_editor_theme()
	return theme.get_color(&"success_color" if ok else &"error_color", &"Editor")

## The editor's label colour, faded back for text that is incidental rather than
## something the user asked to see.
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

# --- Source lines -------------------------------------------------------------

## Walks the raw source, tracking how deeply nested each character is and which
## element of the outer array it belongs to. Done on the text rather than the parsed
## data because [JSON] keeps no line information, and because this has to work on a
## buffer that does not parse at all - it is what puts a validation error on a line,
## and what answers the hover.
##
## Returns:
## [codeblock]
## lines        # the line each top-level element starts on, in order
## index        # element the walk ended inside, -1 before the first one
## depth        # open containers there: 0 outside the array, 1 between commands,
##              # 2 inside a command, 3+ nested deeper in
## open_line    # line/column just past the bracket opening the outer array,
## open_column  # both -1 if the text never opens one
## end_line     # line/column just past the last top-level element's closer,
## end_column   # both -1 while the array is still empty
## [/codeblock]
## The two positions are where new text can be spliced in: after the last command if
## there is one, otherwise straight after the opening bracket.
## Left at the default [param stop_line] the whole text is walked and only
## [code]lines[/code] is meaningful. Given a line and column it stops there instead,
## counting the character at that spot - so hovering a command's opening brace reads
## as being inside it - and [code]index[/code] and [code]depth[/code] describe that
## position. [code]index[/code] is sticky: it stays on the last element opened, so a
## blank line or a comma between two commands still reports the one above it.
##
## Only elements that open a brace or bracket are counted, which is every command in
## a well-formed file. A scalar sitting in the array leaves a gap, so its problems
## lose their line rather than borrowing a neighbour's.
func _scan(text: String, stop_line := -1, stop_column := -1) -> Dictionary:
	var lines := PackedInt32Array()
	var depth := 0
	var index := -1
	var line := 0
	var column := 0
	var in_string := false
	var escaped := false
	var open := Vector2i(-1, -1)
	var end := Vector2i(-1, -1)
	# Whether the outermost container is an array. A document rooted in an object
	# has no command list to append to, so it gets no insertion anchors at all.
	var array_root := false

	for i in text.length():
		if stop_line >= 0 and line > stop_line:
			break

		var c := text[i]

		if in_string:
			if escaped:
				escaped = false
			elif c == "\\":
				escaped = true
			elif c == "\"":
				in_string = false
		else:
			match c:
				"\"":
					in_string = true
				"[", "{":
					# Depth 1 is directly inside the outer array, so anything opening
					# there starts one of the elements we are numbering.
					if depth == 1:
						index += 1
						lines.append(line)
					depth += 1
					if depth == 1 and open.y < 0 and c == "[":
						array_root = true
						open = Vector2i(column + 1, line)
				"]", "}":
					depth -= 1
					# Back to depth 1 means an element just closed, so this is the
					# spot a new one is appended after. Later elements overwrite it,
					# leaving the last.
					if depth == 1 and array_root:
						end = Vector2i(column + 1, line)

		if stop_line >= 0 and line == stop_line and column >= stop_column:
			break

		if c == "\n":
			line += 1
			column = 0
		else:
			column += 1

	# Unbalanced closers while the user is mid-edit would otherwise read as negative.
	return {
		"lines": lines,
		"index": index,
		"depth": maxi(depth, 0),
		"open_line": open.y,
		"open_column": open.x,
		"end_line": end.y,
		"end_column": end.x,
	}

## The line each top-level array element starts on. See [method _scan].
func _element_lines(text: String) -> PackedInt32Array:
	return _scan(text)["lines"]

func _line_of(lines: PackedInt32Array, index: int) -> int:
	if index < 0 or index >= lines.size():
		return -1
	return lines[index]
