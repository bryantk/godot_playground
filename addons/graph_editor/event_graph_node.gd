@tool
class_name EventGraphNode
extends GraphNode

## One event-graph node: built from, and read back into, the
## [code]{id, title, position, command, args, outputs, blocking, key, _unknown}[/code]
## shape [code]graph_document.gd[/code] reads and writes.
##
## Everything about turning that data into rows an author can see and edit - the
## title field, one row per argument, the output ports, the comment toggle, the
## blocking indicator, the category tint - lives here, so
## [code]graph_editor_panel.gd[/code] only has to own the document (which page, which
## array) and the canvas (wiring, selection, layout), not what one node looks like.
##
## [b]Construct through [method create], not [code].new()[/code] directly.[/b] A
## [code]class_name[/code] script's [method Object._init] can be called with no
## arguments by the editor's own class-list scan, so [method _init] stays trivial and
## the real building happens in [method _build], which [method create] calls with the
## document data this node needs.
##
## [b]The document round-trips through here almost untouched.[/b] [member id] and
## [member extra] together are the same node dictionary minus [code]title[/code],
## [code]position[/code] and [code]outputs[/code] - which this control's own
## [member GraphNode.title], [member GraphNode.position_offset] and output rows
## already are. [method to_entry] puts all four back together for the caller to save.
##
## [signal changed] is the one thing outside this file needs to know about: a title
## edit, an argument, the comment, all fire it, so the panel can just mark the
## document dirty without knowing which field moved. Wiring two nodes together is the
## panel's own business instead - it spans nodes, which is a canvas concern, not one
## node's.

signal changed

const Doc := preload("res://addons/graph_editor/graph_document.gd")

## Name of the first row of a graph node - the one carrying the input port and the
## title field. Output rows follow it, so an output's port index is its child index
## minus one, which is what keeps ports and connections lined up.
const HEAD_ROW := "Head"
const OUT_ROW_PREFIX := "Out"
## Rows between the head and the outputs, one per editable argument the node's
## command declares - see [method _add_args_rows]. Neither side's slot is enabled on
## these, so they cost the port numbering above nothing: [GraphEdit] counts a port
## among only the rows enabled for that side, in child order, regardless of what sits
## between them.
const ARG_ROW_PREFIX := "Arg"

## Compass tokens a "dir" argument's dropdown offers - short form only, so it reads as
## a compass rather than a word list. Matches [constant EventCommand.DIRECTION_TOKENS].
const _DIR_OPTIONS: PackedStringArray = ["n", "ne", "e", "se", "s", "sw", "w", "nw"]

## What a "turn" argument's dropdown adds ahead of [constant _DIR_OPTIONS] - the three
## relative turns and "random", matching [constant EventCommand.TURN_TOKENS].
const _TURN_OPTIONS: PackedStringArray = ["turn_cw", "turn_ccw", "turn_180", "random"]

## Named speeds a "speed" argument's dropdown offers, in the same cells (or world
## units) per second [member MotionController.speed] itself is measured in - "Normal"
## sits on that export's own default of 6.0, so a node nobody has touched yet plays at
## the speed an actor already moves at with no [code]speed[/code] argument at all.
const _SPEED_PRESETS: Dictionary = {
	"Slowest": 2.0,
	"Slower": 4.0,
	"Normal": 6.0,
	"Fast": 9.0,
	"Fastest": 12.0,
}

## The one entry of [constant _SPEED_PRESETS] an outside caller has a reason to
## want - [code]graph_editor_panel.gd[/code] seeds a freshly spawned "move_by" node
## with it, rather than reaching into a constant this file otherwise keeps to itself.
static func normal_speed() -> float:
	return _SPEED_PRESETS["Normal"]

## What a "location" argument's dropdown offers - [enum Dialogue.Location]'s own
## names, in its own order, so the index a choice writes into [code]args.location[/code]
## is the same int [method Dialogue.set_window_location] already expects.
const _DIALOGUE_LOCATIONS: PackedStringArray = ["Top", "Middle", "Bottom"]

## [constant EventCommand.START_COMMAND]'s colour, always - overriding
## [method _command_color] rather than combining with it, so the one node every graph
## has exactly one of stays visually distinct from every ordinary command, whatever
## category "start" itself would tint as.
const _START_COLOR := Color(0.55, 1.0, 0.55)

