extends Node

## Headless assertions over [code]InputReplay[/code] (code/world/input_replay.gd):
## record a real [PlayerController] driven by real [code]Input.*[/code] presses over
## real frames, save it, then replay it back and confirm the actor lands in the exact
## same place - even though the replay itself runs as a tight synchronous loop with no
## relation to the recording's own real frame timing, which is the whole point (see
## that file's own class doc on why [GridMotion] is driven by hand with the recorded
## delta rather than whatever delta the replay happens to run at).
##
##     godot --headless --path . res://tests/input_replay_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("InputReplay -- capture, save/load, and deterministic playback")
	print("")

	await _test_record_and_replay_reproduce_the_same_outcome()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_record_and_replay_reproduce_the_same_outcome() -> void:
	_section("record a held direction, replay it back, land on the same cell/facing")
	GameState.clear()

	var recorded := await _build_rig()
	var recorded_actor: Actor = recorded["actor"]

	InputReplay.start_recording()

	Input.action_press("move_right")
	for i in 20:
		await get_tree().process_frame
	Input.action_release("move_right")
	for i in 3:
		await get_tree().process_frame

	InputReplay.stop_recording()
	var slot := InputReplay.save()
	_ok(slot > 0, "the recording saved to a rotating slot")

	var recorded_cell := recorded_actor.cell()
	var recorded_facing := recorded_actor.facing()
	_ok(recorded_cell != Vector3i.ZERO, "holding right actually moved the recorded actor")

	recorded["root"].queue_free()
	await get_tree().process_frame

	# A second, independent rig, starting from the same place - replay must reproduce
	# the recorded outcome on its own actor, not merely leave the first one where it
	# already was.
	var replayed := await _build_rig()
	var replayed_player: PlayerController = replayed["player"]
	var replayed_actor: Actor = replayed["actor"]

	InputReplay.bind(replayed_player)
	_ok(InputReplay.start_replay(slot), "the log loaded back for replay")

	# Synchronous - no awaited frames at all. Real time here has nothing to do with
	# how many recorded frames get processed or how fast; only the recorded delta
	# sequence drives the result.
	var guard := 0
	while not InputReplay.is_finished() and guard < 10000:
		InputReplay.step_replay()
		guard += 1

	_eq(replayed_actor.cell(), recorded_cell,
		"the replayed actor lands on the exact cell the recording did")
	_eq(replayed_actor.facing(), recorded_facing,
		"and ends up facing the same way")
	_ok(not InputReplay.is_replaying(), "InputReplay unbound itself once the log ran out")

	replayed["root"].queue_free()
	await get_tree().process_frame
	GameState.clear()
	_clean_up_log_files()


## Leaves no trace under user:// - SaveGame's own tests (save_game_test.gd) follow the
## same convention for SaveGame.SLOT_PATH.
func _clean_up_log_files() -> void:
	for path in [
		InputReplay.SLOT_PATH_FORMAT % 1, InputReplay.SLOT_PATH_FORMAT % 2,
		InputReplay.SLOT_PATH_FORMAT % 3, InputReplay.META_PATH,
	]:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


# -- Test rig ----------------------------------------------------------------------

## A real, viewful-enough rig: [MapContext], an [Actor] with [GridMotion], and a real
## [PlayerController] child - the one thing tests/event_runner_test.gd's own [method
## _build_actor] does not need, since nothing there reads live [code]Input.*[/code].
func _build_rig() -> Dictionary:
	var root := Node3D.new()
	add_child(root)

	var ctx := MapContext.new()
	ctx.map_id = &"input_replay_test_map"
	ctx.cell_size = Vector3.ONE
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)

	var body := Node3D.new()
	body.name = "player"
	root.add_child(body)

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = &"player"
	actor.facing_count = 4
	body.add_child(actor)

	var adapter := Space3D.new()
	adapter.name = "Space"
	actor.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = 4
	actor.add_child(motion)

	var player := PlayerController.new()
	player.name = "PlayerController"
	actor.add_child(player)

	# Real frames so every _ready() in the chain above has actually run (Actor's own
	# actor_id derivation, PlayerController resolving its parent) before anything reads
	# Input against it.
	for i in 2:
		await get_tree().process_frame

	return {"root": root, "actor": actor, "player": player}


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
