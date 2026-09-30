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
	_test_wait_between_rolls_a_duration_in_range()
	_test_set_fast_forward_forces_the_flag_and_stays_until_something_else_changes_it()
	_test_define_route_retries_when_blocked()
	_test_define_route_retry_targets_original_cell_not_recomputed()
	_test_define_route_jumps_to_blocked_target()
	_test_move_blocked_flow_per_node()
	_test_move_by_restore_keeps_original_target_not_current_position()
	_test_move_by_count_chains_legs_until_done_or_blocked()
	_test_move_by_forward_uses_the_actors_own_facing()
	_test_move_by_towards_and_away_from_player()
	_test_move_by_random_lands_one_cell_away_on_one_axis()
	await _test_move_by_wander_can_stand_still_or_take_one_step()
	_test_camera_move_by_blocked_by_bounds()
	_test_actor_shorthand_in_conditions()
	_test_event_id_is_the_placement_name()
	_test_move_route_paths_around_obstacles_and_remembers()
	await _test_shake_offsets_then_restores_camera()
	_test_eval_var_substitutes_own_name_and_commits_the_result()

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
			"outputs": [{"flow": "reached", "target": ""}, {"flow": "immediate", "target": "join"}]},
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


# -- wait_between: a random duration between "min" and "max", rolled once -------------

func _test_wait_between_rolls_a_duration_in_range() -> void:
	_section("WaitBetween -- rolls a duration between \"min\" and \"max\", once, at start()")
	GameState.clear()

	var ctx := EventContext.for_event(null, &"test_map", &"wait_between_test", null)
	var runner := EventRunner.new(ctx)

	var ex: EventCommandExec = EventCommandExec.create("wait_between")
	ex.setup({}, {"min": 1.0, "max": 2.0}, ctx, runner)
	ex.start()
	_ok(ex.tick(0.5) == EventCommandExec.Status.RUNNING,
		"still running - even the shortest possible roll (1s) can't be done after only 0.5s")

	var left := float(ex.capture().get("left", -1.0))
	_ok(left >= 0.49 and left < 1.51,
		"the roll minus the 0.5s already ticked lands in [0.5, 1.5) (got %s)" % left)

	_ok(ex.tick(10.0) == EventCommandExec.Status.DONE,
		"finishes once comfortably more time has passed than any roll could need")

	# Authored backwards - start() swaps them rather than rolling outside [min, max].
	var swapped: EventCommandExec = EventCommandExec.create("wait_between")
	swapped.setup({}, {"min": 3.0, "max": 1.0}, ctx, runner)
	swapped.start()
	var swapped_left := float(swapped.capture().get("left", -1.0))
	_ok(swapped_left >= 1.0 and swapped_left <= 3.0,
		"min/max authored backwards still rolls inside [1, 3] (got %s)" % swapped_left)

	# Fast-forward collapses it instantly, whatever the roll - the same escape hatch
	# [Wait] itself already has (question 48).
	var was_forced := DebugFlags.force_fast_forward
	DebugFlags.force_fast_forward = true
	var ff: EventCommandExec = EventCommandExec.create("wait_between")
	ff.setup({}, {"min": 5.0, "max": 10.0}, ctx, runner)
	ff.start()
	_ok(ff.tick(0.0) == EventCommandExec.Status.DONE,
		"collapses to done on the very first tick under fast-forward")
	DebugFlags.force_fast_forward = was_forced

	GameState.clear()


