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
