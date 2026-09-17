extends Node

## Headless assertions over [EventScheduler]'s policy, [GameEvent] and the seven
## triggers (decision 44) - segment 6 of docs/stage-c-plan.md.
##
##     godot --headless --path . res://tests/event_scheduler_test.tscn

const FIXTURES := "res://tests/fixtures/"

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("events -- EventScheduler policy, GameEvent, and the seven triggers")
	print("")

	_test_exclusive_refuses_a_second()
	_test_background_suspends_while_exclusive_held()
	_test_keeps_running_opts_out()
	_test_actor_lease_refuses_a_second_runner()

	_test_trigger_on_load()
	_test_trigger_player_touch()
	_test_trigger_event_touch()
	_test_trigger_leave_cell()
	_test_trigger_action()
	_test_trigger_on_flag()
	_test_trigger_auto_parallel()

	_test_page_defers_until_graph_completes_and_art_changes()

	_test_facing_restored_when_untouched()
	_test_facing_kept_when_graph_turns_it()
	_test_lock_facing_ignores_face_commands()
	_test_through_changes_proximity_and_phasing()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- Scheduler policy ---------------------------------------------------------------

func _wait_graph(seconds: float, flag: StringName) -> Array[Dictionary]:
	return [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "w"}]},
		{"id": "w", "command": "wait", "args": {"seconds": seconds},
			"outputs": [{"flow": "next", "target": "f"}]},
		{"id": "f", "command": "set_flag", "args": {"flag": str(flag)}, "outputs": []},
	]


func _test_exclusive_refuses_a_second() -> void:
	_section("EventScheduler -- a second exclusive request is refused, not queued")
	EventScheduler.reset_for_test()

	var ctx := EventContext.for_event(null, &"m", &"e1")
	var r1 := EventRunner.new(ctx)
	_ok(EventScheduler.run_exclusive(r1, _wait_graph(5.0, &"never")),
		"the first exclusive request is accepted")
	_ok(ModeStack.current() == ModeStack.Mode.CUTSCENE,
		"and pushes CUTSCENE, locking the player's step")

	var r2 := EventRunner.new(ctx)
	_ok(not EventScheduler.run_exclusive(r2, _wait_graph(5.0, &"never")),
		"a second request is refused outright while the first still holds the slot")
	r2.latch.detach()

	EventScheduler.reset_for_test()
	_ok(ModeStack.current() == ModeStack.Mode.FIELD, "reset pops CUTSCENE back to FIELD")


func _test_background_suspends_while_exclusive_held() -> void:
	_section("EventScheduler -- background suspends while exclusive is held, resumes after")
	EventScheduler.reset_for_test()
	GameState.clear()

	var ctx := EventContext.for_event(null, &"m", &"e2")
	var exclusive := EventRunner.new(ctx)
	EventScheduler.run_exclusive(exclusive, _wait_graph(1.0, &"exclusive_done"))

	var background := EventRunner.new(ctx)
	EventScheduler.run_background(background, _wait_graph(0.5, &"background_done"))

	# Pumped well past the background's own 0.5s, but the exclusive slot has been held
	# the whole time - if suspension were not real, this would already be finished.
	for _i in 35:
		EventScheduler.tick(1.0 / 60.0)
	_ok(not background.finished,
		"still running after 35 ticks (0.58s) despite its own wait being only 0.5s")
	_ok(not GameState.flag(&"background_done"), "and its flag has not been set yet")

	# Drain the exclusive runner (60 ticks for its 1s wait), then give the background
	# runner its own 0.5s (30 ticks) now that nothing suspends it.
	for _i in 30:
		EventScheduler.tick(1.0 / 60.0)
	_ok(not EventScheduler.is_exclusive_held(), "the exclusive runner has finished and released the slot")

	for _i in 35:
		EventScheduler.tick(1.0 / 60.0)
	_ok(background.finished, "the background runner then finishes on its own")
	_ok(GameState.flag(&"background_done"), "and its flag is set")

	EventScheduler.reset_for_test()
	GameState.clear()


