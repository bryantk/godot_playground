extends Node

## Headless assertions over map transfer: [code]change_map[/code]/[code]change_map_marker[/code]
## (events/commands/map_execs.gd) and the shared fade overlay (core/fade_overlay.gd).
##
##     godot --headless --path . res://tests/change_map_test.tscn
##
## [code]change_map[/code]'s own [method SceneTree.change_scene_to_file] is real, the same
## reason save_game_test.gd needs an actual scene reload rather than the viewless rigs
## event_runner_test.gd builds everywhere else - the executor's own [code]WAIT_MAP[/code]
## poll, and a fade, only mean anything against a real running [SceneTree].

const JRPG_SCENE := "res://games/jrpg/jrpg_demo.tscn"
const ISO_GRID_SCENE := "res://games/isoish/isoish_grid_demo.tscn"

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("map transfer -- change_map, change_map_marker, and the shared fade overlay")
	print("")

	await _test_fade_overlay()
	await _test_change_map_by_cell()
	await _test_change_map_marker()
	_test_marker_lookup()
	await _test_change_map_pauses_background_processing_until_ready()
	await _test_change_map_fades_collapse_under_fast_forward()
	await _test_change_map_from_a_live_game_event_does_not_strand_cutscene()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- FadeOverlay ----------------------------------------------------------------------

func _test_fade_overlay() -> void:
	_section("FadeOverlay -- GameUI's shared fade rig")

	GameUI.fade_to(0.0, 0.0)
	_ok(not GameUI.is_fading(), "seconds <= 0 snaps instantly, no tween left running")

	GameUI.fade_to(1.0, 0.2)
	_ok(GameUI.is_fading(), "a positive duration starts a tween")

	var waited := 0.0
	while GameUI.is_fading() and waited < 1.0:
		await get_tree().process_frame
		waited += get_process_delta_time()
	_ok(not GameUI.is_fading(), "and it finishes on its own")


# -- change_map, an explicit cell/facing -----------------------------------------------

func _test_change_map_by_cell() -> void:
	_section("change_map -- a real scene swap, placing the player at a cell/facing")
	GameState.clear()
	EventScheduler.reset()
	ModeStack.reset()

	await _load_current_scene(JRPG_SCENE)
	var ctx_before: MapContext = get_tree().get_first_node_in_group(&"map_context")
	_ok(ctx_before != null, "the jrpg demo registered its own MapContext first")

	# A cutscene left the camera on an NPC before this transfer fired - the case
	# EventBus.map_arrived (event_bus.gd)/CameraRig._on_map_arrived exists for: that NPC
	# has no equivalent on the destination map, and nothing should still be looking for it.
	var rig_before := ctx_before.camera_rig() if ctx_before != null else null
	if rig_before != null:
		rig_before.follow(&"npc_8_12")
		_eq(rig_before.target(), &"npc_8_12", "camera_follow put it on the NPC first")

	var event_ctx := EventContext.for_event(ctx_before, &"jrpg_demo", &"test")
	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "cm"}]},
		{"id": "cm", "command": "change_map", "args": {
			"map": ISO_GRID_SCENE, "cell": [3, 0, 2], "facing": [1, 0, 0]},
			"outputs": [{"flow": "next", "target": ""}]},
	]

	var runner := EventRunner.new(event_ctx)
	runner.begin(nodes)
	await _pump(runner)

	_ok(runner.finished, "the runner finishes")
	_eq(runner.error, "", "with no error")
	_ok(get_tree().current_scene != null
		and get_tree().current_scene.scene_file_path == ISO_GRID_SCENE,
		"the scene actually swapped to the destination")

	var new_ctx: MapContext = get_tree().get_first_node_in_group(&"map_context")
	_ok(new_ctx != null and new_ctx != ctx_before, "a fresh MapContext registered")
	_ok(event_ctx.map == new_ctx, "EventContext.map was rebound to it (question 51)")

	var player := new_ctx.actor(&"player") if new_ctx != null else null
	_ok(player != null, "the destination scene's own player actor resolved")
	if player != null:
		_eq(player.cell(), Vector3i(3, 0, 2), "placed at the authored cell")
		_eq(player.facing(), Vector3i(1, 0, 0), "and facing the authored direction")

	# EventBus.map_arrived (event_bus.gd) - CameraRig._on_map_arrived's own hook, fired
	# right where the assertions above already confirm the map actually rebound.
	var rig := new_ctx.camera_rig() if new_ctx != null else null
	if rig != null and player != null:
		_eq(rig.target(), player.actor_id,
			"the destination's own camera rig is already following the player, not " +
			"whatever the source map's camera happened to be pointed at")


