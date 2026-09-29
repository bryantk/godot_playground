extends Node

## Headless assertions over [GameEventModifier] and its two built-in modifiers -
## [Pushable] and [RestrictToArea].
##
##     godot --headless --path . res://tests/game_event_modifiers_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("events -- GameEventModifier: Pushable, RestrictToArea")
	print("")

	await _test_pushable_moves_one_cell_and_frees_the_cell_behind_it()
	await _test_pushable_gives_up_when_the_cell_beyond_it_is_blocked()
	await _test_pushable_stops_once_max_pushes_is_spent()
	await _test_pushable_ignores_an_off_centre_diagonal_shove_by_default()
	await _test_pushable_allows_a_diagonal_shove_when_enabled()
	await _test_restrict_to_area_refuses_a_step_that_would_leave_the_zone()
	await _test_restrict_to_area_allows_a_step_that_stays_inside_the_zone()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- Pushable -------------------------------------------------------------------------

func _test_pushable_moves_one_cell_and_frees_the_cell_behind_it() -> void:
	_section("Pushable -- a blocked step against it shoves it one cell further on")

	var world := _build_world()
	var walker := _build_actor(world, &"walker", Vector3i(0, 0, 0))
	var crate := _build_pushable(world, &"crate", Vector3i(1, 0, 0), -1)

	# Actor._claim_spawn_cell runs call_deferred - the spawn claim lands at the end of
	# this frame, not synchronously inside _ready.
	await get_tree().process_frame

	_ok(not walker.motion().step(Vector3i(1, 0, 0)), "the first step is refused - the crate is in the way")
	_eq(crate.cell(), Vector3i(2, 0, 0), "and the crate has been shoved one cell further east")
	_eq((crate.get_parent().get_node("Pushable") as Pushable)._pushes_used, 1,
		"counted as one push")

	_ok(walker.motion().step(Vector3i(1, 0, 0)), "the cell the crate vacated is now free to step into")
	_eq(walker.cell(), Vector3i(1, 0, 0), "so the walker actually moved into it")

	(world["root"] as Node).free()


func _test_pushable_gives_up_when_the_cell_beyond_it_is_blocked() -> void:
	_section("Pushable -- gives up silently when the cell beyond it is itself blocked")

	var world := _build_world()
	var walker := _build_actor(world, &"walker", Vector3i(0, 0, 0))
	var crate := _build_pushable(world, &"crate", Vector3i(1, 0, 0), -1)
	var wall := _build_actor(world, &"wall", Vector3i(2, 0, 0))

	await get_tree().process_frame

	_ok(not walker.motion().step(Vector3i(1, 0, 0)), "still refused")
	_eq(crate.cell(), Vector3i(1, 0, 0), "the crate never moved - the cell behind it was occupied")
	_eq(wall.cell(), Vector3i(2, 0, 0), "and the thing occupying it never moved either")

	(world["root"] as Node).free()


func _test_pushable_stops_once_max_pushes_is_spent() -> void:
	_section("Pushable -- max_pushes exhausted turns it into an ordinary immovable prop")

	var world := _build_world()
	var walker := _build_actor(world, &"walker", Vector3i(0, 0, 0))
	var crate := _build_pushable(world, &"crate", Vector3i(1, 0, 0), 0)

	await get_tree().process_frame

	_ok(not walker.motion().step(Vector3i(1, 0, 0)), "refused, as any solid actor would refuse")
	_eq(crate.cell(), Vector3i(1, 0, 0), "0 max_pushes means it never moves at all")

	(world["root"] as Node).free()


## The bug this guards against: a 2x2 crate's north-west cell is directly north of the
## crate's south-west cell, so a walker standing west of the *south* cell and stepping
## diagonally north-east lands on the *north* cell - blocked, and "aimed at" this event,
## despite the walker never actually squaring up to that cell at all. Off by default,
## so that graze is ignored outright rather than shoving the whole 2x2 footprint
## diagonally from an approach that was never square to it.
func _test_pushable_ignores_an_off_centre_diagonal_shove_by_default() -> void:
	_section("Pushable -- an off-centre diagonal shove against a 2x2+ footprint is ignored by default")

	var world := _build_world()
	var walker := _build_actor(world, &"walker", Vector3i(1, 0, 3), 8)
	var crate := _build_pushable(world, &"crate", Vector3i(2, 0, 2), -1, Vector3i(2, 1, 2), 8)

	await get_tree().process_frame

	_ok(not walker.motion().step(Vector3i(1, 0, -1)),
		"the diagonal step onto the crate's NW cell is still refused")
	_eq(crate.cell(), Vector3i(2, 0, 2), "but the crate itself never moved")
	_eq((crate.get_parent().get_node("Pushable") as Pushable)._pushes_used, 0,
		"no push was counted")

	(world["root"] as Node).free()


func _test_pushable_allows_a_diagonal_shove_when_enabled() -> void:
	_section("Pushable -- allow_diagonal_shoves opts back into the diagonal push")

	var world := _build_world()
	var walker := _build_actor(world, &"walker", Vector3i(1, 0, 3), 8)
	var crate := _build_pushable(world, &"crate", Vector3i(2, 0, 2), -1, Vector3i(2, 1, 2), 8)
	(crate.get_parent().get_node("Pushable") as Pushable).allow_diagonal_shoves = true

	await get_tree().process_frame

	_ok(not walker.motion().step(Vector3i(1, 0, -1)), "the walker's own step is still refused")
	_eq(crate.cell(), Vector3i(3, 0, 1), "but the crate has been shoved diagonally north-east")
	_eq((crate.get_parent().get_node("Pushable") as Pushable)._pushes_used, 1,
		"counted as one push")

	(world["root"] as Node).free()


