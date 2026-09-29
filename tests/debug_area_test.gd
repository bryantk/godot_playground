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
	_test_2d_sizes_itself_from_the_sibling_actors_footprint()
	_test_2d_keeps_the_authored_size_with_no_actor_beside_it()
	_test_2d_sizes_itself_from_a_sibling_collider()
	_test_2d_collider_beats_actor_when_both_are_present()
	_test_2d_an_explicit_target_is_never_overwritten()
	_test_2d_draws_the_grid_cells_a_sibling_polygon_covers()
	_test_2d_polygon_beats_actor_but_loses_to_a_collision_shape()
	_test_3d_builds_a_wire_box_sized_to_area_size()
	_test_3d_box_rests_on_the_anchor_rather_than_straddling_it()
	_test_3d_sizes_itself_from_the_sibling_actors_footprint()
	_test_3d_sizes_itself_from_a_sibling_collider()
	_test_default_colors_differ_between_2d_and_3d()
	_test_2d_fill_is_off_by_default_and_uses_a_transparent_color()
	_test_3d_fill_is_off_by_default_and_uses_a_transparent_color()

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


## "Show the footprint": the box outgrows [member DebugArea2D.area_size]'s own
## default the moment a sibling [Actor] carries a bigger [member Actor.footprint],
## and starts wrapping the whole footprint rather than sitting centred on the
## anchor cell alone. [DebugArea2D] sits directly under the placement root here,
## a sibling of [Actor] and [GameEvent] - see [DebugArea2D]'s own class doc for why
## it must sit there and nowhere deeper.
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
	placement.add_child(area)
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


## The collider-first branch of [method DebugArea2D._sync_target]: with only a
## [CollisionShape2D] beside it (no [Actor] here at all), the box takes the shape's
## own size and centres on the shape's own position, and the resolved sibling gets
## written back into [member DebugArea2D.target].
func _test_2d_sizes_itself_from_a_sibling_collider() -> void:
	_section("DebugArea2D -- sizes itself from a sibling CollisionShape2D (RectangleShape2D)")

	var placement := Node2D.new()
	add_child(placement)

	var collider := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(12, 6)
	collider.shape = rect
	collider.position = Vector2(2, -1)
	placement.add_child(collider)

	var area := DebugArea2D.new()
	placement.add_child(area)
	area._ready()

	_eq(area.target, collider, "auto-search resolves the collider and writes it into target")
	_eq(area.area_size, Vector2(12, 6), "area_size becomes the shape's own size")
	_eq(area._rect_pos, Vector2(-4, -4), "the rect centres on the collider's own position")

	placement.free()


func _test_2d_collider_beats_actor_when_both_are_present() -> void:
	_section("DebugArea2D -- a sibling collider is preferred over a sibling Actor")

	var placement := Node2D.new()
	add_child(placement)

	var actor := Actor.new()
	actor.actor_id = &"has_both"
	actor.footprint = Vector3i(1, 1, 1)
	placement.add_child(actor)

	var collider := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(20, 20)
	collider.shape = rect
	placement.add_child(collider)

	var area := DebugArea2D.new()
	placement.add_child(area)
	area._ready()

	_eq(area.target, collider, "the collider wins the default auto-search over the Actor")

	placement.free()


func _test_2d_an_explicit_target_is_never_overwritten() -> void:
	_section("DebugArea2D -- an explicitly-assigned target is left alone")

	var placement := Node2D.new()
	add_child(placement)

	var actor := Actor.new()
	actor.actor_id = &"explicit"
	actor.footprint = Vector3i(1, 1, 1)
	placement.add_child(actor)

	var collider := CollisionShape2D.new()
	collider.shape = RectangleShape2D.new()
	placement.add_child(collider)

	var area := DebugArea2D.new()
	area.target = actor
	placement.add_child(area)
	area._ready()

	_eq(area.target, actor, "the hand-assigned target overrides the collider-first default")

	placement.free()


## The [CollisionPolygon2D] branch of [method DebugArea2D._sync_footprint]: rather
## than the polygon's own smooth outline, the box becomes one rect per grid cell whose
## own centre falls inside it - the same cell-centre question [method
## AreaZone.zones_at] asks the physics server.
func _test_2d_draws_the_grid_cells_a_sibling_polygon_covers() -> void:
	_section("DebugArea2D -- sizes itself from a sibling CollisionPolygon2D's covered cells")

	var ctx := MapContext.new()
	ctx.cell_size = Vector3(4, 0, 4)
	add_child(ctx)

	var placement := Node2D.new()
	add_child(placement)

	var poly := CollisionPolygon2D.new()
	poly.polygon = PackedVector2Array([
		Vector2(0, 0), Vector2(8, 0), Vector2(8, 4), Vector2(0, 4),
	])
	placement.add_child(poly)

	var area := DebugArea2D.new()
	placement.add_child(area)
	area._ready()

	_eq(area.target, poly, "auto-search resolves the polygon and writes it into target")
	_eq(area._covered_cells.size(), 2, "the 8x4 rect covers exactly two 4x4 cells")
	_ok(area._covered_cells.has(Vector2i(0, 0)) and area._covered_cells.has(Vector2i(1, 0)),
		"specifically the two cells the rect actually spans")
	_eq(area._cell_size, Vector2(4, 4), "cached from MapContext.cell_size's own X/Z")

	ctx.free()
	placement.free()


