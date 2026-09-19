extends Node

## Headless assertions over grid movement in three dimensions: ramps, stairs, ladders
## and falling (open-questions 36, 37, 38).
##
##     godot --headless --path . res://tests/height_test.tscn
##
## [b]3D grid only.[/b] Nothing here touches a flat map or [FreeMotion], and the last
## section proves it: the same map with no [member MapContext.floor_node] behaves exactly
## as it did before any of this existed.
##
## The map is built in code, with a [MeshLibrary] built in code too - items need names,
## not meshes, because [Terrain] reads the name and the orientation and nothing else.
## That keeps this test free of art and of the hand-authored demo scenes.
##
## The layout, one row of Z per thing being tested:
## [codeblock]
## z=0  ramp and stairs, three levels        0 0 R 1 1 S 2 2      (walking east)
## z=2  a ladder up a two-cell cliff         0 0 L . .
##                                              L   2 2
## z=4  ledges to fall off                   . . _ . _
## z=6  a one-cell lip, for no-climb         0 1
## [/codeblock]

var _passed := 0
var _failed := 0
var _steps: Array = []
var _settles: Array = []
var _falls: Array = []

## Item ids in the code-built mesh library. The names are what [Terrain] matches on.
const ITEM_FLOOR := 0
const ITEM_RAMP := 1
const ITEM_STAIRS := 2
const ITEM_LADDER := 3

const N := Vector3i(0, 0, -1)
const S := Vector3i(0, 0, 1)
const E := Vector3i(1, 0, 0)
const W := Vector3i(-1, 0, 0)


func _ready() -> void:
	EventBus.actor_stepped.connect(func (id: StringName, from: Vector3i, to: Vector3i) -> void:
		_steps.append([id, from, to]))
	EventBus.actor_settled.connect(func (id: StringName, cell: Vector3i) -> void:
		_settles.append([id, cell]))
	EventBus.actor_falling.connect(func (id: StringName, from: Vector3i, to: Vector3i) -> void:
		_falls.append([id, from, to]))
	_run()


func _run() -> void:
	print("")
	print("height -- ramps, stairs, ladders and falling")
	print("")

	_test_terrain_reads()
	await _test_ramp_and_stairs()
	await _test_ladder()
	await _test_falling()
	await _test_fall_hook()
	await _test_no_climb()
	await _test_flat_map_untouched()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- Reading the map ----------------------------------------------------------

## Before any actor moves: does [Terrain] read back what was authored? A wrong answer
## here would make every movement assertion below fail for a reason that has nothing to
## do with movement.
func _test_terrain_reads() -> void:
	_section("Terrain -- reading kinds and directions off the GridMap")

	var map := _build_map()
	add_child(map.root)
	var ctx: MapContext = map.ctx

	_ok(Terrain.governs(ctx), "a map with a floor_node is governed by Terrain")
	_eq(Terrain.kind_at(ctx, Vector3i(0, 0, 0)), Terrain.Kind.FLOOR, "flat ground reads as FLOOR")
	_eq(Terrain.kind_at(ctx, Vector3i(2, 0, 0)), Terrain.Kind.RAMP, "a 'ramp' item reads as RAMP")
	_eq(Terrain.kind_at(ctx, Vector3i(5, 1, 0)), Terrain.Kind.RAMP,
		"a 'stairs' item reads as RAMP too -- same rules, different art")
	# The overlay, and the whole reason ladders are a separate layer: one cell, both
	# answers. Sharing the floor layer would have made this an either/or.
	_ok(Terrain.has_ladder(ctx, Vector3i(2, 0, 2)), "the ladder's foot carries a ladder")
	_eq(Terrain.kind_at(ctx, Vector3i(2, 0, 2)), Terrain.Kind.FLOOR,
		"and is still floor underneath it")
	_ok(Terrain.has_ladder(ctx, Vector3i(2, 1, 2)), "the rung above it is ladder")
	_eq(Terrain.kind_at(ctx, Vector3i(2, 1, 2)), Terrain.Kind.VOID, "hanging over air")
	_ok(not Terrain.has_ladder(ctx, Vector3i(0, 0, 0)), "ordinary floor carries no ladder")
	_eq(Terrain.kind_at(ctx, Vector3i(9, 9, 9)), Terrain.Kind.VOID, "empty air reads as VOID")

	# The orientation round trip. Authored east, read back east.
	_eq(Terrain.facing_of(ctx, Vector3i(2, 0, 0)), E, "the ramp was authored rising east")
	_eq(Terrain.facing_of(ctx, Vector3i(5, 1, 0)), E, "so were the stairs")
	_eq(Terrain.ladder_facing(ctx, Vector3i(2, 0, 2)), E, "and the ladder is climbed east")

	_eq(Terrain.surface_offset(ctx, Vector3i(2, 0, 0)), Terrain.RAMP_RISE,
		"a ramp's surface sits half a cell above its own Y")
	_eq(Terrain.surface_offset(ctx, Vector3i(0, 0, 0)), 0.0, "flat ground lifts nothing")
	_eq(Terrain.surface_offset(ctx, Vector3i(2, 1, 2)), 0.0, "and neither does a rung")

	map.root.queue_free()