func _test_keeps_running_opts_out() -> void:
	_section("EventScheduler -- keeps_running opts a background runner out of suspension")
	EventScheduler.reset_for_test()
	GameState.clear()

	var ctx := EventContext.for_event(null, &"m", &"e3")
	var exclusive := EventRunner.new(ctx)
	EventScheduler.run_exclusive(exclusive, _wait_graph(5.0, &"never"))

	var background := EventRunner.new(ctx)
	background.keeps_running = true
	EventScheduler.run_background(background, _wait_graph(0.5, &"waterfall_done"))

	for _i in 35:
		EventScheduler.tick(1.0 / 60.0)
	_ok(background.finished,
		"a keeps_running background runner finishes on schedule despite the exclusive slot")
	_ok(GameState.flag(&"waterfall_done"), "and its flag is set")

	EventScheduler.reset_for_test()
	GameState.clear()


func _test_actor_lease_refuses_a_second_runner() -> void:
	_section("EventScheduler -- a leased actor refuses a second runner")
	EventScheduler.reset_for_test()

	var ctx := EventContext.for_event(null, &"m", &"e4")
	var holder := EventRunner.new(ctx)
	_ok(EventScheduler.try_lease(&"guard", holder), "the first runner leases the actor")

	var other := EventRunner.new(ctx)
	_ok(not EventScheduler.try_lease(&"guard", other),
		"a second runner is refused the same actor")
	other.latch.detach()

	EventScheduler.release_lease(&"guard", holder)
	_ok(not EventScheduler.is_leased(&"guard"), "releasing frees it")
	_ok(EventScheduler.try_lease(&"guard", other), "and a new runner can lease it")

	EventScheduler.reset_for_test()


# -- The seven triggers ---------------------------------------------------------------
#
# Each test builds its own fresh MapContext/actor(s)/GameEvent so nothing leaks between
# triggers, and checks the flag its own fixture sets - plus that a sibling trigger's
# flag, which nothing here should have fired, stays false.

func _test_trigger_on_load() -> void:
	_section("GameEvent -- on_load fires once the event is loaded")
	EventScheduler.reset_for_test()
	GameState.clear()

	var world := _build_world()
	_build_event(world, &"ev", Vector3i(2, 0, 2), FIXTURES + "sched_on_load.event.json")

	_ok(GameState.flag(&"fired_on_load"), "on_load fired")
	_ok(not GameState.flag(&"fired_action"), "and not action")
	world["root"].free()
	EventScheduler.reset_for_test()


func _test_trigger_player_touch() -> void:
	_section("GameEvent -- player_touch fires when the player steps onto the event's cell")
	EventScheduler.reset_for_test()
	GameState.clear()

	var world := _build_world()
	var player := _build_actor(world, &"player", Vector3i(0, 0, 0))
	_build_event(world, &"ev", Vector3i(1, 0, 0), FIXTURES + "sched_player_touch.event.json")

	_ok(not GameState.flag(&"fired_player_touch"), "not yet - the player hasn't moved")
	player.motion().step_keyed(Vector3i(1, 0, 0))
	_ok(GameState.flag(&"fired_player_touch"), "fires the moment the player steps onto it")
	_ok(not GameState.flag(&"fired_leave_cell"), "and not leave_cell")
	world["root"].free()
	EventScheduler.reset_for_test()


func _test_trigger_event_touch() -> void:
	_section("GameEvent -- event_touch fires when the event's own actor steps onto the player")
	EventScheduler.reset_for_test()
	GameState.clear()

	var world := _build_world()
	_build_actor(world, &"player", Vector3i(2, 0, 0))
	var ev := _build_event(world, &"ev", Vector3i(1, 0, 0), FIXTURES + "sched_event_touch.event.json")

	_ok(not GameState.flag(&"fired_event_touch"), "not yet - the event hasn't moved")
	(ev["actor"] as Actor).motion().step_keyed(Vector3i(1, 0, 0))
	_ok(GameState.flag(&"fired_event_touch"), "fires the moment the event steps onto the player")
	world["root"].free()
	EventScheduler.reset_for_test()


