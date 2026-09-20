extends Node

## Headless assertions over [SaveGame] - stage E's own action, built on segment 5's
## save/restore hooks.
##
##     godot --headless --path . res://tests/save_game_test.tscn
##
## The one test here that needs a *real scene reload* rather than the same live actor
## [tests/event_save_test.gd] reuses throughout - [method SceneTree.change_scene_to_file]
## and everything downstream of it (the new map registering [MapContext], its actors
## claiming their spawn cells) is exactly the part none of segment 5's own tests exercise.

const MAP_SCENE := "res://games/isoish/isoish_demo.tscn"

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("save/load game -- SaveGame, a real scene reload")
	print("")

	await _test_save_and_load_round_trip()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_save_and_load_round_trip() -> void:
	_section("SaveGame -- save, clear, load restores flags/actors/the running dialogue")
	GameState.clear()
	EventScheduler.reset()
	ModeStack.reset()

	# A child of root, not of this test node - SceneTree.current_scene refuses any
	# node whose parent isn't root, and SaveGame.save() reads current_scene.scene_file_path
	# as "the map to reload", so this has to be the real thing or SaveGame.load() ends
	# up reloading the test itself.
	var scene := (load(MAP_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	for i in 10:
		await get_tree().process_frame

	GameState.set_flag(&"save_test_flag")

	var player: Actor = scene.get("_player")
	var body := player.get_parent() as Node3D
	# Walk the player into the Wanderer's patrol lane so its event_touch dialogue is
	# running at save time - the thing worth proving survives a real reload, not just
	# a flag.
	body.global_position = Vector3(13.5, 0, 7.5)
	for i in 5:
		await get_tree().physics_frame

	var fired := false
	for i in 400:
		await get_tree().physics_frame
		if EventScheduler.is_exclusive_held():
			fired = true
			break
	_ok(fired, "the wanderer's dialogue is running before the save")

	var saved_player_cell := player.cell()

	_ok(SaveGame.save(), "save() succeeds")

	# Simulate the app being closed and reopened: clear the in-memory state a restart
	# would not carry over. The written file is what load() has to stand on its own.
	GameState.clear()

	_ok(await SaveGame.load(), "load() succeeds")

	_ok(get_tree().current_scene.scene_file_path == MAP_SCENE, "the same scene is loaded again")
	_ok(GameState.flag(&"save_test_flag"), "the flag survived the round trip")

	var ctx: MapContext = get_tree().get_first_node_in_group(&"map_context")
	_ok(ctx != null, "the reloaded map registered a MapContext")

	# Checked before any further physics settles - the player and the Wanderer were
	# touching cells at save time (that's what put the dialogue up), so leaving them
	# physically overlapping for several more frames lets Jolt's own contact
	# resolution shove them apart exactly as it would have in the original session
	# had nothing interrupted it. That is a physics fact of two overlapping capsules,
	# not a save/restore defect - checking immediately is what isolates the latter.
	var new_player := ctx.actor(&"player") if ctx != null else null
	var new_player_cell_text := str(new_player.cell()) if new_player != null else "no actor"
	_ok(new_player != null and new_player.cell() == saved_player_cell,
		"the player is back where it was (%s)" % new_player_cell_text)

	var new_wanderer := ctx.actor(&"wanderer") if ctx != null else null
	_ok(new_wanderer != null, "the wanderer exists on the reloaded map")

	_ok(EventScheduler.is_exclusive_held(),
		"the wanderer's dialogue is running again after the load")

	for i in 5:
		await get_tree().process_frame

	EventScheduler.reset()
	ModeStack.reset()
	GameState.clear()
	var abs_path := ProjectSettings.globalize_path(SaveGame.SLOT_PATH)
	if FileAccess.file_exists(SaveGame.SLOT_PATH):
		DirAccess.remove_absolute(abs_path)


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("    ok    %s" % what)
	else:
		_fail(what)


func _fail(what: String) -> void:
	_failed += 1
	print("    FAIL  %s" % what)
