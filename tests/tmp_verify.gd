extends Node

## Everything the code-built demos were verified for, re-run against the authored scenes.

var _fail := 0

func _ok(c: bool, w: String) -> void:
	print(("  ok    " if c else "  FAIL  ") + w)
	if not c:
		_fail += 1


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

	if grid:
		_ok(player.effective_motion() == Actor.MotionMode.GRID,
			"actor is INHERIT and the map resolves it to GRID")
		_ok(ctx.occupancy.size() >= 1, "occupancy holds %d cells" % ctx.occupancy.size())
		_ok(not Passability.can_enter(ctx, Vector3i(0, 0, 7), player)
			or not Passability.can_enter(ctx, Vector3i(0, 0, 1), player),
			"a border wall refuses entry (terrain data wired)")

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

	# Camera: the followed actor must be pinned.
	var rig = demo.get("_rig")
	if rig != null:
		var cam: Camera3D = rig.get_parent() as Camera3D
		var container: SubViewportContainer = demo.get_node("Upscale")
		var t := float(rig.texels_per_unit)
		var shrink := float(container.stretch_shrink)
		var probe := Node.new()
		probe.set_script(load("res://tests/tmp_probe.gd"))
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
