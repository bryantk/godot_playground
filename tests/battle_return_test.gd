extends Node

## Headless regression: a real, GameEvent-triggered [code]start_battle[/code] returns
## to the field scene it left, even though the very node that started the runner
## (games/jrpg/jrpg_demo.tscn's own BattleTrigger) is torn down along with the rest of
## the map the instant [method SceneTree.change_scene_to_file] swaps to the battle
## scene.
##
## [b]Why tests/change_map_test.gd's own real-reload tests did not catch this[/b]: they
## build an [EventRunner] directly, bypassing [method GameEvent._maybe_fire] entirely -
## so [method GameEvent._exit_tree] (the thing that actually broke this) never ran
## against them at all. This one goes through the real trigger, the same as a player
## pressing the interact button in the game, precisely to close that gap.
##
##     godot --headless --path . res://tests/battle_return_test.tscn

const JRPG_SCENE := "res://games/jrpg/jrpg_demo.tscn"

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("battle -- a real trigger's start_battle returns to the field it left")
	print("")

	await _test_battle_returns_to_the_field_after_its_own_trigger_unloads()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_battle_returns_to_the_field_after_its_own_trigger_unloads() -> void:
	_section("start_battle -- survives its own triggering GameEvent's teardown")
	GameState.clear()
	Party.clear()
	EventScheduler.reset()
	ModeStack.reset()
	BattleTransfer.outcome = &""

	var scene := (load(JRPG_SCENE) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	for i in 10:
		await get_tree().process_frame

	var ctx: MapContext = get_tree().get_first_node_in_group(&"map_context")
	var trigger := scene.get_node("Actors/BattleTrigger/GameEvent") as GameEvent
	_ok(ctx != null and trigger != null, "the demo's own BattleTrigger resolved")
	if ctx == null or trigger == null:
		scene.queue_free()
		return

	# Fires the page's own "action" port directly, the same call
	# EventBus.player_interacted's own listener (GameEvent._on_player_interacted) makes
	# once it decides the player is in range - decoupled from the footprint-aware
	# adjacency/facing math (covered elsewhere, tests/y_test_trigger_test.gd) so this
	# stays focused on the one thing it exists to prove: that start_battle survives its
	# own triggering placement being torn down, not on reproducing exactly where an
	# author has since dragged BattleTrigger to.
	trigger._maybe_fire(&"action")
	var battle_seconds := 0.0
	while get_tree().current_scene.scene_file_path != "res://code/battle/battle_scene.tscn" \
			and battle_seconds < 5.0:
		await get_tree().process_frame
		battle_seconds += get_process_delta_time()
	_ok(get_tree().current_scene.scene_file_path == "res://code/battle/battle_scene.tscn",
		"the battle scene loaded")

	var battle := get_tree().current_scene as BattleScene
	_ok(battle != null, "and it is a real BattleScene")
	if battle == null:
		return

	# The debug "kill all foes" key (~ then 2), called directly - an instant win
	# without needing to drive the action menu's own buttons.
	battle._debug_kill_foes()

	var back_seconds := 0.0
	while get_tree().current_scene.scene_file_path != JRPG_SCENE and back_seconds < 5.0:
		await get_tree().process_frame
		back_seconds += get_process_delta_time()

	_ok(get_tree().current_scene.scene_file_path == JRPG_SCENE,
		"back on the field scene it left (%.1fs)" % back_seconds)

	# The trigger's own fade_in (0.4s) still has to finish before the executor resolves
	# "next" (unwired - the graph simply ends there) and EventScheduler notices the
	# runner finished and releases the exclusive slot.
	var settle_seconds := 0.0
	while EventScheduler.is_exclusive_held() and settle_seconds < 5.0:
		await get_tree().process_frame
		settle_seconds += get_process_delta_time()
	_ok(not EventScheduler.is_exclusive_held(),
		"and the runner finished cleanly (%.1fs)" % settle_seconds)

	EventScheduler.reset()
	ModeStack.reset()
	GameState.clear()
	Party.clear()


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1
