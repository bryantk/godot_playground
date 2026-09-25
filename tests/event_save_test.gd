extends Node

## Headless assertions over [EventRunner]/[EventScheduler] save-restore - segments 5a
## (restart granularity) and 5b (mid-command resume) of docs/stage-c-plan.md.
##
##     godot --headless --path . res://tests/event_save_test.tscn
##
## [b]5b's actual scope here: [code]wait[/code] and [GridMotion]'s own commands[/b]
## ([code]move_to[/code]/[code]move_by[/code]/[code]step[/code]/[code]jump[/code]'s
## ladder-release fall). A resumable command's own [method EventCommandExec.capture]/
## [method EventCommandExec.restore] are now actually called by [EventRunner] - see
## [method EventRunner.restore]'s [code]pending_restore[/code] handling - rather than
## existing unused.
##
## [b]Not covered by a test yet, though the same code path backs it:[/b] a capture
## mid-fall (a ladder release or a walk off a ledge) - [method GridMotion.to_save]/
## [method GridMotion.from_save] carry [code]falling[/code]/[code]fall_wait[/code]/
## [code]fall_pending[/code] alongside the step fields, but nothing here builds a
## height-capable map to exercise it. [FreeMotion] has no capture at all - every
## free-motion command restarts (a legal downgrade, question 39).
##
## [b]Known gap:[/b] a runner captured mid-[code]call[/code] (a nested frame) is not
## exercised - every case here is a single top-level frame.

const FIXTURE := "res://tests/fixtures/save_test.event.json"
const SCRATCH_DOC := "user://event_save_test_doc.event.json"

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("event save/restore -- segment 5a (restart granularity) and 5b (mid-command resume)")
	print("")

	_test_doc_hash()
	_test_resume_at_captured_node()
	_test_hash_mismatch_restarts()
	_test_scheduler_round_trip()
	_test_battle_refuses_save()
	_test_wait_resumes_remaining_time()
	_test_move_to_mid_step_resume()

	var abs_path := ProjectSettings.globalize_path(SCRATCH_DOC)
	if FileAccess.file_exists(SCRATCH_DOC):
		DirAccess.remove_absolute(abs_path)

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- EventCommand.doc_hash -----------------------------------------------------

func _test_doc_hash() -> void:
	_section("EventCommand.doc_hash -- stable over editor bookkeeping, sensitive to real edits")

	var a: Array[Dictionary] = [
		{"id": "start", "title": "Start", "position": {"x": 0, "y": 0}, "command": "start",
			"args": {}, "outputs": [{"flow": "next", "target": "n1"}]},
		{"id": "n1", "title": "wait", "position": {"x": 100, "y": 0}, "command": "wait",
			"args": {"seconds": 1.0}, "outputs": []},
	]
	var b: Array[Dictionary] = [
		{"id": "n1", "title": "renamed", "position": {"x": 999, "y": 999}, "command": "wait",
			"args": {"seconds": 1.0}, "outputs": []},
		{"id": "start", "title": "Start", "position": {"x": 0, "y": 0}, "command": "start",
			"args": {}, "outputs": [{"flow": "next", "target": "n1"}]},
	]
	_eq(EventCommand.doc_hash(a), EventCommand.doc_hash(b),
		"title/position edits and node reordering leave the hash unchanged")

	var c: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {}, "outputs": [{"flow": "next", "target": "n1"}]},
		{"id": "n1", "command": "wait", "args": {"seconds": 2.0}, "outputs": []},
	]
	_ok(EventCommand.doc_hash(a) != EventCommand.doc_hash(c),
		"a real arg edit (1.0 -> 2.0 seconds) changes the hash")


# -- EventRunner.to_save/restore ------------------------------------------------

func _write_scratch_doc(seconds: float, flag_name: String) -> void:
	var f := FileAccess.open(SCRATCH_DOC, FileAccess.WRITE)
	f.store_string(JSON.stringify([
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "n1"}]},
		{"id": "n1", "command": "set_flag", "args": {"flag": flag_name},
			"outputs": [{"flow": "next", "target": "n2"}]},
		{"id": "n2", "command": "wait", "args": {"seconds": seconds},
			"outputs": [{"flow": "next", "target": "n3"}]},
		{"id": "n3", "command": "set_flag", "args": {"flag": "reached_n3"}, "outputs": []},
	]))
	f.close()


func _graph_from(path: String) -> Array[Dictionary]:
	var doc := EventDocument.parse(FileAccess.get_file_as_string(path))
	return (doc["pages"][0] as Dictionary)["graph"]