# -- Ramps and stairs ---------------------------------------------------------

## Three elevations, walked end to end and back. The ramp connects 0 to 1, the stairs
## connect 1 to 2, and the only difference between them is the item name.
func _test_ramp_and_stairs() -> void:
	_section("Ramps and stairs -- walking three elevations, up")

	var map := _build_map()
	add_child(map.root)
	await get_tree().process_frame
	var ctx: MapContext = map.ctx
	var actor: Actor = _spawn(map, Vector3i(0, 0, 0))
	await get_tree().process_frame

	_eq(actor.cell(), Vector3i(0, 0, 0), "spawns on the low floor")

	_ok(await _step(actor, E), "east along the low floor")
	_eq(actor.cell(), Vector3i(1, 0, 0), "still on level 0")

	# The decision Kyle made explicit: a ramp's cell is its *lower* end, so stepping on
	# is a level step and the climb happens on the way off.
	_ok(await _step(actor, E), "east onto the ramp")
	_eq(actor.cell(), Vector3i(2, 0, 0), "the ramp commits to the lower cell, not the upper one")
	_eq(_rest_offset(actor),
		Terrain.RAMP_RISE * ctx.cell_size.y + Terrain.RAMP_STANCE_UP * ctx.cell_size.y,
		"and the sprite is lifted to the slope it is standing on, plus its standing stance")

	_ok(await _step(actor, E), "east off the top of the ramp")
	_eq(actor.cell(), Vector3i(3, 1, 0), "one cell up, onto level 1")
	_eq(_rest_offset(actor), 0.0, "and the lift is gone again on flat ground")

	_ok(await _step(actor, E), "east along level 1")
	_eq(actor.cell(), Vector3i(4, 1, 0), "still on level 1")

	_ok(await _step(actor, E), "east onto the stairs")
	_eq(actor.cell(), Vector3i(5, 1, 0), "stairs commit to the lower cell as a ramp does")

	_ok(await _step(actor, E), "east off the top of the stairs")
	_eq(actor.cell(), Vector3i(6, 2, 0), "onto level 2 -- the third elevation")

	_ok(await _step(actor, E), "east along level 2")
	_eq(actor.cell(), Vector3i(7, 2, 0), "the far end")

	_section("Ramps and stairs -- and back down again")

	_ok(await _step(actor, W), "west along level 2")
	_eq(actor.cell(), Vector3i(6, 2, 0), "still level 2")

	# Descending is the mirror of climbing: the ramp below must rise back toward us.
	_ok(await _step(actor, W), "west onto the stairs from above")
	_eq(actor.cell(), Vector3i(5, 1, 0), "down one, onto the stairs' own cell")

	_ok(await _step(actor, W), "west off the stairs")
	_eq(actor.cell(), Vector3i(4, 1, 0), "back on level 1")

	_ok(await _step(actor, W), "west to the ramp's upper neighbour")
	_eq(actor.cell(), Vector3i(3, 1, 0), "still level 1")
	_ok(await _step(actor, W), "west down the ramp")
	_eq(actor.cell(), Vector3i(2, 0, 0), "onto the ramp at level 0")
	_ok(await _step(actor, W), "west off the ramp")
	_eq(actor.cell(), Vector3i(1, 0, 0), "back where we started, on level 0")

	_section("Ramps -- a ramp is not a staircase sideways")

	# Walking across a ramp's face rather than up it is an ordinary level step, and
	# walking into the ramp's *high* side from level 0 is a wall - the ramp rises away.
	_ok(not await _step(actor, N), "north off the edge of the walkway is refused")
	_eq(actor.cell(), Vector3i(1, 0, 0), "and moved nothing")

	map.root.queue_free()


# -- Ladders ------------------------------------------------------------------

