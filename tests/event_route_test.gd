extends Node

## Headless assertions over [EventRoute] - segment 7 of docs/stage-c-plan.md, the
## compiler only. Nothing here starts a route through [GameEvent] or an
## [EventScheduler] lease - that wiring, and the interruption/resume path question 52
## describes, is a separate slice of this segment.
##
##     godot --headless --path . res://tests/event_route_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("events -- EventRoute, the route compiler")
	print("")

	_test_fixed_and_empty_compile_to_nothing()
	_test_waypoints_compile_shape()
	_test_waypoints_loop_none_has_no_wraparound()
	_test_waypoints_loop_cycle_wraps_to_start()
	_test_waypoints_pingpong_bounces()
	_test_steps_compile_shape_and_face_wait()
	_test_steps_pingpong_inverts_directions()
	_test_seek_modes_compile_shape()
	_test_seek_reverse_compiles_a_flip_pair()
	_test_on_blocked_wait_loops_on_itself()
	_test_on_blocked_skip_matches_next()
	_test_on_blocked_reverse_targets_previous_move()
	_test_on_blocked_repath_warns_and_skips()

	_test_waypoints_drives_an_actor_to_the_end()
	_test_pingpong_actually_reverses_at_both_ends()
	_test_on_blocked_wait_holds_until_unblocked()
	_test_on_blocked_skip_advances_past_a_blocked_waypoint()
	_test_steps_same_shape_from_two_spawns()
	_test_toward_walks_the_actor_at_the_target()

	_test_shared_route_resolves()
	_test_shared_route_override_and_missing()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- compile shape --------------------------------------------------------------------

func _test_fixed_and_empty_compile_to_nothing() -> void:
	_section("compile -- fixed and empty routes produce no commands")
	_eq(EventRoute.compile({}).size(), 0, "an empty route dictionary")
	_eq(EventRoute.compile({"mode": "fixed"}).size(), 0, "an explicit 'fixed' mode")
	_eq(EventRoute.compile({"mode": "waypoints", "waypoints": []}).size(), 0,
		"waypoints with an empty list")
	_eq(EventRoute.compile({"mode": "nonsense"}).size(), 0, "an unrecognised mode")
	_ok(EventRoute.is_stationary({}), "is_stationary() agrees for an empty route")
	_ok(EventRoute.is_stationary({"mode": "fixed"}), "is_stationary() agrees for 'fixed'")
	_ok(not EventRoute.is_stationary({"mode": "steps", "steps": ["n"]}),
		"but not for a route with real steps")


func _test_waypoints_compile_shape() -> void:
	_section("compile -- waypoints -> start + one route_move_to per point")
	var route := {
		"mode": "waypoints", "loop": "none", "on_blocked": "skip",
		"waypoints": [{"cell": [1, 0, 0]}, {"cell": [2, 0, 0]}],
	}
	var nodes := EventRoute.compile(route)
	var by_id := _index(nodes)

	_eq(nodes.size(), 3, "start plus two waypoints")
	_ok(by_id.has("start") and str(by_id["start"]["command"]) == EventCommand.START_COMMAND,
		"the first node is 'start'")
	var moves := _filter_command(nodes, "route_move_to")
	_eq(moves.size(), 2, "two route_move_to nodes")
	_eq(Vector3i(moves[0]["args"]["cell"]), Vector3i(1, 0, 0), "the first targets (1,0,0)")
	_eq(Vector3i(moves[1]["args"]["cell"]), Vector3i(2, 0, 0), "the second targets (2,0,0)")


func _test_waypoints_loop_none_has_no_wraparound() -> void:
	_section("compile -- waypoints, loop 'none' -- the last node has no 'next'")
	var nodes := EventRoute.compile({
		"mode": "waypoints", "loop": "none",
		"waypoints": [{"cell": [1, 0, 0]}, {"cell": [2, 0, 0]}],
	})
	var moves := _filter_command(nodes, "route_move_to")
	_eq(_flow_target(moves[1], "next"), "", "the final waypoint's 'next' is unwired")


func _test_waypoints_loop_cycle_wraps_to_start() -> void:
	_section("compile -- waypoints, loop 'cycle' -- the last node's 'next' targets the first")
	var nodes := EventRoute.compile({
		"mode": "waypoints", "loop": "cycle",
		"waypoints": [{"cell": [1, 0, 0]}, {"cell": [2, 0, 0]}],
	})
	var moves := _filter_command(nodes, "route_move_to")
	_eq(_flow_target(moves[1], "next"), str(moves[0]["id"]),
		"wraps back to the first waypoint")