func _test_resume_at_captured_node() -> void:
	_section("EventRunner -- captured mid-wait resumes there, not from the top")
	GameState.clear()
	_write_scratch_doc(10.0, "reached_n1")

	var rig := _build_rig()
	var actor: Actor = rig["actor"]
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"save_test", actor)

	var runner := EventRunner.new(ctx)
	runner.begin(_graph_from(SCRATCH_DOC), SCRATCH_DOC, 0)

	_ok(not runner.finished, "blocked on the wait node rather than running to completion")
	_ok(GameState.flag(&"reached_n1"), "n1 already ran before the capture")

	var saved := runner.to_save()
	GameState.clear()  # the world is about to be torn down and rebuilt

	var restored := EventRunner.from_save(saved, rig["ctx"])
	_ok(not restored.finished, "the restored runner is still mid-graph")
	_ok(not GameState.flag(&"reached_n1"),
		"n1 did not re-run - the resume picked up at the wait, not from the start")

	for i in 20:
		restored.tick(1.0)
	_ok(restored.finished, "the wait finishes and the graph runs to its own end")
	_ok(GameState.flag(&"reached_n3"), "n3 ran exactly once, after the resume")


func _test_hash_mismatch_restarts() -> void:
	_section("EventRunner -- a doc edited since the save restarts that frame instead")
	GameState.clear()
	_write_scratch_doc(10.0, "reached_n1")

	var rig := _build_rig()
	var actor: Actor = rig["actor"]
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"save_test", actor)

	var runner := EventRunner.new(ctx)
	runner.begin(_graph_from(SCRATCH_DOC), SCRATCH_DOC, 0)
	var saved := runner.to_save()
	GameState.clear()

	# The file changes on disk between the save and the restore - a different flag name
	# on n1, the same shape otherwise.
	_write_scratch_doc(10.0, "reached_n1_v2")

	var restored := EventRunner.from_save(saved, rig["ctx"])
	_ok(not restored.finished, "still runs (the edited file still parses clean)")

	for i in 15:
		restored.tick(1.0)
	_ok(restored.finished, "runs to completion against the edited file")
	_ok(GameState.flag(&"reached_n1_v2"),
		"restarted from the top against the new file - n1 ran under its new name")
	_ok(not GameState.flag(&"reached_n1"), "not under its old one")
	_ok(GameState.flag(&"reached_n3"), "and reached the end")


# -- EventScheduler.to_save/from_save -------------------------------------------

func _test_scheduler_round_trip() -> void:
	_section("EventScheduler -- exclusive runner and its lease survive a round trip")
	GameState.clear()
	EventScheduler.reset()
	_write_scratch_doc(10.0, "sched_reached_n1")

	var rig := _build_rig()
	var actor: Actor = rig["actor"]
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"save_test", actor)
	var runner := EventRunner.new(ctx)

	_ok(EventScheduler.try_lease(actor.actor_id, runner), "the actor is leased to the runner")
	_ok(EventScheduler.run_exclusive(runner, _graph_from(SCRATCH_DOC), SCRATCH_DOC, 0),
		"the exclusive slot is taken")
	_eq(ModeStack.current(), ModeStack.Mode.CUTSCENE, "and the cutscene mode is pushed")

	var brain: PlayerController = rig["brain"]
	_ok(brain.is_suspended(), "the actor's own controller is suspended for the run")

	var saved := EventScheduler.to_save()
	EventScheduler.reset()
	ModeStack.reset()
	_ok(not brain.is_suspended(), "reset()'s stop() gave the controller back")

	EventScheduler.from_save(saved, rig["ctx"])
	_ok(EventScheduler.is_exclusive_held(), "the exclusive slot is held again after restore")
	_eq(ModeStack.current(), ModeStack.Mode.CUTSCENE, "cutscene mode is pushed again")
	_eq(EventScheduler.lease_holder(actor.actor_id), EventScheduler.exclusive_runner(),
		"the lease points at the restored runner, not the one before the round trip")
	_ok(brain.is_suspended(), "the controller is suspended again, by the restored runner")

	for i in 15:
		EventScheduler.tick(1.0)
	_ok(not EventScheduler.is_exclusive_held(), "the slot frees once the restored run finishes")
	_ok(ModeStack.is_field(), "and cutscene mode pops back to field")
	_ok(not brain.is_suspended(), "and the controller is handed back")

	EventScheduler.reset()
	ModeStack.reset()


func _test_battle_refuses_save() -> void:
	_section("EventScheduler -- to_save() during BATTLE is refused outright")
	ModeStack.push(ModeStack.Mode.BATTLE)
	var saved := EventScheduler.to_save()
	_ok(saved.is_empty(), "returns {} rather than a battle-time snapshot")
	ModeStack.reset()


# -- Segment 5b: mid-command resume ---------------------------------------------

