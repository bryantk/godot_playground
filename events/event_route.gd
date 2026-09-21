class_name EventRoute

## Compiles a page's [code]route[/code] dictionary (event-pages.md §3) into the same
## node-array shape [EventRunner] already walks. A route is not a second execution
## engine (§3.1) - [method compile] is a small code generator that runs once, ahead of
## the ordinary runner, and everything after that is the runtime ordinary pages already
## use: [code]start[/code], [code]move_to[/code]/[code]step[/code]/[code]wait[/code]/
## [code]face_direction[/code], plus the three route-only executors in
## [code]events/commands/route_execs.gd[/code] that give a compiled node a "blocked"
## flow port to hang [code]on_blocked[/code] on.
##
## [b]Scope.[/b] This takes an already-resolved route dictionary - [code]mode[/code],
## [code]loop[/code], [code]on_blocked[/code], [code]speed[/code], and
## [code]waypoints[/code]/[code]steps[/code]/[code]target[/code] as the mode requires.
## A [code]{"use": "name"}[/code] reference is resolved separately, by [method resolve]
## below, before [method compile] ever sees the dictionary - the same "accept shorthand
## at the boundary, normalise immediately" rule §2.1 already applies to pages. Whether a
## page's own route field gets that resolution automatically is [GameEvent]'s wiring,
## not this file's.
##
## [b]`on_blocked`'s four policies, as compiled wiring, not runtime logic:[/b]
##
## - [code]wait[/code]: the "blocked" port goes through one small [constant RETRY_DELAY]
##   `wait` node and back to the same node - retry, but not on the very same tick. A
##   viewless test actor's grid step settles synchronously (event_runner_test.gd's own
##   class doc), so a same-tick retry against a wall that never moves is
##   indistinguishable from a `goto` cycle and trips [constant EventRunner.NODE_BUDGET]
##   in one [method EventRunner.begin] call - the interstitial wait is what makes "hold
##   here until it clears" an actual hold rather than an instant, budget-exhausting spin.
## - [code]skip[/code]: "blocked" is wired to whatever "next" already targets (including
##   nothing, for a route's own last node), so a refused step or waypoint is treated as
##   if it had happened.
## - [code]reverse[/code]: "blocked" is wired to the previous move node in the sequence
##   (the first move node has nowhere to reverse to, and loops on itself instead). For
##   `toward`/`away`, which have no "previous node" at all, this instead compiles both
##   directions as a two-node pair and has each one's "blocked" port flip to the other -
##   a wall in the way of the chase becomes the one moment the monster tries retreating.
## - [code]repath[/code]: no A* exists yet for an actor to path around a block
##   (`move_to`'s own `path: "astar"` is the same accepted-but-unbuilt gap,
##   next-session.md's "known gaps" list) - treated as `skip`, with a warning, rather
##   than silently behaving as `wait` forever.
##
## [b]`toward`/`away`/`random` are always paced through the same [constant RETRY_DELAY]
## wait[/b] on "blocked", regardless of `on_blocked` - reaching the target (nothing left
## to close the distance with) reads as "blocked" the same way a wall does, and a static
## target sits there forever exactly like a wall does. Without the pause, a chase that
## catches its target would spin the same way an unpaced `wait` policy would.
##
## [b]`pingpong` is expanded before compiling[/b], not handled as runtime state: a
## waypoint list becomes forward + its own reversed middle, wired as a cycle, so
## A,B,C bounces A,B,C,B,A,B,C,... with no separate "which way am I going" flag for a
## save to lose track of. A `steps` list mirrors the same way, with each directional
## token inverted (n<->s, e<->w) on the return leg.


## The pause a paced "blocked" retry waits before trying again - see the class doc's
## note on `wait` and on `toward`/`away`/`random`. Short enough that a patrol resumes
## within a fraction of a second of a wall clearing, long enough that it is nowhere
## near [constant EventRunner.NODE_BUDGET] worth of retries per real second.
const RETRY_DELAY := 0.25


