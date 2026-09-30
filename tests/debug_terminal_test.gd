extends Node

## Headless assertions over the debug menu's terminal (code/world/debug/debug_menu.gd):
## EVAL against [GameState], history, Tab completion, and the ModeStack hold that keeps
## typing from walking the player.
##
##     godot --headless --path . res://tests/debug_terminal_test.tscn

const DebugMenu := preload("res://code/world/debug/debug_menu.gd")

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("debug menu -- terminal")
	print("")

	GameState.clear()
	var menu: Node = DebugMenu.new()
	add_child(menu)

	_section("terminal -- GDScript expressions run with GameState as the base")
	_eq(menu._evaluate("flag(\"door\")"), "false", "a bare GameState method reads a flag")
	menu._evaluate("set_flag(\"door\")")
	_ok(GameState.flag(&"door"), "set_flag wrote through to GameState")
	_eq(menu._evaluate("game_state.flag(\"door\")"), "true", "game_state names the same object")
	_ok(menu._evaluate("1 +").begins_with("parse error"), "a malformed line reports a parse error")
	_ok(menu._evaluate("nope()").begins_with("error"), "an unknown call reports an error")

	_section("terminal -- history walks back with Up and forward with Down")
	menu._terminal_input.text_submitted.emit("1 + 1")
	menu._terminal_input.text_submitted.emit("2 + 2")
	menu._history_step(-1)
	_eq(menu._terminal_input.text, "2 + 2", "Up recalls the last submission")
	menu._history_step(-1)
	_eq(menu._terminal_input.text, "1 + 1", "Up again recalls the one before")
	menu._history_step(1)
	menu._history_step(1)
	_eq(menu._terminal_input.text, "", "Down past the newest returns to a blank line")

	_section("terminal -- Tab completes from GameState's own members")
	menu._terminal_input.text = "set_f"
	menu._terminal_input.caret_column = 5
	menu._complete()
	_eq(menu._terminal_input.text, "set_flag", "a unique prefix is filled in")
	menu._terminal_input.text = "var_"
	menu._terminal_input.caret_column = 4
	menu._complete()
	_ok(menu._terminal_input.text.begins_with("var_"), "a shared prefix is kept")

	_section("terminal -- focusing the field holds ModeStack.MENU so the player stops")
	var depth := ModeStack.depth()
	menu._on_terminal_focus_entered()
	_eq(ModeStack.current(), ModeStack.Mode.MENU, "focus pushes MENU")
	menu._on_terminal_focus_exited()
	_eq(ModeStack.depth(), depth, "losing focus pops it again")
	menu._on_terminal_focus_exited()
	_eq(ModeStack.depth(), depth, "and a second loss does not pop twice")

	GameState.clear()
	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, "%s (got %s, want %s)" % [what, str(got), str(want)] if got != want else what)
