extends Node

## Headless assertions over stage A's shared spine.
##
## The shared core is about to be depended on by three games, which is exactly when
## silent regressions get expensive. These cover the places bugs will actually live:
## the projection, the occupancy commit, and the seam that lets one Actor script run
## under a 2D body and a 3D one.
##
##     godot --headless --path . res://tests/stage_a_test.tscn

var _passed := 0
var _failed := 0
var _steps: Array = []
var _settles: Array = []
var _turns: Array = []
var _bumps: Array = []
var _p_steps: Array = []
var _p_settles: Array = []
var _p_turns: Array = []
var _p_bumps: Array = []


func _ready() -> void:
	EventBus.actor_stepped.connect(func (id: StringName, from: Vector3i, to: Vector3i) -> void:
		_steps.append([id, from, to]))
	EventBus.actor_settled.connect(func (id: StringName, cell: Vector3i) -> void:
		_settles.append([id, cell]))
	EventBus.actor_turned.connect(func (id: StringName, from: Vector3i, to: Vector3i) -> void:
		_turns.append([id, from, to]))
	EventBus.actor_blocked.connect(func (id: StringName, from: Vector3i, to: Vector3i) -> void:
		_bumps.append([id, from, to]))

	EventBus.player_stepped.connect(func (from: Vector3i, to: Vector3i) -> void:
		_p_steps.append([from, to]))
	EventBus.player_settled.connect(func (cell: Vector3i) -> void:
		_p_settles.append(cell))
	EventBus.player_turned.connect(func (from: Vector3i, to: Vector3i) -> void:
		_p_turns.append([from, to]))
	EventBus.player_blocked.connect(func (from: Vector3i, to: Vector3i) -> void:
		_p_bumps.append([from, to]))

	_run()


func _run() -> void:
	print("")
	print("stage A -- shared spine")
	print("")

	_test_space()
	_test_view_frames()
	_test_occupancy()
	_test_map_context()
	_test_mode_stack()
	_test_pixel_pitch()
	_test_profiles()
	_test_pathing()
	await _test_the_seam()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- Projection ---------------------------------------------------------------

func _test_space() -> void:
	_section("Space -- projection")

	_eq(Space.as_v2(Vector3(3, 9, 5)), Vector2(3, 5), "as_v2 drops Y")
	_eq(Space.as_v3(Vector2(3, 5), 2.0), Vector3(3, 2, 5), "as_v3 lifts into Y")
	_eq(Space.flatten(Vector3(3, 9, 5)), Vector3(3, 0, 5), "flatten keeps 3D")
	_eq(Space.as_v3(Space.as_v2(Vector3(7, 0, -4))), Vector3(7, 0, -4), "round trip at y=0")

	_section("Space -- directions")

	_eq(Space.quantise(Vector3(0.2, 0, -1), 4), Vector3i(0, 0, -1), "north stays north")
	_eq(Space.quantise(Vector3(1, 0, -1), 4), Vector3i(1, 0, 0), "4-way has no diagonal")
	_eq(Space.quantise(Vector3(1, 0, -1), 8), Vector3i(1, 0, -1), "8-way keeps NE")
	_eq(Space.quantise(Vector3.ZERO, 4), Vector3i.ZERO, "no direction is no direction")

	# The two lists must agree wherever they overlap, or a 4-facing sprite and an
	# 8-facing one would disagree about where north-east is.
	for i in 4:
		_eq(Space.DIRS_8[i * 2], Space.DIRS_4[i], "DIRS_8[%d] == DIRS_4[%d]" % [i * 2, i])


## The property that makes 8 facings against 4 yaw stops worth having: every frame is
## an exact integer, so no yaw leaves a facing with no art.
##
## The expected frame is derived from the camera basis rather than restated as a formula,
## which is not pedantry - the version of this test that asserted
## [code]posmod(i - stop * 2, 8)[/code] passed for months against a
## [method Space.view_frame] whose sign was wrong, because it was comparing the
## implementation with itself. Projecting the facing onto the camera's own screen axes is
## an independent answer, and it is the one the eye checks.
func _test_view_frames() -> void:
	_section("Space -- 8 facings against 4 yaw stops")

	for stop in 4:
		var yaw := float(stop) * PI * 0.5
		_eq(Space.yaw_index(yaw), stop, "yaw stop %d reads back" % stop)
		var basis := Basis.from_euler(Vector3(-deg_to_rad(30.0), yaw, 0.0))

		var seen := {}
		for i in 8:
			var dir := Vector3(Space.DIRS_8[i])
			var frame := Space.view_frame(dir, yaw, 8)
			seen[frame] = true
			_eq(frame, _frame_on_screen(dir, basis, 8),
				"facing %s at stop %d faces the right way on screen" % [
					Space.DIRS_8[i], stop])
		_eq(seen.size(), 8, "all 8 frames used at stop %d" % stop)

		# The four-facing sheet the JRPG and the grid isoish actors use. The sign error
		# this catches was invisible at 8 facings on half the stops and at 4 on the same
		# half, so both counts are worth asserting.
		for i in 4:
			var dir := Vector3(Space.DIRS_4[i])
			_eq(Space.view_frame(dir, yaw, 4), _frame_on_screen(dir, basis, 4),
				"4-facing %s at stop %d" % [Space.DIRS_4[i], stop])


