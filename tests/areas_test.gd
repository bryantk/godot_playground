extends Node

## Headless assertions over the area system - [AreaZone], [AreaComponent] and
## [SpeedModifier].
##
##     godot --headless --path . res://tests/areas_test.tscn
##
## What is worth asserting here is [b]when[/b] things happen, not that they happen: the
## whole design turns on a zone being known at step commit rather than a physics frame
## later, and on an exit landing at the visual settle rather than at the commit that left.
## Both are invisible in a screenshot and obvious in a cell-by-cell trace, which is what
## this is. How the mud actually feels is a thing to be played, not asserted.

var _passed := 0
var _failed := 0

## Zone signals, in the order they arrived: ["entered", &"slow"] and so on.
var _log: Array = []


func _ready() -> void:
	print("")
	print("areas -- zones, components and speed")
	print("")

	_test_cardinals()
	await _test_zone_crossings()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- Directions ---------------------------------------------------------------

func _test_cardinals() -> void:
	_section("Passability.cardinals -- a heading as flags")

	_eq(Passability.cardinals(Vector3(0, 0, -1)), Passability.NORTH, "north is north")
	_eq(Passability.cardinals(Vector3(1, 0, 0)), Passability.EAST, "east is east")
	_eq(Passability.cardinals(Vector3(0, 0, 1)), Passability.SOUTH, "south is south")
	_eq(Passability.cardinals(Vector3(-1, 0, 0)), Passability.WEST, "west is west")

	# The 8-way answer: a diagonal is both of the cardinals it lies between, which is
	# what lets one rule serve a grid step and an analog heading.
	_eq(Passability.cardinals(Vector3(1, 0, -1)), Passability.NORTH | Passability.EAST,
		"north-east is both")
	_eq(Passability.cardinals(Vector3(-0.3, 0, 0.9)), Passability.SOUTH | Passability.WEST,
		"an analog heading resolves the same way")
	_eq(Passability.cardinals(Vector3.ZERO), 0, "standing still is no direction")
	_eq(Passability.cardinals(Vector3(0, 1, 0)), 0, "a purely vertical move is no direction")


# -- Crossings ----------------------------------------------------------------

