extends Node

## Headless assertions over [EventRunner], [EventCommandExec] and the executors in
## events/commands/ - segment 4 of docs/stage-c-plan.md.
##
##     godot --headless --path . res://tests/event_runner_test.tscn
##
## Every actor here is deliberately viewless (no [ActorView] child), which is what
## makes a grid move settle synchronously inside a single [method EventRunner.tick]
## call rather than spanning real frames - the same assumption segment 4's four
## motion-key fixes exist to make safe.

const CALL_TARGET := "res://tests/fixtures/call_target.event.json"

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("events -- EventRunner, the executor interface, and segment 4's commands")
	print("")

	_test_greet_guard()
	_test_say_blocks_until_finished()
	_test_if_goto_label()
	_test_call_and_exit_call()
	_test_goto_cycle_trips_budget()
	_test_nonblocking_key_joined_by_wait_for()
	_test_print_debug_runs_and_continues()
	_test_define_route_retries_when_blocked()
	_test_define_route_jumps_to_blocked_target()
	_test_move_by_restore_keeps_original_target_not_current_position()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- greet_guard end to end --------------------------------------------------------

func _test_greet_guard() -> void:
	_section("EventRunner -- greet_guard.event.json runs to completion")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"greet_guard", guard)

	var text := FileAccess.get_file_as_string("res://docs/events/greet_guard.event.json")
	var doc := EventDocument.parse(text)
	_ok((doc["problems"] as Array).is_empty(), "the worked example parses clean")

	var pages: Array = doc["pages"]
	var graph: Array[Dictionary] = (pages[0] as Dictionary)["graph"]

	var responder := func (_text: String, _options: Dictionary, key: String) -> void:
		EventBus.dialogue_finished.emit(key)
	EventBus.dialogue_enqueue.connect(responder)

	var runner := EventRunner.new(ctx)
	runner.begin(graph)
	_pump(runner)

	EventBus.dialogue_enqueue.disconnect(responder)

	_ok(runner.finished, "the runner finishes")
	_eq(runner.error, "", "with no error")
	_eq(guard.cell(), Vector3i(1, 0, 0), "and the guard ends one cell east of spawn")


# -- say blocks until the test says so ---------------------------------------------

func _test_say_blocks_until_finished() -> void:
	_section("EventRunner -- a say node advances only when dialogue_finished fires")
	GameState.clear()

	var rig := _build_rig()
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"say_test", rig["guard"])

	# A Dictionary, not a bare String: GDScript captures a lambda's outer locals by
	# value, so assigning to a captured String inside the closure would never be seen
	# out here - a mutable container is what makes the capture actually round-trip.
	var captured := {"key": ""}
	var capture := func (_text: String, _options: Dictionary, key: String) -> void:
		captured["key"] = key
	EventBus.dialogue_enqueue.connect(capture)

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "n1"}]},
		{"id": "n1", "command": "say", "args": {"text": "hi"},
			"outputs": [{"flow": "next", "target": ""}]},
	]

	var runner := EventRunner.new(ctx)
	runner.begin(nodes)
	_pump(runner, 30)
	_ok(not runner.finished, "still waiting after 30 ticks with nobody answering")

	EventBus.dialogue_finished.emit(captured["key"])
	runner.tick(1.0 / 60.0)
	_ok(runner.finished, "and finishes the moment the test answers it")

	EventBus.dialogue_enqueue.disconnect(capture)


# -- if / goto / label --------------------------------------------------------------

func _test_if_goto_label() -> void:
	_section("EventRunner -- if branches, goto/label chain with no executor of their own")

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "hop"}]},
		{"id": "hop", "command": "goto", "args": {},
			"outputs": [{"flow": "next", "target": "landed"}]},
		{"id": "landed", "command": "label", "args": {"name": "landed"},
			"outputs": [{"flow": "next", "target": "branch"}]},
		{"id": "branch", "command": "if", "args": {"condition": "chapter >= 2"},
			"outputs": [{"flow": "true", "target": "t"}, {"flow": "false", "target": "f"}]},
		{"id": "t", "command": "set_flag", "args": {"flag": "took_true"}, "outputs": []},
		{"id": "f", "command": "set_flag", "args": {"flag": "took_false"}, "outputs": []},
	]

	GameState.clear()
	var ctx := EventContext.for_event(null, &"test_map", &"branch_test", null)
	var runner := EventRunner.new(ctx)
	runner.begin(nodes)
	_ok(runner.finished, "an all-synchronous chain finishes inside begin() alone")
	_ok(GameState.flag(&"took_false"), "chapter unset (0) takes the false branch")
	_ok(not GameState.flag(&"took_true"), "and not the true one")

	GameState.clear()
	GameState.var_set(&"chapter", 2.0)
	var runner2 := EventRunner.new(ctx)
	runner2.begin(nodes)
	_ok(GameState.flag(&"took_true"), "chapter == 2 takes the true branch")
	_ok(not GameState.flag(&"took_false"), "and not the false one")
	GameState.clear()


# -- call / exit_call ---------------------------------------------------------------