## A ladder up a two-cell cliff: mount from the ground, climb rung by rung, dismount
## over the top onto level 2, and come back down. Then let go of it.
func _test_ladder() -> void:
	_section("Ladders -- mounting, climbing and dismounting")

	var map := _build_map()
	add_child(map.root)
	await get_tree().process_frame
	var actor: Actor = _spawn(map, Vector3i(1, 0, 2))
	await get_tree().process_frame

	_eq(actor.cell(), Vector3i(1, 0, 2), "spawns on the low floor beside the ladder")

	_ok(await _step(actor, E), "east into the ladder, from the side it is mounted on")
	_eq(actor.cell(), Vector3i(2, 0, 2), "on the bottom rung")

	_ok(await _step(actor, E), "east again -- pressing into the wall climbs")
	_eq(actor.cell(), Vector3i(2, 1, 2), "up one rung")

	_ok(await _step(actor, E), "east again, at the top of the ladder")
	_eq(actor.cell(), Vector3i(3, 2, 2), "dismounts over the edge onto level 2")

	_section("Ladders -- and back down")

	_ok(await _step(actor, W), "west, back over the edge onto the ladder")
	_eq(actor.cell(), Vector3i(2, 1, 2), "on the top rung")

	_ok(await _step(actor, W), "west again -- pressing away from the wall descends")
	_eq(actor.cell(), Vector3i(2, 0, 2), "down one rung")

	_ok(await _step(actor, W), "west off the bottom rung")
	_eq(actor.cell(), Vector3i(1, 0, 2), "back on the low floor")

	_section("Ladders -- sideways is not a move, and jump is the release")

	# Back onto the ladder, one rung up.
	_ok(await _step(actor, E), "east onto the bottom rung")
	_ok(await _step(actor, E), "and up one")
	_eq(actor.cell(), Vector3i(2, 1, 2), "on the top rung")

	_ok(not await _step(actor, N), "stepping sideways off a ladder is refused")
	_eq(actor.cell(), Vector3i(2, 1, 2), "so the actor stays on the rung")

	# Letting go slides to the foot of the ladder. The lower rung is not *ground*, so
	# this is the case a plain search for floor would fall straight through.
	actor.motion().jump(1.0)
	await _settled(actor)
	_eq(actor.cell(), Vector3i(2, 0, 2), "jump lets go and drops to the foot of the ladder")

	_section("Ladders -- the foot is floor first and a ladder second")

	# The foot is floor *and* ladder, which is the point of the separate layer: standing
	# there the actor is on solid ground and walks off in any direction like anywhere
	# else, and the ladder only adds the move into the wall. Sharing one layer made this
	# either/or, and the tile under the ladder simply went missing.
	var ctx: MapContext = map.ctx
	_ok(Terrain.has_ladder(ctx, actor.cell()), "the foot carries a ladder")
	_ok(Terrain.is_ground(Terrain.kind_at(ctx, actor.cell())), "and is ground at the same time")

	_ok(await _step(actor, N), "north off the foot -- sideways is a normal walk here")
	_eq(actor.cell(), Vector3i(2, 0, 1), "and it moved, because the foot is not a rung")

	_ok(await _step(actor, S), "south, back onto the foot")
	_eq(actor.cell(), Vector3i(2, 0, 2), "standing on it, not hanging")
	_ok(await _step(actor, E), "east from the foot still climbs")
	_eq(actor.cell(), Vector3i(2, 1, 2), "onto the rung above")

	_section("Ladders -- a top rung level with the floor, not tucked under it")

	# The layout that used to fail. Both rules assumed the last rung sat one cell *below*
	# the upper floor, so a ladder run up flush with the top surface matched nothing:
	# stepping off the ledge toward it fell straight past, and climbing it stranded the
	# actor on the top rung with no way off.
	var flush: Actor = _spawn(map, Vector3i(1, 0, 12), &"flush")
	await get_tree().process_frame

	_ok(await _step(flush, E), "east onto the foot of the ladder")
	_eq(flush.cell(), Vector3i(2, 0, 12), "standing on it")
	_ok(await _step(flush, E), "east climbs")
	_eq(flush.cell(), Vector3i(2, 1, 12), "first rung")
	_ok(await _step(flush, E), "east climbs again")
	_eq(flush.cell(), Vector3i(2, 2, 12), "top rung, level with the floor beside it")

	_ok(await _step(flush, E), "east off the top rung")
	_eq(flush.cell(), Vector3i(3, 2, 12), "dismounts level, not one cell up")

	# The half Kyle hit: walking back off the ledge must catch the ladder, not fall.
	_falls.clear()
	_ok(await _step(flush, W), "west off the ledge, back toward the ladder")
	_eq(flush.cell(), Vector3i(2, 2, 12), "lands on the top rung")
	_eq(_falls.size(), 0, "and nothing fell")

	_ok(await _step(flush, W), "west descends")
	_eq(flush.cell(), Vector3i(2, 1, 12), "one rung down")
	_ok(await _step(flush, W), "west descends again")
	_eq(flush.cell(), Vector3i(2, 0, 12), "on the foot")

	_section("Ladders -- a rung left behind in the floor layer is not ground")

	# What an author is left with after painting a ladder before the ladder layer
	# existed: the same cell in both. Reading the leftover as floor made the rung solid,
	# which switched off the guard that keeps a hanging actor on its ladder - so pressing
	# a perpendicular direction walked off the rung into open air and fell.
	var ctx2: MapContext = map.ctx
	_ok(Terrain.has_ladder(ctx2, Vector3i(1, 1, 14)), "the rung is on the ladder layer")
	_eq(Terrain.kind_at(ctx2, Vector3i(1, 1, 14)), Terrain.Kind.VOID,
		"and the copy of it in the floor layer reads as VOID, not floor")

	var stray: Actor = _spawn(map, Vector3i(0, 0, 14), &"stray")
	await get_tree().process_frame
	_ok(await _step(stray, E), "east to the foot of the cliff")
	_eq(stray.cell(), Vector3i(1, 0, 14), "under the ladder")
	_ok(await _step(stray, E), "east onto the rung")
	_eq(stray.cell(), Vector3i(1, 1, 14), "hanging on it")

	_falls.clear()
	_ok(not await _step(stray, N), "north off the rung is refused")
	_eq(stray.cell(), Vector3i(1, 1, 14), "so the actor is still on the ladder")
	_eq(_falls.size(), 0, "and did not walk off into the air and fall")

	map.root.queue_free()