## Five colours, one per command category - [member GraphNode.self_modulate] tints
## the whole node (panel included, since [GraphNode] has no simpler "colour the
## background" knob), so this is what a glance at the graph says about a node's kind.
## Blocking is a separate signal - see [method _add_blocking_indicator] - so it does
## not fight this colour for the same pixels.
const _CATEGORY_COLORS: Dictionary = {
	"flow": Color(0.82, 0.82, 0.86),
	"movement": Color(0.6, 0.88, 0.62),
	"dialogue": Color(1.0, 0.85, 0.55),
	"state": Color(0.82, 0.68, 1.0),
	"world": Color(0.6, 0.82, 0.95),
}

## [constant _CATEGORY_COLORS]'s five buckets, each an array of the [EventCommand]
## names that tint as it - the same grouping [code]event_command.gd[/code]'s own
## section comments already use ("-- Flow --", "-- Actor --", ...), with Map,
## Presentation and Battle folded into one "world" bucket to keep to five colours
## rather than seven. The category is the key rather than the command so a category's
## whole membership reads in one place, the way the section comments already group them.
const _COMMAND_CATEGORIES: Dictionary = {
	"flow": ["start", "wait", "goto", "label", "if", "ask", "call", "wait_for", "end",
		"re_validate"],

	"movement": ["move_to", "move_by", "step", "face_direction", "face_to", "jump",
		"follow", "set_speed", "teleport", "wait_settle"],

	"dialogue": ["say", "append_say", "close_window"],

	"state": ["set_flag", "set_self_flag", "set_var", "add_var"],

	"world": ["change_map", "fade", "shake", "camera_to", "camera_follow", "play_anim",
		"play_sound", "play_music", "set_visible", "start_battle"],
}

## Generated, or blank for the start node (question 47 follow-up) - what other nodes'
## outputs target. Kept separate from [member GraphNode.name] because a name is
## sanitised for the scene tree and can collide; every lookup goes through this
## instead of reading the name back.
var id: String = ""

## Everything a document node carries that this control has no dedicated field for -
## command, args, blocking, key, and whatever [code]_unknown[/code] carries (a
## [code]"//"[/code] comment included). Round-tripped verbatim by [method to_entry]:
## the fix for the data-loss bug where a graph opened and saved here used to keep
## only id, title, position and outputs.
var extra: Dictionary = {}


## Builds and returns a node for [param node] - one entry of the document, in
## [code]graph_document.gd[/code]'s shape. Wiring is not applied here: targets are
## ids, which cannot be resolved until every node in the page exists - the panel's own
## job, once every node it needs has been created.
##
## [b]Output ports come from the command, not from [param node]'s own
## [code]outputs[/code].[/b] [method EventCommand.flows_of] is authoritative for how
## many ports a node has and what each is named - a linear command has one "next",
## "if" has "true"/"false", "ask" has one per choice - so a port is never something an
## author adds or removes directly; it follows from choosing a command, same as the
## arguments it takes.
static func create(node: Dictionary) -> EventGraphNode:
	var graph_node := EventGraphNode.new()
	graph_node._build(node)
	return graph_node

func _build(node: Dictionary) -> void:
	var start_node := str(node.get("command", "")) == EventCommand.START_COMMAND

	id = str(node.get("id", ""))
	name = _scene_name(id)
	title = node.get("command", Doc.DEFAULT_TITLE)
	position_offset = node.get("position", Vector2.ZERO)
	extra = _initial_extra(node)

	# The start node's id is always blank and never a target an author needs to see,
	# so it alone skips the label every other node gets.
	if not start_node:
		var id_label := Label.new()
		id_label.text = id
		id_label.add_theme_color_override(&"font_color", _muted_color())
		id_label.tooltip_text = "Node id - generated, and what other nodes target."
		id_label.mouse_filter = Control.MOUSE_FILTER_PASS
		get_titlebar_hbox().add_child(id_label)

	if not start_node:
		_add_head_row()
	_add_args_rows(node)
	for flow in EventCommand.flows_of(node):
		_add_output_row(flow)
	_add_comment_rows()
	_refresh_slots()

	# Green for the start node, always; every other node by its command's category -
	# so a glance at the graph groups movement, dialogue and the rest apart,
	# independent of whether any given one happens to block.
	self_modulate = _START_COLOR if start_node \
		else _command_color(str(node.get("command", "")))

