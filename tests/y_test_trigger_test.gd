extends Node

## Headless assertion over [code]games/jrpg/jrpg_demo.tscn[/code]'s [code]y_test[/code]
## placement: a [GameEvent]-only trigger with no art of its own, [code]through: true[/code]
## on its page, and a [code]player_touch[/code] trigger - so it has no visual, and the
## player can walk onto its cell (not bounce off it like an ordinary NPC) and fire it.
##
##     godot --headless --path . res://tests/y_test_trigger_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("events -- jrpg_demo's y_test: invisible, through, and player_touch")
	print("")
	await _test_y_test()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_y_test() -> void:
	_section("y_test -- no visual, phases, and fires player_touch when walked onto")

	var scene: Node = load("res://games/jrpg/jrpg_demo.tscn").instantiate()
	add_child(scene)
	# _push_init's own push already ran (Node._enter_tree, on add_child above); this
	# is only for Actor._claim_spawn_cell's deferred Occupancy placement to land.
	await get_tree().physics_frame
	await get_tree().physics_frame

	var ctx := MapContext.of(scene)
	var player: Actor = ctx.actor(&"player")
	var y_test: Actor = ctx.actor(&"y_test")
	_ok(player != null, "the player resolved")
	_ok(y_test != null, "y_test resolved under the id its GameEvent pushed")
	if player == null or y_test == null:
		scene.free()
		return

	_ok(not (y_test.view().visual() as CanvasItem).visible,
		"y_test's sprite is hidden - visible=false, no sheet in its page's art")
	_ok(ctx.occupancy.phases(&"y_test"),
		"and Occupancy agrees it phases - through: true on its page")

	# Teleport the player one cell short of y_test and take the one step that lands
	# exactly on it - an ordinary blocking NPC would refuse this step outright. Tried
	# from all four sides rather than one fixed direction: which side of y_test's own
	# cell the pathing layer happens to have painted open is level-authoring, not part
	# of what this test is proving.
	var target := y_test.cell()
	var landed := false
	var dirs: Array[Vector3i] = [
		Vector3i(1, 0, 0), Vector3i(-1, 0, 0), Vector3i(0, 0, 1), Vector3i(0, 0, -1)]
	for dir in dirs:
		var approach: Vector3i = target - dir
		(player.adapter() as SpaceAdapter).set_world_position(ctx.cell_centre(approach))
		player.motion().step_keyed(dir)
		await get_tree().create_timer(0.2).timeout
		if player.cell() == target:
			landed = true
			break

	_ok(landed, "the player reached y_test's own cell from some side, unrefused")
	_eq(player.view().y_level, 1,
		"player_touch fired y_test's page, whose set_y_level command hit the player")

	scene.free()


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