## True while [param route] is empty or explicitly [code]"fixed"[/code] - "never
## moves" (event-pages.md §3), which is not the same as an empty compiled command list
## for any other reason (a malformed route also compiles to []).
static func is_stationary(route: Dictionary) -> bool:
	return route.is_empty() or str(route.get("mode", "fixed")) == "fixed"


## Resolves a [code]{"use": "<name>"}[/code] reference against
## [code]res://events/routes/<name>.route.json[/code] (event-pages.md §3.2).
## [code]mode[/code]/[code]loop[/code]/[code]on_blocked[/code]/[code]speed[/code] may be
## overridden at the reference site; [code]waypoints[/code]/[code]steps[/code] may not -
## a page either uses the template's list whole or authors its own inline, never a
## partial mix with no readable meaning. A route with no [code]use[/code] key passes
## through unchanged.
static func resolve(route: Dictionary) -> Dictionary:
	if not route.has("use"):
		return route

	var route_name := str(route["use"])
	var path := "res://events/routes/%s.route.json" % route_name
	if not FileAccess.file_exists(path):
		push_error("EventRoute: shared route '%s' not found at %s." % [route_name, path])
		return {"mode": "fixed"}

	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_error("EventRoute: shared route '%s' is not a valid route document." % route_name)
		return {"mode": "fixed"}

	var merged: Dictionary = (parsed as Dictionary).duplicate(true)
	for key in ["mode", "loop", "on_blocked", "speed"]:
		if route.has(key):
			merged[key] = route[key]
	return merged


## The compiled command stream, ready for [method EventRunner.begin] - empty for
## [code]"fixed"[/code], an empty move list, or an unrecognised mode (reported, not
## thrown - this file's own version of event_command.gd's repair-and-report rule).
static func compile(route: Dictionary) -> Array[Dictionary]:
	var mode := str(route.get("mode", "fixed"))
	var loop := str(route.get("loop", "none"))
	var on_blocked := str(route.get("on_blocked", "wait"))
	var speed: Variant = route.get("speed")

	var body: Array[Dictionary] = []
	match mode:
		"fixed":
			return []
		"waypoints":
			body = _compile_waypoints(route.get("waypoints", []), loop, on_blocked, speed)
		"steps":
			body = _compile_steps(route.get("steps", []), loop, on_blocked, speed)
		"toward":
			body = _compile_seek("toward", str(route.get("target", "@player")), on_blocked, speed)
		"away":
			body = _compile_seek("away", str(route.get("target", "@player")), on_blocked, speed)
		"random":
			body = _compile_seek("random", "", on_blocked, speed)
		_:
			push_warning("EventRoute: unknown mode '%s'." % mode)
			return []

	if body.is_empty():
		return []

	var start_node := _node("start", EventCommand.START_COMMAND, {})
	_add_output(start_node, "next", str(body[0].get("id", "")))
	var out: Array[Dictionary] = [start_node]
	out.append_array(body)
	return out


# -- waypoints ----------------------------------------------------------------------

static func _compile_waypoints(waypoints_in: Array, loop: String, on_blocked: String,
		speed: Variant) -> Array[Dictionary]:
	if waypoints_in.is_empty():
		return []

	var points := _mirrored_waypoints(waypoints_in, loop)
	var nodes: Array[Dictionary] = []
	var by_id: Dictionary = {}
	var move_ids: Array[String] = []
	var first_id := ""
	var prev_terminal := ""

	for point_v: Variant in points:
		var point: Dictionary = point_v
		var move_id := _next_id(nodes)
		var move_args := {"cell": _cell_of(point.get("cell", Vector3i.ZERO))}
		if speed != null:
			move_args["speed"] = float(speed)
		var move_node := _node(move_id, "route_move_to", move_args)
		nodes.append(move_node)
		by_id[move_id] = move_node
		move_ids.append(move_id)
		if first_id == "":
			first_id = move_id
		if prev_terminal != "":
			_wire_next(by_id, prev_terminal, move_id)

		var terminal := move_id
		if point.has("face"):
			var face_id := _next_id(nodes)
			var face_node := _node(face_id, "face_direction", {"direction": point["face"]})
			nodes.append(face_node)
			by_id[face_id] = face_node
			_wire_next(by_id, terminal, face_id)
			terminal = face_id
		if point.has("wait"):
			var wait_id := _next_id(nodes)
			var wait_node := _node(wait_id, "wait", {"seconds": float(point["wait"])})
			nodes.append(wait_node)
			by_id[wait_id] = wait_node
			_wire_next(by_id, terminal, wait_id)
			terminal = wait_id

		prev_terminal = terminal

	if loop == "cycle" or loop == "pingpong":
		_wire_next(by_id, prev_terminal, first_id)

	_wire_on_blocked(nodes, by_id, move_ids, on_blocked)
	return nodes