func _test_waypoints_pingpong_bounces() -> void:
	_section("compile -- waypoints, loop 'pingpong' -- forward plus the reversed middle")
	var nodes := EventRoute.compile({
		"mode": "waypoints", "loop": "pingpong",
		"waypoints": [{"cell": [0, 0, 0]}, {"cell": [1, 0, 0]}, {"cell": [2, 0, 0]}],
	})
	var moves := _filter_command(nodes, "route_move_to")
	# A, B, C, B - then wraps to A: A,B,C,B,A,B,C,B,... never doubling an endpoint.
	_eq(moves.size(), 4, "A, B, C, and B again")
	var cells: Array[Vector3i] = []
	for m in moves:
		cells.append(Vector3i(m["args"]["cell"]))
	_eq(cells, [Vector3i(0, 0, 0), Vector3i(1, 0, 0), Vector3i(2, 0, 0), Vector3i(1, 0, 0)],
		"A, B, C, B in that order")
	_eq(_flow_target(moves[3], "next"), str(moves[0]["id"]), "and wraps back to A")


func _test_steps_compile_shape_and_face_wait() -> void:
	_section("compile -- steps -- direction tokens, plus 'wait' and 'face' entries")
	var nodes := EventRoute.compile({
		"mode": "steps", "loop": "none", "on_blocked": "skip",
		"steps": ["n", "n", {"wait": 1.5}, "e", {"face": "s"}],
	})
	var commands: Array[String] = []
	for n in nodes:
		commands.append(str(n["command"]))
	_eq(commands, ["start", "route_step", "route_step", "wait", "route_step", "face_direction"],
		"one node per token, in order")
	var wait_node := nodes[3]
	_eq(float(wait_node["args"]["seconds"]), 1.5, "the wait carries its seconds")
	var face_node := nodes[5]
	_eq(str(face_node["args"]["direction"]), "s", "the face carries its direction")


func _test_steps_pingpong_inverts_directions() -> void:
	_section("compile -- steps, loop 'pingpong' -- the return leg inverts each direction")
	var nodes := EventRoute.compile({
		"mode": "steps", "loop": "pingpong", "steps": ["n", "n", "e"],
	})
	var moves := _filter_command(nodes, "route_step")
	var dirs: Array[String] = []
	for m in moves:
		dirs.append(str(m["args"]["direction"]))
	_eq(dirs, ["n", "n", "e", "w", "s", "s"], "forward, then the inverted reverse")
	_eq(_flow_target(moves[5], "next"), str(moves[0]["id"]), "and wraps back to the start")


func _test_seek_modes_compile_shape() -> void:
	_section("compile -- toward/away/random -- a single self-looping node")
	for mode in ["toward", "away", "random"]:
		var nodes := EventRoute.compile({"mode": mode, "on_blocked": "wait"})
		var moves := _filter_command(nodes, "route_seek")
		_eq(moves.size(), 1, "'%s' compiles to one route_seek node" % mode)
		_eq(str(moves[0]["args"]["mode"]), mode, "carrying its own mode")
		_eq(_flow_target(moves[0], "next"), str(moves[0]["id"]), "looping on itself")


func _test_seek_reverse_compiles_a_flip_pair() -> void:
	_section("compile -- toward with on_blocked 'reverse' -- a toward/away pair that flips")
	var nodes := EventRoute.compile({"mode": "toward", "on_blocked": "reverse"})
	var by_id := _index(nodes)
	var moves := _filter_command(nodes, "route_seek")
	_eq(moves.size(), 2, "two route_seek nodes")
	_eq(str(moves[0]["args"]["mode"]), "toward", "the first is toward")
	_eq(str(moves[1]["args"]["mode"]), "away", "the second is away")

	# Paced through a wait node (RETRY_DELAY), same as any other "blocked" port - see
	# EventRoute._paced. Follow it one hop to confirm it still flips to the other mode.
	var after_a: Dictionary = by_id[_flow_target(moves[0], "blocked")]
	var after_b: Dictionary = by_id[_flow_target(moves[1], "blocked")]
	_eq(str(after_a["command"]), "wait", "toward's block is paced")
	_eq(_flow_target(after_a, "next"), str(moves[1]["id"]), "then flips to away")
	_eq(str(after_b["command"]), "wait", "away's block is paced")
	_eq(_flow_target(after_b, "next"), str(moves[0]["id"]), "then flips back to toward")