## [code]set_fast_forward[/code] (events/commands/state_execs.gd's own
## [code]SetFastForward[/code]) - a graph's own hold on [member
## DebugFlags.force_fast_forward], left set until something else changes it (unlike
## key 0's own hold, which [method DebugFlags._process] clears on release).
func _test_set_fast_forward_forces_the_flag_and_stays_until_something_else_changes_it() -> void:
	_section("EventRunner -- set_fast_forward forces DebugFlags.force_fast_forward, no args means on")
	var was_forced := DebugFlags.force_fast_forward
	DebugFlags.force_fast_forward = false

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "n1"}]},
		{"id": "n1", "command": "set_fast_forward", "args": {},
			"outputs": [{"flow": "next", "target": "n2"}]},
		{"id": "n2", "command": "set_flag", "args": {"flag": "after_set_fast_forward"}, "outputs": []},
	]

	var ctx := EventContext.for_event(null, &"test_map", &"set_fast_forward_test", null)
	var runner := EventRunner.new(ctx)
	runner.begin(nodes)

	_ok(runner.finished, "an all-synchronous chain finishes inside begin() alone")
	_eq(runner.error, "", "with no error - set_fast_forward has an executor, not the generic fallback")
	_ok(DebugFlags.force_fast_forward, "no \"enabled\" arg means turn it on, same as set_flag's own default")
	_ok(GameState.flag(&"after_set_fast_forward"), "and control reached the node after it")

	DebugFlags.force_fast_forward = was_forced
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
			"outputs": [{"flow": "reached", "target": "done"}, {"flow": "immediate", "target": ""}]},
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


## The overshoot the single-cell test above cannot exercise: a multi-cell move_by that
## commits *part* of its distance before a transient obstruction refuses the rest, then
## retries once that obstruction clears. The retry must still aim at the cell this move
## was originally authored to reach - not a new one re-derived by re-applying "cells"
## against wherever the partial attempt left the actor, which would overshoot by however
## far it already got.
func _test_define_route_retry_targets_original_cell_not_recomputed() -> void:
	_section("EventRunner -- a retried move_by keeps its original target, not one recomputed off partial progress")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	var map: MapContext = rig["ctx"]
	map.occupancy.place(&"blocker", Vector3i(2, 0, 0))
	var ctx := EventContext.for_event(map, &"test_map", &"retry_target_test", guard)

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "dr"}]},
		{"id": "dr", "command": "define_route", "args": {},
			"outputs": [{"flow": "next", "target": "mv"}]},
		{"id": "mv", "command": "move_by", "args": {"cells": [3, 0, 0]},
			"outputs": [{"flow": "reached", "target": "done"}, {"flow": "immediate", "target": ""}]},
		{"id": "done", "command": "set_flag", "args": {"flag": "route_done"}, "outputs": []},
	]

	var runner := EventRunner.new(ctx)
	runner.begin(nodes)

	_eq(guard.cell(), Vector3i(1, 0, 0),
		"the first attempt commits the one cell it could before the blocker refuses the rest")
	_ok(not runner.finished, "blocked, and retrying")

	# Clears before the retry actually fires - a transient obstruction, not the
	# permanent one the test above leaves in place for its own entire run.
	map.occupancy.release_actor(&"blocker")
	runner.tick(1.0 / 60.0)  # the one-tick pause resolves and the retry itself fires

	_ok(runner.finished, "the route finishes once the retry succeeds")
	_eq(guard.cell(), Vector3i(3, 0, 0),
		"landed exactly at the originally authored target - not one shifted 3 more " +
		"cells past wherever the blocked attempt left off")
	_ok(GameState.flag(&"route_done"), "and the graph actually continued past the move")
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
			"outputs": [{"flow": "reached", "target": "should_not_run"}, {"flow": "immediate", "target": ""}]},
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