# -- Falling ------------------------------------------------------------------

func _test_falling() -> void:
	_section("Falling -- a drop inside the limit, one cell at a time")

	var map := _build_map()
	add_child(map.root)
	await get_tree().process_frame
	var ctx: MapContext = map.ctx
	_eq(ctx.max_fall_cells, 2, "this map permits a two-cell fall")

	var actor: Actor = _spawn(map, Vector3i(5, 2, 4))
	await get_tree().process_frame

	_steps.clear()
	_settles.clear()
	_ok(await _step(actor, W), "west off the ledge")
	_eq(actor.cell(), Vector3i(4, 0, 4), "lands two cells below, on the low floor")

	# "Repeated one-cell steps" is meant literally: the step off the ledge and each cell
	# of the drop are ordinary steps and each publishes its own pair of signals.
	_eq(_steps.size(), 3, "one step off the ledge plus two cells of falling")
	_eq(_settles.size(), 3, "and a settle for each")
	if _steps.size() == 3:
		_eq(_steps[0][2], Vector3i(4, 2, 4), "the step off the ledge leaves the actor over air")
		_eq(_steps[1][2], Vector3i(4, 1, 4), "then down one")
		_eq(_steps[2][2], Vector3i(4, 0, 4), "then down onto the floor")

	_section("Falling -- a drop past the limit is refused, not survived")

	var deep: Actor = _spawn(map, Vector3i(3, 2, 4), &"deep")
	await get_tree().process_frame
	_eq(Terrain.drop_below(ctx, Vector3i(2, 2, 4), 8), 3, "the pit is three cells deep")

	_steps.clear()
	_ok(not await _step(deep, W), "west into the deep pit is refused")
	_eq(deep.cell(), Vector3i(3, 2, 4), "the actor has not moved at all")
	_eq(_steps.size(), 0, "and nothing was published, because nothing happened")

	_section("Falling -- a taken landing cell stops the fall, it does not hang it")

	# The faller above is standing on (4,0,4). Drop a second actor down the same column
	# and it has nowhere to land. What matters is not where it ends up - on air, which is
	# odd but visible - but that it stops being busy: a pending fall counts as busy, so
	# one left un-paid-out would keep a round open forever.
	var onto: Actor = _spawn(map, Vector3i(5, 2, 4), &"onto")
	await get_tree().process_frame
	_ok(await _step(onto, W), "west off the same ledge, onto an occupied landing")
	_ok(not onto.motion().is_busy(), "the fall stopped rather than hanging")
	_ok(onto.cell() != actor.cell(), "and did not land inside the actor already there")

	_section("Falling -- the limit is what makes a ledge a wall")

	ctx.max_fall_cells = 0
	var pinned: Actor = _spawn(map, Vector3i(3, 2, 4), &"pinned")
	await get_tree().process_frame
	_ok(not await _step(pinned, E), "with max_fall_cells 0, even a two-cell ledge is a wall")
	_eq(pinned.cell(), Vector3i(3, 2, 4), "and the actor stays on the ledge")

	map.root.queue_free()