# -- on_blocked wiring ------------------------------------------------------------------

func _test_on_blocked_wait_loops_on_itself() -> void:
	_section("compile -- on_blocked 'wait' -- 'blocked' retries through a paced wait")
	var nodes := EventRoute.compile({
		"mode": "steps", "on_blocked": "wait", "steps": ["n", "e"],
	})
	var by_id := _index(nodes)
	var moves := _filter_command(nodes, "route_step")

	var retry_id_0 := _flow_target(moves[0], "blocked")
	_ok(retry_id_0 != str(moves[0]["id"]), "the first node does not retry on the same tick")
	_eq(str(by_id[retry_id_0]["command"]), "wait", "instead through a wait node")
	_eq(_flow_target(by_id[retry_id_0], "next"), str(moves[0]["id"]),
		"which then leads back to the same step")

	var retry_id_1 := _flow_target(moves[1], "blocked")
	_eq(str(by_id[retry_id_1]["command"]), "wait", "the second node is paced the same way")
	_eq(_flow_target(by_id[retry_id_1], "next"), str(moves[1]["id"]), "back to itself")


func _test_on_blocked_skip_matches_next() -> void:
	_section("compile -- on_blocked 'skip' -- 'blocked' targets whatever 'next' targets")
	var nodes := EventRoute.compile({
		"mode": "steps", "on_blocked": "skip", "steps": ["n", "e"],
	})
	var moves := _filter_command(nodes, "route_step")
	_eq(_flow_target(moves[0], "blocked"), _flow_target(moves[0], "next"),
		"a blocked first step still advances")


func _test_on_blocked_reverse_targets_previous_move() -> void:
	_section("compile -- on_blocked 'reverse' -- 'blocked' targets the previous move node")
	var nodes := EventRoute.compile({
		"mode": "steps", "on_blocked": "reverse", "steps": ["n", "n", "e"],
	})
	var moves := _filter_command(nodes, "route_step")
	_eq(_flow_target(moves[0], "blocked"), str(moves[0]["id"]),
		"the first move has nowhere to reverse to, so it retries itself")
	_eq(_flow_target(moves[1], "blocked"), str(moves[0]["id"]), "the second reverses to the first")
	_eq(_flow_target(moves[2], "blocked"), str(moves[1]["id"]), "the third reverses to the second")


func _test_on_blocked_repath_warns_and_skips() -> void:
	_section("compile -- on_blocked 'repath' -- no pathfinder yet, behaves like 'skip'")
	var nodes := EventRoute.compile({
		"mode": "steps", "on_blocked": "repath", "steps": ["n", "e"],
	})
	var moves := _filter_command(nodes, "route_step")
	_eq(_flow_target(moves[0], "blocked"), _flow_target(moves[0], "next"),
		"falls back to the 'skip' wiring")
	_eq(_flow_target(moves[1], "blocked"), _flow_target(moves[1], "next"),
		"including '' for the route's own last node")


# -- driving an actual actor -----------------------------------------------------------

func _test_waypoints_drives_an_actor_to_the_end() -> void:
	_section("runtime -- a compiled waypoints route walks the actor to the last point")
	GameState.clear()
	var rig := _build_rig()
	var guard: Actor = rig["guard"]

	var nodes := EventRoute.compile({
		"mode": "waypoints", "loop": "none",
		"waypoints": [{"cell": [1, 0, 0]}, {"cell": [1, 0, 1]}],
	})
	var runner := EventRunner.new(EventContext.for_event(rig["ctx"], &"m", &"e", guard))
	runner.begin(nodes)
	_pump(runner)

	_ok(runner.finished, "the runner finishes")
	_eq(guard.cell(), Vector3i(1, 0, 1), "and the guard ends on the last waypoint")


## Not a live drive of the actual infinite pingpong wraparound - a viewless test actor's
## grid step settles synchronously (event_runner_test.gd's own class doc), so a
## genuinely endless compiled loop with nothing to pace it hits
## [constant EventRunner.NODE_BUDGET] inside a single [method EventRunner.begin] call
## the same way a real `goto` cycle would - there is no real per-frame animation time
## to space the iterations out the way a live game has. [method
## _test_waypoints_pingpong_bounces] above already proves the wraparound wiring itself
## is correct (A, B, C, B, then back to A); this proves the *execution* of that same
## shape - out and back - by compiling the two-lap sequence directly with `loop: "none"`
## instead of relying on the wrap.
func _test_pingpong_actually_reverses_at_both_ends() -> void:
	_section("runtime -- the shape pingpong compiles to actually walks out and back")
	GameState.clear()
	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	var start_cell := guard.cell()

	var nodes := EventRoute.compile({
		"mode": "steps", "loop": "none", "on_blocked": "wait",
		"steps": ["n", "n", "s", "s", "n", "n"],
	})
	var runner := EventRunner.new(EventContext.for_event(rig["ctx"], &"m", &"e", guard))
	runner.begin(nodes)
	_pump(runner)

	_ok(runner.finished, "the runner finishes")
	_eq(guard.cell(), start_cell + Vector3i(0, 0, -2), "ending back at the far point")


