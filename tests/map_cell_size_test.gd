extends Node

## Headless assertions over [member MapContext.map_cell_size]: a map's tile art can
## stay painted at its own (coarser) grid while actors move and occupy a finer one,
## with [method Passability.allows_step] only consulting the paint at a crossed *map*
## cell boundary - the fix for cell_size=8 breaking collision when a map's TileMapLayer
## was still painted for cell_size=16 (jrpg_demo's own regression).
##
##     godot --headless --path . res://tests/map_cell_size_test.tscn

const E := Passability.EAST
const S := Passability.SOUTH
const N := Passability.NORTH
const W := Passability.WEST

## Mirrors tests/stage_a_test.gd's own atlas map for jrpg_pathing.tres.
const PATHING_TILES := {
	0: Vector2i(0, 0), 6: Vector2i(1, 0), 14: Vector2i(2, 0), 12: Vector2i(3, 0),
	5: Vector2i(0, 1), 7: Vector2i(1, 1), 15: Vector2i(2, 1), 13: Vector2i(3, 1),
	10: Vector2i(0, 2), 3: Vector2i(1, 2), 11: Vector2i(2, 2), 9: Vector2i(3, 2),
	8: Vector2i(0, 3), 1: Vector2i(1, 3), 4: Vector2i(2, 3), 2: Vector2i(3, 3),
}

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("core -- MapContext.map_cell_size, the actor-grid/tile-grid ratio")
	print("")

	_test_unset_map_cell_size_is_the_identity()
	_test_step_inside_one_map_cell_ignores_the_paint()
	_test_step_crossing_a_map_cell_boundary_checks_the_paint()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_unset_map_cell_size_is_the_identity() -> void:
	_section("map_cell_of -- unset map_cell_size is the identity, every existing map's default")

	var ctx := MapContext.new()
	ctx.cell_size = Vector3(8, 0, 8)
	_eq(ctx.map_cell_of(Vector3i(3, 0, -5)), Vector3i(3, 0, -5),
		"a cell maps to itself with no map_cell_size set")
	ctx.free()


func _build_ctx() -> Dictionary:
	var root := Node2D.new()
	add_child(root)
	var ctx := MapContext.new()
	ctx.name = "MapContext"
	ctx.cell_size = Vector3(1, 0, 1)
	ctx.map_cell_size = Vector3(2, 0, 2)
	ctx.collision_node = ^"../Pathing"
	root.add_child(ctx)

	var layer := TileMapLayer.new()
	layer.name = "Pathing"
	layer.tile_set = load("res://games/jrpg/jrpg_pathing.tres")
	root.add_child(layer)

	return {"root": root, "ctx": ctx, "layer": layer}


func _test_step_inside_one_map_cell_ignores_the_paint() -> void:
	_section("allows_step -- a step that stays inside one map cell ignores the paint entirely")

	var rig := _build_ctx()
	var ctx: MapContext = rig["ctx"]
	var layer: TileMapLayer = rig["layer"]

	# Map cell (0,0,0) covers actor cells (0,0,0) and (1,0,0) at this 2:1 ratio.
	# Painted with nothing open at all - a wall by every reading - and the internal
	# step between its two actor cells is still allowed, because the mask describes
	# the map cell's own four outer sides, not a subdivision it does not know exists.
	_paint(layer, Vector3i(0, 0, 0), 0)
	_eq(ctx.map_cell_of(Vector3i(0, 0, 0)), Vector3i(0, 0, 0), "both actor cells...")
	_eq(ctx.map_cell_of(Vector3i(1, 0, 0)), Vector3i(0, 0, 0), "...share one map cell")
	_ok(Passability.allows_step(ctx, Vector3i(0, 0, 0), Vector3i(1, 0, 0)),
		"internal step allowed despite a blank (all-walls) map tile")

	(rig["root"] as Node).free()


func _test_step_crossing_a_map_cell_boundary_checks_the_paint() -> void:
	_section("allows_step -- a step crossing a map cell boundary is checked against the paint")

	var rig := _build_ctx()
	var ctx: MapContext = rig["ctx"]
	var layer: TileMapLayer = rig["layer"]

	# Map cell (0,0,0) [actor cells x=0,1] painted open to the east; map cell (1,0,0)
	# [actor cells x=2,3] left unpainted (OPEN). The crossing is actor cell (1,0,0) ->
	# (2,0,0), which lands on the map cell boundary itself.
	_paint(layer, Vector3i(0, 0, 0), E)
	_eq(ctx.map_cell_of(Vector3i(1, 0, 0)), Vector3i(0, 0, 0), "leaving from map cell 0")
	_eq(ctx.map_cell_of(Vector3i(2, 0, 0)), Vector3i(1, 0, 0), "into map cell 1")
	_ok(Passability.allows_step(ctx, Vector3i(1, 0, 0), Vector3i(2, 0, 0)),
		"east flag on map cell 0 and an unpainted (open) map cell 1 agree")

	# Repaint map cell 0 with no east flag - the same boundary now refuses the step,
	# proving the check really did move to the map cell's own edge, not the actor
	# cell's non-existent one.
	_paint(layer, Vector3i(0, 0, 0), S)
	_ok(not Passability.allows_step(ctx, Vector3i(1, 0, 0), Vector3i(2, 0, 0)),
		"no east flag on map cell 0 refuses the same crossing")

	(rig["root"] as Node).free()


func _paint(layer: TileMapLayer, cell: Vector3i, mask: int) -> void:
	layer.set_cell(Space.as_v2i(cell), 0, PATHING_TILES[mask])


# -- Assertion helpers ---------------------------------------------------------------

func _section(title: String) -> void:
	print("  %s" % title)

func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1

func _eq(got: Variant, want: Variant, what: String) -> void:
	var same: bool = got == want
	print(("    ok    " if same else "    FAIL  ") + what
		+ ("" if same else "  (got %s, want %s)" % [got, want]))
	if same:
		_passed += 1
	else:
		_failed += 1