## A move command's own "blocked" flow, no define_route anywhere: wired, the refused
## move counts as completed and the graph flows on from "blocked"; unwired, the command
## waits a frame and retries - so a looped path awaiting "reached" resumes the same
## loop once the obstruction clears.
func _test_move_blocked_flow_per_node() -> void:
	_section("EventRunner -- a move's own \"blocked\" flow: wired skips on, unwired waits and retries")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	var map: MapContext = rig["ctx"]
	map.occupancy.place(&"blocker", Vector3i(1, 0, 0))
	var ctx := EventContext.for_event(map, &"test_map", &"blocked_flow_test", guard)

	var wired: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "mv"}]},
		{"id": "mv", "command": "move_by", "args": {"cells": [1, 0, 0]},
			"outputs": [{"flow": "reached", "target": "should_not_run"},
				{"flow": "immediate", "target": ""}, {"flow": "blocked", "target": "gave_up"}]},
		{"id": "should_not_run", "command": "set_flag",
			"args": {"flag": "should_not_run"}, "outputs": []},
		{"id": "gave_up", "command": "set_flag",
			"args": {"flag": "took_blocked"}, "outputs": []},
	]
	var runner := EventRunner.new(ctx)
	runner.begin(wired)
	_ok(runner.finished, "wired: the run finishes instead of retrying")
	_ok(GameState.flag(&"took_blocked"), "wired: flowed on from \"blocked\"")
	_ok(not GameState.flag(&"should_not_run"), "wired: \"reached\" never fired")

	GameState.clear()
	var unwired: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "mv"}]},
		{"id": "mv", "command": "move_by", "args": {"cells": [1, 0, 0]},
			"outputs": [{"flow": "reached", "target": "done"}, {"flow": "immediate", "target": ""}]},
		{"id": "done", "command": "set_flag", "args": {"flag": "moved_on"}, "outputs": []},
	]
	var runner2 := EventRunner.new(ctx)
	runner2.begin(unwired)
	for i in 5:
		runner2.tick(1.0 / 60.0)
	_ok(not runner2.finished, "unwired: still waiting while the cell stays blocked")
	_eq(runner2.error, "", "unwired: no node-budget error")

	map.occupancy.release_actor(&"blocker")
	runner2.tick(1.0 / 60.0)
	runner2.tick(1.0 / 60.0)
	_ok(runner2.finished, "unwired: finishes once the blocker leaves")
	_eq(guard.cell(), Vector3i(1, 0, 0), "unwired: the move was retried and landed")
	_ok(GameState.flag(&"moved_on"), "unwired: \"reached\" fired after the retry")
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


func _test_move_by_count_chains_legs_until_done_or_blocked() -> void:
	_section("MoveBy -- \"token:N\" walks N one-cell legs, stopping early if a leg blocks")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	guard.set_facing(Vector3i(1, 0, 0))
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"count_test", guard)
	var runner := EventRunner.new(ctx)

	var ex: EventCommandExec = EventCommandExec.create("move_by")
	ex.setup({"key": "mv"}, {"cells": "forward:3"}, ctx, runner)
	ex.start()
	_ok(ex.own_key() != "", "own_key() is already the chain's key right after start()")
	_ok(ex.tick(0.0) == EventCommandExec.Status.DONE,
		"three unobstructed legs still settle synchronously")
	_eq(guard.cell(), Vector3i(3, 0, 0), "landed 3 cells over - one full \"cells\" delta per count")
	_ok(not ex.was_blocked(), "and reads as unblocked")

	# Guard is at (3, 0, 0) now. A blocker two cells further over: the chain gets one
	# leg in (to (4, 0, 0)), then the second comes up blocked at (5, 0, 0) - it must
	# stop there rather than skipping past the blocker onto the third.
	(rig["ctx"] as MapContext).occupancy.place(&"blocker", Vector3i(5, 0, 0))
	var ex2: EventCommandExec = EventCommandExec.create("move_by")
	ex2.setup({}, {"cells": "forward:3"}, ctx, runner)
	ex2.start()
	_ok(ex2.tick(0.0) == EventCommandExec.Status.DONE, "the chain still settles, just short")
	_eq(guard.cell(), Vector3i(4, 0, 0), "one more leg landed before the blocker refused the next")
	_ok(ex2.was_blocked(), "and reads as blocked - the chain stopped rather than finishing count")

	GameState.clear()