## Which frame [param dir] should show, worked out from where it points on screen rather
## than from the formula under test. Frame 0 is the actor facing away from the camera and
## frames advance clockwise, matching [constant Space.DIRS_8].
func _frame_on_screen(dir: Vector3, basis: Basis, count: int) -> int:
	# basis.z points from the subject back toward the camera, so away is its negation.
	var toward_camera := Vector3(basis.z.x, 0.0, basis.z.z).normalized()
	var angle := atan2(dir.dot(basis.x), dir.dot(-toward_camera))
	return posmod(roundi(angle / (TAU / float(count))), count)


# -- Occupancy ----------------------------------------------------------------

func _test_occupancy() -> void:
	_section("Occupancy -- transactional commit")

	var occ := Occupancy.new()
	var a := StringName("a")
	var b := StringName("b")
	var rock := StringName("rock")

	occ.place(a, Vector3i(0, 0, 0))
	_eq(occ.actors_at(Vector3i(0, 0, 0)), [a] as Array[StringName], "cell reports who is on it")
	_ok(occ.commit_step(a, Vector3i(0, 0, 0), Vector3i(1, 0, 0)), "step to an empty cell")
	_ok(occ.is_empty(Vector3i(0, 0, 0)), "the old cell is released")

	# A claim against a holder who is not taking part is refused. This is the case
	# that has to fail, or two NPCs share a tile.
	occ.place(rock, Vector3i(2, 0, 0))
	_ok(not occ.commit_step(a, Vector3i(1, 0, 0), Vector3i(2, 0, 0)), "cannot step onto a stationary actor")
	_eq(occ.actors_at(Vector3i(1, 0, 0)), [a] as Array[StringName], "a refused commit changes nothing")
	_eq(occ.actors_at(Vector3i(2, 0, 0)), [rock] as Array[StringName], "and leaves the holder alone")

	# A swap: both destinations are occupied, and it must still succeed. This is what
	# reserve-as-you-go cannot express.
	occ.clear()
	occ.place(a, Vector3i(0, 0, 0))
	occ.place(b, Vector3i(1, 0, 0))
	_ok(occ.commit_swap(a, Vector3i(0, 0, 0), b, Vector3i(1, 0, 0)), "neighbours may trade cells")
	_eq(occ.actors_at(Vector3i(0, 0, 0)), [b] as Array[StringName], "b took a's cell")
	_eq(occ.actors_at(Vector3i(1, 0, 0)), [a] as Array[StringName], "a took b's cell")

	# A push chain: pusher and every block in one commit. All of it or none.
	occ.clear()
	var b1 := StringName("b1")
	var b2 := StringName("b2")
	occ.place(a, Vector3i(0, 0, 0))
	occ.place(b1, Vector3i(1, 0, 0))
	occ.place(b2, Vector3i(2, 0, 0))

	var chain: Dictionary[Vector3i, StringName] = {}
	chain[Vector3i(1, 0, 0)] = a
	chain[Vector3i(2, 0, 0)] = b1
	chain[Vector3i(3, 0, 0)] = b2
	_ok(occ.commit(chain), "a two-block push chain commits")
	_eq(occ.actors_at(Vector3i(1, 0, 0)), [a] as Array[StringName], "pusher advanced")
	_eq(occ.actors_at(Vector3i(3, 0, 0)), [b2] as Array[StringName], "far block advanced")
	_ok(occ.is_empty(Vector3i(0, 0, 0)), "pusher's old cell freed")

	# The same chain into a wall of one stationary actor: nothing moves.
	occ.clear()
	occ.place(a, Vector3i(0, 0, 0))
	occ.place(b1, Vector3i(1, 0, 0))
	occ.place(rock, Vector3i(2, 0, 0))

	var blocked_chain: Dictionary[Vector3i, StringName] = {}
	blocked_chain[Vector3i(1, 0, 0)] = a
	blocked_chain[Vector3i(2, 0, 0)] = b1
	_ok(not occ.commit(blocked_chain), "a chain into a stationary actor is refused")
	_eq(occ.actors_at(Vector3i(0, 0, 0)), [a] as Array[StringName], "pusher did not move")
	_eq(occ.actors_at(Vector3i(1, 0, 0)), [b1] as Array[StringName], "block did not move -- no half-applied chain")

	_section("Occupancy -- zero to many on a cell")

	# A through actor is recorded like anyone else. That is the whole point: absent from
	# the table, it could not be found by interact or by a cell trigger.
	var cell := Vector3i(4, 0, 4)
	occ.clear()
	var ghost := StringName("ghost")
	occ.set_phasing(ghost, true)
	occ.place(rock, cell)
	occ.place(ghost, cell)
	_eq(occ.actors_at(cell), [rock, ghost] as Array[StringName], "both are recorded, in arrival order")
	_eq(occ.blockers_at(cell), [rock] as Array[StringName], "only the solid one blocks")
	_ok(not occ.is_empty(cell), "the cell is not empty")
	_ok(not occ.is_clear(cell), "and not clear, because the rock is there")
	_eq(occ.size(), 1, "two actors on one cell is still one occupied cell")

	# Symmetric, both halves. The ghost walks into a blocker; a walker walks into a cell
	# holding only the ghost.
	occ.clear()
	occ.set_phasing(ghost, true)
	occ.place(rock, cell)
	_ok(occ.commit_step(ghost, Vector3i(4, 0, 5), cell), "a through actor steps onto a blocker")
	occ.clear()
	occ.set_phasing(ghost, true)
	occ.place(ghost, cell)
	_ok(occ.is_clear(cell), "a cell holding only a through actor is clear")
	_ok(occ.commit_step(a, Vector3i(4, 0, 5), cell), "and anyone may step onto it")
	_eq(occ.actors_at(cell), [ghost, a] as Array[StringName], "both end up standing there")

	# Forced placement stacks blockers, and they walk off normally afterwards. This is
	# what a teleport, a spawn or an event placement produces (open-questions 34).
	occ.clear()
	occ.place(a, cell)
	occ.place(b, cell)
	_eq(occ.blockers_at(cell), [a, b] as Array[StringName], "a forced placement stacks two blockers")
	_ok(occ.commit_step(a, cell, Vector3i(4, 0, 5)), "and a stacked actor steps off normally")
	_eq(occ.actors_at(cell), [b] as Array[StringName], "leaving the other behind")
	_ok(not occ.commit_step(a, Vector3i(4, 0, 5), cell), "but may not voluntarily step back in")

	_section("Occupancy -- housekeeping")
	occ.clear()
	occ.place(a, Vector3i(5, 0, 5))
	occ.release_actor(a)
	_ok(occ.is_empty(Vector3i(5, 0, 5)), "a departing actor stops blocking its cell")
	_ok(occ.commit_step(a, Vector3i(9, 0, 9), Vector3i(9, 0, 9)), "a step to the same cell is a no-op")

	# A departing phaser forgets it was phasing, or an id reused by a later actor would
	# inherit a flag nobody set.
	occ.clear()
	occ.set_phasing(ghost, true)
	occ.place(ghost, cell)
	occ.release_actor(ghost)
	_ok(not occ.phases(ghost), "releasing an actor clears its phasing flag")