func _test_zone_crossings() -> void:
	_section("AreaZone -- a grid actor crossing a 2D zone")

	var map := _build_map()
	var root: Node2D = map["root"]
	add_child(root)

	# Cells 2..4 on row z=0, slowing eastward movement by half.
	var slow := _build_zone(root, &"slow", Rect2i(Vector2i(2, 0), Vector2i(3, 1)))
	var mud: SpeedModifier = slow["modifier"]
	mud.scale = 0.5
	mud.east = true

	# Overlapping it at cells 4..5, slowing everything, to prove the two multiply.
	var tar := _build_zone(root, &"tar", Rect2i(Vector2i(4, 0), Vector2i(2, 1)))
	(tar["modifier"] as SpeedModifier).scale = 0.5

	var actor: Actor = map["actor"]
	var motion := actor.motion() as GridMotion
	_watch(slow["zone"])
	_watch(tar["zone"])

	# Shapes reach the physics server on the next physics tick, not when they are added.
	await get_tree().physics_frame
	await get_tree().physics_frame

	# -- The query itself
	_eq(AreaZone.zones_at(actor, Vector3i(3, 0, 0)).size(), 1, "one zone covers cell 3")
	_eq(AreaZone.zones_at(actor, Vector3i(4, 0, 0)).size(), 2, "two zones cover cell 4")
	_ok(AreaZone.zones_at(actor, Vector3i(0, 0, 0)).is_empty(), "no zone covers cell 0")

	# -- Walking in
	var open := motion.step_duration(Vector3i(1, 0, 0))
	await _step(actor, Vector3i(1, 0, 0))          # 0 -> 1, still outside
	_ok(_log.is_empty(), "crossing no boundary fires nothing")

	# Synchronously after step() returns, which is the commit: the zone is already known
	# and the modifier is already registered. This is the assertion the whole design is
	# for - a physics overlap signal would still be a frame away here.
	motion.step(Vector3i(1, 0, 0))                 # 1 -> 2, enters
	_eq(_log, [["entered", &"slow"]], "entering fires at commit, and only entering")
	_near(motion.speed_scale(Vector3(1, 0, 0)), 0.5, "eastward speed is halved at commit")
	_near(motion.speed_scale(Vector3(0, 0, -1)), 1.0, "northward speed is untouched")
	_near(motion.step_duration(Vector3i(1, 0, 0)), open * 2.0,
		"so the step that is entering takes twice as long")

	await _settled(actor)
	_eq(_log, [["entered", &"slow"], ["arrived", &"slow"]],
		"arriving fires when the sprite catches up")

	# -- Overlapping zones
	_log.clear()
	await _step(actor, Vector3i(1, 0, 0))          # 2 -> 3
	await _step(actor, Vector3i(1, 0, 0))          # 3 -> 4, enters the second zone
	_near(motion.speed_scale(Vector3(1, 0, 0)), 0.25, "two zones multiply, not maximise")
	_near(motion.speed_scale(Vector3(0, 0, 1)), 0.5,
		"and only the one without a direction rule applies going south")

	# -- Walking out
	_log.clear()
	motion.step(Vector3i(1, 0, 0))                 # 4 -> 5, leaves the first zone
	_eq(_log, [["leaving", &"slow"]], "leaving fires at commit, with no exit yet")
	_near(motion.speed_scale(Vector3(1, 0, 0)), 0.25,
		"the step out of the mud is still a step out of mud")

	await _settled(actor)
	_eq(_log, [["leaving", &"slow"], ["exited", &"slow"], ["arrived", &"tar"]],
		"the exit lands when the sprite is wholly out")

	_log.clear()
	await _step(actor, Vector3i(1, 0, 0))          # 5 -> 6, leaves the second
	_eq(_log, [["leaving", &"tar"], ["exited", &"tar"]], "and the last zone lets go")
	_near(motion.speed_scale(Vector3(1, 0, 0)), 1.0, "speed is its own again")
	_ok(actor.areas().is_empty(), "the actor is in no zones")

	# -- Several components on one zone
	#
	# One shape, one crossing, any number of things acting on it - a zone that speeds you
	# one way and slows you the other is two modifiers, not one with a sign. Each is asked
	# separately and each answers for its own directions.
	_section("AreaZone -- any number of components")

	var twin := _build_zone(root, &"twin", Rect2i(Vector2i(8, 0), Vector2i(2, 1)))
	var quick: SpeedModifier = twin["modifier"]
	quick.scale = 2.0
	quick.north = true

	var sticky := SpeedModifier.new()
	sticky.name = "Speed2"
	sticky.scale = 0.5
	sticky.south = true
	(twin["zone"] as AreaZone).add_child(sticky)

	await get_tree().physics_frame
	await _step(actor, Vector3i(1, 0, 0))          # 6 -> 7
	await _step(actor, Vector3i(1, 0, 0))          # 7 -> 8, into the twin

	_near(motion.speed_scale(Vector3(0, 0, -1)), 2.0, "the first component speeds north up")
	_near(motion.speed_scale(Vector3(0, 0, 1)), 0.5, "the second slows south down")
	_near(motion.speed_scale(Vector3(1, 0, 0)), 1.0, "and neither touches east")

	# The failure this guards against is one component silently winning: two that share a
	# direction have to compound, or "any number" is a fiction.
	sticky.north = true
	_near(motion.speed_scale(Vector3(0, 0, -1)), 1.0,
		"two components on one direction multiply (2.0 x 0.5)")

	# -- The filter
	_section("AreaComponent -- who is affected")

	var npc: Actor = map["npc"]
	mud.affects = AreaComponent.Affects.PLAYER
	npc.motion().step(Vector3i(0, 0, -1))          # (2, 0, 1) -> (2, 0, 0), into the mud
	_ok((slow["zone"] as AreaZone).has_actor(npc), "an unaffected actor still enters the zone")
	_near(npc.motion().speed_scale(Vector3(1, 0, 0)), 1.0,
		"but a player-only modifier does not slow it")
	await _settled(npc)

	root.queue_free()