## [constant EventCommand.MOVE_DIR_TOKENS]'s "forward" - [method _build_rig]'s own
## guard starts facing whatever [Actor]'s own default is, so this sets a facing by hand
## first to make sure "forward" is reading it, not coincidentally matching a default.
func _test_move_by_forward_uses_the_actors_own_facing() -> void:
	_section("MoveBy -- \"forward\" moves one cell in whatever direction the actor already faces")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	guard.set_facing(Vector3i(0, 0, 1))
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"forward_test", guard)
	var runner := EventRunner.new(ctx)

	var ex: EventCommandExec = EventCommandExec.create("move_by")
	ex.setup({}, {"cells": "forward"}, ctx, runner)
	ex.start()
	_ok(ex.tick(0.0) == EventCommandExec.Status.DONE, "settles synchronously, same as a literal delta")
	_eq(guard.cell(), Vector3i(0, 0, 1), "moved one cell the way the actor was already facing")

	GameState.clear()


## [constant EventCommand.MOVE_DIR_TOKENS]' "towards_player"/"away_from_player" -
## [method _build_rig]'s own player sits at (2, 0, 0), guard at (0, 0, 0): one cardinal
## step along the only axis that differs.
func _test_move_by_towards_and_away_from_player() -> void:
	_section("MoveBy -- \"towards_player\"/\"away_from_player\" take one step along the player's own axis")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"towards_test", guard)
	var runner := EventRunner.new(ctx)

	var towards: EventCommandExec = EventCommandExec.create("move_by")
	towards.setup({}, {"cells": "towards_player"}, ctx, runner)
	towards.start()
	_ok(towards.tick(0.0) == EventCommandExec.Status.DONE, "settles synchronously")
	_eq(guard.cell(), Vector3i(1, 0, 0), "one cell closer to the player at (2, 0, 0)")

	var away: EventCommandExec = EventCommandExec.create("move_by")
	away.setup({}, {"cells": "away_from_player"}, ctx, runner)
	away.start()
	_ok(away.tick(0.0) == EventCommandExec.Status.DONE, "settles synchronously")
	_eq(guard.cell(), Vector3i(0, 0, 0), "one cell back the way it came, away from the player")

	GameState.clear()


## [constant EventCommand.MOVE_DIR_TOKENS]' "random" - not which cardinal direction (
## that is [method EventCommand._random_cardinal]'s own business, not this command's),
## only that it lands exactly one cell away on one axis, the way any of the four could.
func _test_move_by_random_lands_one_cell_away_on_one_axis() -> void:
	_section("MoveBy -- \"random\" moves exactly one cell, along one axis")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"random_test", guard)
	var runner := EventRunner.new(ctx)

	var ex: EventCommandExec = EventCommandExec.create("move_by")
	ex.setup({}, {"cells": "random"}, ctx, runner)
	ex.start()
	_ok(ex.tick(0.0) == EventCommandExec.Status.DONE, "settles synchronously")

	var delta := guard.cell() - Vector3i.ZERO
	_ok(absi(delta.x) + absi(delta.y) + absi(delta.z) == 1,
		"landed exactly one cell away (got %s)" % guard.cell())


## [constant EventCommand.MOVE_DIR_TOKENS]' "wander" - [method
## EventCommand._random_cardinal_or_stay]'s own five equally-likely outcomes, so 60
## legs run the odds of never once landing on "stand still" (or never once moving)
## down to about 1 in 10^4 - unlucky enough to treat a failure here as a real bug, not
## a fluke.
##
## [b]A "stand still" leg does not settle inside its own [method
## EventCommandExec.tick] the way every other leg here does[/b] - unlike everywhere
## else in this file's own class doc ("every actor here is deliberately viewless...
## which is what makes a grid move settle synchronously"), [method
## GridMotion.move_to] given the cell the actor is already on resolves its key through
## a deferred [signal EventBus.command_finished] instead (see that method's own
## comment on why - a caller has not connected to the key yet at the point the call
## returns it). This is the one test in the file that has to actually wait a real
## frame for that, rather than assuming synchronous settlement like every other move.
func _test_move_by_wander_can_stand_still_or_take_one_step() -> void:
	_section("MoveBy -- \"wander\" is \"random\" plus a fifth outcome: stand still")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"wander_test", guard)
	var runner := EventRunner.new(ctx)

	var saw_stay := false
	var saw_move := false
	for i in 60:
		var before := guard.cell()
		var ex: EventCommandExec = EventCommandExec.create("move_by")
		ex.setup({}, {"cells": "wander"}, ctx, runner)
		ex.start()

		var status := ex.tick(0.0)
		var frames := 0
		while status != EventCommandExec.Status.DONE and frames < 5:
			await get_tree().process_frame
			status = ex.tick(0.0)
			frames += 1
		_ok(status == EventCommandExec.Status.DONE, "settles within a few frames at most")

		var step := guard.cell() - before
		var distance := absi(step.x) + absi(step.y) + absi(step.z)
		_ok(distance == 0 or distance == 1,
			"every leg is either a stand-still or exactly one cell (got delta %s)" % step)
		if distance == 0:
			saw_stay = true
		else:
			saw_move = true

	_ok(saw_stay, "stood still at least once across 60 legs")
	_ok(saw_move, "and moved at least once across 60 legs")

	GameState.clear()


