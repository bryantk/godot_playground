extends Node

## The three demo scenes, loaded and driven as the game loads them.
##
##     godot --headless --path . res://tests/demo_scenes_test.tscn
##
## There is no generator behind these scenes any more - [code]jrpg_demo.tscn[/code] and
## the two iso ones are hand-authored files, edited in the editor, and this is what keeps
## them honest. It instantiates each, resolves the nodes the demo scripts expect to find
## by path, holds a direction, and checks that the actor walks, animates, stops, and
## stays pinned under the camera rig. A node renamed or moved in the editor breaks an
## [code]@onready[/code] path, and it shows up here rather than on the next play.

var _fail := 0

func _ok(c: bool, w: String) -> void:
	print(("  ok    " if c else "  FAIL  ") + w)
	if not c:
		_fail += 1


## One prefab, three roles. The player, a routed NPC and an NPC with no brain at all
## are the same scene file on disk; what separates them is the child hanging off the
## actor. This is the assertion that catches the tempting regression - giving NPCs their
## own scene again the next time one needs something the player does not have.
func _check_brains(ctx: MapContext, player: Actor) -> void:
	var routed: Actor = null
	var idle: Actor = null
	for who: Actor in ctx.actors():
		if who == player:
			continue
		if who.brain() is RouteBrain:
			routed = who
		elif who.brain() == null:
			idle = who

	_ok(player.brain() is PlayerBrain, "the player's brain is a PlayerBrain")
	_ok(routed != null, "an NPC is driven by a RouteBrain")
	_ok(idle != null, "an NPC has no brain and is only scenery")
	if routed == null or idle == null:
		return

	var prefab := (player.get_parent() as Node).scene_file_path
	_ok(prefab != "" and prefab == (routed.get_parent() as Node).scene_file_path
		and prefab == (idle.get_parent() as Node).scene_file_path,
		"all three are '%s'" % prefab.get_file())

	# The route walks itself with nobody touching the keyboard; the brainless one does
	# not drift.
	#
	# Watched until it moves rather than sampled once after a fixed wait. A route is a
	# loop of walks and waits, and the iso demo's longest wait is 1.5s - so a single
	# sample taken 1.4s later can land wholly inside a wait and call a working patrol
	# broken, which is exactly what it did. The window covers a whole cycle instead.
	var was_routed := routed.cell()
	var was_idle := idle.cell()
	var moved := false
	var waited := 0.0
	while waited < 5.0 and not moved:
		await get_tree().create_timer(0.1).timeout
		waited += 0.1
		moved = routed.cell() != was_routed

	_ok(moved, "the routed NPC walked its list (%s -> %s after %0.1fs)" % [
		was_routed, routed.cell(), waited])
	_ok(idle.cell() == was_idle, "the brainless NPC stayed put")


## Shift plus a direction turns to face it and takes no step. Held, not tapped: there is
## no grace timer left to race, so this is a plain press-and-check.
func _check_turn(player: Actor, dir_action: String) -> void:
	var cell := player.cell()
	var before := player.facing()
	Input.action_press("turn_in_place")
	Input.action_press(dir_action)
	for i in 10:
		await get_tree().process_frame

	_ok(player.facing() != before, "Shift+direction turned (%s -> %s)" % [
		before, player.facing()])
	_ok(player.cell() == cell, "turning in place changed no cell")

	Input.action_release(dir_action)
	Input.action_release("turn_in_place")
	await get_tree().process_frame


## Every demo carries one example slow patch. What is checked here is the two ways an
## authored zone fails [i]silently[/i] - both invisible in the editor, both leaving a shape
## that simply never does anything:
##
## - a component parented so that it never found its zone, and
## - an actor whose motion cannot reach the zone: grid actors resolve zones by a point
##   query on [constant AreaZone.LAYER], free ones by the area's overlap signals, so a
##   zone that is not monitorable is invisible to game 2 and one off the query layer is
##   invisible to game 1.
##
## Whether the patch is in a sensible place, and whether the slowdown reads, is a thing to
## be walked rather than asserted.
func _check_zones(demo: Node, player: Actor) -> void:
	var zones: Array[AreaZone] = []
	_collect_zones(demo, zones)
	_ok(not zones.is_empty(), "the demo has %d example zone(s)" % zones.size())

	for zone in zones:
		var area := zone.area()
		_ok(area != null, "'%s' hangs off an Area2D/Area3D" % zone.name)
		if area == null:
			continue

		_ok(int(area.get("collision_layer")) & AreaZone.LAYER != 0,
			"'%s' is on the zone query layer" % zone.name)
		_ok(bool(area.get("monitorable")), "'%s' is monitorable" % zone.name)

		var components := 0
		for node in area.get_children() + zone.get_children():
			if node is AreaComponent:
				components += 1
				_ok((node as AreaComponent).zone() == zone,
					"'%s' found its zone" % node.name)
		_ok(components > 0, "'%s' carries %d component(s)" % [zone.name, components])

	# The modifier must be able to answer for this demo's actor at all - a component that
	# resolved nothing still returns 1.0 and would look identical to a zone with no
	# modifier in it.
	_ok(player.motion() != null and player.motion().speed_scale(Vector3(1, 0, 0)) > 0.0,
		"the player's speed scale is answerable")


