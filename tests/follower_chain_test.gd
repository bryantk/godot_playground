extends Node

## Headless assertions over the party caterpillar: [Occupancy]'s follower pass-through rules
## and [FollowerChain] building, trailing, grouping and saving its followers.
##
##     godot --headless --path . res://tests/follower_chain_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("party -- FollowerChain")
	print("")

	_test_occupancy_pass_through()
	await _test_chain()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_occupancy_pass_through() -> void:
	_section("Occupancy -- followers pass the leader and each other, nobody else")
	var occ := Occupancy.new()
	occ.set_leader(&"hero", true)
	occ.set_follower(&"f1", true)
	occ.set_follower(&"f2", true)
	var cell := Vector3i(4, 0, 4)

	occ.place(&"f1", cell)
	_ok(occ.is_free_for(cell, &"hero"), "the leader may step onto a follower")
	_ok(occ.is_free_for(cell, &"f2"), "a follower may step onto another follower")
	_ok(not occ.is_free_for(cell, &"npc"), "any other actor is blocked by a follower")

	occ.place(&"hero", Vector3i(5, 0, 4))
	_ok(occ.is_free_for(Vector3i(5, 0, 4), &"f1"), "a follower may step onto the leader")
	_ok(not occ.is_free_for(Vector3i(5, 0, 4), &"npc"), "but the leader still blocks everyone else")

	occ.place(&"npc", Vector3i(6, 0, 4))
	_ok(not occ.is_free_for(Vector3i(6, 0, 4), &"f1"), "a follower is blocked by an ordinary actor")
	_ok(not occ.is_free_for(Vector3i(6, 0, 4), &"hero"), "and so is the leader")

	var changes: Dictionary[Vector3i, StringName] = {cell: &"hero"}
	_ok(occ.commit(changes), "a committed step onto a follower goes through")


func _test_chain() -> void:
	_section("FollowerChain -- a follower per sheeted party member, trailing the player")

	var root := Node3D.new()
	add_child(root)
	var ctx := MapContext.new()
	ctx.map_id = &"follower_test_map"
	ctx.cell_size = Vector3.ONE
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)
	var player := _build_actor(root, &"player", Vector3i(5, 0, 5), ctx)

	var member := PartyMember.new()
	member.id = &"melina"
	member.follower_sheet = ImageTexture.create_from_image(Image.create(4, 4, false, Image.FORMAT_RGBA8))
	var plain := PartyMember.new()
	plain.id = &"no_sheet"
	var active: Array[PartyMember] = [member, plain]
	Party.active = active
	Party.changed.emit()

	await _frames(4)
	var follower := ctx.actor(&"melina")
	_ok(follower != null, "a follower was built for the member with a sheet")
	_ok(ctx.actor(&"no_sheet") == null, "and none for the member without one")
	_eq(follower.cell() if follower != null else Vector3i.ZERO, player.cell(),
		"it starts on the player's cell")

	for i in 3:
		player.motion().step(Vector3i(1, 0, 0))
		await _frames(3)
	_eq(player.cell(), Vector3i(8, 0, 5), "the player walked three cells east")
	_eq(follower.cell(), Vector3i(7, 0, 5), "the follower stands on the player's last footprint")
	_ok(ctx.occupancy.is_free_for(follower.cell(), &"player"), "the player can walk onto it")
	_ok(not ctx.occupancy.is_free_for(follower.cell(), &"someone_else"),
		"another actor cannot")

	_section("FollowerChain -- group up walks stragglers back and waits for them")
	follower.motion().move_to(Vector3i(0, 0, 0), {"path": "raw"})
	FollowerChain.gather()
	_ok(FollowerChain.is_grouping(), "gathering is in progress")
	await _frames(60)
	_ok(not FollowerChain.is_grouping(), "and finishes once everyone has stopped moving")

	_section("FollowerChain -- remove, add back, and save")
	FollowerChain.remove_member(&"melina")
	await _frames(3)
	_ok(ctx.actor(&"melina") == null, "remove_member takes the follower off the map")
	var saved := FollowerChain.to_save()
	_eq((saved["excluded"] as Array).size(), 1, "and the removal is saved")
	FollowerChain.from_save({})
	await _frames(4)
	_ok(ctx.actor(&"melina") != null, "an empty save brings the member back")

	FollowerChain.show_followers(false)
	_ok(true, "hiding with no view to hide does not error")

	FollowerChain.reset()
	root.queue_free()
	await _frames(2)


func _build_actor(root: Node, id: StringName, cell: Vector3i, ctx: MapContext) -> Actor:
	var body := Node3D.new()
	body.name = str(id)
	body.position = ctx.cell_centre(cell)
	root.add_child(body)

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
	actor.add_child(motion)
	return actor


func _frames(count: int) -> void:
	for i in count:
		await get_tree().physics_frame


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what if got == want else "%s (got %s, want %s)" % [what, str(got), str(want)])