## Everything in [param node] this control has no dedicated field for - every key
## besides id, title, position and outputs.
static func _initial_extra(node: Dictionary) -> Dictionary:
	var result: Dictionary = node.duplicate(true)
	result.erase("id")
	result.erase("title")
	result.erase("position")
	result.erase("outputs")
	return result

## [param command]'s category colour, or plain white for a command no category in
## [constant _COMMAND_CATEGORIES] names (an unknown command, or the blank placeholder
## a freshly dropped node starts as before a command is chosen).
static func _command_color(command: String) -> Color:
	for category: Variant in _COMMAND_CATEGORIES:
		if (_COMMAND_CATEGORIES[category] as Array).has(command):
			return _CATEGORY_COLORS.get(category, Color.WHITE)
	return Color.WHITE

## A scene name for [param id]. Node names cannot hold [code]. : @ / " %[/code], and
## two different ids could sanitise to the same string, so the name is for the scene
## tree and [GraphEdit] only - [member id] is the real identity.
static func _scene_name(id: String) -> String:
	var name_hint := id.validate_node_name()
	return name_hint if name_hint != "" else "Node"

## True for a node built from a [constant EventCommand.START_COMMAND] entry.
func is_start() -> bool:
	return str(extra.get("command", "")) == EventCommand.START_COMMAND

## This node as a document entry, given [param outputs] - which the caller must
## supply, since a port's target comes from [GraphEdit]'s own connection list,
## something only the panel has a view across every node to resolve.
func to_entry(outputs: Array[Dictionary]) -> Dictionary:
	var entry: Dictionary = extra.duplicate(true)
	entry["id"] = id
	entry["title"] = title
	entry["position"] = position_offset
	entry["outputs"] = outputs
	return entry

## Every output row, in port order - the flow name [method row_flow] reads back is
## this row's identity, not a stored type, so a caller wanting the wiring goes through
## these rather than assuming port count from the command.
func output_rows() -> Array[Node]:
	var rows: Array[Node] = []
	for child in get_children():
		if str(child.name).begins_with(OUT_ROW_PREFIX):
			rows.append(child)
	return rows

## The flow name [method _add_output_row] gave [param row].
func row_flow(row: Node) -> String:
	return row.get_meta(&"flow", "")

## Re-applies every slot from this node's rows.
##
## [GraphNode] indexes slots by child index, and numbers ports by counting the enabled
## slots before them - so with the head row at index 0, an output's port index is
## always its child index minus one. Every output is a flow port now, so there is one
## slot type and one colour rather than a per-row choice.
##
## [b]The start node has no input slot.[/b] Nothing may flow into the node execution
## begins at - that would make it reachable from somewhere else too, which is exactly
## the ambiguity a single named entry point exists to remove.
func _refresh_slots() -> void:
	var has_input := not is_start()
	for i in get_child_count():
		var row := get_child(i)
		var is_head: bool = row.name == HEAD_ROW
		var is_output: bool = str(row.name).begins_with(OUT_ROW_PREFIX)

		set_slot(i,
			is_head and has_input, 0, Doc.UNTYPED_COLOR,
			is_output, Doc.FLOW_SLOT_TYPE, Doc.FLOW_COLOR)

## The input row. Also holds the title field, so the row that has no output port is
## the one carrying the only per-node value worth editing.
func _add_head_row() -> void:
	var row := HBoxContainer.new()
	row.name = HEAD_ROW

	var field := LineEdit.new()
	field.name = "TitleField"
	field.text = title
	field.placeholder_text = Doc.DEFAULT_TITLE
	field.custom_minimum_size = Vector2(120, 0)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.text_changed.connect(_on_title_field_changed)
	row.add_child(field)

	add_child(row)

func _on_title_field_changed(text: String) -> void:
	title = text if text != "" else Doc.DEFAULT_TITLE
	changed.emit()