## No actors involved - a camera command's only "rig" is a MapContext and a RoomCamera2D,
## the same sibling-under-one-root shape [method _build_rig] gives an actor.
func _test_move_route_paths_around_obstacles_and_remembers() -> void:
	_section("MoveRoute -- A* around a blocker, stores JSON move commands, no_path_found (no movement) when walled in")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	var map: MapContext = rig["ctx"]
	map.occupancy.place(&"blocker", Vector3i(1, 0, 0))
	var ctx := EventContext.for_event(map, &"test_map", &"route_test", guard)
	var runner := EventRunner.new(ctx)

	var ex: EventCommandExec = EventCommandExec.create("move_route")
	ex.setup({}, {"cell": Vector3i(2, 0, 1)}, ctx, runner)
	ex.start()
	_ok(ex.tick(0.0) == EventCommandExec.Status.DONE, "a clear route settles synchronously")
	_eq(guard.cell(), Vector3i(2, 0, 1), "walked around the blocker to the target")
	_eq(ex.flow_port(), EventCommand.FLOW_REACHED, "and leaves by \"reached\"")
	_ok(not ex.was_blocked(), "unblocked")
	_eq(guard.move_route.size(), 3, "the route is stored as one JSON move command per step")
	_eq((guard.move_route[0] as Dictionary)["command"], "move_to", "each is a move_to")

	var saved := guard.to_save()
	guard.move_route = []
	guard.from_save(saved)
	_eq(guard.move_route.size(), 3, "the most recent route survives save/load")

	# The debug view draws what is left of the stored route: put the guard back at the
	# start and all three steps are ahead of it again; at the end, none are.
	_eq(DebugRouteView.route_lines(map).size(), 0, "debug route view: nothing left once the route is walked")
	guard.motion().move_to(Vector3i.ZERO, {"path": "raw"})
	var lines := DebugRouteView.route_lines(map)
	_eq(lines.size(), 1, "debug route view: one route drawn for the actor that has one")
	_eq(lines[0].size() if lines.size() == 1 else -1, 4, "from its own cell through all three steps")

	# Walled in: every neighbour of (6, 0, 6) is held, so it cannot be reached. A tight
	# node cap keeps the search short; the actor stays put and reports it.
	for d in Passability.STEPS:
		map.occupancy.place(StringName("wall%d_%d" % [d.x, d.z]), Vector3i(6, 0, 6) + d)
	var cell_before := guard.cell()
	var ex2: EventCommandExec = EventCommandExec.create("move_route")
	ex2.setup({}, {"cell": Vector3i(6, 0, 6), "max_nodes": 150}, ctx, runner)
	ex2.start()
	_ok(ex2.tick(0.0) == EventCommandExec.Status.DONE, "the walled-in search finishes at once")
	_eq(ex2.flow_port(), EventCommand.FLOW_NO_PATH_FOUND, "and leaves by \"no_path_found\"")
	_eq(guard.cell(), cell_before, "and the actor did not move at all")
	_eq(guard.move_route.size(), 0, "with no stale route left stored")

	GameState.clear()