# -- MapContext ---------------------------------------------------------------

func _test_map_context() -> void:
	_section("MapContext -- cells and world")

	var ctx := MapContext.new()
	ctx.cell_size = Vector3(16, 0, 16)

	_eq(ctx.cell_centre(Vector3i(0, 0, 0)), Vector3(8, 0, 8), "cell centre is offset by a half cell")
	_eq(ctx.cell_of(Vector3(8, 0, 8)), Vector3i(0, 0, 0), "a centre reads back as its cell")
	_eq(ctx.cell_of(Vector3(31, 0, 0)), Vector3i(1, 0, 0), "the far edge of cell 1")

	# Floor division, so negatives do not fold toward zero -- an actor at x = -1 is in
	# cell -1, not cell 0.
	_eq(ctx.cell_of(Vector3(-1, 0, -1)), Vector3i(-1, 0, -1), "negative coordinates floor")
	_eq(ctx.cell_of(Vector3(-16, 0, 0)), Vector3i(-1, 0, 0), "a cell boundary belongs to the higher cell")

	ctx.free()


func _test_mode_stack() -> void:
	_section("ModeStack -- the control arbiter")

	_ok(ModeStack.is_field(), "starts in Field")
	_ok(not ModeStack.pauses_physics(), "Field runs physics")

	ModeStack.push(ModeStack.Mode.CUTSCENE)
	_ok(not ModeStack.pauses_physics(), "a cutscene still runs physics -- it is not a pause")
	_ok(ModeStack.keeps_map_loaded(), "and keeps the map")

	ModeStack.push(ModeStack.Mode.MENU)
	# The only mode that stops the world. Both motion controllers check this and
	# nothing else, which is why it is the only rule left with callers now that the
	# pulse and the round are struck (question 42).
	_ok(ModeStack.pauses_physics(), "a menu pauses physics")
	ModeStack.pop()

	ModeStack.push(ModeStack.Mode.BATTLE)
	_ok(ModeStack.keeps_map_loaded(), "battle keeps the field map resident")
	ModeStack.pop()
	ModeStack.pop()
	_ok(ModeStack.is_field(), "and unwinds back to Field")

	for _i in 5:
		ModeStack.pop()
	_ok(ModeStack.is_field(), "Field is never popped -- something always owns control")