static func _mirrored_waypoints(waypoints_in: Array, loop: String) -> Array:
	if loop != "pingpong" or waypoints_in.size() <= 2:
		return waypoints_in.duplicate()
	var middle := waypoints_in.slice(1, waypoints_in.size() - 1)
	middle.reverse()
	var out := waypoints_in.duplicate()
	out.append_array(middle)
	return out


# -- steps ----------------------------------------------------------------------------

static func _compile_steps(steps_in: Array, loop: String, on_blocked: String,
		speed: Variant) -> Array[Dictionary]:
	if steps_in.is_empty():
		return []

	var tokens := _mirrored_steps(steps_in, loop)
	var nodes: Array[Dictionary] = []
	var by_id: Dictionary = {}
	var move_ids: Array[String] = []
	var first_id := ""
	var prev_id := ""

	# Unlike a waypoint's own route_move_to, "step" carries no per-node speed arg
	# (event_command.gd's own "step" definition has none either) - a route's speed
	# is the actor's persistent MotionController.speed, set once before the first step.
	if speed != null:
		var speed_id := _next_id(nodes)
		var speed_node := _node(speed_id, "set_speed", {"speed": float(speed)})
		nodes.append(speed_node)
		by_id[speed_id] = speed_node
		first_id = speed_id
		prev_id = speed_id

	for token_v: Variant in tokens:
		var node_id := _next_id(nodes)
		var node: Dictionary
		var is_move := false

		if token_v is Dictionary:
			var d: Dictionary = token_v
			if d.has("wait"):
				node = _node(node_id, "wait", {"seconds": float(d["wait"])})
			elif d.has("face"):
				node = _node(node_id, "face_direction", {"direction": d["face"]})
			else:
				push_warning("EventRoute: unrecognised steps entry %s." % d)
				continue
		else:
			var move_args := {"direction": str(token_v)}
			node = _node(node_id, "route_step", move_args)
			is_move = true

		nodes.append(node)
		by_id[node_id] = node
		if is_move:
			move_ids.append(node_id)
		if first_id == "":
			first_id = node_id
		if prev_id != "":
			_wire_next(by_id, prev_id, node_id)
		prev_id = node_id

	if loop == "cycle" or loop == "pingpong":
		_wire_next(by_id, prev_id, first_id)

	_wire_on_blocked(nodes, by_id, move_ids, on_blocked)
	return nodes


static func _invert_step_token(token: String) -> String:
	match token:
		"n": return "s"
		"s": return "n"
		"e": return "w"
		"w": return "e"
		"ne": return "sw"
		"sw": return "ne"
		"nw": return "se"
		"se": return "nw"
		_: return token


static func _mirrored_steps(steps_in: Array, loop: String) -> Array:
	if loop != "pingpong":
		return steps_in.duplicate()
	var reversed_tokens := steps_in.duplicate()
	reversed_tokens.reverse()
	var mirrored: Array = []
	for t: Variant in reversed_tokens:
		mirrored.append(_invert_step_token(t) if t is String else t)
	var out := steps_in.duplicate()
	out.append_array(mirrored)
	return out


# -- toward / away / random -----------------------------------------------------------