func _test_call_and_exit_call() -> void:
	_section("EventRunner -- call clones and pushes a frame; exit_call pops it early")
	GameState.clear()

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "c1"}]},
		{"id": "c1", "command": "call", "args": {"document": CALL_TARGET},
			"outputs": [{"flow": "next", "target": "after"}]},
		{"id": "after", "command": "set_flag", "args": {"flag": "after_call"}, "outputs": []},
	]

	var ctx := EventContext.for_event(null, &"test_map", &"call_test", null)
	var runner := EventRunner.new(ctx)
	runner.begin(nodes)

	_ok(runner.finished, "the caller's own graph runs to completion")
	_ok(GameState.flag(&"in_callee_start"), "the callee's start node ran")
	_ok(not GameState.flag(&"should_not_run"), "exit_call popped before the callee's tail")
	_ok(GameState.flag(&"after_call"), "and control returned to the caller's own next")
	GameState.clear()


# -- a goto cycle trips the node budget ---------------------------------------------

func _test_goto_cycle_trips_budget() -> void:
	_section("EventRunner -- a goto cycle trips the node budget rather than hanging")

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "a"}]},
		{"id": "a", "command": "goto", "args": {},
			"outputs": [{"flow": "next", "target": "b"}]},
		{"id": "b", "command": "label", "args": {"name": "b"},
			"outputs": [{"flow": "next", "target": "a"}]},
	]

	var ctx := EventContext.for_event(null, &"test_map", &"cycle_test", null)
	var runner := EventRunner.new(ctx)
	runner.begin(nodes)

	_ok(runner.finished, "the runner stops itself rather than hanging forever")
	_ok(runner.error != "", "and records an error")
	_ok(runner.error.contains("\"a\"") or runner.error.contains("\"b\""),
		"naming the node it was on when the budget tripped -- got: %s" % runner.error)


# -- a non-blocking command's authored key, joined by a later wait_for --------------

func _test_nonblocking_key_joined_by_wait_for() -> void:
	_section("EventRunner -- a non-blocking move's authored key is joined by wait_for")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"nonblocking_test", guard)

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "mv"}]},
		{"id": "mv", "command": "move_by", "args": {"cells": [2, 0, 0]}, "key": "mv",
			"blocking": false,
			"outputs": [{"flow": "next", "target": "join"}]},
		{"id": "join", "command": "wait_for", "args": {"key": "mv"},
			"outputs": [{"flow": "next", "target": ""}]},
	]

	var runner := EventRunner.new(ctx)
	runner.begin(nodes)

	_ok(runner.finished, "the graph completes")
	_eq(guard.cell(), Vector3i(2, 0, 0), "and the guard actually moved the 2 cells")


# -- print_debug: prints and moves on, nothing else observable -----------------------

func _test_print_debug_runs_and_continues() -> void:
	_section("EventRunner -- print_debug prints to the console and flows to next")
	GameState.clear()

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "n1"}]},
		{"id": "n1", "command": "print_debug", "args": {"text": "hello from a graph"},
			"outputs": [{"flow": "next", "target": "n2"}]},
		{"id": "n2", "command": "set_flag", "args": {"flag": "after_print_debug"}, "outputs": []},
	]

	var ctx := EventContext.for_event(null, &"test_map", &"print_debug_test", null)
	var runner := EventRunner.new(ctx)
	runner.begin(nodes)

	_ok(runner.finished, "an all-synchronous chain finishes inside begin() alone")
	_eq(runner.error, "", "with no error - print_debug has an executor, not the generic fallback")
	_ok(GameState.flag(&"after_print_debug"), "and control reached the node after it")
	GameState.clear()


# -- define_route ----------------------------------------------------------------------

## The exact shape that used to trip the node budget: a hand-wired back-and-forth of
## ordinary move_by nodes, permanently blocked. define_route with "blocked" left unwired
## keeps the run alive instead by retrying - one scheduler tick of pause between each
## attempt, so retrying forever never spends the node budget the way a same-tick spin
## would.
func _test_define_route_retries_when_blocked() -> void:
	_section("EventRunner -- define_route retries a blocked move rather than tripping the budget")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	# A phantom blocker rather than a second Actor - stage_a_test.gd's own technique:
	# Occupancy answers on ids, and what is under test is the refusal, not who is there.
	(rig["ctx"] as MapContext).occupancy.place(&"blocker", Vector3i(1, 0, 0))
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"retry_test", guard)

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "dr"}]},
		# "blocked" left unwired entirely - no entry for it at all - which is what
		# means "retry" rather than "jump".
		{"id": "dr", "command": "define_route", "args": {},
			"outputs": [{"flow": "next", "target": "mv"}]},
		{"id": "mv", "command": "move_by", "args": {"cells": [1, 0, 0]},
			"outputs": [{"flow": "next", "target": "done"}]},
		{"id": "done", "command": "set_flag", "args": {"flag": "route_done"}, "outputs": []},
	]

	var runner := EventRunner.new(ctx)
	runner.begin(nodes)

	_ok(not runner.finished, "still busy retrying, permanently blocked, right out of begin()")
	_eq(runner.error, "", "no node-budget error even after begin()'s own synchronous pass")

	for i in 10:
		runner.tick(1.0 / 60.0)
	_ok(not runner.finished, "still retrying ten ticks later - the one-tick pause keeps it alive")
	_eq(runner.error, "", "and still no budget error")
	_eq(guard.cell(), Vector3i.ZERO, "the guard has made no progress - every attempt is refused")

	runner.stop()
	GameState.clear()