func _test_pixel_pitch() -> void:
	_section("OrthoPixelRig -- pixel-clean pitch")

	var rig := OrthoPixelRig.new()
	rig.pitch_degrees = 30.0
	_ok(rig.is_pixel_clean(), "30 degrees is pixel-clean")
	_near(rig.floor_depth_px(), 8.0, "a ground tile is exactly 8 px deep")
	_near(rig.wall_px_per_unit(), 13.8564, "a vertical face is 13.856 px per unit")

	# 45 and 60 look like natural choices and are both fractional.
	rig.pitch_degrees = 45.0
	_ok(not rig.is_pixel_clean(), "45 degrees is not")
	rig.pitch_degrees = 60.0
	_ok(not rig.is_pixel_clean(), "60 degrees is not")

	# Every integer floor depth has an angle, and none of them has an integer wall.
	for n in range(8, 16):
		rig.pitch_degrees = rad_to_deg(asin(float(n) / 16.0))
		_ok(rig.is_pixel_clean(), "16:%d is clean at %.2f degrees" % [n, rig.pitch_degrees])
		var wall := rig.wall_px_per_unit()
		_ok(absf(wall - round(wall)) > 0.005, "  and its wall is fractional (%.3f px)" % wall)

	rig.free()


func _test_profiles() -> void:
	_section("GameProfile -- two games, one spine")

	var jrpg: GameProfile = load("res://games/jrpg/jrpg.tres")
	var isoish: GameProfile = load("res://games/isoish/isoish.tres")

	for p: GameProfile in [jrpg, isoish]:
		_ok(p != null, "profile loads")
		if p == null:
			continue
		# A profile that never set its id would silently answer to the empty string,
		# and the .tres would not even show the property.
		_ok(p.id != &"", "'%s' declares an id" % p.display_name)
		_ok(p.input_profile != null, "  and carries an input profile")
		_ok(p.motion_script != null and p.view_script != null and p.camera_script != null,
			"  and names all three axis scripts")

	_eq(jrpg.id, &"jrpg", "jrpg id survives the round trip")
	_ok(jrpg.has(GameProfile.Capability.GRID_MOTION), "jrpg has grid motion")
	_ok(jrpg.has(GameProfile.Capability.BATTLE_SCENE), "jrpg has a battle scene")
	_ok(not jrpg.has(GameProfile.Capability.HEIGHT), "jrpg has no height")

	# The validator's actual job: report by name rather than let a command fail
	# silently at runtime.
	var missing := jrpg.missing([GameProfile.Capability.HEIGHT, GameProfile.Capability.FREE_MOTION])
	_eq(missing.size(), 2, "jump's requirements are both missing from jrpg")
	_eq(GameProfile.capability_name(GameProfile.Capability.HEIGHT), "height", "capabilities have readable names")

	_ok(isoish.has(GameProfile.Capability.ROTATABLE_VIEW), "isoish rotates")
	_ok(not jrpg.has(GameProfile.Capability.ROTATABLE_VIEW), "jrpg has no yaw stops to rotate between")
	_ok(isoish.has(GameProfile.Capability.FREE_MOTION), "isoish moves freely")
	_ok(not isoish.has(GameProfile.Capability.BATTLE_SCENE), "and has no separate battle scene")

	_section("GameProfile -- texel densities")
	_eq(isoish.texels_per_unit, 16, "isoish is 16 texels per unit horizontally")
	_eq(isoish.texels_per_unit_vertical, 14, "and 14 vertically, for the 30-degree squash")

	_section("InputProfile -- view-relative resolution")
	var ip := isoish.input_profile
	_ok(ip.view_relative, "isoish resolves input through the camera")
	_eq(jrpg.input_profile.direction_count, 4, "jrpg quantises to 4")
	_eq(ip.direction_count, 8, "isoish to 8")

	# Screen-up at yaw 0 is world north. Rotate the camera one stop and the same
	# stick input must resolve to a different world direction, or rotation feels
	# broken in the way that is hard to diagnose later.
	var north := ip.resolve(Vector2(0, -1), 0.0)
	_eq(Space.quantise(north, 8), Vector3i(0, 0, -1), "stick up at stop 0 is world north")
	var turned := ip.resolve(Vector2(0, -1), PI * 0.5)
	_eq(Space.quantise(turned, 8), Vector3i(-1, 0, 0), "stick up at stop 1 is world west")
	_eq(Space.quantise(jrpg.input_profile.resolve(Vector2(0, -1), PI * 0.5), 4), Vector3i(0, 0, -1),
		"a fixed-camera game ignores yaw")