## The cheapest 5b case: [Wait] already had a real [method EventCommandExec.capture]/
## [method EventCommandExec.restore] since segment 4 (the interface existed, unused) -
## this proves [EventRunner] now actually calls them.
func _test_wait_resumes_remaining_time() -> void:
	_section("EventRunner -- a wait resumes with its remaining time, not a fresh count")
	GameState.clear()

	var rig := _build_rig()
	var actor: Actor = rig["actor"]
	var ctx := EventContext.for_event(rig["ctx"], &"test_map", &"save_test", actor)

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {}, "outputs": [{"flow": "next", "target": "n1"}]},
		{"id": "n1", "command": "wait", "args": {"seconds": 1.5},
			"outputs": [{"flow": "next", "target": "n2"}]},
		{"id": "n2", "command": "set_flag", "args": {"flag": "waited"}, "outputs": []},
	]

	var runner := EventRunner.new(ctx)
	runner.begin(nodes)
	runner.tick(0.6)
	_ok(not runner.finished, "still waiting")

	var restored := EventRunner.from_save(runner.to_save(), rig["ctx"])
	restored.tick(0.85)
	_ok(not restored.finished and not GameState.flag(&"waited"),
		"0.85s of a 0.9s remainder isn't quite enough - a fresh 1.5s would have finished by now")
	restored.tick(0.1)
	_ok(restored.finished and GameState.flag(&"waited"),
		"the remaining ~0.05s finishes it - resumed at 0.9s left, not restarted at 1.5")


## The plan's own headline case: a multi-cell [code]move_to[/code] captured mid-step
## restores to the same remainder and travels exactly the cells it was asked for in
## total - the assertion that catches a step replayed (5 cells) or dropped (3).
##
## Drives [method GridMotion._process] by hand with fixed deltas rather than
## [code]await get_tree().process_frame[/code] - this rig's nodes are genuinely live in
## a running [SceneTree] (unlike every viewless rig elsewhere in this suite), but a
## headless run's real per-frame delta is not something a test should depend on being
## small (or large) enough to land mid-step. A synchronous run of direct calls, with no
## [code]await[/code] in between, cannot race the engine's own automatic [method
## Node._process] dispatch either - nothing yields back to it until this function does.
func _test_move_to_mid_step_resume() -> void:
	_section("EventRunner/GridMotion -- a move_to captured mid-step travels exactly 4 cells")
	GameState.clear()

	var rig := _build_rig(true)
	var actor: Actor = rig["actor"]
	var ctx: MapContext = rig["ctx"]
	var motion := actor.motion()
	var ectx := EventContext.for_event(ctx, &"test_map", &"save_test", actor)

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {}, "outputs": [{"flow": "next", "target": "n1"}]},
		{"id": "n1", "command": "move_to", "args": {"cell": [4, 0, 0]},
			"outputs": [{"flow": "next", "target": ""}]},
	]

	var runner := EventRunner.new(ectx)
	runner.begin(nodes)  # commits the first cell synchronously - see the class doc

	motion._process(0.1)  # partway through a 0.25s step at speed 4.0 - not yet settled
	runner.tick(0.1)

	_ok(not runner.finished, "still mid-move")
	_eq(actor.cell(), Vector3i(1, 0, 0), "the first cell is already committed - the body snaps at commit")
	_eq(ctx.occupancy.cells_of(actor.actor_id).size(), 1,
		"exactly one cell claimed while mid-step - the body is never logically between cells")

	var restored := EventRunner.from_save(runner.to_save(), ctx)

	var finished := false
	for i in 200:
		motion._process(0.05)
		restored.tick(0.05)
		if restored.finished:
			finished = true
			break

	_ok(finished, "the restored move_to runs to completion")
	_eq(actor.cell(), Vector3i(4, 0, 0), "arrived exactly at the destination, not short or past it")
	_eq(ctx.occupancy.cells_of(actor.actor_id).size(), 1,
		"and still exactly one cell claimed once it settles")


# -- Harness --------------------------------------------------------------------

## [param with_view] adds an [ActorView] over a bare [Node3D] visual - without one, a
## step settles synchronously inside commit (every rig elsewhere in this suite is
## viewless on purpose), which is no good for a test that needs a step genuinely
## in flight to capture mid-tween.
func _build_rig(with_view: bool = false) -> Dictionary:
	var root := Node3D.new()
	add_child(root)

	var ctx := MapContext.new()
	ctx.map_id = &"test_map"
	ctx.cell_size = Vector3.ONE
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)

	var body := Node3D.new()
	body.name = "actor"
	root.add_child(body)

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = &"actor"
	body.add_child(actor)

	var adapter := Space3D.new()
	adapter.name = "Space"
	actor.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = 4
	motion.speed = 4.0
	actor.add_child(motion)

	# Only suspend()/is_suspended() are under test here - PlayerController's own
	# _think never runs (nothing calls _process in this synchronous rig).
	var brain := PlayerController.new()
	brain.name = "PlayerController"
	actor.add_child(brain)

	if with_view:
		var visual := Node3D.new()
		visual.name = "Visual"
		body.add_child(visual)
		var view := ActorView.new()
		view.name = "View"
		actor.add_child(view)
		view.bind_visual(visual)

	return {"root": root, "ctx": ctx, "actor": actor, "brain": brain}


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(cond: bool, what: String) -> void:
	if cond:
		_passed += 1
		print("    ok    %s" % what)
	else:
		_fail(what)


func _eq(got: Variant, want: Variant, what: String) -> void:
	if got == want:
		_passed += 1
		print("    ok    %s" % what)
	else:
		_fail("%s  (got %s, want %s)" % [what, got, want])


func _fail(what: String) -> void:
	_failed += 1
	print("    FAIL  %s" % what)
