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
	_test_parent_stays_hidden_while_the_menu_is_closed()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_parent_visibility_follows_the_debug_flag() -> void:
	_section("debug_only -- hides/shows its own parent, not itself")

	# show_debug_view() is the catch-all "is any category on" - every category starts
	# true (DebugFlags._ready()), so all of them have to go off together to exercise
	# the "hidden" side; flipping one back on is enough for the "shown" side, without
	# caring which. The menu itself also has to be open - is_category_visible() (and
	# so show_debug_view()) reads false outright while it's closed, regardless of any
	# category's own state.
	var was_menu_open := DebugFlags._menu_open
	DebugFlags._menu_open = true
	var saved := DebugFlags._category_visible.duplicate()
	for category in DebugFlags.CATEGORIES:
		DebugFlags._category_visible[category] = false

	var marker := Node2D.new()
	add_child(marker)

	var debug_only := Node.new()
	debug_only.set_script(load("res://games/jrpg/debug_only.gd"))
	marker.add_child(debug_only)

	_ok(not marker.visible, "the parent starts hidden while the debug view is off")

	DebugFlags._category_visible[&"event"] = true
	debug_only._process(0.0)
	_ok(marker.visible, "and is shown the moment it is switched on")

	DebugFlags._category_visible[&"event"] = false
	debug_only._process(0.0)
	_ok(not marker.visible, "hidden again when it's switched back off")

	DebugFlags._category_visible = saved
	DebugFlags._menu_open = was_menu_open
	marker.free()


## "disable drawing debug areas in game UNLESS the ~ debug window is open" - every
## category can be on and it still must not draw with the menu itself closed.
func _test_parent_stays_hidden_while_the_menu_is_closed() -> void:
	_section("debug_only -- stays hidden while the debug menu is closed, categories on or not")

	var was_menu_open := DebugFlags._menu_open
	DebugFlags._menu_open = false
	var saved := DebugFlags._category_visible.duplicate()
	for category in DebugFlags.CATEGORIES:
		DebugFlags._category_visible[category] = true

	var marker := Node2D.new()
	add_child(marker)

	var debug_only := Node.new()
	debug_only.set_script(load("res://games/jrpg/debug_only.gd"))
	marker.add_child(debug_only)
	debug_only._process(0.0)

	_ok(not marker.visible, "hidden with every category on, since the menu itself is closed")

	DebugFlags._menu_open = true
	debug_only._process(0.0)
	_ok(marker.visible, "and shown the moment the menu opens, same category state untouched")

	DebugFlags._category_visible = saved
	DebugFlags._menu_open = was_menu_open
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