func _test_trigger_leave_cell() -> void:
	_section("GameEvent -- leave_cell fires when something steps off the event's cell")
	EventScheduler.reset_for_test()
	GameState.clear()

	var world := _build_world()
	var player := _build_actor(world, &"player", Vector3i(1, 0, 0))
	_build_event(world, &"ev", Vector3i(1, 0, 0), FIXTURES + "sched_leave_cell.event.json")

	_ok(not GameState.flag(&"fired_leave_cell"), "not yet - the player is standing on it")
	player.motion().step_keyed(Vector3i(1, 0, 0))
	_ok(GameState.flag(&"fired_leave_cell"), "fires the moment the player steps off it")
	world["root"].free()
	EventScheduler.reset_for_test()


func _test_trigger_action() -> void:
	_section("GameEvent -- action fires when the player interacts facing the event")
	EventScheduler.reset_for_test()
	GameState.clear()

	var world := _build_world()
	var player := _build_actor(world, &"player", Vector3i(0, 0, 0))
	player.set_facing(Vector3i(1, 0, 0))
	_build_event(world, &"ev", Vector3i(1, 0, 0), FIXTURES + "sched_action.event.json")

	EventBus.player_interacted.emit()
	_ok(GameState.flag(&"fired_action"),
		"fires when the player presses interact while facing the event's cell")
	world["root"].free()
	EventScheduler.reset_for_test()


func _test_trigger_on_flag() -> void:
	_section("GameEvent -- on_flag fires when GameState changes, not on a page switch")
	EventScheduler.reset_for_test()
	GameState.clear()

	var world := _build_world()
	_build_event(world, &"ev", Vector3i(0, 0, 0), FIXTURES + "sched_on_flag.event.json")

	GameState.set_flag(&"anything")
	_ok(GameState.flag(&"fired_on_flag"), "fires on an unrelated flag changing")
	world["root"].free()
	EventScheduler.reset_for_test()


func _test_trigger_auto_parallel() -> void:
	_section("GameEvent -- auto (parallel) starts as a background runner, not exclusive")
	EventScheduler.reset_for_test()
	GameState.clear()

	var world := _build_world()
	_build_event(world, &"ev", Vector3i(0, 0, 0), FIXTURES + "sched_auto_parallel.event.json")

	_ok(not EventScheduler.is_exclusive_held(), "auto+parallel does not take the exclusive slot")
	_ok(EventScheduler.background_runners().size() == 1, "and runs as one background runner")
	world["root"].free()
	EventScheduler.reset_for_test()


# -- Page switch deferred to graph completion, and art applied on the switch ---------

func _test_page_defers_until_graph_completes_and_art_changes() -> void:
	_section("GameEvent -- a page switch defers until the running graph completes")
	EventScheduler.reset_for_test()
	GameState.clear()

	var world := _build_world()
	var rig := _build_event(world, &"ev", Vector3i(0, 0, 0), FIXTURES + "sched_page_defer.event.json")
	var ev: GameEvent = rig["event"]
	var sheet := (rig["actor"] as Actor).view().visual() as SpriteSheet

	_ok(ev.active_page() == 0, "on_load starts the runner on page 1")
	_ok(sheet.texture == null, "page 1's art carries no sheet, so none is applied")

	GameState.set_flag(&"advance")
	_ok(ev.active_page() == 0, "still page 1 - the 2s wait node is still running")

	for _i in 130:  # 130 * 1/60 s > the 2s wait
		EventScheduler.tick(1.0 / 60.0)
		ev.poll()

	_ok(ev.active_page() == 1, "switches to page 2 once the graph finally completes")
	_ok(sheet.texture != null, "and page 2's sheet art is applied - the apply_art fix")

	world["root"].free()
	EventScheduler.reset_for_test()
	GameState.clear()


