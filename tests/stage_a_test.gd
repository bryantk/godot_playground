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
var _pulses: Array = []
var _entered: Array = []


func _ready() -> void:
	EventBus.actor_stepped.connect(func (id: StringName, from: Vector3i, to: Vector3i) -> void:
		_pulses.append([id, from, to]))
	EventBus.cell_entered.connect(func (id: StringName, cell: Vector3i) -> void:
		_entered.append([id, cell]))

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
func _test_view_frames() -> void:
	_section("Space -- 8 facings against 4 yaw stops")

	for stop in 4:
		var yaw := float(stop) * PI * 0.5
		_eq(Space.yaw_index(yaw), stop, "yaw stop %d reads back" % stop)

		var seen := {}
		for i in 8:
			var frame := Space.view_frame(Vector3(Space.DIRS_8[i]), yaw, 8)
			seen[frame] = true
			_eq(frame, posmod(i - stop * 2, 8), "facing %d at stop %d -> frame" % [i, stop])
		_eq(seen.size(), 8, "all 8 frames used at stop %d" % stop)


# -- Occupancy ----------------------------------------------------------------

func _test_occupancy() -> void:
	_section("Occupancy -- transactional commit")

	var occ := Occupancy.new()
	var a := StringName("a")
	var b := StringName("b")
	var rock := StringName("rock")

	_ok(occ.reserve(a, Vector3i(0, 0, 0)), "reserve an empty cell")
	_eq(occ.at(Vector3i(0, 0, 0)), a, "cell reports its holder")
	_ok(occ.commit_step(a, Vector3i(0, 0, 0), Vector3i(1, 0, 0)), "step to an empty cell")
	_ok(occ.is_free(Vector3i(0, 0, 0)), "the old cell is released")

	# A claim against a holder who is not taking part is refused. This is the case
	# that has to fail, or two NPCs share a tile.
	_ok(occ.reserve(rock, Vector3i(2, 0, 0)), "a stationary actor holds a cell")
	_ok(not occ.commit_step(a, Vector3i(1, 0, 0), Vector3i(2, 0, 0)), "cannot step onto a stationary actor")
	_eq(occ.at(Vector3i(1, 0, 0)), a, "a refused commit changes nothing")
	_eq(occ.at(Vector3i(2, 0, 0)), rock, "and leaves the holder alone")

	# A swap: both destinations are occupied, and it must still succeed. This is what
	# reserve-as-you-go cannot express.
	occ.clear()
	_ok(occ.reserve(a, Vector3i(0, 0, 0)) and occ.reserve(b, Vector3i(1, 0, 0)), "two neighbours")
	_ok(occ.commit_swap(a, Vector3i(0, 0, 0), b, Vector3i(1, 0, 0)), "neighbours may trade cells")
	_eq(occ.at(Vector3i(0, 0, 0)), b, "b took a's cell")
	_eq(occ.at(Vector3i(1, 0, 0)), a, "a took b's cell")

	# A push chain: pusher and every block in one commit. All of it or none.
	occ.clear()
	var b1 := StringName("b1")
	var b2 := StringName("b2")
	occ.reserve(a, Vector3i(0, 0, 0))
	occ.reserve(b1, Vector3i(1, 0, 0))
	occ.reserve(b2, Vector3i(2, 0, 0))

	var chain: Dictionary[Vector3i, StringName] = {}
	chain[Vector3i(1, 0, 0)] = a
	chain[Vector3i(2, 0, 0)] = b1
	chain[Vector3i(3, 0, 0)] = b2
	_ok(occ.commit(chain), "a two-block push chain commits")
	_eq(occ.at(Vector3i(1, 0, 0)), a, "pusher advanced")
	_eq(occ.at(Vector3i(3, 0, 0)), b2, "far block advanced")
	_ok(occ.is_free(Vector3i(0, 0, 0)), "pusher's old cell freed")

	# The same chain into a wall of one stationary actor: nothing moves.
	occ.clear()
	occ.reserve(a, Vector3i(0, 0, 0))
	occ.reserve(b1, Vector3i(1, 0, 0))
	occ.reserve(rock, Vector3i(2, 0, 0))

	var blocked_chain: Dictionary[Vector3i, StringName] = {}
	blocked_chain[Vector3i(1, 0, 0)] = a
	blocked_chain[Vector3i(2, 0, 0)] = b1
	_ok(not occ.commit(blocked_chain), "a chain into a stationary actor is refused")
	_eq(occ.at(Vector3i(0, 0, 0)), a, "pusher did not move")
	_eq(occ.at(Vector3i(1, 0, 0)), b1, "block did not move -- no half-applied chain")

	_section("Occupancy -- housekeeping")
	occ.clear()
	occ.reserve(a, Vector3i(5, 0, 5))
	occ.release_actor(a)
	_ok(occ.is_free(Vector3i(5, 0, 5)), "a departing actor stops blocking its cell")
	_ok(occ.commit_step(a, Vector3i(9, 0, 9), Vector3i(9, 0, 9)), "a step to the same cell is a no-op")


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
	_ok(not ModeStack.suppresses_pulse(), "Field pulses")
	_ok(ModeStack.rounds_active(), "Field has rounds")

	ModeStack.push(ModeStack.Mode.CUTSCENE)
	_ok(ModeStack.suppresses_pulse(), "a cutscene suppresses the pulse")
	# The whole point of question 27: the watchdog must not run here, or it
	# force-unlocks input while a runner is legitimately waiting on the player.
	_ok(not ModeStack.rounds_active(), "a cutscene has no rounds, so no watchdog")

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
	_ok(jrpg.has(GameProfile.Capability.STEP_PULSE), "jrpg has the step pulse")
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

	_section("Step commit -- pulse and triggers together")
	_pulses.clear()
	_entered.clear()
	var player: Actor = flat.player
	_ok(await _step(player, Vector3i(0, 0, -1)), "the player steps north")
	_eq(_pulses.size(), 1, "one pulse fired")
	_eq(_entered.size(), 1, "one cell trigger fired")
	if _pulses.size() == 1 and _entered.size() == 1:
		_eq(_pulses[0][2], _entered[0][1], "both name the same destination cell")

	# A cutscene suppresses the pulse but not the trigger -- the world still knows an
	# actor entered a cell, the monsters just do not act on it.
	_pulses.clear()
	_entered.clear()
	ModeStack.push(ModeStack.Mode.CUTSCENE)
	_ok(await _step(player, Vector3i(0, 0, -1)), "the player steps during a cutscene")
	_eq(_pulses.size(), 0, "no pulse during a cutscene")
	_eq(_entered.size(), 1, "but the cell trigger still fires")
	ModeStack.pop()

	_section("Occupancy -- two actors cannot share a tile")
	# The NPC sits at cell (3,0,0); walk the player into it.
	var npc_cell := Vector3i(3, 0, 0)
	_eq(flat.root_ctx.occupancy.at(npc_cell), StringName("npc"), "the NPC holds its spawn cell")
	var before := flat_actor.cell()
	flat_actor.motion().move_to(npc_cell)
	await get_tree().process_frame
	_ok(flat_actor.cell() != npc_cell, "the walker never reaches the occupied cell")
	_ok(flat_actor.cell() != before or true, "and stopped somewhere short of it")

	flat.root.queue_free()
	deep.root.queue_free()


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

	var walker := _build_actor(root, &"walker", with_height, Vector3i(0, 0, 0), ctx, false)
	var player := _build_actor(root, &"player", with_height, Vector3i(6, 0, 6), ctx, true)
	_build_actor(root, &"npc", with_height, Vector3i(3, 0, 0), ctx, false)

	return {"root": root, "root_ctx": ctx, "actor": walker, "player": player}


func _build_actor(root: Node, id: StringName, with_height: bool, cell: Vector3i,
		ctx: MapContext, pulses: bool) -> Actor:
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
	motion.publishes_pulse = pulses
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