static func _compile_seek(mode: String, target: String, on_blocked: String,
		speed: Variant) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	var by_id: Dictionary = {}

	if on_blocked == "reverse" and mode != "random":
		var opposite := "away" if mode == "toward" else "toward"
		var id_a := _next_id(nodes)
		var node_a := _node(id_a, "route_seek", _seek_args(mode, target, speed))
		nodes.append(node_a)
		by_id[id_a] = node_a
		var id_b := _next_id(nodes)
		var node_b := _node(id_b, "route_seek", _seek_args(opposite, target, speed))
		nodes.append(node_b)
		by_id[id_b] = node_b

		_add_output(node_a, "next", id_a)
		_add_output(node_b, "next", id_b)
		_add_output(node_a, "blocked", _paced(nodes, by_id, id_b))
		_add_output(node_b, "blocked", _paced(nodes, by_id, id_a))
		return nodes

	var id := _next_id(nodes)
	var node := _node(id, "route_seek", _seek_args(mode, target, speed))
	nodes.append(node)
	by_id[id] = node
	_add_output(node, "next", id)

	if on_blocked == "repath":
		push_warning("EventRoute: on_blocked 'repath' has no pathfinder yet - treated as 'skip'.")
	_add_output(node, "blocked", _paced(nodes, by_id, id))
	return nodes


## A [constant RETRY_DELAY] `wait` node inserted between "blocked" and [param target_id],
## returning the wait node's own id - what every seek "blocked" port points to (see the
## class doc), and what a waypoint/step's own `wait` policy points to as well.
static func _paced(nodes: Array[Dictionary], by_id: Dictionary, target_id: String) -> String:
	var wait_id := _next_id(nodes)
	var wait_node := _node(wait_id, "wait", {"seconds": RETRY_DELAY})
	nodes.append(wait_node)
	by_id[wait_id] = wait_node
	_add_output(wait_node, "next", target_id)
	return wait_id


static func _seek_args(mode: String, target: String, speed: Variant) -> Dictionary:
	var out := {"mode": mode}
	if target != "":
		out["target"] = target
	if speed != null:
		out["speed"] = float(speed)
	return out


# -- on_blocked wiring, shared by waypoints and steps ----------------------------------

static func _wire_on_blocked(nodes: Array[Dictionary], by_id: Dictionary,
		move_ids: Array[String], on_blocked: String) -> void:
	if on_blocked == "repath":
		push_warning("EventRoute: on_blocked 'repath' has no pathfinder yet - treated as 'skip'.")

	for i in move_ids.size():
		var move_id := move_ids[i]
		var node: Dictionary = by_id[move_id]

		match on_blocked:
			"skip", "repath":
				# Whatever "next" already targets, including "" for a route's own last
				# node - a block there is a block on the way out, not a retry.
				_add_output(node, "blocked", _next_target(node))
			"reverse":
				_add_output(node, "blocked", move_ids[i - 1] if i > 0 else move_id)
			_:
				# "wait", and the fallback for anything else - see _paced's own doc for
				# why this is not a same-tick self-loop.
				_add_output(node, "blocked", _paced(nodes, by_id, move_id))


# -- node builders ----------------------------------------------------------------------

static func _next_id(nodes: Array) -> String:
	return "r%d" % nodes.size()


static func _node(id: String, command: String, args: Dictionary) -> Dictionary:
	return {"id": id, "command": command, "args": args, "outputs": []}


static func _add_output(node: Dictionary, flow: String, target: String) -> void:
	(node["outputs"] as Array).append({"flow": flow, "target": target})


static func _wire_next(by_id: Dictionary, from_id: String, to_id: String) -> void:
	_add_output(by_id[from_id], "next", to_id)


static func _next_target(node: Dictionary) -> String:
	for output: Variant in node.get("outputs", []) as Array:
		if output is Dictionary and str((output as Dictionary).get("flow", "")) == "next":
			return str((output as Dictionary).get("target", ""))
	return ""


static func _cell_of(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value as Vector3i
	if value is Vector3:
		return Vector3i(value as Vector3)
	if value is Array and (value as Array).size() >= 3:
		var a := value as Array
		return Vector3i(int(a[0]), int(a[1]), int(a[2]))
	push_warning("EventRoute: cannot read '%s' as a cell." % value)
	return Vector3i.ZERO