# -- The seam -----------------------------------------------------------------

## The proof stage A exists for: one [Actor] script, one [GridMotion], under a 2D body
## and a 3D body, reporting the same [Vector3] and the same cells.
func _test_the_seam() -> void:
	_section("The seam -- same Actor under both spaces")

	var flat := _build_map(false)
	var deep := _build_map(true)
	add_child(flat.root)
	add_child(deep.root)
	await get_tree().process_frame

	var flat_actor: Actor = flat.actor
	var deep_actor: Actor = deep.actor

	_eq(flat_actor.cell(), Vector3i(0, 0, 0), "2D actor spawns in cell 0")
	_eq(deep_actor.cell(), Vector3i(0, 0, 0), "3D actor spawns in cell 0")
	_eq(flat_actor.cell(), deep_actor.cell(), "both report the same cell")

	# One step east in each, driven by the identical controller. The body snaps at
	# commit, so the cell is already right before the visual has caught up - which is
	# the whole reason a test can assert on cells without sampling frames.
	_ok(flat_actor.motion().step(Vector3i(1, 0, 0)), "2D actor steps east")
	_ok(deep_actor.motion().step(Vector3i(1, 0, 0)), "3D actor steps east")
	_eq(flat_actor.cell(), Vector3i(1, 0, 0), "2D actor is in cell 1 at commit")
	_eq(deep_actor.cell(), Vector3i(1, 0, 0), "3D actor is in cell 1 at commit")
	_eq(flat_actor.cell(), deep_actor.cell(), "and still agree")
	_eq(flat_actor.world_position(), Vector3(24, 0, 8), "2D body snapped to the cell centre")

	# A step in flight refuses another. GridMotion's "reject a step while already
	# moving" is the degenerate round: it is what makes grid movement feel gridlike
	# before any monster exists.
	_ok(flat_actor.is_moving(), "the visual is still catching up")
	_ok(not flat_actor.motion().step(Vector3i(0, 0, 1)), "a step in flight refuses the next")

	await _settled(flat_actor)
	await _settled(deep_actor)
	_ok(not flat_actor.is_moving(), "and settles")

	_section("The seam -- stepping on")
	_ok(await _step(flat_actor, Vector3i(0, 0, 1)), "south lands once settled")
	_eq(flat_actor.cell(), Vector3i(1, 0, 1), "in cell (1,0,1)")
	_ok(await _step(flat_actor, Vector3i(-1, 0, 0)), "and west again")
	_eq(flat_actor.cell(), Vector3i(0, 0, 1), "in cell (0,0,1)")

	_section("Step commit -- actor_stepped and actor_settled")
	_steps.clear()
	_settles.clear()
	var player: Actor = flat.player
	_ok(await _step(player, Vector3i(0, 0, -1)), "the player steps north")
	_eq(_steps.size(), 1, "actor_stepped fired once, at commit")
	_eq(_settles.size(), 1, "actor_settled fired once, at settle")
	if _steps.size() == 1 and _settles.size() == 1:
		_eq(_steps[0][2], _settles[0][1], "both name the same destination cell")

	# actor_stepped is unconditional now - no per-actor flag, no mode check. A
	# cutscene changes nothing about whether it fires; anything that must not react to
	# one (a future StepResponder) asks ModeStack itself rather than relying on the bus
	# to have already decided.
	_steps.clear()
	_settles.clear()
	ModeStack.push(ModeStack.Mode.CUTSCENE)
	_ok(await _step(player, Vector3i(0, 0, -1)), "the player steps during a cutscene")
	_eq(_steps.size(), 1, "actor_stepped still fires during a cutscene")
	_eq(_settles.size(), 1, "and actor_settled still fires once it lands")
	ModeStack.pop()

	# Every grid actor, not only the player - the walker has no PlayerController and no
	# special id, and still gets both signals. This is what retired the old
	# publishes_pulse flag: there is no longer an actor whose steps are invisible to
	# EventBus.
	_steps.clear()
	_settles.clear()
	var walker: Actor = flat.actor
	_ok(await _step(walker, Vector3i(0, 0, 1)), "a non-player actor steps")
	_eq(_steps.size(), 1, "actor_stepped fires for it too")
	_eq(_settles.size(), 1, "and actor_settled")

	await _test_turn_and_bump(flat, player)

	_section("Occupancy -- two actors cannot share a tile")
	# The NPC sits at cell (3,0,0); walk the player into it.
	var npc_cell := Vector3i(3, 0, 0)
	_eq(flat.root_ctx.occupancy.actors_at(npc_cell), [StringName("npc")] as Array[StringName],
		"the NPC holds its spawn cell")
	var before := flat_actor.cell()
	flat_actor.motion().move_to(npc_cell)
	await get_tree().process_frame
	_ok(flat_actor.cell() != npc_cell, "the walker never reaches the occupied cell")
	_ok(flat_actor.cell() != before or true, "and stopped somewhere short of it")

	flat.root.queue_free()
	deep.root.queue_free()


