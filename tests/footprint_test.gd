extends Node

## Headless assertions over multi-cell [member Actor.footprint]: [Occupancy] claiming
## and moving every cell of a footprint at once, and [Passability] checking every
## crossed edge of one, not just the anchor cell's own.
##
##     godot --headless --path . res://tests/footprint_test.tscn

const N := Passability.NORTH
const E := Passability.EAST
const S := Passability.SOUTH
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
	print("actors/core -- multi-cell footprints")
	print("")

	_test_actor_reports_its_footprint_cells()
	_test_spawn_claims_every_footprint_cell()
	_test_step_moves_the_whole_footprint()
	_test_step_refused_by_a_blocker_on_any_footprint_cell()
	_test_pathing_mask_checks_every_footprint_edge()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_actor_reports_its_footprint_cells() -> void:
	_section("Actor.footprint_cells -- anchored at cell(), one entry per default footprint")

	var solo := Actor.new()
	_eq(solo.footprint_cells(), [Vector3i.ZERO], "the default 1x1x1 footprint is just cell()")

	var wide := Actor.new()
	wide.footprint = Vector3i(2, 1, 3)
	_eq(wide.footprint_cells(),
		[Vector3i(0, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, 2),
			Vector3i(1, 0, 0), Vector3i(1, 0, 1), Vector3i(1, 0, 2)],
		"a 2x1x3 footprint covers all six cells from the anchor")

	solo.free()
	wide.free()


func _test_spawn_claims_every_footprint_cell() -> void:
	_section("Actor._claim_spawn_cell -- place_many over the whole footprint")

	var root := Node3D.new()
	add_child(root)
	var ctx := MapContext.new()
	ctx.map_id = &"footprint_spawn_test"
	ctx.cell_size = Vector3.ONE
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)

	var body := Node3D.new()
	body.position = ctx.cell_centre(Vector3i(3, 0, 4))
	var actor := Actor.new()
	actor.actor_id = &"big"
	actor.footprint = Vector3i(2, 1, 1)
	body.add_child(actor)
	var adapter := Space3D.new()
	actor.add_child(adapter)
	root.add_child(body)

	actor._claim_spawn_cell()

	var claimed := ctx.occupancy.cells_of(&"big")
	_ok(claimed.has(Vector3i(3, 0, 4)), "the anchor cell is claimed")
	_ok(claimed.has(Vector3i(4, 0, 4)), "and the second footprint cell too")
	_eq(claimed.size(), 2, "and nothing extra")

	root.free()


func _test_step_moves_the_whole_footprint() -> void:
	_section("GridMotion.step -- a footprint actor moves every one of its cells together")

	var rig := _build_world()
	var actor := _build_footprint_actor(rig, &"mover", Vector3i(2, 1, 1), Vector3i(0, 0, 0))

	var stepped := actor.motion().step(Vector3i(1, 0, 0))
	_ok(stepped, "the step succeeds on open ground")
	_eq(actor.cell(), Vector3i(1, 0, 0), "the anchor cell advanced by one")

	var claimed := (rig["ctx"] as MapContext).occupancy.cells_of(&"mover")
	_ok(claimed.has(Vector3i(1, 0, 0)) and claimed.has(Vector3i(2, 0, 0)),
		"and Occupancy now holds both of the new footprint's cells")
	_ok(not claimed.has(Vector3i(0, 0, 0)) and not claimed.has(Vector3i(1, 0, 0) - Vector3i(1, 0, 0)),
		"with the old anchor cell released")
	_eq(claimed.size(), 2, "still exactly two cells, not a stray third")

	(rig["root"] as Node).free()


func _test_step_refused_by_a_blocker_on_any_footprint_cell() -> void:
	_section("GridMotion.step -- refused if a blocker sits on ANY destination cell, not just the anchor")

	var rig := _build_world()
	var ctx: MapContext = rig["ctx"]
	var actor := _build_footprint_actor(rig, &"mover", Vector3i(2, 1, 1), Vector3i(0, 0, 0))

	# A step east would land the footprint on (1,0,0) and (2,0,0). Block only the
	# second cell - the one a 1x1 actor's own step would never have touched.
	ctx.occupancy.place(&"rock", Vector3i(2, 0, 0))

	var stepped := actor.motion().step(Vector3i(1, 0, 0))
	_ok(not stepped, "refused even though the anchor's own destination cell is clear")
	_eq(actor.cell(), Vector3i(0, 0, 0), "and the actor never moved")

	(rig["root"] as Node).free()


func _test_pathing_mask_checks_every_footprint_edge() -> void:
	_section("Passability.can_enter_footprint -- every crossed edge is consulted, not just the anchor's")

	var root := Node2D.new()
	add_child(root)
	var ctx := MapContext.new()
	ctx.name = "MapContext"
	ctx.cell_size = Vector3(16, 0, 16)
	ctx.collision_node = ^"../Pathing"
	root.add_child(ctx)

	var layer := TileMapLayer.new()
	layer.name = "Pathing"
	layer.tile_set = load("res://games/jrpg/jrpg_pathing.tres")
	root.add_child(layer)

	# A 2-cell-wide footprint at (0,0,0)/(0,0,1), stepping south (+Z) onto (0,0,1)/(0,0,2).
	# Wall off only the second cell's own south face - the anchor's own edge stays open.
	var from_cells: Array[Vector3i] = [Vector3i(0, 0, 0), Vector3i(0, 0, 1)]
	var to_cells: Array[Vector3i] = [Vector3i(0, 0, 1), Vector3i(0, 0, 2)]

	var actor := Actor.new()
	actor.actor_id = &"footprint_walker"

	_ok(Passability.can_enter_footprint(ctx, from_cells, to_cells, actor),
		"open ground: every pair of edges agrees, so the footprint may enter")

	_paint(layer, Vector3i(0, 0, 1), N | E | W)  # no south flag on the second cell
	_ok(not Passability.can_enter_footprint(ctx, from_cells, to_cells, actor),
		"one blocked edge on the far cell refuses the whole footprint's step")

	actor.free()
	root.free()


# -- Test rig ------------------------------------------------------------------------

func _build_world() -> Dictionary:
	var root := Node3D.new()
	add_child(root)

	var ctx := MapContext.new()
	ctx.map_id = &"footprint_test"
	ctx.cell_size = Vector3.ONE
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)

	return {"root": root, "ctx": ctx}


## Deliberately viewless - no ActorView child - so a step settles synchronously inside
## whatever call started it, matching every headless test actor elsewhere in tests/.
func _build_footprint_actor(world: Dictionary, id: StringName, footprint: Vector3i,
		cell: Vector3i) -> Actor:
	var root: Node = world["root"]
	var ctx: MapContext = world["ctx"]

	var body := Node3D.new()
	body.name = str(id)
	body.position = ctx.cell_centre(cell)

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = id
	actor.footprint = footprint
	actor.facing_count = 4
	body.add_child(actor)

	var adapter := Space3D.new()
	adapter.name = "Space"
	actor.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = 4
	actor.add_child(motion)

	root.add_child(body)
	actor._claim_spawn_cell()
	return actor


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