func _collect_zones(node: Node, into: Array[AreaZone]) -> void:
	if node is AreaZone:
		into.append(node as AreaZone)
	for child in node.get_children():
		_collect_zones(child, into)


## Fastest single physics frame while [param walk] is held, in world units per second,
## walking from [param from] every time.
##
## [b]The peak, not an average or a fixed-window distance.[/b] [member
## FreeMotion.acceleration] ramps the opening frames, and the demo map has walls, so a
## window long enough for the speed to be stable is long enough to stop against
## something. The fastest frame is the one that happened in open ground at full speed,
## whenever that was.
##
## [b]And placed back at [param from] first[/b], which matters more than it looks: the
## iso demo has a 0.5x [SpeedModifier] strip directly along the player's path, so two
## samples taken from wherever the previous one stopped are partly a measurement of how
## far into the mud each one got. Same start, same zones, same walls - the run modifier
## is then the only thing that differs between the two numbers.
func _top_speed(player: Actor, walk: String, modifier: String, from: Vector3) -> float:
	var body := player.get_parent() as Node3D
	if body != null:
		body.global_position = from
	for i in 4:
		await get_tree().physics_frame

	Input.action_press(walk)
	if modifier != "":
		Input.action_press(modifier)

	var best := 0.0
	var last := player.world_position()
	for i in 40:
		await get_tree().physics_frame
		var now := player.world_position()
		best = maxf(best, Space.flatten(now - last).length() / get_physics_process_delta_time())
		last = now

	Input.action_release(walk)
	if modifier != "":
		Input.action_release(modifier)
	while player.is_travelling():
		await get_tree().process_frame
	return best


