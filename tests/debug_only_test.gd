extends Node

## Headless assertions over [code]games/jrpg/debug_only.gd[/code]: a child node that
## hides or shows its own parent by following [method DebugFlags.show_debug_view] at
## runtime - the same visibility rule [DebugArea2D]/[DebugArea3D] use, applied to an
## ordinary debug-only marker (an [AreaZone]'s own visualization) instead of a fresh
## node type.
##
##     godot --headless --path . res://tests/debug_only_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("games/jrpg -- debug_only.gd follows DebugFlags.show_debug_view")
	print("")

	_test_parent_visibility_follows_the_debug_flag()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_parent_visibility_follows_the_debug_flag() -> void:
	_section("debug_only -- hides/shows its own parent, not itself")

	var was_on := DebugFlags.show_debug_view()
	DebugFlags._show_debug_view = false

	var marker := Node2D.new()
	add_child(marker)

	var debug_only := Node.new()
	debug_only.set_script(load("res://games/jrpg/debug_only.gd"))
	marker.add_child(debug_only)

	_ok(not marker.visible, "the parent starts hidden while the debug view is off")

	DebugFlags._show_debug_view = true
	debug_only._process(0.0)
	_ok(marker.visible, "and is shown the moment it is switched on")

	DebugFlags._show_debug_view = false
	debug_only._process(0.0)
	_ok(not marker.visible, "hidden again when it's switched back off")

	DebugFlags._show_debug_view = was_on
	marker.free()


# -- Assertion helpers ---------------------------------------------------------------

func _section(title: String) -> void:
	print("  %s" % title)

func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1