# -- The fall hook ------------------------------------------------------------

## `fall_delay` and `Actor.falling`: the window and the thing that opens it.
func _test_fall_hook() -> void:
	_section("Falling -- announced before it starts")

	var map := _build_map()
	add_child(map.root)
	await get_tree().process_frame
	var actor: Actor = _spawn(map, Vector3i(0, 2, 10))
	await get_tree().process_frame

	# The local signal and the bus one, carrying where the actor is and where it lands.
	var local: Array = []
	actor.falling.connect(func (from: Vector3i, to: Vector3i) -> void:
		local.append([from, to]))

	_falls.clear()
	_ok(await _step(actor, E), "east off the two-cell ledge")
	_eq(local.size(), 1, "Actor.falling fired once for the whole fall, not once per cell")
	_eq(_falls.size(), 1, "and EventBus.actor_falling with it")
	if local.size() == 1:
		_eq(local[0][0], Vector3i(1, 2, 10), "from the cell the actor is standing on nothing in")
		_eq(local[0][1], Vector3i(1, 0, 10), "naming where it will land, before it lands")
	_eq(actor.cell(), Vector3i(1, 0, 10), "and it did land there")

	_section("Falling -- fall_delay holds the actor in the air")

	var slow: Actor = _spawn(map, Vector3i(3, 2, 10), &"slow")
	await get_tree().process_frame
	slow.motion().fall_delay = 0.25

	var announced: Array = []
	slow.falling.connect(func (from: Vector3i, _to: Vector3i) -> void:
		announced.append(from))

	# Stepped off, but deliberately not waited out - the point is what is true *during*
	# the hang, which _settled would sit through.
	_ok(slow.motion().step(E), "east off the ledge")
	await _settled_step(slow)

	_eq(announced.size(), 1, "the fall is announced as soon as the step off settles")
	_eq(slow.cell(), Vector3i(4, 2, 10), "but the actor is still up in the air")
	_ok(slow.motion().is_busy(), "and still busy, so no round closes under it")

	await _settled(slow)
	_eq(slow.cell(), Vector3i(4, 0, 10), "once the delay is out it falls the rest of the way")
	_ok(not slow.motion().is_busy(), "and is done")

	_section("Falling -- letting go of a ladder never hangs")

	# fall_delay is the beat after walking off something by accident. A ladder release
	# was asked for, so it drops at once however long the hang is set to.
	var dropper: Actor = _spawn(map, Vector3i(1, 0, 2), &"dropper")
	await get_tree().process_frame
	dropper.motion().fall_delay = 5.0

	_ok(await _step(dropper, E), "onto the foot of the ladder")
	_ok(await _step(dropper, E), "and up a rung")
	_eq(dropper.cell(), Vector3i(2, 1, 2), "hanging on it")

	# Asserted on the step, not on where it ends up: _settled waits up to 600 frames, so
	# a five-second hang would eventually finish and the final cell would look right
	# either way. The drop having *started* by the next frame is the thing that is only
	# true when the release skips the delay.
	_steps.clear()
	dropper.motion().jump(1.0)
	await get_tree().process_frame
	var dropped := 0
	for s in _steps:
		if s[0] == &"dropper":
			dropped += 1
	_ok(dropped > 0, "the release commits its first cell immediately, not after fall_delay")

	await _settled(dropper)
	_eq(dropper.cell(), Vector3i(2, 0, 2), "and lands at the foot of the ladder")

	_section("Falling -- a cancelled hang drops nothing")

	var held: Actor = _spawn(map, Vector3i(6, 2, 10), &"held")
	await get_tree().process_frame
	held.motion().fall_delay = 5.0
	_ok(held.motion().step(E), "east off the ledge")
	await _settled_step(held)
	_eq(held.cell(), Vector3i(7, 2, 10), "hanging over the drop")

	# A cutscene seizing the actor mid-hang must not have it fall out from under itself
	# later, and must not leave a pending fall that keeps it busy forever.
	held.motion().cancel()
	_ok(not held.motion().is_busy(), "cancel clears the pending fall rather than hanging it")
	await get_tree().process_frame
	await get_tree().process_frame
	_eq(held.cell(), Vector3i(7, 2, 10), "and the actor stays where the cutscene left it")

	map.root.queue_free()