func _check(path: String, label: String, walk: String, grid: bool) -> void:
	print("  -- %s" % label)
	var demo := (load(path) as PackedScene).instantiate()
	add_child(demo)
	for i in 20:
		await get_tree().process_frame

	var player: Actor = demo.get("_player")
	_ok(player != null, "player actor resolved from the scene")
	var view := player.view()
	var sheet = view.visual()
	_ok(sheet != null, "view bound its sprite via visual_path")
	_ok(player.adapter() != null, "space adapter bound its body")
	_ok(player.motion() != null, "motion controller present")
	var ctx := player.context()
	_ok(ctx != null and ctx.has_actor(&"player"), "registered with the map context")

	_check_zones(demo, player)

	if grid:
		_ok(player.effective_motion() == Actor.MotionMode.GRID,
			"actor is INHERIT and the map resolves it to GRID")
		_ok(ctx.occupancy.size() >= 1, "occupancy holds %d cells" % ctx.occupancy.size())
		var terrain := ctx.get_node_or_null(ctx.collision_node)
		if terrain is GridMap:
			_ok(not Passability.can_enter(ctx, Vector3i(0, 0, 7), player)
				or not Passability.can_enter(ctx, Vector3i(0, 0, 1), player),
				"a border wall refuses entry (terrain data wired)")
		else:
			# 2D collision is hand-painted. The count is reported rather than asserted:
			# an unpainted map is open ground by design, so this cannot demand cells
			# before anyone has painted them, but it does demand the layer be wired.
			var layer := terrain as TileMapLayer
			var painted: int = layer.get_used_cells().size() if layer != null else -1
			_ok(painted >= 0, "a pathing layer is the collision node (%d cells painted)"
				% painted)

			# Whether any cell is painted is the author's business, but paint that
			# refuses nothing is paint that is not wired up - a mask read back as OPEN
			# everywhere would pass every other check in here silently.
			var restricted := 0
			for cell: Vector2i in layer.get_used_cells():
				if Passability.directions(ctx, Space.as_v3i(cell)) != Passability.OPEN:
					restricted += 1
			_ok(painted == 0 or restricted > 0,
				"%d painted cells refuse at least one side" % restricted)
		await _check_brains(ctx, player)
		await _check_turn(player, walk)

	# Walking: does it move, animate, and stop cleanly?
	var before := player.cell()
	Input.action_press(walk)
	var waited := 0.0
	while not player.is_travelling() and waited < 1.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_ok(player.is_travelling(), "walks when a direction is held")
	for i in 8:
		await get_tree().process_frame
	_ok(sheet.running, "walk cycle runs while moving")
	await get_tree().create_timer(0.7).timeout
	_ok(player.cell() != before, "covered ground (%s -> %s)" % [before, player.cell()])
	Input.action_release(walk)
	while player.is_travelling():
		await get_tree().process_frame
	await get_tree().create_timer(0.4).timeout
	_ok(not sheet.running, "walk cycle stops when still")

	# Run, free motion only - a grid actor's step is one cell whether or not the key is
	# held, and game 1 binds that key to turn_in_place anyway.
	#
	# This measures ground covered per frame rather than reading `run_speed_scale` back,
	# because the bug it exists to catch was the field being read and then thrown away:
	# the brain multiplied the direction vector by it and FreeMotion.set_intent quantised
	# that vector on the next line, normalising the magnitude off. Every unit test of the
	# field's value would have passed while the player walked.
	if not grid:
		var from := player.world_position()
		var walk_speed := await _top_speed(player, walk, "", from)
		var run_speed := await _top_speed(player, walk, "run", from)
		# The ratio is reported because it is the readable number: both samples are taken
		# through the same mud and the same acceleration ramp, so the factor between them
		# is the brain's run_speed_scale and nothing else. The absolute figures are well
		# under FreeMotion.speed for that reason, and that is not a fault.
		var ratio := run_speed / maxf(walk_speed, 0.0001)
		_ok(run_speed > walk_speed * 1.25,
			"holding run moves faster (%.1f -> %.1f u/s, %.2fx)"
				% [walk_speed, run_speed, ratio])

	# Camera: the followed actor must be pinned.
	var rig = demo.get("_rig")
	if rig != null:
		var cam: Camera3D = rig.get_parent() as Camera3D
		var container: SubViewportContainer = demo.get_node("Upscale")
		var t := float(rig.texels_per_unit)
		var shrink := float(container.stretch_shrink)
		var probe := Node.new()
		probe.set_script(load("res://tests/screen_probe.gd"))
		probe.process_priority = 1000
		probe.cam = cam
		probe.sprite = sheet
		probe.container = container
		probe.t = t
		probe.shrink = shrink
		add_child(probe)
		Input.action_press(walk)
		for i in 20:
			await get_tree().process_frame
		probe.armed = true
		for i in 50:
			await get_tree().process_frame
		probe.armed = false
		Input.action_release(walk)
		var s: Array[float] = probe.samples
		var lo: float = s[0]
		var hi: float = s[0]
		for v in s:
			lo = minf(lo, v); hi = maxf(hi, v)
		_ok(hi - lo == 0.0, "followed actor pinned on screen (spread %.0f px)" % [hi - lo])
		probe.queue_free()
		while player.is_travelling():
			await get_tree().process_frame

	demo.queue_free()
	await get_tree().process_frame


func _ready() -> void:
	await _check("res://games/jrpg/jrpg_demo.tscn", "jrpg", "move_up", true)
	await _check("res://games/isoish/isoish_grid_demo.tscn", "iso grid", "move_left", true)
	await _check("res://games/isoish/isoish_demo.tscn", "iso free", "move_left", false)

	# The launcher must still find its three demos.
	var menu := (load("res://demos/demo_launcher.tscn") as PackedScene).instantiate()
	add_child(menu)
	await get_tree().process_frame
	var buttons: Array = menu.call("_buttons")
	print("  -- launcher")
	_ok(buttons.size() == 3, "launcher lists %d demos" % buttons.size())
	var all_scenes := true
	for b in buttons:
		if b.get_meta("scene") == null:
			all_scenes = false
	_ok(all_scenes, "every button carries a scene")

	print("")
	print("%s" % ("all good" if _fail == 0 else "%d FAILED" % _fail))
	get_tree().quit(_fail)