## "blocked" wired to a node: a blocked move jumps straight there instead of retrying,
## skipping whatever "next" the move itself would otherwise have taken.
func _test_define_route_jumps_to_blocked_target() -> void:
	_section("EventRunner -- define_route jumps to \"blocked\" instead of retrying, when wired")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	(rig["ctx"] as MapContext).occupancy.place(&"blocker", Vector3i(1, 0, 0))
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"jump_test", guard)

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "dr"}]},
		{"id": "dr", "command": "define_route", "args": {},
			"outputs": [
				{"flow": "next", "target": "mv"},
				{"flow": "blocked", "target": "gave_up"},
			]},
		{"id": "mv", "command": "move_by", "args": {"cells": [1, 0, 0]},
			"outputs": [{"flow": "next", "target": "should_not_run"}]},
		{"id": "should_not_run", "command": "set_flag",
			"args": {"flag": "should_not_run"}, "outputs": []},
		{"id": "gave_up", "command": "set_flag",
			"args": {"flag": "reached_blocked_target"}, "outputs": []},
	]

	var runner := EventRunner.new(ctx)
	runner.begin(nodes)

	_ok(runner.finished, "the run finishes rather than retrying or tripping the node budget")
	_eq(runner.error, "", "with no error")
	_ok(GameState.flag(&"reached_blocked_target"), "and jumped straight to \"blocked\"'s target")
	_ok(not GameState.flag(&"should_not_run"), "skipping the move's own \"next\" entirely")
	_eq(guard.cell(), Vector3i.ZERO, "the guard never actually moved")
	GameState.clear()


## The bug a hand-wired patrol actually hit: a route preempted mid-move_by (a triggered
## graph taking the lease, then handing it back) and resumed used to recompute its own
## target cell relative to wherever the actor had already gotten to by resume time,
## rather than where it stood when the move began - so a move that in fact finished
## exactly where it meant to still read as blocked, and define_route's own retry (see
## the section above) would send it another full "cells" delta further than authored.
## MoveBy/StepCmd's own target_cell now rides along in capture()'s own state instead of
## being rederived, which is what this proves directly against the executor.
func _test_move_by_restore_keeps_original_target_not_current_position() -> void:
	_section("MoveBy -- restore() keeps the move's original target, not one recomputed off the resumed position")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"capture_restore_test", guard)
	var runner := EventRunner.new(ctx)

	var ex: EventCommandExec = EventCommandExec.create("move_by")
	ex.setup({}, {"cells": Vector3i(0, 0, -2)}, ctx, runner)
	ex.start()
	_ok(ex.tick(0.0) == EventCommandExec.Status.DONE, "a viewless actor's move settles synchronously")
	_eq(guard.cell(), Vector3i(0, 0, -2), "landed the full 2 cells, unobstructed")
	_ok(not ex.was_blocked(), "and reads as unblocked")

	# The same shape EventRunner._drive() gives a pending_restore node: a fresh executor,
	# restore() instead of start(), built against whatever capture() returned earlier -
	# here taken after the move above already fully committed, since the point under
	# test is what restore() reconstructs its target from, not when capture() ran.
	var saved := ex.capture()
	var resumed: EventCommandExec = EventCommandExec.create("move_by")
	resumed.setup({}, {"cells": Vector3i(0, 0, -2)}, ctx, runner)
	resumed.restore(saved)
	resumed.tick(0.0)

	_eq(guard.cell(), Vector3i(0, 0, -2), "restore() does not move the actor again")
	_ok(not resumed.was_blocked(),
		"was_blocked() reads false - the original target survived, not one recomputed " +
		"another 2 cells past the resumed position")
	GameState.clear()


# -- Test rig ------------------------------------------------------------------------

func _build_rig() -> Dictionary:
	var root := Node3D.new()
	add_child(root)

	var ctx := MapContext.new()
	ctx.map_id = &"test_map"
	ctx.cell_size = Vector3.ONE
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)

	var guard := _build_actor(root, &"guard", Vector3i(0, 0, 0), ctx)
	_build_actor(root, &"player", Vector3i(2, 0, 0), ctx)

	return {"root": root, "ctx": ctx, "guard": guard}


## Deliberately viewless - no ActorView child - so a step settles synchronously inside
## whatever call started it, matching every headless test actor segment 4 assumes.
func _build_actor(root: Node, id: StringName, cell: Vector3i, ctx: MapContext) -> Actor:
	var body := Node3D.new()
	body.name = str(id)
	body.position = ctx.cell_centre(cell)
	root.add_child(body)

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

	return actor


func _pump(runner: EventRunner, max_ticks: int = 600, dt: float = 1.0 / 60.0) -> void:
	var n := 0
	while not runner.finished and n < max_ticks:
		runner.tick(dt)
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