func _test_on_blocked_wait_holds_until_unblocked() -> void:
	_section("runtime -- on_blocked 'wait' holds at the wall until it clears")
	GameState.clear()
	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	var blocker: Actor = _build_actor(rig["root"], &"blocker", guard.cell() + Vector3i(1, 0, 0),
		rig["ctx"])

	var nodes := EventRoute.compile({
		"mode": "steps", "on_blocked": "wait", "steps": ["e", "e"],
	})
	var runner := EventRunner.new(EventContext.for_event(rig["ctx"], &"m", &"e", guard))
	runner.begin(nodes)
	_pump(runner, 30)

	_ok(not runner.finished, "still blocked - the runner has not finished")
	_eq(guard.cell(), Vector3i(0, 0, 0), "the guard has not moved off its spawn cell")

	blocker.motion().move_to(blocker.cell() + Vector3i(0, 0, -5))
	_pump(runner, 600)
	_ok(runner.finished, "once the way clears, the route completes")
	_eq(guard.cell(), Vector3i(2, 0, 0), "and the guard reaches its second step")


func _test_on_blocked_skip_advances_past_a_blocked_waypoint() -> void:
	_section("runtime -- on_blocked 'skip' treats a refused step as done and moves on")
	GameState.clear()
	var rig := _build_rig()
	var guard: Actor = rig["guard"]
	_build_actor(rig["root"], &"blocker", guard.cell() + Vector3i(1, 0, 0), rig["ctx"])

	var nodes := EventRoute.compile({
		"mode": "steps", "on_blocked": "skip", "steps": ["e", "n"],
	})
	var runner := EventRunner.new(EventContext.for_event(rig["ctx"], &"m", &"e", guard))
	runner.begin(nodes)
	_pump(runner)

	_ok(runner.finished, "the runner finishes rather than waiting forever")
	_eq(guard.cell(), Vector3i(0, 0, -1), "the blocked east step is skipped; only 'n' lands")


func _test_steps_same_shape_from_two_spawns() -> void:
	_section("runtime -- a steps route produces the same relative shape from two spawns")
	GameState.clear()
	var route := {"mode": "steps", "on_blocked": "wait", "steps": ["n", "n", "e"]}

	var rig_a := _build_rig(Vector3i(0, 0, 0))
	var runner_a := EventRunner.new(
		EventContext.for_event(rig_a["ctx"], &"m", &"e", rig_a["guard"]))
	runner_a.begin(EventRoute.compile(route))
	_pump(runner_a)

	var rig_b := _build_rig(Vector3i(5, 0, 5))
	var runner_b := EventRunner.new(
		EventContext.for_event(rig_b["ctx"], &"m", &"e", rig_b["guard"]))
	runner_b.begin(EventRoute.compile(route))
	_pump(runner_b)

	var delta_a: Vector3i = rig_a["guard"].cell() - Vector3i(0, 0, 0)
	var delta_b: Vector3i = rig_b["guard"].cell() - Vector3i(5, 0, 5)
	_eq(delta_a, delta_b, "the same displacement regardless of spawn cell")


## The player actor a compiled 'toward' route chases is itself occupancy-blocking, so
## the chase closes to one cell short and then paces its own "blocked" retry
## ([constant EventRoute.RETRY_DELAY]) rather than spinning - a single
## [method EventRunner.begin] call already walks the whole approach and stops there,
## with no need to pump further ticks to observe it.
func _test_toward_walks_the_actor_at_the_target() -> void:
	_section("runtime -- 'toward' recomputes direction live and closes the distance")
	GameState.clear()
	var rig := _build_rig(Vector3i(0, 0, 0))
	var guard: Actor = rig["guard"]
	# rig's own second actor is "player", three cells east - see _build_rig.

	var nodes := EventRoute.compile({"mode": "toward", "target": "@player", "on_blocked": "wait"})
	var runner := EventRunner.new(EventContext.for_event(rig["ctx"], &"m", &"e", guard))
	runner.begin(nodes)

	_ok(not runner.finished, "still running - paced against the player's own occupied cell")
	_eq(guard.cell(), Vector3i(2, 0, 0), "two steps east, stopped just short of the player")