func _test_actor_shorthand_in_conditions() -> void:
	_section("EventCondition -- the @actor. shorthand: at, near, near_event, flag")
	GameState.clear()

	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"shorthand_test", guard)
	var cctx := ctx.condition_ctx()

	var holds := func(text: String) -> bool:
		var parsed := EventCondition.parse_expression(text)
		_ok((parsed["problems"] as Array).is_empty(), "\"%s\" parses" % text)
		return EventCondition.evaluate(parsed["tree"], cctx)

	_ok(holds.call("@self.at(0, 0, 0)"), "at: the guard is on its own cell")
	_ok(not holds.call("@self.at(1, 0, 0)"), "at: and not on the next one")
	_ok(holds.call("@guard.at(0,0,0)"), "an actor is named by id as well as @self")
	_ok(holds.call("@player.at(2, 0, 0)"), "@player resolves")
	_ok(holds.call("@self.near(2, 0, 0, 2)"), "near: two cells away is within 2")
	_ok(not holds.call("@self.near(2, 0, 0, 1)"), "near: but not within 1")
	_ok(holds.call("@self.near(1, 0, 1, 2)"), "near: Manhattan - the diagonal is 2 away")
	_ok(not holds.call("@self.near(1, 0, 1, 1)"), "near: so a diagonal is outside 1")
	_ok(holds.call("@self.near_event(@player, 2)"), "near_event: the player is 2 cells off")
	_ok(not holds.call("@self.near_event(@player, 1)"), "near_event: not within 1")
	_ok(holds.call("not @self.at(5, 0, 5) and @self.near(0, 0, 0, 0)"), "they combine with and / not")
	_ok(not holds.call("@self.flag(\"alerted\")"), "flag: reads false with no event holding it")

	var bad := EventCondition.parse_expression("@self.flag(\"alerted\", true)")
	_ok(not (bad["problems"] as Array).is_empty(), "a write is refused in a condition")
	_ok(not (EventCondition.parse_expression("@self.teleport(1)")["problems"] as Array).is_empty(),
		"an unknown method is reported")
	_ok(not (EventCondition.parse_expression("@self.at(1, 2)")["problems"] as Array).is_empty(),
		"a wrong argument count is reported")

	var tree: Dictionary = EventCondition.parse_expression("@self.near(2, 0, 0, 2)")["tree"]
	_ok((EventCondition.validate(tree) as Array).is_empty(), "the tree validates")

	# The terminal's half: the same questions through Expression, via the actors proxy.
	var proxy := ActorQueries.ActorsProxy.new(rig["ctx"])
	var expression := Expression.new()
	expression.parse("actors[\"guard\"].near(2, 0, 0, 2) and actors[\"player\"].at(2, 0, 0) "
		+ "and actors[\"guard\"].near_event(actors[\"player\"], 2)", ["actors"])
	_ok(expression.execute([proxy], null, true) == true and not expression.has_execute_failed(),
		"terminal: actors[...] answers at / near / near_event through Expression")
	GameState.clear()


func _test_event_id_is_the_placement_name() -> void:
	_section("GameEvent.event_id -- the placement's name, so two \"GameEvent\" nodes do not share flags")
	GameState.clear()

	var rig := _build_rig()
	var map: MapContext = rig["ctx"]
	var guard: Actor = rig["guard"]
	var other := _build_actor(rig["root"], &"Other_Guard", Vector3i(4, 0, 4), map)

	var first := GameEvent.new()
	first.name = "GameEvent"
	guard.get_parent().add_child(first)
	var second := GameEvent.new()
	second.name = "GameEvent"
	other.get_parent().add_child(second)

	_eq(first.event_id(), &"guard", "the id is the parent's name, lower-cased")
	_eq(second.event_id(), &"other_guard", "and differs per placement")

	ActorQueries.set_flag(guard, &"talked", true)
	_ok(ActorQueries.flag(guard, &"talked"), "a flag set on one actor reads back on it")
	_ok(not ActorQueries.flag(other, &"talked"), "and is not set on the other")
	GameState.clear()