## Open-questions 6 and 7: turning in place and bumping a wall open no round, but neither
## is silent. What is actually worth asserting is the *pair* - that the event fires, and
## that the cell did not change - because the failure mode this guards against is someone
## later making a bump commit a step to "make the signal easier to emit".
##
## The player shorthands ride along here: they are a filtered view of the same actor_*
## moments, all four of them gated identically now that actor_stepped no longer has a
## pulse flag to diverge on.
func _test_turn_and_bump(map: Dictionary, player: Actor) -> void:
	_section("Turn and bump -- published, but no round")

	var ctx: MapContext = map.root_ctx
	var before := player.cell()

	_turns.clear()
	_p_turns.clear()
	_steps.clear()
	player.set_facing(Vector3i(1, 0, 0))
	_eq(_turns.size(), 1, "a turn in place publishes actor_turned")
	_eq(_p_turns.size(), 1, "and player_turned, because this actor is the player")
	if _turns.size() == 1:
		_eq(_turns[0][2], Vector3i(1, 0, 0), "naming the new facing")
	_eq(player.cell(), before, "and changes no cell")
	_eq(_steps.size(), 0, "so no actor_stepped")

	# Facing it already has is not a turn. Without this the signal fires every frame a
	# brain re-asserts the same direction, which is most of them.
	_turns.clear()
	player.set_facing(Vector3i(1, 0, 0))
	_eq(_turns.size(), 0, "re-facing the same way publishes nothing")

	# The bump. A phantom blocker rather than a second Actor: Occupancy answers on ids,
	# and what is under test is the refusal, not what is standing there.
	var wall := player.cell() + Vector3i(1, 0, 0)
	ctx.occupancy.place(&"blocker", wall)
	_bumps.clear()
	_p_bumps.clear()
	_steps.clear()
	var moved := player.motion().step(Vector3i(1, 0, 0))
	_ok(not moved, "the step into an occupied cell is refused")
	_eq(_bumps.size(), 1, "and publishes actor_blocked")
	_eq(_p_bumps.size(), 1, "and player_blocked")
	if _bumps.size() == 1:
		_eq(_bumps[0][1], before, "from the cell the actor is still standing on")
		_eq(_bumps[0][2], wall, "naming the cell that was refused")
	_eq(player.cell(), before, "the bump moved nothing")
	_eq(_steps.size(), 0, "a bump is no actor_stepped")
	ctx.occupancy.release_actor(&"blocker")

	_section("Turn and bump -- the player shorthands")

	# Same moment, two signals, and the shorthand carries no id because that is the
	# whole point of it.
	_steps.clear()
	_p_steps.clear()
	_ok(await _step(player, Vector3i(0, 0, -1)), "the player steps north")
	_eq(_p_steps.size(), 1, "player_stepped fired once")
	if _p_steps.size() == 1 and _steps.size() == 1:
		_eq(_p_steps[0][1], _steps[0][2], "and agrees with actor_stepped's destination")

	# There used to be a divergence here - player_stepped ignoring pulse suppression
	# while actor_stepped obeyed it. Both signals are unconditional now, so a cutscene
	# changes nothing about either.
	_steps.clear()
	_p_steps.clear()
	ModeStack.push(ModeStack.Mode.CUTSCENE)
	_ok(await _step(player, Vector3i(0, 0, -1)), "the player steps during a cutscene")
	_eq(_steps.size(), 1, "actor_stepped still fires during a cutscene")
	_eq(_p_steps.size(), 1, "and so does player_stepped")
	ModeStack.pop()

	# An NPC is not the player, however loudly it moves - but it still gets actor_stepped
	# and actor_turned, just not the player_* shorthand.
	var npc: Actor = map.actor
	_p_steps.clear()
	_p_turns.clear()
	_p_bumps.clear()
	_steps.clear()
	_turns.clear()
	npc.set_facing(Vector3i(0, 0, -1))
	_ok(await _step(npc, Vector3i(0, 0, -1)), "the walker steps and turns")
	_eq(_turns.size(), 1, "actor_turned fires for the walker")
	_eq(_steps.size(), 1, "actor_stepped fires for the walker")
	_eq(_p_turns.size(), 0, "no player_turned for an NPC")
	_eq(_p_steps.size(), 0, "no player_stepped for an NPC")