# -- change_map_marker, a named point in the destination scene -------------------------

func _test_change_map_marker() -> void:
	_section("change_map_marker -- placing the player at a named MapMarker3D instead")
	GameState.clear()
	EventScheduler.reset()
	ModeStack.reset()

	await _load_current_scene(JRPG_SCENE)
	var event_ctx := EventContext.for_event(
		get_tree().get_first_node_in_group(&"map_context"), &"jrpg_demo", &"test")

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "cm"}]},
		{"id": "cm", "command": "change_map_marker", "args": {
			"map": ISO_GRID_SCENE, "marker": "arrival"},
			"outputs": [{"flow": "next", "target": ""}]},
	]

	var runner := EventRunner.new(event_ctx)
	runner.begin(nodes)
	await _pump(runner)

	_ok(runner.finished, "the runner finishes")
	_eq(runner.error, "", "with no error")

	var new_ctx: MapContext = get_tree().get_first_node_in_group(&"map_context")
	var player := new_ctx.actor(&"player") if new_ctx != null else null
	_ok(player != null, "the destination scene's own player actor resolved")
	if player != null:
		# games/isoish/isoish_grid_demo.tscn's own "Arrival" MapMarker3D, authored at
		# the same spot its own Player placement spawns - see that scene's own note.
		_eq(player.cell(), Vector3i(8, 0, 7), "placed at the marker's own cell")


# -- ChangeMapMarker's own recursive lookup, no scene reload needed --------------------

func _test_marker_lookup() -> void:
	_section("ChangeMapMarker._find_marker -- recursive, by name, either space")
	const MapExecs := preload("res://code/events/commands/map_execs.gd")

	var root := Node3D.new()
	var nested := Node3D.new()
	root.add_child(nested)
	var marker := MapMarker3D.new()
	marker.marker_name = &"deep"
	marker.facing = "e"
	nested.add_child(marker)

	var found := MapExecs.ChangeMapMarker._find_marker(root, &"deep")
	_ok(found == marker, "finds a marker nested two levels down")
	_ok(MapExecs.ChangeMapMarker._find_marker(root, &"missing") == null,
		"and null for a name nothing carries")
	_eq((found as MapMarker3D).resolved_facing(), Vector3i(1, 0, 0),
		"resolved_facing() reads the compass token")

	root.free()


# -- ModeStack.Mode.TRANSITION -- the exit/load/ready lifecycle -----------------------