# -- No climb tolerance -------------------------------------------------------

## The asymmetry 2D's painted mask could not express: the same one-cell lip is a wall
## from below and a drop from above.
func _test_no_climb() -> void:
	_section("No climb tolerance -- a lip is a wall up and a drop down")

	var map := _build_map()
	add_child(map.root)
	await get_tree().process_frame
	var low: Actor = _spawn(map, Vector3i(0, 0, 6))
	await get_tree().process_frame

	_ok(not await _step(low, E), "east into a one-cell lip is refused -- only ramps climb")
	_eq(low.cell(), Vector3i(0, 0, 6), "nothing moved")

	var high: Actor = _spawn(map, Vector3i(1, 1, 8), &"high")
	await get_tree().process_frame
	_ok(await _step(high, W), "west off the same lip is allowed")
	_eq(high.cell(), Vector3i(0, 0, 8), "and drops the one cell onto the floor below")

	map.root.queue_free()


# -- The flat case ------------------------------------------------------------

## The guarantee that none of this reaches game 1. The identical map with its
## floor_node cleared moves exactly as a flat map always has.
func _test_flat_map_untouched() -> void:
	_section("3D grid only -- a map with no floor_node is untouched")

	var map := _build_map()
	var ctx: MapContext = map.ctx
	ctx.floor_node = NodePath()
	add_child(map.root)
	await get_tree().process_frame

	_ok(not Terrain.governs(ctx), "Terrain does not govern a map with no floor GridMap")

	var actor: Actor = _spawn(map, Vector3i(0, 0, 0))
	await get_tree().process_frame

	# The ramp is still standing there in the GridMap. Without floor_node it is scenery.
	_ok(await _step(actor, E), "east")
	_ok(await _step(actor, E), "east onto what would have been the ramp")
	_eq(actor.cell(), Vector3i(2, 0, 0), "the step stayed on its own Y")
	_ok(await _step(actor, E), "east again")
	_eq(actor.cell(), Vector3i(3, 0, 0), "no climb, because nothing is reading the terrain")
	_eq(_rest_offset(actor), 0.0, "and no ramp lift on the sprite")

	map.root.queue_free()


# -- Building the map ---------------------------------------------------------