# -- shared routes ----------------------------------------------------------------------

func _test_shared_route_resolves() -> void:
	_section("resolve -- a {use: name} reference reads res://events/routes/<name>.route.json")
	var route := EventRoute.resolve({"use": "patrol_ns"})
	_eq(str(route.get("mode", "")), "steps", "the template's mode carries over")
	_eq((route.get("steps", []) as Array), ["n", "n"], "and its steps")
	_ok(not EventRoute.compile(route).is_empty(), "and it compiles to real commands")


func _test_shared_route_override_and_missing() -> void:
	_section("resolve -- speed/loop override at the reference site; a missing route errors")
	var overridden := EventRoute.resolve({"use": "patrol_ns", "speed": 5.0, "loop": "cycle"})
	_eq(float(overridden["speed"]), 5.0, "speed is overridden")
	_eq(str(overridden["loop"]), "cycle", "loop is overridden")
	_eq((overridden.get("steps", []) as Array), ["n", "n"], "steps are still the template's own")

	var missing := EventRoute.resolve({"use": "does_not_exist"})
	_eq(str(missing.get("mode", "")), "fixed", "a missing template falls back to 'fixed'")
	_eq(EventRoute.compile(missing).size(), 0, "which compiles to nothing")


# -- rig ---------------------------------------------------------------------------------

## Same shape as tests/event_runner_test.gd's own rig: one grid MapContext, no floor or
## collision layer (occupancy alone is what a route's on_blocked test needs), a guard at
## [param guard_cell] and a player three cells east of it.
func _build_rig(guard_cell: Vector3i = Vector3i.ZERO) -> Dictionary:
	var root := Node3D.new()
	add_child(root)

	var ctx := MapContext.new()
	ctx.map_id = &"test_map"
	ctx.cell_size = Vector3.ONE
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)

	var guard := _build_actor(root, &"guard", guard_cell, ctx)
	_build_actor(root, &"player", guard_cell + Vector3i(3, 0, 0), ctx)

	return {"root": root, "ctx": ctx, "guard": guard}


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

	# Actor._ready() defers its own spawn-cell claim (call_deferred, since a
	# scene-authored actor already has its children but a hand-built one like this
	# might not yet) - a headless run driven only through EventRunner.tick(), never a
	# real SceneTree frame, has nothing that ever flushes that deferred call. Calling
	# it directly is what makes a second actor's occupied cell actually block anyone.
	actor._claim_spawn_cell()
	return actor


func _pump(runner: EventRunner, max_ticks: int = 600, dt: float = 1.0 / 60.0) -> void:
	var n := 0
	while not runner.finished and n < max_ticks:
		runner.tick(dt)
		n += 1


## Pumps until [param n] more grid cells have been entered (or the runner finishes, or a
## generous tick budget runs out) - for a route with no natural end, where [method _pump]
## would spin until its own budget rather than stopping at a meaningful point.
func _pump_steps(runner: EventRunner, n: int, max_ticks: int = 2000, dt: float = 1.0 / 60.0) -> void:
	var seen := 0
	var last_cell: Vector3i = runner.ctx.self_actor.cell() if runner.ctx.self_actor != null \
		else Vector3i.ZERO
	var t := 0
	while seen < n and t < max_ticks and not runner.finished:
		runner.tick(dt)
		t += 1
		var actor := runner.ctx.self_actor
		if actor != null and actor.cell() != last_cell:
			last_cell = actor.cell()
			seen += 1


# -- small helpers over a compiled node list ---------------------------------------------

func _index(nodes: Array[Dictionary]) -> Dictionary:
	var by_id := {}
	for n in nodes:
		by_id[str(n["id"])] = n
	return by_id


func _filter_command(nodes: Array[Dictionary], command: String) -> Array:
	var out: Array = []
	for n in nodes:
		if str(n["command"]) == command:
			out.append(n)
	return out


func _flow_target(node: Dictionary, flow: String) -> String:
	for output: Variant in node.get("outputs", []) as Array:
		if output is Dictionary and str((output as Dictionary).get("flow", "")) == flow:
			return str((output as Dictionary).get("target", ""))
	return ""


# -- assertion helpers --------------------------------------------------------------------

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
