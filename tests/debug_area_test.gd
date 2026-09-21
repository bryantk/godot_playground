extends Node

## Headless assertions over [DebugArea2D] and [DebugArea3D]: draws an outline/wireframe,
## nothing else, and follows [method DebugFlags.show_debug_view] at runtime while
## always showing in the editor.
##
##     godot --headless --path . res://tests/debug_area_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("core -- DebugArea2D / DebugArea3D")
	print("")

	_test_2d_hidden_then_shown_by_the_debug_flag()
	_test_2d_follows_the_placement_through_a_plain_node_parent()
	_test_3d_builds_a_wire_box_sized_to_area_size()
	_test_3d_follows_the_placement_through_a_plain_node_parent()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_2d_hidden_then_shown_by_the_debug_flag() -> void:
	_section("DebugArea2D -- follows DebugFlags.show_debug_view at runtime")

	var was_on := DebugFlags.show_debug_view()
	DebugFlags._show_debug_view = false

	var area := DebugArea2D.new()
	add_child(area)

	_ok(not area.visible, "hidden while the debug view starts off")

	DebugFlags._show_debug_view = true
	area._process(0.0)
	_ok(area.visible, "shown the moment it is switched on")

	DebugFlags._show_debug_view = false
	area._process(0.0)
	_ok(not area.visible, "and hidden again when it's switched back off")

	DebugFlags._show_debug_view = was_on
	area.free()


## The shape a real placement is: [DebugArea2D] as [GameEvent]'s own child, [GameEvent]
## a plain [Node] sibling of [Actor] under a [Node2D] placement root - see
## [method DebugArea2D._find_anchor]'s own doc for why a [CanvasItem] child of a plain
## [Node] cannot just inherit that root's transform for free.
func _test_2d_follows_the_placement_through_a_plain_node_parent() -> void:
	_section("DebugArea2D -- mirrors the placement's position through a plain-Node parent")

	var placement := Node2D.new()
	placement.position = Vector2(100, 50)
	add_child(placement)

	var game_event := Node.new()
	game_event.name = "GameEvent"
	placement.add_child(game_event)

	var area := DebugArea2D.new()
	game_event.add_child(area)
	area._ready()

	_eq(area.global_position, placement.global_position,
		"the marker starts where the placement is, not at the world origin")

	placement.position = Vector2(-40, 200)
	area._process(0.0)
	_eq(area.global_position, placement.global_position,
		"and keeps tracking it after the placement moves")

	placement.free()


func _test_3d_builds_a_wire_box_sized_to_area_size() -> void:
	_section("DebugArea3D -- one MeshInstance3D wire box, rebuilt when area_size changes")

	var area := DebugArea3D.new()
	add_child(area)

	var box := area.get_node_or_null("WireBox") as MeshInstance3D
	_ok(box != null, "the wire box child exists after _ready")
	_ok(box.mesh is ArrayMesh, "carrying a real mesh, not a placeholder")

	var first_mesh := box.mesh
	area.area_size = Vector3(2, 3, 4)
	_ok(box.mesh != first_mesh, "changing area_size rebuilds the mesh rather than scaling the node")

	area.free()


func _test_3d_follows_the_placement_through_a_plain_node_parent() -> void:
	_section("DebugArea3D -- mirrors the placement's position through a plain-Node parent")

	var placement := Node3D.new()
	placement.position = Vector3(1, 0, 2)
	add_child(placement)

	var game_event := Node.new()
	game_event.name = "GameEvent"
	placement.add_child(game_event)

	var area := DebugArea3D.new()
	game_event.add_child(area)
	area._ready()

	_eq(area.global_position, placement.global_position,
		"the marker starts where the placement is, not at the world origin")

	placement.position = Vector3(-4, 0, 20)
	area._process(0.0)
	_eq(area.global_position, placement.global_position,
		"and keeps tracking it after the placement moves")

	placement.free()


# -- Assertion helpers ---------------------------------------------------------------

func _section(title: String) -> void:
	print("  %s" % title)

func _eq(got: Variant, want: Variant, what: String) -> void:
	var same: bool = got == want
	print(("    ok    " if same else "    FAIL  ") + what
		+ ("" if same else "  (got %s, want %s)" % [got, want]))
	if same:
		_passed += 1
	else:
		_failed += 1

func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1