## Three elevations and the connections between them, built in code. See the class
## docstring for the layout.
func _build_map() -> Dictionary:
	var root := Node3D.new()
	root.name = "HeightMap"

	var lib := _build_library()

	var gm := GridMap.new()
	gm.name = "Floor"
	gm.cell_size = Vector3.ONE
	gm.cell_center_y = false
	gm.mesh_library = lib
	root.add_child(gm)

	# Ladders are their own layer, so a cell can be floor *and* ladder. Sharing the floor
	# layer would evict the tile at a ladder's foot.
	var ladders := GridMap.new()
	ladders.name = "Ladders"
	ladders.cell_size = Vector3.ONE
	ladders.cell_center_y = false
	ladders.mesh_library = lib
	root.add_child(ladders)

	var ctx := MapContext.new()
	ctx.name = "MapContext"
	ctx.map_id = &"height_test"
	ctx.cell_size = Vector3.ONE
	ctx.supports_height = true
	ctx.default_motion = Actor.MotionMode.GRID
	ctx.floor_node = NodePath("../Floor")
	ctx.ladder_node = NodePath("../Ladders")
	ctx.max_fall_cells = 2
	root.add_child(ctx)

	# z=0: level 0 -> ramp -> level 1 -> stairs -> level 2, walking east.
	_put(gm, Vector3i(0, 0, 0), ITEM_FLOOR)
	_put(gm, Vector3i(1, 0, 0), ITEM_FLOOR)
	_put(gm, Vector3i(2, 0, 0), ITEM_RAMP, E)
	_put(gm, Vector3i(3, 1, 0), ITEM_FLOOR)
	_put(gm, Vector3i(4, 1, 0), ITEM_FLOOR)
	_put(gm, Vector3i(5, 1, 0), ITEM_STAIRS, E)
	_put(gm, Vector3i(6, 2, 0), ITEM_FLOOR)
	_put(gm, Vector3i(7, 2, 0), ITEM_FLOOR)

	# z=2: a ladder climbing the two-cell cliff between level 0 and level 2. The rungs
	# hang in the air against the cliff face; the floor beside the top is what the
	# dismount needs, and its absence is the authoring error open-questions 38 names.
	#
	# The foot of the ladder is floor *and* ladder at once - the point of the separate
	# layer. Standing there the actor is on solid ground and free to walk away in any
	# direction; pressing into the wall is the move the ladder adds.
	_put(gm, Vector3i(0, 0, 2), ITEM_FLOOR)
	_put(gm, Vector3i(1, 0, 2), ITEM_FLOOR)
	_put(gm, Vector3i(2, 0, 2), ITEM_FLOOR)
	_put(gm, Vector3i(2, 0, 1), ITEM_FLOOR)   # somewhere to walk off the foot sideways
	_put(ladders, Vector3i(2, 0, 2), ITEM_LADDER, E)
	_put(ladders, Vector3i(2, 1, 2), ITEM_LADDER, E)
	_put(gm, Vector3i(3, 2, 2), ITEM_FLOOR)
	_put(gm, Vector3i(4, 2, 2), ITEM_FLOOR)

	# z=4: two ledges. (5,2) drops two cells to (4,0) - inside the limit. (3,2) drops
	# three to (2,-1) - past it.
	_put(gm, Vector3i(5, 2, 4), ITEM_FLOOR)
	_put(gm, Vector3i(4, 0, 4), ITEM_FLOOR)
	_put(gm, Vector3i(3, 2, 4), ITEM_FLOOR)
	_put(gm, Vector3i(2, -1, 4), ITEM_FLOOR)

	# z=6 and z=8: a bare one-cell lip, with no ramp on it. Two copies, because the two
	# halves of the asymmetry are walked by two actors at once and the one dropping must
	# not land on the one standing below - an occupied landing cell is its own case and
	# not the one under test here.
	_put(gm, Vector3i(0, 0, 6), ITEM_FLOOR)
	_put(gm, Vector3i(1, 1, 6), ITEM_FLOOR)
	_put(gm, Vector3i(0, 0, 8), ITEM_FLOOR)
	_put(gm, Vector3i(1, 1, 8), ITEM_FLOOR)

	# z=10: three two-cell ledges, far enough apart that three actors can be dropped off
	# them at once without one landing on another - which stops a fall dead and would
	# make the hook tests fail for a reason that is not the hook.
	for i in 3:
		var x := i * 3
		_put(gm, Vector3i(x, 2, 10), ITEM_FLOOR)
		_put(gm, Vector3i(x + 1, 0, 10), ITEM_FLOOR)

	# z=12: the *other* way to build a ladder, and the one that used to drop the player
	# down the cliff instead of onto the rungs. Here the topmost rung is level with the
	# upper floor rather than tucked a cell under it - which is how a ladder looks when
	# it reaches the top of what it is leaning on.
	_put(gm, Vector3i(0, 0, 12), ITEM_FLOOR)
	_put(gm, Vector3i(1, 0, 12), ITEM_FLOOR)
	_put(gm, Vector3i(2, 0, 12), ITEM_FLOOR)
	_put(ladders, Vector3i(2, 0, 12), ITEM_LADDER, E)
	_put(ladders, Vector3i(2, 1, 12), ITEM_LADDER, E)
	_put(ladders, Vector3i(2, 2, 12), ITEM_LADDER, E)   # level with the floor beside it
	_put(gm, Vector3i(3, 2, 12), ITEM_FLOOR)
	_put(gm, Vector3i(4, 2, 12), ITEM_FLOOR)

	# z=14: a ladder cell left behind in the *floor* layer as well as the ladder layer,
	# which is what an author ends up with after painting one before the ladder layer
	# existed. It must not read as ground - see Terrain._kind_of_item.
	# The shape of the demo map's own ladder: a foot cell that is floor and ladder, one
	# rung hanging above it, and the upper floor beside that rung.
	_put(gm, Vector3i(0, 0, 14), ITEM_FLOOR)
	_put(gm, Vector3i(1, 0, 14), ITEM_FLOOR)
	_put(ladders, Vector3i(1, 0, 14), ITEM_LADDER, E)
	_put(ladders, Vector3i(1, 1, 14), ITEM_LADDER, E)
	_put(gm, Vector3i(1, 1, 14), ITEM_LADDER, E)        # the leftover, in the floor layer
	_put(gm, Vector3i(2, 2, 14), ITEM_FLOOR)
	# Somewhere far below, so a wrong answer falls instead of being harmlessly refused.
	_put(gm, Vector3i(1, -4, 14), ITEM_FLOOR)

	return {"root": root, "ctx": ctx, "grid": gm}


