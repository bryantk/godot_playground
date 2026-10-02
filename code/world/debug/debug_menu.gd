extends CanvasLayer

## The debug-category overlay [DebugFlags] builds for itself, in a debug build only
## (see [method DebugFlags._ready]) - a plain list of the six toggleable categories
## ([member DebugFlags.CATEGORIES]), each line showing its own key and current on/off
## state. Hidden until [code]~[/code] opens it ([signal DebugFlags.menu_opened_changed]);
## [signal DebugFlags.category_toggled] is what keeps a line's own text current without
## polling every frame. Non-blocking by design - nothing here touches [ModeStack], so
## the game keeps running while this is open, the same as the single flag it replaces
## never paused anything either.

## [member DebugFlags.CATEGORIES], spelled out for the label text - kept here rather
## than in [DebugFlags] itself since nothing there needs a human-readable name, only
## the [StringName] key.
const _LABELS := ["Event", "Area", "Transfer Marker", "Actor", "Passability", "Interact", "Route"]

var _lines: Array[Label] = []

var font_size := 10

## The seventh line, key 0 - [member DebugFlags.force_fast_forward] is a continuous
## hold state, not a press-to-flip category, so this is repainted every frame in
## [method _process] instead of off a signal the way [member _lines] are.
var _fast_forward_line: Label = null


func _ready() -> void:
	layer = 100
	visible = false

	var panel := PanelContainer.new()
	add_child(panel)

	var box := VBoxContainer.new()
	panel.add_child(box)

	var grid := GridContainer.new()
	grid.set_columns(2)
	box.add_child(grid)

	for i in DebugFlags.CATEGORIES.size():
		var line := Label.new()
		line.add_theme_font_size_override("font_size", font_size)
		grid.add_child(line)
		_lines.append(line)

	_fast_forward_line = Label.new()
	_fast_forward_line.add_theme_font_size_override("font_size", font_size)
	grid.add_child(_fast_forward_line)

	_build_replay_controls(box)
	_build_terminal(box)

	_repaint_all()

	DebugFlags.menu_opened_changed.connect(_on_menu_opened_changed)
	DebugFlags.category_toggled.connect(_on_category_toggled)


func _process(_delta: float) -> void:
	# Replay is stepped here, every frame whether or not the menu is showing - it is what
	# wires InputReplay's "call step_replay once per frame" contract to a real loop.
	if InputReplay.is_replaying():
		InputReplay.step_replay()

	if visible:
		_fast_forward_line.text = "[0] Fast Forward: %s" % (
			"ON" if DebugFlags.force_fast_forward else "OFF")
		_repaint_replay()


# -- Input capture / replay ---------------------------------------------------

var _record_button: Button = null
var _replay_buttons: Array[Button] = []
var _cancel_button: Button = null
var _replay_status: Label = null

## What the status line shows when nothing is recording or playing - the last thing done.
var _replay_note := "idle"


func _build_replay_controls(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())

	var heading := Label.new()
	heading.text = "Input replay"
	heading.add_theme_font_size_override("font_size", font_size - 4)
	box.add_child(heading)

	var row := HBoxContainer.new()
	box.add_child(row)

	_record_button = Button.new()
	_record_button.pressed.connect(_on_record_pressed)
	row.add_child(_record_button)

	for slot in range(1, InputReplay.SLOT_COUNT + 1):
		var button := Button.new()
		button.text = "Replay %d" % slot
		button.pressed.connect(_on_replay_pressed.bind(slot))
		row.add_child(button)
		_replay_buttons.append(button)

	_cancel_button = Button.new()
	_cancel_button.text = "Stop replay"
	_cancel_button.pressed.connect(_on_stop_replay_pressed)
	row.add_child(_cancel_button)

	_replay_status = Label.new()
	box.add_child(_replay_status)
	box.add_theme_font_size_override("font_size", font_size)
	_repaint_replay()


func _repaint_replay() -> void:
	var recording := InputReplay.is_recording()
	var replaying := InputReplay.is_replaying()
	_record_button.text = "Stop + save" if recording else "Record"
	_record_button.disabled = replaying
	_cancel_button.disabled = not replaying
	for button in _replay_buttons:
		button.disabled = recording or replaying

	if recording:
		_replay_status.text = "REC %d frames" % InputReplay.frame_count()
	elif replaying:
		_replay_status.text = "PLAY %d / %d" % [InputReplay.replay_cursor(), InputReplay.frame_count()]
	else:
		_replay_status.text = _replay_note