## One output port: a label naming its flow, and nothing else. No type to pick, no
## button to remove it - [method create]'s docstring says why.
func _add_output_row(flow: String) -> void:
	var row := HBoxContainer.new()
	# Numbered by the ports already present, which is also the port index this row
	# will answer to once _refresh_slots() runs.
	row.name = OUT_ROW_PREFIX + str(output_rows().size())
	row.set_meta(&"flow", flow)

	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(spacer)

	var label := Label.new()
	label.name = "Flow"
	label.text = flow if flow != "" else "(unnamed)"
	label.add_theme_color_override(&"font_color", _muted_color())
	row.add_child(label)

	add_child(row)

## An hourglass at the bottom-right of [param row] when this command blocks - the
## runner waits for it before moving on. This is the whole reason blocking is not a
## whole-node tint any more: [member self_modulate] now spends its one colour on the
## command's category ([method _command_color]) instead, and blocking needed a signal
## of its own that would not fight it for the same pixels.
##
## Skipped for the start node - every graph's start blocks by definition (its own
## registry entry says so), so flagging it teaches an author nothing a glance at the
## green start node does not already say.
func _add_blocking_indicator(row: HBoxContainer) -> void:
	if is_start() or not EventCommand.is_blocking(extra):
		return

	var icon := Label.new()
	icon.name = "Blocking"
	icon.text = "⏳"
	icon.tooltip_text = "Blocking - the runner waits for this before moving on."
	icon.add_theme_color_override(&"font_color", _muted_color())
	row.add_child(icon)

## Bottom-left "+"/"-" toggle for this node's [code]"//"[/code] comment, and the text
## field it shows or hides - collapsed by default, so a node with nothing to say costs
## no space. Every node gets one, the start node included: a comment is authoring
## metadata, not something a command declares, so nothing about [method flows_of] or
## [method _add_args_rows] decides whether one is offered.
##
## The same row carries [method _add_blocking_indicator] at the bottom-right - not
## because a comment and blocking have anything to do with each other, but because a
## node's bottom edge is otherwise empty, and one shared row costs less height than two.
func _add_comment_rows() -> void:
	var toggle_row := HBoxContainer.new()
	toggle_row.name = "CommentToggle"

	var toggle := Button.new()
	toggle.name = "Toggle"
	toggle.text = "+"
	toggle.custom_minimum_size = Vector2(24, 0)
	toggle.tooltip_text = "Comment"
	toggle_row.add_child(toggle)

	# Left-aligned rather than stretched: without this a lone HBoxContainer child
	# widens to fill the node, which is fine for the flow label above (right-aligned
	# instead) but wrong for a toggle that has to sit at the bottom-left.
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	toggle_row.add_child(spacer)

	_add_blocking_indicator(toggle_row)

	add_child(toggle_row)

	var body := TextEdit.new()
	body.name = "CommentBody"
	body.text = _node_comment()
	body.placeholder_text = "Comment"
	body.custom_minimum_size = Vector2(160, 56)
	body.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	body.visible = false
	body.text_changed.connect(func() -> void:
		_set_node_comment(body.text)
		_refresh_comment_toggle(toggle))
	add_child(body)

	toggle.pressed.connect(func() -> void:
		body.visible = not body.visible
		toggle.text = "-" if body.visible else "+"
		# A [GraphNode]'s size is sticky - an author's own drag-resize is meant to
		# survive a child changing - so hiding the comment field does not shrink the
		# node back on its own. Resetting to zero lets the next layout pass settle it
		# at its new minimum instead of leaving the collapsed field's space reserved.
		reset_size())

	_refresh_comment_toggle(toggle)

## This node's [code]"//"[/code] comment, if it has one - passenger data under
## [member extra]'s [code]_unknown[/code] bag, the same path any key neither
## [code]graph_document.gd[/code] nor [EventCommand] recognises rides through
## ([constant Doc.NODE_KEYS]'s docstring).
func _node_comment() -> String:
	var unknown: Dictionary = extra.get("_unknown", {})
	return str(unknown.get("//", ""))

## Writes [param text] as this node's comment, or removes it entirely once blank - an
## empty comment is the same as never having written one, so nothing is saved for it.
func _set_node_comment(text: String) -> void:
	var unknown: Dictionary = extra.get("_unknown", {})
	if not extra.has("_unknown"):
		extra["_unknown"] = unknown

	if text.strip_edges() == "":
		unknown.erase("//")
	else:
		unknown["//"] = text
	changed.emit()