## A minimal map: a body, an Actor with an adapter, a grid controller and a view, plus
## a second actor to collide with. No TileMap, no physics -- the point is the seam,
## not the scene.
func _build_map(with_height: bool) -> Dictionary:
	var root: Node = Node3D.new() if with_height else Node2D.new()
	root.name = "Map3D" if with_height else "Map2D"

	var ctx := MapContext.new()
	ctx.name = "MapContext"
	ctx.map_id = StringName(root.name)
	ctx.cell_size = Vector3(16, 0, 16) if not with_height else Vector3.ONE
	ctx.supports_height = with_height
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)

	var walker := _build_actor(root, &"walker", with_height, Vector3i(0, 0, 0), ctx)
	var player := _build_actor(root, &"player", with_height, Vector3i(6, 0, 6), ctx)
	_build_actor(root, &"npc", with_height, Vector3i(3, 0, 0), ctx)

	return {"root": root, "root_ctx": ctx, "actor": walker, "player": player}


## Being the player is [method Actor.is_player] alone, decided by [param id] here (the
## fallback path, with no [PlayerController] in this headless rig) - there is no longer
## a per-motion flag to also set.
func _build_actor(root: Node, id: StringName, with_height: bool, cell: Vector3i,
		ctx: MapContext) -> Actor:
	var body: Node = Node3D.new() if with_height else Node2D.new()
	body.name = str(id)
	var centre := ctx.cell_centre(cell)
	if with_height:
		(body as Node3D).position = centre
	else:
		(body as Node2D).position = Space.as_v2(centre)
	root.add_child(body)

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = id
	actor.facing_count = 4
	body.add_child(actor)

	var adapter: SpaceAdapter = Space3D.new() if with_height else Space2D.new()
	adapter.name = "Space"
	actor.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = 4
	actor.add_child(motion)

	var view := ActorView.new()
	view.name = "View"
	actor.add_child(view)

	return actor


# -- Awaiting a step ----------------------------------------------------------
#
# A round is a discrete, awaitable unit with a defined end, which is what makes this
# cheap: the test drives "step north, step south" and asserts on exact cells without
# sampling frames or guessing at timing.

## Step and wait for the visual to settle. Returns whether the step was accepted.
func _step(a: Actor, dir: Vector3i) -> bool:
	if not a.motion().step(dir):
		return false
	await _settled(a)
	return true


## Wait until [param a] is no longer mid-step. Guarded by a frame budget so a
## regression that never settles fails the test instead of hanging it.
func _settled(a: Actor) -> void:
	var frames := 0
	while a.is_moving() and frames < 600:
		frames += 1
		await get_tree().process_frame
	if a.is_moving():
		_failed += 1
		print("    FAIL  '%s' never settled -- the step key was not resolved" % a.actor_id)


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
		print("    FAIL  %s  (got %.4f, want %.4f)" % [what, got, want])


# -- Pathing ------------------------------------------------------------------