func _on_record_pressed() -> void:
	if InputReplay.is_recording():
		InputReplay.stop_recording()
		var slot := InputReplay.save()
		_replay_note = "saved to slot %d" % slot if slot > 0 else "save failed"
	else:
		InputReplay.start_recording()


func _on_replay_pressed(slot: int) -> void:
	var player := _find_player_controller(get_tree().root)
	if player == null:
		_replay_note = "no player to replay into"
		return
	InputReplay.bind(player)
	if InputReplay.start_replay(slot):
		_replay_note = "replayed slot %d" % slot
	else:
		InputReplay.unbind()
		_replay_note = "slot %d has no log" % slot


func _on_stop_replay_pressed() -> void:
	InputReplay.stop_replay()
	_replay_note = "replay stopped"


func _find_player_controller(node: Node) -> PlayerController:
	if node is PlayerController:
		return node as PlayerController
	for child in node.get_children():
		var found := _find_player_controller(child)
		if found != null:
			return found
	return null


func _on_menu_opened_changed(open: bool) -> void:
	visible = open
	if open:
		_repaint_all()
	elif _terminal_input != null:
		_terminal_input.release_focus()


func _on_category_toggled(category: StringName, shown: bool) -> void:
	var i := DebugFlags.CATEGORIES.find(category)
	if i >= 0:
		_set_line(i, shown)


func _repaint_all() -> void:
	for i in _lines.size():
		_set_line(i, DebugFlags.is_category_visible(DebugFlags.CATEGORIES[i]))


func _set_line(i: int, shown: bool) -> void:
	_lines[i].text = "[%d] %s: %s" % [i + 1, _LABELS[i], "ON" if shown else "OFF"]


# -- Terminal -----------------------------------------------------------------

## How many output lines and prior submissions the terminal keeps.
const _TERMINAL_LINES := 4
const _HISTORY_LIMIT := 100

var _terminal_output: RichTextLabel = null
var _terminal_input: LineEdit = null

## Prior submissions, oldest first, walked with Up/Down. [member _history_cursor] is an
## index into it, or [code]_history.size()[/code] when sitting on the fresh line.
var _history: Array[String] = []
var _history_cursor := 0

## Whether this menu has pushed [constant ModeStack.Mode.MENU] for the field being
## focused - typing "wasd" into it must not also walk the player around, and the mode
## stack is what [PlayerController] already reads to stop doing that.
var _holding_mode := false


func _build_terminal(box: VBoxContainer) -> void:
	box.add_child(HSeparator.new())

	var heading := Label.new()
	heading.text = "Terminal (GDScript expression on GameState - Up/Down history, Tab completes, Esc leaves)"
	heading.add_theme_font_size_override("font_size", font_size)
	box.add_child(heading)

	_terminal_output = RichTextLabel.new()
	_terminal_output.custom_minimum_size = Vector2(420, 60)
	_terminal_output.scroll_following = true
	_terminal_output.fit_content = false
	box.add_child(_terminal_output)

	_terminal_input = LineEdit.new()
	_terminal_input.placeholder_text = "e.g. var_get(\"chapter\")   or   set_flag(\"door_open\")"
	_terminal_input.keep_editing_on_text_submit = true
	_terminal_input.text_submitted.connect(_on_terminal_submitted)
	_terminal_input.gui_input.connect(_on_terminal_gui_input)
	_terminal_input.focus_entered.connect(_on_terminal_focus_entered)
	_terminal_input.focus_exited.connect(_on_terminal_focus_exited)
	box.add_child(_terminal_input)


func _on_terminal_focus_entered() -> void:
	if not _holding_mode:
		_holding_mode = true
		ModeStack.push(ModeStack.Mode.MENU)


func _on_terminal_focus_exited() -> void:
	if _holding_mode:
		_holding_mode = false
		ModeStack.pop()


func _on_terminal_gui_input(event: InputEvent) -> void:
	var key := event as InputEventKey
	if key == null or not key.pressed:
		return

	match key.keycode:
		KEY_UP:
			_history_step(-1)
			_terminal_input.accept_event()
		KEY_DOWN:
			_history_step(1)
			_terminal_input.accept_event()
		KEY_TAB:
			_complete()
			_terminal_input.accept_event()
		KEY_ESCAPE, KEY_QUOTELEFT:
			# Backtick would otherwise be typed into the field, and this is the key that
			# closes the menu - so it leaves the field instead, and the next press closes.
			_terminal_input.accept_event()
			_terminal_input.release_focus()