## White when this node already carries a comment, grey when it does not - true
## before [param toggle] is even pressed, since the whole point of colouring it is to
## say whether there is something to see behind a still-closed field.
func _refresh_comment_toggle(toggle: Button) -> void:
	var has_comment := _node_comment().strip_edges() != ""
	toggle.add_theme_color_override(&"font_color", Color.WHITE if has_comment else _muted_color())

## One row per argument the node's command declares - a "wait" node's [code]seconds[/code]
## as a number field, a "move_by" node's [code]cells[/code] as a cell field, and so on -
## so the graph itself is where an author edits a command's data, not just its wiring.
##
## Skipped for a command with no [code]args[/code] at all (start, goto, end, ...), and
## per-argument for [constant EventCommand.T_CHOICES]: "ask"'s choices are edited by
## adding and wiring flow ports (see [method EventCommand.flows_of]), not as a field here.
func _add_args_rows(node: Dictionary) -> void:
	var command := str(node.get("command", ""))
	var spec: Dictionary = EventCommand.definition(command).get("args", {})
	if spec.is_empty():
		return

	var args: Dictionary = node.get("args", {})
	for key: Variant in spec:
		var declared := str(spec[key])
		var type := declared.trim_suffix("?")
		if type == EventCommand.T_CHOICES:
			continue
		_add_arg_row(command, str(key), type, declared.ends_with("?"), args.get(key))

## One argument's row: its name, and a control matching its declared type - except
## for the handful of arguments below with a control specific to what they mean
## rather than just their [code]T_*[/code] type, each a step past what the type alone
## could offer:
##
## - "move_by"'s [code]cells[/code] as a direction and a count, not a raw delta;
## - any "speed" as a named preset, not a bare number;
## - any "location" as [enum Dialogue.Location]'s own names;
## - "say" and "append_say"'s [code]text[/code] as a text area, since a dialogue line
##   is prose, not a single-line value like every other string argument.
func _add_arg_row(command: String, key: String, type: String, optional: bool,
		value: Variant) -> void:
	if (command == "say" or command == "append_say") and key == "text":
		_add_text_area_row(key, value)
		return

	var row := HBoxContainer.new()
	row.name = ARG_ROW_PREFIX + key.to_pascal_case()

	var label := Label.new()
	label.text = key + ("?" if optional else "")
	label.tooltip_text = "%s (%s)" % [type, "optional" if optional else "required"]
	label.custom_minimum_size = Vector2(64, 0)
	label.add_theme_color_override(&"font_color", _muted_color())
	row.add_child(label)

	if command == "move_by" and key == "cells":
		_add_move_direction_control(row, key, value)
	elif key == "speed" and type == EventCommand.T_FLOAT:
		var speed_picker := _make_speed_control(value, optional)
		speed_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		speed_picker.tooltip_text = label.tooltip_text
		_connect_speed_control(speed_picker, key)
		row.add_child(speed_picker)
	elif key == "location" and type == EventCommand.T_INT:
		var location_picker := _make_location_control(value, optional)
		location_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		location_picker.tooltip_text = label.tooltip_text
		_connect_location_control(location_picker, key)
		row.add_child(location_picker)
	else:
		# An actor argument every actor command declares optional defaults to "@self"
		# at runtime (event_command.gd's docstring on COMMANDS) - showing that instead
		# of blank is what "pre-fill the actor as itself" meant, and it costs nothing:
		# the field stays untouched in args until an author edits it, same as every
		# other optional field here.
		var seed_value: Variant = value
		if type == EventCommand.T_ACTOR and optional and value == null:
			seed_value = "@self"

		var control := _make_arg_control(type, seed_value)
		control.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		control.tooltip_text = label.tooltip_text
		_connect_arg_control(control, type, optional, key)
		row.add_child(control)

	add_child(row)