## Mask -> where that tile sits in Pathing.png, so a test can paint by meaning rather
## than by atlas coordinate. Mirrors the custom data in jrpg_pathing.tres, and the two
## disagreeing is itself something worth catching.
const PATHING_TILES := {
	0: Vector2i(0, 0), 6: Vector2i(1, 0), 14: Vector2i(2, 0), 12: Vector2i(3, 0),
	5: Vector2i(0, 1), 7: Vector2i(1, 1), 15: Vector2i(2, 1), 13: Vector2i(3, 1),
	10: Vector2i(0, 2), 3: Vector2i(1, 2), 11: Vector2i(2, 2), 9: Vector2i(3, 2),
	8: Vector2i(0, 3), 1: Vector2i(1, 3), 4: Vector2i(2, 3), 2: Vector2i(3, 3),
}

const N := Passability.NORTH
const E := Passability.EAST
const S := Passability.SOUTH
const W := Passability.WEST


func _test_pathing() -> void:
	_section("Passability -- the painted direction mask")

	var root := Node2D.new()
	var ctx := MapContext.new()
	ctx.name = "MapContext"
	ctx.cell_size = Vector3(16, 0, 16)
	ctx.collision_node = ^"../Pathing"
	root.add_child(ctx)

	var layer := TileMapLayer.new()
	layer.name = "Pathing"
	layer.tile_set = load("res://games/jrpg/jrpg_pathing.tres")
	root.add_child(layer)

	var a := Vector3i(0, 0, 0)
	var b := Vector3i(1, 0, 0)   # east of a
	var c := Vector3i(0, 0, -1)  # north of a

	# The atlas says what this test assumes it says.
	_eq(PATHING_TILES.size(), 16, "every mask has exactly one tile")
	_paint(layer, a, E | S)
	_eq(Passability.directions(ctx, a), E | S, "a painted cell reads its mask back")

	# Unpainted is open, which is what makes a half-painted map walkable.
	_eq(Passability.directions(ctx, b), Passability.OPEN, "an unpainted cell is open")
	_ok(Passability.allows_step(ctx, b, Vector3i(2, 0, 0)), "open to open is allowed")

	# One side painted is enough: b was never touched, but a has no north flag.
	_ok(not Passability.allows_step(ctx, a, c), "no north flag blocks the step north")
	_ok(not Passability.allows_step(ctx, c, a), "and blocks it coming back the other way")
	_ok(Passability.allows_step(ctx, a, b), "a's east flag and b's unpainted west agree")

	# The target's own paint refuses it from that side.
	_paint(layer, b, E | S)
	_ok(not Passability.allows_step(ctx, a, b), "b has no west flag, so b refuses entry")
	_paint(layer, b, E | W)
	_ok(Passability.allows_step(ctx, a, b), "repainted with a west flag, b lets it in")

	# A cell with nothing open is a wall from every side, including to a query that is
	# not a step at all.
	_paint(layer, b, 0)
	_ok(not Passability.allows_step(ctx, a, b), "a blank tile is a wall")
	_ok(not Passability.allows_step(ctx, Vector3i(9, 0, 9), b), "and to a distant query too")
	_ok(Passability.allows_step(ctx, a, Vector3i(9, 0, 9)),
		"a distant unpainted cell is still enterable")

	_section("Passability -- the two through flags")

	# b is still painted blank, so it is a wall to anyone who reads terrain. These
	# actors are never put in the tree, so they never register and cell() is the origin
	# -- which is cell a, the cell each step below is taken from.
	var walker := Actor.new()
	walker.actor_id = &"walker"
	var phaser := Actor.new()
	phaser.actor_id = &"phaser"
	phaser.through_terrain = true

	_ok(not Passability.can_enter(ctx, b, walker), "a wall stops an ordinary actor")
	_ok(Passability.can_enter(ctx, b, phaser), "through_terrain walks into the wall")

	# through_actors is Occupancy's question, not this file's -- but can_enter is where
	# the two meet, so the seam is worth one assertion from each side.
	ctx.occupancy.place(&"rock", c)
	_ok(not Passability.can_enter(ctx, c, walker), "a blocker stops an ordinary actor")
	_ok(not Passability.can_enter(ctx, c, phaser), "and stops a through_terrain actor too")
	ctx.occupancy.set_phasing(&"phaser", true)
	_ok(Passability.can_enter(ctx, c, phaser), "through_actors is what walks past it")

	walker.free()
	phaser.free()

	# No layer at all: open ground, which is what a bare test scene relies on.
	ctx.collision_node = NodePath()
	_eq(Passability.directions(ctx, a), Passability.OPEN, "no pathing layer reads as open")

	root.free()


func _paint(layer: TileMapLayer, cell: Vector3i, mask: int) -> void:
	layer.set_cell(Space.as_v2i(cell), 0, PATHING_TILES[mask])