# -- Facing memory: captured before an interaction, restored after unless the graph
# itself turned or moved the actor -----------------------------------------------------

func _test_facing_restored_when_untouched() -> void:
	_section("GameEvent -- facing is restored after an interaction that never touches it")
	EventScheduler.reset_for_test()
	GameState.clear()

	var world := _build_world()
	var player := _build_actor(world, &"player", Vector3i(0, 0, 0))
	var rig := _build_event(world, &"ev", Vector3i(1, 0, 0), FIXTURES + "sched_action_no_turn.event.json")
	var ev: GameEvent = rig["event"]
	var npc: Actor = rig["actor"]

	npc.set_facing(Vector3i(0, 0, -1))  # north, before anything happens
	player.set_facing(Vector3i(1, 0, 0))
	EventBus.player_interacted.emit()
	_ok(ev.is_busy(), "the graph's own wait keeps the interaction in flight")

	# Something other than the graph nudges the actor's facing mid-interaction - a
	# stray call, not a movement command any executor issued. It should not survive.
	npc.set_facing(Vector3i(1, 0, 0))

	for _i in 20:  # past the fixture's 0.2s wait
		EventScheduler.tick(1.0 / 60.0)
		ev.poll()

	_ok(GameState.flag(&"fired_no_turn"), "the graph itself still ran to completion")
	_eq(npc.facing(), Vector3i(0, 0, -1),
		"and facing is restored to what it was before the interaction, not the stray nudge")

	world["root"].free()
	EventScheduler.reset_for_test()
	GameState.clear()


func _test_facing_kept_when_graph_turns_it() -> void:
	_section("GameEvent -- facing is kept when the graph itself turns the actor")
	EventScheduler.reset_for_test()
	GameState.clear()

	var world := _build_world()
	var player := _build_actor(world, &"player", Vector3i(0, 0, 0))
	var rig := _build_event(world, &"ev", Vector3i(1, 0, 0), FIXTURES + "sched_action_turn.event.json")
	var ev: GameEvent = rig["event"]
	var npc: Actor = rig["actor"]

	npc.set_facing(Vector3i(0, 0, -1))  # north, before anything happens
	player.set_facing(Vector3i(1, 0, 0))
	EventBus.player_interacted.emit()
	ev.poll()

	_ok(GameState.flag(&"fired_turn"), "the graph ran to completion")
	_eq(npc.facing(), Vector3i(0, 0, 1),
		"and keeps the south face_direction the graph itself issued, not north again")

	world["root"].free()
	EventScheduler.reset_for_test()
	GameState.clear()


# -- lock_facing / through, siblings of art and conditions --------------------------

func _test_lock_facing_ignores_face_commands() -> void:
	_section("GameEvent -- lock_facing makes the actor ignore facing commands")
	EventScheduler.reset_for_test()
	GameState.clear()

	var world := _build_world()
	var player := _build_actor(world, &"player", Vector3i(0, 0, 0))
	var rig := _build_event(world, &"ev", Vector3i(1, 0, 0), FIXTURES + "sched_lock_facing.event.json")
	var npc: Actor = rig["actor"]

	_ok(npc.facing_locked, "the page's lock_facing was applied to the actor on activation")
	_eq(npc.facing(), Vector3i(0, 0, 1), "south is Actor's own untouched default facing")

	player.set_facing(Vector3i(1, 0, 0))
	EventBus.player_interacted.emit()

	_ok(GameState.flag(&"fired_lock_facing"), "the graph still ran to completion")
	_eq(npc.facing(), Vector3i(0, 0, 1),
		"but its face_direction east never turned the actor - still the untouched default")

	world["root"].free()
	EventScheduler.reset_for_test()
	GameState.clear()


