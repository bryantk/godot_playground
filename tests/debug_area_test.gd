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
	_test_2d_sizes_itself_from_the_sibling_actors_footprint()
	_test_2d_keeps_the_authored_size_with_no_actor_beside_it()
	_test_3d_builds_a_wire_box_sized_to_area_size()
	_test_3d_box_rests_on_the_anchor_rather_than_straddling_it()
	_test_3d_follows_the_placement_through_a_plain_node_parent()
	_test_3d_sizes_itself_from_the_sibling_actors_footprint()

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


## "Show the footprint": the box outgrows [member DebugArea2D.area_size]'s own
## default the moment a sibling [Actor] carries a bigger [member Actor.footprint],
## and starts wrapping the whole footprint rather than sitting centred on the
## anchor cell alone.
func _test_2d_sizes_itself_from_the_sibling_actors_footprint() -> void:
	_section("DebugArea2D -- auto-sizes and re-anchors from a sibling Actor's footprint")

	var ctx := MapContext.new()
	ctx.cell_size = Vector3(4, 0, 4)
	add_child(ctx)

	var placement := Node2D.new()
	add_child(placement)

	var actor := Actor.new()
	actor.actor_id = &"footprint_2d"
	actor.footprint = Vector3i(2, 1, 1)
	placement.add_child(actor)

	var game_event := Node.new()
	game_event.name = "GameEvent"
	placement.add_child(game_event)

	var area := DebugArea2D.new()
	game_event.add_child(area)
	area._ready()

	_eq(area.area_size, Vector2(8, 4), "area_size becomes footprint.x/z * cell_size")
	_eq(area._rect_pos, Vector2(-2, -2), "and the rect starts half a cell up/left of the anchor")

	ctx.free()
	placement.free()


func _test_2d_keeps_the_authored_size_with_no_actor_beside_it() -> void:
	_section("DebugArea2D -- a bodiless event (no Actor) keeps area_size exactly as authored")

	var area := DebugArea2D.new()
	area.area_size = Vector2(30, 10)
	add_child(area)

	_eq(area.area_size, Vector2(30, 10), "no Actor beside it, so nothing to derive a size from")
	_eq(area._rect_pos, Vector2(-15, -5), "and it stays centred on offset, as it always was")

	area.free()


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


## Regression: the box used to sit centred on the anchor - which is an actor's own
## ground position, not its middle - so it hung half its own height below the floor.
func _test_3d_box_rests_on_the_anchor_rather_than_straddling_it() -> void:
	_section("DebugArea3D -- the box rests on the anchor's ground, not centred through it")

	var area := DebugArea3D.new()
	area.area_size = Vector3(1, 2, 1)
	add_child(area)

	var box := area.get_node_or_null("WireBox") as MeshInstance3D
	_eq(box.position, Vector3(0, 1, 0), "raised by half its own height, so its base is at y=0")

	area.area_size = Vector3(1, 6, 1)
	_eq(box.position, Vector3(0, 3, 0), "and re-raised when area_size's own height changes")

	area.offset = Vector3(0, 1, 0)
	_eq(box.position, Vector3(0, 4, 0), "offset stacks on top of the half-height raise")

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


func _test_3d_sizes_itself_from_the_sibling_actors_footprint() -> void:
	_section("DebugArea3D -- auto-sizes X/Z (never Y) and re-anchors from a sibling Actor's footprint")

	var ctx := MapContext.new()
	ctx.cell_size = Vector3(4, 0, 4)
	add_child(ctx)

	var placement := Node3D.new()
	add_child(placement)

	var actor := Actor.new()
	actor.actor_id = &"footprint_3d"
	actor.footprint = Vector3i(1, 1, 3)
	placement.add_child(actor)

	var game_event := Node.new()
	game_event.name = "GameEvent"
	placement.add_child(game_event)

	var area := DebugArea3D.new()
	area.area_size = Vector3(1, 5, 1)
	game_event.add_child(area)
	area._ready()

	_eq(area.area_size, Vector3(4, 5, 12), "X/Z from footprint * cell_size; Y left exactly as authored")
	var box := area.get_node_or_null("WireBox") as MeshInstance3D
	_eq(box.position, Vector3(0, 2.5, 4), "X/Z re-anchored to the footprint, Y still resting on the ground")

	ctx.free()
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