# -- Building -----------------------------------------------------------------

func _build_map() -> Dictionary:
	var root := Node2D.new()
	root.name = "Map2D"

	var ctx := MapContext.new()
	ctx.name = "MapContext"
	ctx.map_id = &"areas"
	ctx.cell_size = Vector3(16, 0, 16)
	ctx.supports_height = false
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)

	return {
		"root": root,
		"ctx": ctx,
		"actor": _build_actor(root, ctx, &"walker", Vector3i(0, 0, 0)),
		"npc": _build_actor(root, ctx, &"npc", Vector3i(2, 0, 1)),
	}


func _build_actor(root: Node, ctx: MapContext, id: StringName, cell: Vector3i) -> Actor:
	var body := Node2D.new()
	body.name = str(id)
	body.position = Space.as_v2(ctx.cell_centre(cell))
	root.add_child(body)

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = id
	body.add_child(actor)

	var adapter := Space2D.new()
	adapter.name = "Space"
	actor.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	actor.add_child(motion)

	var view := ActorView.new()
	view.name = "View"
	actor.add_child(view)

	return actor


## An [Area2D] over the cell rectangle [param cells], carrying a zone and one modifier.
func _build_zone(root: Node2D, id: StringName, cells: Rect2i) -> Dictionary:
	var area := Area2D.new()
	area.name = str(id)
	area.position = Vector2(
		(float(cells.position.x) + cells.size.x * 0.5) * 16.0,
		(float(cells.position.y) + cells.size.y * 0.5) * 16.0)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	# A hair under the cells it covers, so a query at the centre of a neighbouring cell
	# cannot catch the edge.
	rect.size = Vector2(cells.size) * 16.0 - Vector2(0.1, 0.1)
	shape.shape = rect
	area.add_child(shape)

	var zone := AreaZone.new()
	zone.name = "Zone"
	zone.zone_id = id
	area.add_child(zone)

	var modifier := SpeedModifier.new()
	modifier.name = "Speed"
	zone.add_child(modifier)

	root.add_child(area)
	return {"area": area, "zone": zone, "modifier": modifier}


func _watch(zone: AreaZone) -> void:
	zone.actor_entered.connect(func (_a: Actor) -> void: _log.append(["entered", zone.zone_id]))
	zone.actor_arrived.connect(func (_a: Actor) -> void: _log.append(["arrived", zone.zone_id]))
	zone.actor_leaving.connect(func (_a: Actor) -> void: _log.append(["leaving", zone.zone_id]))
	zone.actor_exited.connect(func (_a: Actor) -> void: _log.append(["exited", zone.zone_id]))


# -- Awaiting a step ----------------------------------------------------------

func _step(a: Actor, dir: Vector3i) -> bool:
	if not a.motion().step(dir):
		return false
	await _settled(a)
	return true


func _settled(a: Actor) -> void:
	var frames := 0
	while a.is_moving() and frames < 600:
		frames += 1
		await get_tree().process_frame
	if a.is_moving():
		_failed += 1
		print("    FAIL  '%s' never settled" % a.actor_id)


# -- Harness ------------------------------------------------------------------

func _section(title: String) -> void:
	print("  %s" % title)


func _ok(condition: bool, what: String) -> void:
	if condition:
		_passed += 1
		print("    ok    %s" % what)
	else:
		_failed += 1
		print("    FAIL  %s" % what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	if got == want:
		_passed += 1
		print("    ok    %s" % what)
	else:
		_failed += 1
		print("    FAIL  %s  (got %s, want %s)" % [what, got, want])


func _near(got: float, want: float, what: String) -> void:
	if absf(got - want) < 0.001:
		_passed += 1
		print("    ok    %s" % what)
	else:
		_failed += 1
		print("    FAIL  %s  (got %0.4f, want %0.4f)" % [what, got, want])