func _test_2d_polygon_beats_actor_but_loses_to_a_collision_shape() -> void:
	_section("DebugArea2D -- auto-search order is CollisionShape2D, then CollisionPolygon2D, then Actor")

	var placement := Node2D.new()
	add_child(placement)

	var actor := Actor.new()
	actor.actor_id = &"polygon_vs_actor"
	actor.footprint = Vector3i(1, 1, 1)
	placement.add_child(actor)

	var poly := CollisionPolygon2D.new()
	poly.polygon = PackedVector2Array([Vector2(0, 0), Vector2(4, 0), Vector2(4, 4), Vector2(0, 4)])
	placement.add_child(poly)

	var area := DebugArea2D.new()
	placement.add_child(area)
	area._ready()

	_eq(area.target, poly, "the polygon wins the default auto-search over the Actor")

	var collider := CollisionShape2D.new()
	collider.shape = RectangleShape2D.new()
	placement.add_child(collider)

	area.target = null
	area._ready()

	_eq(area.target, collider, "but a CollisionShape2D still wins over the polygon")

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


## [DebugArea3D] sits directly under the placement root here, a sibling of [Actor]
## and [GameEvent] - see [DebugArea3D]'s own class doc (via [DebugArea2D]'s) for why
## it must sit there and nowhere deeper.
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
	placement.add_child(area)
	area._ready()

	_eq(area.area_size, Vector3(4, 5, 12), "X/Z from footprint * cell_size; Y left exactly as authored")
	var box := area.get_node_or_null("WireBox") as MeshInstance3D
	_eq(box.position, Vector3(0, 2.5, 4), "X/Z re-anchored to the footprint, Y still resting on the ground")

	ctx.free()
	placement.free()


## The collider-first branch of [method DebugArea3D._sync_target]: with only a
## [CollisionShape3D] beside it (no [Actor] here at all), the box takes the shape's
## own size and centres on the collider's own [member CollisionShape3D.position] -
## no ground-resting correction, unlike the footprint path.
func _test_3d_sizes_itself_from_a_sibling_collider() -> void:
	_section("DebugArea3D -- sizes itself from a sibling CollisionShape3D (BoxShape3D)")

	var placement := Node3D.new()
	add_child(placement)

	var collider := CollisionShape3D.new()
	var box := BoxShape3D.new()
	box.size = Vector3(2, 3, 4)
	collider.shape = box
	collider.position = Vector3(0, 1.5, 0)
	placement.add_child(collider)

	var area := DebugArea3D.new()
	placement.add_child(area)
	area._ready()

	_eq(area.target, collider, "auto-search resolves the collider and writes it into target")
	_eq(area.area_size, Vector3(2, 3, 4), "area_size becomes the shape's own size")
	var box_mesh := area.get_node_or_null("WireBox") as MeshInstance3D
	_eq(box_mesh.position, Vector3(0, 1.5, 0),
		"the box centres on the collider's own position, no ground-resting correction")

	placement.free()


func _test_default_colors_differ_between_2d_and_3d() -> void:
	_section("DebugArea2D / DebugArea3D -- default colors differ so mixed views read apart")

	var area2d := DebugArea2D.new()
	add_child(area2d)
	var area3d := DebugArea3D.new()
	add_child(area3d)

	_ok(area2d.color != area3d.color, "2D and 3D defaults are not the same color")

	area2d.free()
	area3d.free()


func _test_2d_fill_is_off_by_default_and_uses_a_transparent_color() -> void:
	_section("DebugArea2D -- fill defaults off and washes color at a quarter alpha")

	var area := DebugArea2D.new()
	add_child(area)

	_ok(not area.fill, "fill starts off - the outline alone is the default")
	var faded: Color = area._fill_color()
	_eq(Vector3(faded.r, faded.g, faded.b), Vector3(area.color.r, area.color.g, area.color.b),
		"the fill is the same color")
	_eq(faded.a, area.color.a * 0.25, "at a quarter of its own alpha")

	area.free()


func _test_3d_fill_is_off_by_default_and_uses_a_transparent_color() -> void:
	_section("DebugArea3D -- fill defaults off, adds a sized FillBox once switched on")

	var area := DebugArea3D.new()
	area.area_size = Vector3(2, 3, 4)
	add_child(area)

	var fill_box := area.get_node_or_null("FillBox") as MeshInstance3D
	_ok(fill_box != null, "the fill box exists from the first _ready, same as WireBox")
	_ok(not fill_box.visible, "but stays hidden until fill is switched on")

	area.fill = true
	_ok(fill_box.visible, "switching fill on shows it")
	_eq((fill_box.mesh as BoxMesh).size, Vector3(2, 3, 4), "sized the same as the wireframe box")

	var faded: Color = area._fill_color()
	_eq(Vector3(faded.r, faded.g, faded.b), Vector3(area.color.r, area.color.g, area.color.b),
		"the fill is the same color")
	_eq(faded.a, area.color.a * 0.25, "at a quarter of its own alpha")

	area.free()


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