## A dialogue line's own row: the label above rather than beside, and a multi-line
## [TextEdit] instead of a [LineEdit] - the one argument here that is prose rather
## than a single value.
func _add_text_area_row(key: String, value: Variant) -> void:
	var box := VBoxContainer.new()
	box.name = ARG_ROW_PREFIX + key.to_pascal_case()

	var label := Label.new()
	label.text = key
	label.add_theme_color_override(&"font_color", _muted_color())
	box.add_child(label)

	var edit := TextEdit.new()
	edit.text = str(value) if value != null else ""
	edit.custom_minimum_size = Vector2(200, 72)
	edit.wrap_mode = TextEdit.LINE_WRAPPING_BOUNDARY
	edit.text_changed.connect(func() -> void: _set_node_arg(key, edit.text))
	box.add_child(edit)

	add_child(box)

## A control for one argument's declared type, seeded with its current [param value].
## Falls back to a plain text field for every type with nothing more specific below -
## [constant EventCommand.T_STRING], [code]actor[/code], [code]condition[/code],
## [code]flag[/code], [code]var[/code] and [code]key[/code] terms alike, since all of
## them are just text an author types.
func _make_arg_control(type: String, value: Variant) -> Control:
	match type:
		EventCommand.T_FLOAT, EventCommand.T_SECONDS:
			var spin := SpinBox.new()
			spin.min_value = 0.0 if type == EventCommand.T_SECONDS else -100000.0
			spin.max_value = 100000.0
			spin.step = 0.01
			spin.value = float(value) if value is float or value is int else 0.0
			return spin

		EventCommand.T_INT:
			var spin := SpinBox.new()
			spin.min_value = -100000
			spin.max_value = 100000
			spin.step = 1
			spin.value = int(value) if value is float or value is int else 0
			return spin

		EventCommand.T_BOOL:
			var check := CheckBox.new()
			check.button_pressed = value is bool and value
			return check

		EventCommand.T_DIR:
			return _make_option_control(_DIR_OPTIONS, str(value) if value != null else "")

		EventCommand.T_TURN:
			var options := PackedStringArray()
			options.append_array(_TURN_OPTIONS)
			options.append_array(_DIR_OPTIONS)
			return _make_option_control(options, str(value) if value != null else "")

		EventCommand.T_CELL:
			var edit := LineEdit.new()
			edit.placeholder_text = "x, y, z"
			edit.text = _cell_text(value)
			return edit

		_:
			var edit := LineEdit.new()
			edit.text = str(value) if value != null else ""
			return edit

## An [OptionButton] offering [param options] plus a leading "(unset)" for an argument
## an author has not given a value yet - selecting it clears the argument rather than
## authoring an empty string, which [constant EventCommand.T_DIR] and
## [constant EventCommand.T_TURN] would both reject as not a direction.
func _make_option_control(options: PackedStringArray, current: String) -> OptionButton:
	var picker := OptionButton.new()
	picker.add_item("(unset)")
	for option in options:
		picker.add_item(option)

	var index := options.find(current.to_lower())
	picker.select(index + 1 if index >= 0 else 0)
	return picker

## "move_by"'s [code]cells[/code] as the direction-and-count pair an author actually
## thinks in, rather than a raw [code][x, y, z][/code] delta - the same shape the
## "mov" terse alias expands from ([method EventCommand._expand_terse]), reassembled
## here instead of shared with it since that method is private to its file.
##
## Two controls in [param row] rather than one, so this bypasses
## [method _make_arg_control]/[method _connect_arg_control] and wires itself.
func _add_move_direction_control(row: HBoxContainer, key: String, value: Variant) -> void:
	var decomposed := _direction_and_count(value)

	var direction := _make_option_control(_DIR_OPTIONS, decomposed["direction"])
	direction.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(direction)

	var count := SpinBox.new()
	count.min_value = 1
	count.max_value = 1000
	count.step = 1
	count.value = decomposed["count"] if decomposed["count"] > 0 else 1
	count.custom_minimum_size = Vector2(64, 0)
	row.add_child(count)

	var commit := func() -> void:
		if direction.selected <= 0:
			_clear_node_arg(key)
			return
		var dir := EventCommand.direction_of(direction.get_item_text(direction.selected))
		var n := int(count.value)
		_set_node_arg(key, [dir.x * n, dir.y * n, dir.z * n])

	direction.item_selected.connect(func(_index: int) -> void: commit.call())
	count.value_changed.connect(func(_value: float) -> void: commit.call())