## Real EventScheduler.tick() calls throughout, not [method _pump]'s direct
## [method EventRunner.tick] - the whole point is to prove [code]change_map[/code]
## doesn't deadlock the very scheduler it needs to keep ticking it (see
## [method EventScheduler.tick]'s own doc on why the exclusive runner is exempt from
## [method ModeStack.pauses_physics]), and that background runners genuinely pause
## for the transition rather than merely by coincidence.
func _test_change_map_pauses_background_processing_until_ready() -> void:
	_section("change_map -- ModeStack.Mode.TRANSITION pauses background processing, without deadlocking itself")
	GameState.clear()
	EventScheduler.reset()
	ModeStack.reset()

	await _load_current_scene(JRPG_SCENE)
	var ctx_before: MapContext = get_tree().get_first_node_in_group(&"map_context")

	# A background probe whose own wait (0.05s) is much shorter than the transition
	# below (0.2s fade out + swap + 0.2s fade in) - if EventScheduler ever ticked it
	# during the transition, it would finish and set its flag well before the
	# transition itself does.
	var bg_ctx := EventContext.for_event(ctx_before, &"jrpg_demo", &"bg_probe")
	var bg_nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "w"}]},
		{"id": "w", "command": "wait", "args": {"seconds": 0.05},
			"outputs": [{"flow": "next", "target": "sf"}]},
		{"id": "sf", "command": "set_flag", "args": {"flag": "bg_advanced"}, "outputs": []},
	]
	var bg_runner := EventRunner.new(bg_ctx)
	EventScheduler.run_background(bg_runner, bg_nodes)
	_ok(not bg_runner.finished, "background probe started, waiting on its own short timer")

	var event_ctx := EventContext.for_event(ctx_before, &"jrpg_demo", &"test")
	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "cm"}]},
		{"id": "cm", "command": "change_map", "args": {
			"map": ISO_GRID_SCENE, "cell": [3, 0, 2], "facing": [1, 0, 0],
			"fade_out": 0.2, "fade_in": 0.2},
			"outputs": [{"flow": "next", "target": ""}]},
	]
	var runner := EventRunner.new(event_ctx)
	_ok(EventScheduler.run_exclusive(runner, nodes), "acquired the exclusive slot")
	_ok(ModeStack.current() == ModeStack.Mode.TRANSITION,
		"ModeStack.Mode.TRANSITION pushed the instant change_map's own start() ran")

	# Real frames through the actual scheduler for the fade-out's own duration - well
	# before the scene has even swapped.
	var elapsed := 0.0
	while elapsed < 0.15:
		await get_tree().process_frame
		EventScheduler.tick(get_process_delta_time())
		elapsed += get_process_delta_time()
	_ok(not runner.finished, "the transition itself is still going - not deadlocked")
	_ok(not GameState.flag(&"bg_advanced"),
		"the background probe made no progress mid-fade-out, though its own timer is shorter than this wait")

	# The rest of the way through the scene swap and the fade-in.
	var guard := 0
	while EventScheduler.is_exclusive_held() and guard < 600:
		await get_tree().process_frame
		EventScheduler.tick(get_process_delta_time())
		guard += 1
	_ok(not EventScheduler.is_exclusive_held(), "the transition finished")
	_ok(ModeStack.current() != ModeStack.Mode.TRANSITION,
		"ModeStack.Mode.TRANSITION was popped again, not left stuck")

	# A few more frames for the background probe's own short wait to resolve now that
	# ticking has resumed.
	for i in 10:
		await get_tree().process_frame
		EventScheduler.tick(get_process_delta_time())
	_ok(GameState.flag(&"bg_advanced"),
		"and the background probe finally advanced once processing resumed")

	EventScheduler.reset()
	ModeStack.reset()
	GameState.clear()


## A *real* [GameEvent], still parented under the map it is about to unload, driving
## the transfer - not [method EventRunner.begin]/[method EventRunner.tick] called
## directly the way every other test above does. That distinction is the whole point:
## with no fade and nothing else queued, [method SceneTree.change_scene_to_file] (called
## from inside [code]change_map_marker[/code]'s own [code]start()[/code]) tears down
## this map - and the very [GameEvent] running this graph - before that [code]start()[/code]
## call even returns. [method GameEvent._exit_tree] firing reentrantly right there used
## to see [member EventRunner._Frame.exec] still null (not assigned until one statement
## later) and stop this runner out from under its own still-running command, leaving
## [constant ModeStack.Mode.CUTSCENE] (pushed by [method EventScheduler.run_exclusive])
## stranded forever - the player locked out of moving on every map's own transfer point,
## permanently, since nothing else was ever going to pop it.
func _test_change_map_from_a_live_game_event_does_not_strand_cutscene() -> void:
	_section("change_map_marker -- fired from a live GameEvent, ModeStack returns all the way to FIELD")
	GameState.clear()
	EventScheduler.reset()
	ModeStack.reset()

	await _load_current_scene(ISO_GRID_SCENE)
	_ok(ModeStack.is_field(), "starts at FIELD")

	var transfer_event := get_tree().current_scene.get_node(
		"Upscale/World/Map/Actors/MapTransfer/GameEvent")
	_ok(transfer_event != null, "the scene's own map-transfer GameEvent resolved")

	# The same private entry point GameEvent._on_player_interacted calls for the
	# "action" trigger - simulating the button press itself would need a live Input
	# map this test has no business depending on.
	transfer_event.call("_maybe_fire", &"action")

	var guard := 0
	while (EventScheduler.is_exclusive_held() or not ModeStack.is_field()) and guard < 600:
		await get_tree().process_frame
		EventScheduler.tick(get_process_delta_time())
		guard += 1

	_ok(not EventScheduler.is_exclusive_held(), "the transfer's own runner finished")
	_ok(ModeStack.is_field(),
		"and ModeStack.Mode.CUTSCENE came back off too - not stranded above FIELD forever")

	var new_ctx: MapContext = get_tree().get_first_node_in_group(&"map_context")
	_ok(new_ctx != null and new_ctx.map_id == &"isoish_demo", "landed on the destination map")

	EventScheduler.reset()
	ModeStack.reset()
	GameState.clear()