func _test_through_changes_proximity_and_phasing() -> void:
	_section("GameEvent -- through switches action to same-cell and phases the actor")
	EventScheduler.reset_for_test()
	GameState.clear()

	var world := _build_world()
	var player := _build_actor(world, &"player", Vector3i(1, 0, 0))
	var rig := _build_event(world, &"ev", Vector3i(1, 0, 0), FIXTURES + "sched_through.event.json")
	var npc: Actor = rig["actor"]
	var ctx: MapContext = world["ctx"]

	_ok(npc.through_actors, "the page's through was applied to the actor on activation")
	_ok(npc.through_terrain, "and through_terrain alongside it")
	_ok(ctx.occupancy.phases(npc.actor_id),
		"and Occupancy's own phasing table agrees - not just the export property")

	# Standing on the same cell, not adjacent - through has no facing side that means
	# anything, so the proximity rule switches from "adjacent and facing" to this.
	player.set_facing(Vector3i(0, 0, -1))
	EventBus.player_interacted.emit()
	_ok(GameState.flag(&"fired_through"),
		"action fires for standing on the same cell, facing away from it")

	world["root"].free()
	EventScheduler.reset_for_test()
	GameState.clear()


# -- The test rig ---------------------------------------------------------------------

func _build_world() -> Dictionary:
	var root := Node3D.new()
	add_child(root)

	var ctx := MapContext.new()
	ctx.map_id = &"sched_test"
	ctx.cell_size = Vector3.ONE
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)

	return {"root": root, "ctx": ctx}


## Deliberately viewless - no ActorView child - matching every headless actor segment
## 4 and 6 assume: a step settles synchronously, in whatever call started it.
func _build_actor(world: Dictionary, id: StringName, cell: Vector3i) -> Actor:
	var root: Node = world["root"]
	var ctx: MapContext = world["ctx"]

	var body := Node3D.new()
	body.name = str(id)
	body.position = ctx.cell_centre(cell)

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = id
	actor.facing_count = 4
	body.add_child(actor)

	var adapter := Space3D.new()
	adapter.name = "Space"
	actor.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = 4
	actor.add_child(motion)

	root.add_child(body)
	return actor


## An event does carry a real [SpriteSheet] visual - unlike the plain actors above -
## so the art-reconciliation test has something to observe changing.
func _build_event(world: Dictionary, id: StringName, cell: Vector3i,
		doc_path: String) -> Dictionary:
	var root: Node = world["root"]
	var ctx: MapContext = world["ctx"]

	var body := Node3D.new()
	body.name = str(id) + "_body"
	body.position = ctx.cell_centre(cell)

	var event := GameEvent.new()
	event.name = str(id)
	event.document_path = doc_path
	body.add_child(event)

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = id
	actor.facing_count = 4
	event.add_child(actor)

	var adapter := Space3D.new()
	adapter.name = "Space"
	actor.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = 4
	actor.add_child(motion)

	var view := SpriteView2D.new()
	view.name = "View"
	# Three levels up from View (-> actor -> event -> body), not one: GameEvent sits
	# between the body and the actor here, matching event-pages.md §4.3's layout.
	view.visual_path = NodePath("../../../Sheet")
	actor.add_child(view)

	# A sibling of `event` under the body, not of `View` under the actor - a Sprite2D
	# needs a Node2D/Node3D parent to have a transform at all (ActorView warns about
	# exactly this otherwise). 3x3 frames, matching the one real sheet texture this
	# project ships (Test_SpriteSheet_D_U_Side.png), so SpriteSheet's own _ready()
	# does not immediately index a frame that does not exist.
	var sheet := SpriteSheet.new()
	sheet.name = "Sheet"
	sheet.hframes = 3
	sheet.vframes = 3
	body.add_child(sheet)

	root.add_child(body)
	return {"root": root, "event": event, "actor": actor}


func _pump(runner: EventRunner, max_ticks: int = 600, dt: float = 1.0 / 60.0) -> void:
	var n := 0
	while not runner.finished and n < max_ticks:
		EventScheduler.tick(dt)
		n += 1


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