## [param value] decomposed into one of [constant _DIR_OPTIONS] and a positive count -
## the inverse of [code]direction * count[/code], which is how a "mov" alias or this
## same control built the cell to begin with. Empty and 0 when [param value] is not a
## clean multiple of one compass direction - a cell authored by hand as something an
## eight-way compass cannot express.
func _direction_and_count(value: Variant) -> Dictionary:
	var cell := _as_cell_or_zero(value)
	if cell == Vector3i.ZERO:
		return {"direction": "", "count": 0}

	var count := maxi(maxi(absi(cell.x), absi(cell.y)), absi(cell.z))
	if count == 0 or cell.x % count != 0 or cell.y % count != 0 or cell.z % count != 0:
		return {"direction": "", "count": 0}

	var unit := Vector3i(cell.x / count, cell.y / count, cell.z / count)
	for token in _DIR_OPTIONS:
		if EventCommand.direction_of(token) == unit:
			return {"direction": token, "count": count}

	return {"direction": "", "count": 0}

## [param value] as a [Vector3i], or [constant Vector3i.ZERO] for anything not shaped
## like a cell. Duplicated from [method EventCommand._as_cell] rather than calling it -
## that method is private to its file, the same reasoning [code]event_document.gd[/code]
## gives for its own small duplicated helpers.
func _as_cell_or_zero(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Vector3:
		var v: Vector3 = value
		return Vector3i(roundi(v.x), roundi(v.y), roundi(v.z))
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Vector3i(int(a[0]), int(a[1]), int(a[2]))
	return Vector3i.ZERO

## An [OptionButton] of [constant _SPEED_PRESETS], for any "speed" argument. An
## optional speed gets a leading "(unset)"; a value that matches no preset exactly -
## greet_guard.event.json's hand-typed [code]0.18[/code], for one - gets a trailing
## "Custom" entry instead of being silently rounded to the preset nearest it.
func _make_speed_control(value: Variant, optional: bool) -> OptionButton:
	var picker := OptionButton.new()
	if optional:
		picker.add_item("(unset)")

	var labels: Array = _SPEED_PRESETS.keys()
	var authored := value is float or value is int
	var matched := -1
	for label in labels:
		picker.add_item(str(label))
		if authored and is_equal_approx(float(value), float(_SPEED_PRESETS[label])):
			matched = picker.item_count - 1

	if authored and matched < 0:
		picker.add_item("Custom (%s)" % str(value))
		picker.select(picker.item_count - 1)
	elif matched >= 0:
		picker.select(matched)
	elif optional:
		picker.select(0)
	else:
		# Required and never authored: falls back to "Normal", the preset that matches
		# what a node with no speed argument at all already plays at.
		picker.select(labels.find("Normal") + (1 if optional else 0))

	return picker

func _connect_speed_control(picker: OptionButton, key: String) -> void:
	picker.item_selected.connect(func(index: int) -> void:
		var text := picker.get_item_text(index)
		if text == "(unset)":
			_clear_node_arg(key)
		elif _SPEED_PRESETS.has(text):
			_set_node_arg(key, _SPEED_PRESETS[text])
		# Else the "Custom (...)" entry: nothing new to write, it only shows what the
		# node already carries.
	)

## An [OptionButton] of [constant _DIALOGUE_LOCATIONS], matching
## [enum Dialogue.Location] by index rather than by name - the args value this reads
## and writes is the int [method Dialogue.set_window_location] takes.
func _make_location_control(value: Variant, optional: bool) -> OptionButton:
	var picker := OptionButton.new()
	if optional:
		picker.add_item("(unset)")
	for label in _DIALOGUE_LOCATIONS:
		picker.add_item(label)

	var index := int(value) if (value is float or value is int) \
		and int(value) >= 0 and int(value) < _DIALOGUE_LOCATIONS.size() else -1
	var offset := 1 if optional else 0
	picker.select(index + offset if index >= 0 else 0)
	return picker

func _connect_location_control(picker: OptionButton, key: String) -> void:
	picker.item_selected.connect(func(index: int) -> void:
		var text := picker.get_item_text(index)
		if text == "(unset)":
			_clear_node_arg(key)
		else:
			_set_node_arg(key, _DIALOGUE_LOCATIONS.find(text))
	)

## Wires [param control]'s change signal to write straight into this node's command
## args, keyed by [param key]. [param optional] only matters for the option controls,
## whose "(unset)" entry has no value of its own to write.
func _connect_arg_control(control: Control, type: String, optional: bool, key: String) -> void:
	match type:
		EventCommand.T_FLOAT, EventCommand.T_SECONDS:
			(control as SpinBox).value_changed.connect(
				func(value: float) -> void: _set_node_arg(key, value))

		EventCommand.T_INT:
			(control as SpinBox).value_changed.connect(
				func(value: float) -> void: _set_node_arg(key, int(value)))

		EventCommand.T_BOOL:
			(control as CheckBox).toggled.connect(
				func(pressed: bool) -> void: _set_node_arg(key, pressed))

		EventCommand.T_DIR, EventCommand.T_TURN:
			var picker := control as OptionButton
			picker.item_selected.connect(func(index: int) -> void:
				if index <= 0:
					_clear_node_arg(key)
				else:
					_set_node_arg(key, picker.get_item_text(index)))

		EventCommand.T_CELL:
			var edit := control as LineEdit
			edit.text_submitted.connect(
				func(_text: String) -> void: _commit_cell_arg(key, edit, optional))
			edit.focus_exited.connect(
				func() -> void: _commit_cell_arg(key, edit, optional))

		_:
			var edit := control as LineEdit
			edit.text_changed.connect(func(text: String) -> void:
				if optional and text.strip_edges() == "":
					_clear_node_arg(key)
				else:
					_set_node_arg(key, text))

## [param value] as "x, y, z", or "" for anything that is not shaped like a cell -
## an unauthored optional argument, most of the time.
func _cell_text(value: Variant) -> String:
	if value is Vector3i:
		var v: Vector3i = value
		return "%d, %d, %d" % [v.x, v.y, v.z]
	if value is Vector3:
		var v: Vector3 = value
		return "%s, %s, %s" % [v.x, v.y, v.z]
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return "%s, %s, %s" % [a[0], a[1], a[2]]
	return ""

## [param text] as a three-element array - the same shape a hand-authored
## [code].event.json[/code] cell already uses - or null when it does not split into
## three numbers.
func _parse_cell(text: String) -> Variant:
	var parts := text.split(",")
	if parts.size() != 3:
		return null

	var cell := []
	for part in parts:
		var trimmed := part.strip_edges()
		if not trimmed.is_valid_float():
			return null
		cell.append(int(round(float(trimmed))))
	return cell

## Reads [param field]'s text back into this node's args on submit or blur. Bad text
## is rejected rather than authored: the field is reset to whatever the argument last
## held, so a stray character an author has not finished typing yet cannot silently
## replace a working cell.
func _commit_cell_arg(key: String, field: LineEdit, optional: bool) -> void:
	var text := field.text.strip_edges()
	if text == "":
		if optional:
			_clear_node_arg(key)
		else:
			field.text = _cell_text((extra.get("args", {}) as Dictionary).get(key))
		return

	var cell := _parse_cell(text)
	if cell == null:
		field.text = _cell_text((extra.get("args", {}) as Dictionary).get(key))
		return

	_set_node_arg(key, cell)

## Writes [param value] into this node's command args, creating the "args" dictionary
## on [member extra] if this is its first edited argument, and fires [signal changed].
func _set_node_arg(key: String, value: Variant) -> void:
	var args: Dictionary = extra.get("args", {})
	if not extra.has("args"):
		extra["args"] = args
	args[key] = value
	changed.emit()

## The other half of [method _set_node_arg]: removes [param key] entirely rather than
## authoring an empty value, for an optional argument put back to "not given".
func _clear_node_arg(key: String) -> void:
	var args: Dictionary = extra.get("args", {})
	if args.has(key):
		args.erase(key)
		changed.emit()

## The editor's label colour, faded back for text that is incidental rather than
## something the user asked to see. Duplicated from [code]graph_editor_panel.gd[/code]
## rather than shared - a one-line theme lookup, the same reasoning
## [code]event_document.gd[/code] gives its own small duplicated helpers.
func _muted_color() -> Color:
	var theme := EditorInterface.get_editor_theme()
	var color := Color.WHITE
	if theme.has_color(&"font_color", &"Editor"):
		color = theme.get_color(&"font_color", &"Editor")

	color.a *= 0.6
	return color