func _test_shake_offsets_then_restores_camera() -> void:
	_section("Shake -- the camera is offset while shaking and back exactly at rest afterwards")
	GameState.clear()

	var root := Node2D.new()
	add_child(root)
	var ctx := MapContext.new()
	ctx.map_id = &"shake_test_map"
	root.add_child(ctx)
	var camera := Camera2D.new()
	root.add_child(camera)
	var rig := RoomCamera2D.new()
	camera.add_child(rig)

	var ectx := EventContext.for_event(ctx, &"shake_test_map", &"shake_test")
	var runner := EventRunner.new(ectx)
	var ex: EventCommandExec = EventCommandExec.create("shake")
	ex.setup({"key": "sh"}, {"strength": 20.0, "seconds": 0.2}, ectx, runner)
	ex.start()
	_ok(ex.own_key() != "", "shake mints a key")
	_ok(ex.tick(0.0) == EventCommandExec.Status.RUNNING, "and is still running right after start")

	var moved := false
	for i in 6:
		await get_tree().process_frame
		if camera.offset != Vector2.ZERO:
			moved = true
	_ok(moved, "the camera was offset at some point during the shake")

	await get_tree().create_timer(0.4).timeout
	_ok(ex.tick(0.0) == EventCommandExec.Status.DONE, "finished after its seconds elapsed")
	_eq(camera.offset, Vector2.ZERO, "camera offset is exactly zero again afterwards")
	_eq(ex.flow_port(), EventCommand.FLOW_REACHED, "and it leaves by \"reached\"")

	root.free()
	GameState.clear()


func _test_camera_move_by_blocked_by_bounds() -> void:
	_section("CameraMoveBy -- a leg outside camera_bounds stops the chain, the camera's own \"blocked\"")
	GameState.clear()

	var root := Node2D.new()
	add_child(root)

	var ctx := MapContext.new()
	ctx.map_id = &"cam_test_map"
	ctx.cell_size = Vector3.ONE * 16.0
	root.add_child(ctx)

	var camera := Camera2D.new()
	root.add_child(camera)
	var rig := RoomCamera2D.new()
	# Three cells wide at 16px each - room for two legs east of the origin cell before
	# a third would land outside it.
	rig.bounds = Rect2(Vector2.ZERO, Vector2(48, 48))
	camera.add_child(rig)

	var ectx := EventContext.for_event(ctx, &"cam_test_map", &"cam_test")
	var runner := EventRunner.new(ectx)

	var ex: EventCommandExec = EventCommandExec.create("camera_move_by")
	ex.setup({}, {"cells": "random:5"}, ectx, runner)
	ex.start()
	_ok(ex.tick(0.0) == EventCommandExec.Status.DONE,
		"the chain settles instantly - nothing here waits on a real tween")
	_ok(ex.was_blocked(),
		"and reads as blocked - it left the bounds before it ran out of count")

	root.free()
	GameState.clear()


func _test_eval_var_substitutes_own_name_and_commits_the_result() -> void:
	_section("EvalVar -- \"{v}\" substitutes \"var\"'s own name, and the boolean result commits back to it")
	GameState.clear()

	var rig := _build_rig()
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"eval_var_test")
	var runner := EventRunner.new(ctx)

	GameState.var_set(&"chapter", 5.0)
	var ex: EventCommandExec = EventCommandExec.create("eval_var")
	ex.setup({}, {"var": "chapter", "expression": "{v} >= 5"}, ctx, runner)
	ex.start()
	_ok(GameState.var_get(&"chapter") == true, "chapter >= 5 held, so chapter now reads true")

	GameState.var_set(&"chapter", 5.0)
	var ex2: EventCommandExec = EventCommandExec.create("eval_var")
	ex2.setup({}, {"var": "chapter", "expression": "{v} >= 10"}, ctx, runner)
	ex2.start()
	_ok(GameState.var_get(&"chapter") == false, "chapter >= 10 did not, so chapter now reads false")

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