func _history_step(direction: int) -> void:
	if _history.is_empty():
		return
	_history_cursor = clampi(_history_cursor + direction, 0, _history.size())
	_terminal_input.text = _history[_history_cursor] if _history_cursor < _history.size() else ""
	_terminal_input.caret_column = _terminal_input.text.length()


func _on_terminal_submitted(text: String) -> void:
	var line := text.strip_edges()
	_terminal_input.clear()
	if line == "":
		return

	if _history.is_empty() or _history.back() != line:
		_history.append(line)
		if _history.size() > _HISTORY_LIMIT:
			_history.pop_front()
	_history_cursor = _history.size()

	_print_terminal("> " + line)
	_print_terminal(_evaluate(line))


## Runs [param line] as a GDScript expression with [GameState] as its base instance - so
## its methods read as bare calls ([code]flag("x")[/code], [code]var_set("n", 3)[/code] - plain strings, since Expression has no &"" literal) -
## and also as the input [code]game_state[/code]. The [code]@actor.[/code] shorthand
## ([ActorQueries]) works the same as in a condition: [code]@guard[/code] is rewritten to
## [code]actors["guard"][/code], so [code]@guard.near(3,0,4,2)[/code] and
## [code]@guard.flag("alerted", true)[/code] both run. Returns the text to show: the
## result, or what went wrong.
func _evaluate(line: String) -> String:
	var map := get_tree().get_first_node_in_group(&"map_context") as MapContext
	var expression := Expression.new()
	var error := expression.parse(_expand_actor_terms(line), ["game_state", "actors"])
	if error != OK:
		return "parse error: %s" % expression.get_error_text()

	var result: Variant = expression.execute(
		[GameState, ActorQueries.ActorsProxy.new(map)], GameState, true)
	if expression.has_execute_failed():
		return "error: %s" % expression.get_error_text()
	if result == null:
		return "<null>"
	if result is Object:
		return str(result)
	return var_to_str(result)


## Every [code]@name[/code] (a hyphen joins name parts, as in [code]@debug-3[/code]) as
## [code]actors["name"][/code] - Expression cannot parse an "@" term itself.
static func _expand_actor_terms(line: String) -> String:
	var term := RegEx.new()
	term.compile("@([A-Za-z_][A-Za-z0-9_]*(?:-[A-Za-z0-9_]+)*)")
	return term.sub(line, "actors[\"$1\"]", true)


func _print_terminal(text: String) -> void:
	_terminal_output.append_text(text.replace("[", "[lb]") + "\n")
	# Bounded: drop the oldest line once over the cap, so a long session does not grow
	# the label without limit.
	while _terminal_output.get_paragraph_count() > _TERMINAL_LINES:
		_terminal_output.remove_paragraph(0)


## Completes the identifier ending at the caret from [GameState]'s own methods and
## properties (plus [code]game_state[/code] itself): a single match is filled in, several
## extend to their common prefix and list what is left to choose from.
func _complete() -> void:
	var text := _terminal_input.text
	var caret := _terminal_input.caret_column
	var start := caret
	while start > 0 and _is_identifier_char(text[start - 1]):
		start -= 1
	var prefix := text.substr(start, caret - start)

	var matches: Array[String] = []
	for name in _completion_names():
		if name.begins_with(prefix) and name != prefix:
			matches.append(name)
	if matches.is_empty():
		return

	matches.sort()
	var common := matches[0]
	for name in matches:
		while not name.begins_with(common):
			common = common.left(common.length() - 1)

	_terminal_input.text = text.substr(0, start) + common + text.substr(caret)
	_terminal_input.caret_column = start + common.length()
	if matches.size() > 1:
		_print_terminal("  ".join(matches))


func _completion_names() -> Array[String]:
	var names: Array[String] = ["game_state"]
	for method: Dictionary in GameState.get_method_list():
		var name := str(method["name"])
		if not name.begins_with("_"):
			names.append(name)
	for property: Dictionary in GameState.get_property_list():
		var name := str(property["name"])
		if not name.begins_with("_") and not name.contains("/") and not names.has(name):
			names.append(name)
	return names


static func _is_identifier_char(c: String) -> bool:
	return c == "_" or (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or (c >= "0" and c <= "9")