## Items need names and nothing else: [Terrain] matches the name and reads the cell's
## orientation. A mesh would only be something to render, and this test renders nothing.
func _build_library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	for pair in [[ITEM_FLOOR, "floor"], [ITEM_RAMP, "ramp"], [ITEM_STAIRS, "stairs"],
			[ITEM_LADDER, "ladder"]]:
		lib.create_item(pair[0])
		lib.set_item_name(pair[0], pair[1])
	return lib


func _put(gm: GridMap, cell: Vector3i, item: int, facing: Vector3i = Vector3i.ZERO) -> void:
	gm.set_cell_item(cell, item, _ori(gm, facing) if facing != Vector3i.ZERO else 0)


## The orthogonal index that turns [constant Terrain.MODELLED_FACING] into [param dir].
##
## Searched rather than computed, because the search is obviously right and the Euler
## angle that produces a given orthogonal index is obviously nothing. The round trip is
## asserted separately in [method _test_terrain_reads], so this cannot quietly agree with
## a broken [method Terrain.facing_of] - the authored direction is checked against the
## direction a human wrote down.
func _ori(gm: GridMap, dir: Vector3i) -> int:
	for i in 24:
		var basis := gm.get_basis_with_orthogonal_index(i)
		if Space.quantise(basis * Terrain.MODELLED_FACING, 4) == dir:
			return i
	_fail("no orthogonal index faces %s" % dir)
	return 0


func _spawn(map: Dictionary, cell: Vector3i, id: StringName = &"walker") -> Actor:
	var ctx: MapContext = map.ctx
	var body := Node3D.new()
	body.name = str(id)
	body.position = ctx.cell_centre(cell)
	(map.root as Node3D).add_child(body)

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = id
	actor.facing_count = 4
	body.add_child(actor)

	var adapter := Space3D.new()
	adapter.name = "Space"
	actor.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = 4
	motion.speed = 30.0
	actor.add_child(motion)

	var view := ActorView.new()
	view.name = "View"
	actor.add_child(view)

	return actor


## The sprite's resting lift above the body, in world units - zero everywhere but a ramp.
func _rest_offset(actor: Actor) -> float:
	var v := actor.view()
	return 0.0 if v == null else v.offset().y


# -- Harness ------------------------------------------------------------------

## A step, awaited to settle. Returns whether the step was taken at all, so a refusal is
## distinguishable from a step that happened and went nowhere.
func _step(actor: Actor, dir: Vector3i) -> bool:
	var took: bool = actor.motion().step(dir)
	if took:
		await _settled(actor)
	return took


## Waits for the step in flight to settle and no further - specifically [i]not[/i] through
## the fall that may follow it, which is what [method _settled] would do. Waiting on
## [signal Actor.arrived] rather than on a busy flag is the only way to stop inside a
## hang, since a hanging actor is deliberately still busy.
func _settled_step(actor: Actor) -> void:
	var landed := [false]
	var tap := func (_cell: Vector3i) -> void: landed[0] = true
	actor.arrived.connect(tap)
	var guard := 0
	while not landed[0] and guard < 600:
		guard += 1
		await get_tree().process_frame
	if actor.arrived.is_connected(tap):
		actor.arrived.disconnect(tap)
	if not landed[0]:
		_fail("'%s' never settled its step" % actor.actor_id)


## Waits out everything in flight, a fall and its hang included - [method
## GridMotion.is_busy] counts both as busy precisely so this reads as one wait rather
## than one per cell.
func _settled(actor: Actor) -> void:
	var guard := 0
	while actor.motion().is_busy() and guard < 600:
		guard += 1
		await get_tree().process_frame
	if guard >= 600:
		_fail("'%s' never settled" % actor.actor_id)


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("    ok    %s" % what)
	else:
		_fail(what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	if _same(got, want):
		_passed += 1
		print("    ok    %s" % what)
	else:
		_fail("%s  (got %s, want %s)" % [what, got, want])


func _same(a: Variant, b: Variant) -> bool:
	if a is float or b is float:
		return is_equal_approx(float(a), float(b))
	return a == b


func _fail(what: String) -> void:
	_failed += 1
	print("    FAIL  %s" % what)