## The same fade_out/fade_in 0.2s each as the test above, but with [method
## DebugFlags.is_fast_forward] held - [method ChangeMapBase.start]/[method
## ChangeMapBase._begin_fade_in] read both as 0 while it is, so the whole transition
## (fade out, scene swap, fade in) finishes within a handful of frames instead of
## needing the 0.4s of real fade time alone the test above spends mid-transition.
func _test_change_map_fades_collapse_under_fast_forward() -> void:
	_section("change_map -- fade_out/fade_in collapse to one frame under DebugFlags.is_fast_forward")
	GameState.clear()
	EventScheduler.reset()
	ModeStack.reset()
	var was_forced := DebugFlags.force_fast_forward
	DebugFlags.force_fast_forward = true

	await _load_current_scene(JRPG_SCENE)
	var ctx_before: MapContext = get_tree().get_first_node_in_group(&"map_context")

	var event_ctx := EventContext.for_event(ctx_before, &"jrpg_demo", &"test")
	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "cm"}]},
		{"id": "cm", "command": "change_map", "args": {
			"map": ISO_GRID_SCENE, "cell": [3, 0, 2], "facing": [1, 0, 0],
			"fade_out": 0.2, "fade_in": 0.2},
			"outputs": [{"flow": "next", "target": ""}]},
	]
	var runner := EventRunner.new(event_ctx)
	_ok(EventScheduler.run_exclusive(runner, nodes), "acquired the exclusive slot")

	const FRAME_BUDGET := 30
	var guard := 0
	while EventScheduler.is_exclusive_held() and guard < FRAME_BUDGET:
		await get_tree().process_frame
		EventScheduler.tick(get_process_delta_time())
		guard += 1

	_ok(not EventScheduler.is_exclusive_held(),
		"the transition finished within %d frames (got %d), not the full 0.4s of fade time" %
			[FRAME_BUDGET, guard])
	_ok(not GameUI.is_fading(), "and the fade overlay was not left mid-tween")

	DebugFlags.force_fast_forward = was_forced
	EventScheduler.reset()
	ModeStack.reset()
	GameState.clear()


# -- Helpers ----------------------------------------------------------------------------

## Replaces [member SceneTree.current_scene] with a fresh instance of [param path],
## freeing whatever was there first - a direct load rather than [code]change_map[/code]'s
## own [method SceneTree.change_scene_to_file], for the same reason save_game_test.gd's
## own rig uses one: this is the *starting* scene each sub-test drives a transfer out of,
## not the thing under test.
func _load_current_scene(path: String) -> void:
	# self excluded: the very first call finds this test's own node still set as
	# current_scene (the entry scene --path passed on the command line), and freeing
	# the node running this coroutine out from under it hangs the whole run.
	var old := get_tree().current_scene
	if old != null and old != self:
		get_tree().current_scene = null
		old.queue_free()
		await get_tree().process_frame

	var scene := (load(path) as PackedScene).instantiate()
	get_tree().root.add_child.call_deferred(scene)
	await get_tree().process_frame
	get_tree().current_scene = scene
	for i in 5:
		await get_tree().process_frame


## Real frames, not a tight synchronous loop - [method ChangeMapBase._swap_scene]'s own
## [method SceneTree.change_scene_to_file] defers the actual swap, so nothing downstream
## of it (the new MapContext registering, a fade's own Tween) happens without the engine
## given real frames to run them on.
func _pump(runner: EventRunner, max_frames: int = 600) -> void:
	var n := 0
	while not runner.finished and n < max_frames:
		runner.tick(get_process_delta_time())
		await get_tree().process_frame
		n += 1


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, "%s (got %s, want %s)" % [what, got, want] if got != want else what)