# -- RestrictToArea -------------------------------------------------------------------

func _test_restrict_to_area_refuses_a_step_that_would_leave_the_zone() -> void:
	_section("RestrictToArea -- a step that would land outside the zone is refused")

	var world := _build_world()
	var rig := _build_restricted_actor(world, &"fenced", Vector3i(1, 0, 0),
		Rect2i(Vector2i(0, 0), Vector2i(2, 1)))
	var npc: Actor = rig["actor"]

	# The zone's own collider reaches the physics server on the next tick, not the
	# frame it was added - see AreaZone.zones_at's own callers for the same wait.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var blocked_seen := []
	var on_blocked := func (id: StringName, _from: Vector3i, _to: Vector3i) -> void:
		blocked_seen.append(id)
	EventBus.actor_blocked.connect(on_blocked)

	_ok(not npc.motion().step(Vector3i(1, 0, 0)), "cell (2,0,0) is outside the fenced 2x1 zone")
	_eq(npc.cell(), Vector3i(1, 0, 0), "so it never moved")
	_eq(blocked_seen, [&"fenced"], "and the ordinary actor_blocked signal still fired")

	EventBus.actor_blocked.disconnect(on_blocked)
	(world["root"] as Node).free()


func _test_restrict_to_area_allows_a_step_that_stays_inside_the_zone() -> void:
	_section("RestrictToArea -- a step that stays inside the zone is untouched")

	var world := _build_world()
	var rig := _build_restricted_actor(world, &"fenced", Vector3i(1, 0, 0),
		Rect2i(Vector2i(0, 0), Vector2i(2, 1)))
	var npc: Actor = rig["actor"]

	await get_tree().physics_frame
	await get_tree().physics_frame

	_ok(npc.motion().step(Vector3i(-1, 0, 0)), "cell (0,0,0) is still inside the fenced zone")
	_eq(npc.cell(), Vector3i(0, 0, 0), "so the step actually landed")

	(world["root"] as Node).free()


# -- Building -----------------------------------------------------------------

func _build_world() -> Dictionary:
	var root := Node2D.new()
	add_child(root)

	var ctx := MapContext.new()
	ctx.map_id = &"modifiers_test"
	ctx.cell_size = Vector3(16, 0, 16)
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)

	return {"root": root, "ctx": ctx}


func _build_actor(world: Dictionary, id: StringName, cell: Vector3i,
		direction_count: int = 4) -> Actor:
	var ctx: MapContext = world["ctx"]

	var body := Node2D.new()
	body.name = str(id)
	body.position = Space.as_v2(ctx.cell_centre(cell))

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = id
	body.add_child(actor)

	var adapter := Space2D.new()
	adapter.name = "Space"
	actor.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = direction_count
	actor.add_child(motion)

	(world["root"] as Node).add_child(body)
	return actor


## An [Actor]/[GameEvent]/[Pushable] rig, [GameEvent] and [Pushable] siblings of the
## [Actor] under one placement body - the shape [method GameEvent._find_actor] resolves
## through its own "sibling under the same parent" fallback.
func _build_pushable(world: Dictionary, id: StringName, cell: Vector3i, max_pushes: int,
		footprint: Vector3i = Vector3i.ONE, direction_count: int = 4) -> Actor:
	var actor := _build_actor(world, id, cell, direction_count)
	actor.footprint = footprint
	var body := actor.get_parent()

	var event := GameEvent.new()
	event.name = "GameEvent"
	body.add_child(event)

	var pushable := Pushable.new()
	pushable.name = "Pushable"
	pushable.max_pushes = max_pushes
	body.add_child(pushable)

	return actor


func _build_restricted_actor(world: Dictionary, id: StringName, cell: Vector3i,
		zone_cells: Rect2i) -> Dictionary:
	var ctx: MapContext = world["ctx"]
	var actor := _build_actor(world, id, cell)
	var body := actor.get_parent()

	var event := GameEvent.new()
	event.name = "GameEvent"
	body.add_child(event)

	var area := Area2D.new()
	area.name = "Zone"
	(world["root"] as Node).add_child(area)

	var shape := CollisionShape2D.new()
	var rect := RectangleShape2D.new()
	rect.size = Vector2(zone_cells.size) * Vector2(ctx.cell_size.x, ctx.cell_size.z)
	shape.shape = rect
	shape.position = Vector2(
		(float(zone_cells.position.x) + zone_cells.size.x * 0.5) * ctx.cell_size.x,
		(float(zone_cells.position.y) + zone_cells.size.y * 0.5) * ctx.cell_size.z)
	area.add_child(shape)

	var zone := AreaZone.new()
	zone.name = "AreaZone"
	area.add_child(zone)

	var restrict := RestrictToArea.new()
	restrict.name = "RestrictToArea"
	restrict.target_zone = zone
	body.add_child(restrict)

	return {"actor": actor, "event": event, "zone": zone}


# -- Assertion helpers ----------------------------------------------------------------

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
