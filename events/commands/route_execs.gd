## Executors for the three commands [EventRoute] compiles to and nothing else ever
## authors - [code]route_step[/code], [code]route_move_to[/code], [code]route_seek[/code].
## Each has a second flow port, "blocked" ([method flow_port]), so the compiler can wire
## a page's own [code]on_blocked[/code] policy (wait/skip/reverse/repath, event-pages.md
## §3) as ordinary graph wiring instead of teaching [EventRunner] a new concept.
##
## "Blocked" is read after the fact, not from a signal: each executor remembers the cell
## it meant to land on and compares [method Actor.cell] once its own key resolves, the
## same information [GridMotion]'s own [code]blocked[/code] signal carries, without
## needing this file to connect to it.


## One grid step, direction fixed at compile time (`step_n`, `step_s`, ... - a `steps`
## route entry). See [code]actors/commands/actor_execs.gd[/code]'s own [code]StepCmd[/code],
## which this mirrors exactly apart from [method flow_port].
class RouteStep extends EventCommandExec:
	var _key := ""
	var _target_cell := Vector3i.ZERO

	func start() -> void:
		var a := actor()
		if a == null:
			return
		ctx.mark_actor_touched(a)
		var dir := EventCommand.direction_of(args.get("direction"))
		_target_cell = a.cell() + dir
		var m := a.motion()
		if m is GridMotion:
			_key = (m as GridMotion).step_keyed(dir)
		else:
			m.step(dir)
			_key = ""

	func tick(_delta: float) -> int:
		return Status.DONE if _key == "" or runner.latch.consume(_key) else Status.RUNNING

	func flow_port() -> String:
		var a := actor()
		return "next" if a != null and a.cell() == _target_cell else "blocked"

	func own_key() -> String:
		return _key

	func cancel() -> void:
		var a := actor()
		if a != null:
			a.motion().cancel()

	func resumable() -> bool:
		return true

	func capture() -> Dictionary:
		var a := actor()
		var m := a.motion() if a != null else null
		return {"motion": (m as GridMotion).to_save()} if m is GridMotion else {}

	func restore(state: Dictionary) -> void:
		var a := actor()
		if a == null:
			return
		var m := a.motion()
		if not (m is GridMotion):
			start()
			return
		ctx.mark_actor_touched(a)
		var dir := EventCommand.direction_of(args.get("direction"))
		_target_cell = a.cell() + dir
		var keys := (m as GridMotion).from_save(state.get("motion", {}))
		_key = str(keys.get("step_key", ""))


## One waypoint - `move_to`'s own [code]MoveTo[/code] with a "blocked" port instead of
## silently stopping short (`on_blocked`, event-pages.md §3).
class RouteMoveTo extends EventCommandExec:
	var _key := ""
	var _target_cell := Vector3i.ZERO

	func start() -> void:
		var a := actor()
		if a == null:
			return
		ctx.mark_actor_touched(a)
		_target_cell = Vector3i(args.get("cell", Vector3i.ZERO))
		var opts := {}
		if args.has("speed"):
			opts["speed"] = args["speed"]
		_key = a.motion().move_to(_target_cell, opts)

	func tick(_delta: float) -> int:
		return Status.DONE if _key == "" or runner.latch.consume(_key) else Status.RUNNING

	func flow_port() -> String:
		var a := actor()
		return "next" if a != null and a.cell() == _target_cell else "blocked"

	func own_key() -> String:
		return _key

	func cancel() -> void:
		var a := actor()
		if a != null:
			a.motion().cancel()

	func resumable() -> bool:
		return true

	func capture() -> Dictionary:
		var a := actor()
		var m := a.motion() if a != null else null
		return {"motion": (m as GridMotion).to_save()} if m is GridMotion else {}

	func restore(state: Dictionary) -> void:
		var a := actor()
		if a == null:
			return
		var m := a.motion()
		if not (m is GridMotion):
			start()
			return
		ctx.mark_actor_touched(a)
		_target_cell = Vector3i(args.get("cell", Vector3i.ZERO))
		var keys := (m as GridMotion).from_save(state.get("motion", {}))
		_key = str(keys.get("route_key", ""))


## `toward`/`away`/`random` (event-pages.md §3) - the one command whose direction is
## read live, on every [method start], rather than baked in at compile time: "toward
## becomes a move_to recomputed each pulse" (stage-c-plan.md segment 7). [EventRoute]
## wires this node's own "next" back to itself, so a fresh direction is chosen every
## time the loop comes back around.
##
## [b]Deliberately RESUME_RESTART.[/b] A capture would only ever be a single cell's
## worth of progress toward a target that has likely already moved again by the time a
## save is loaded - recomputing fresh on restart is not a compromise here the way it
## would be for an authored `move_to`, it is the more correct behaviour.
class RouteSeek extends EventCommandExec:
	var _key := ""
	var _target_cell := Vector3i.ZERO
	var _did_move := false

	const _CARDINALS: Array[Vector3i] = [
		Vector3i(0, 0, -1), Vector3i(0, 0, 1), Vector3i(-1, 0, 0), Vector3i(1, 0, 0),
	]

	func start() -> void:
		_did_move = false
		var a := actor()
		if a == null:
			return
		var dir := _pick_direction(a, str(args.get("mode", "random")))
		if dir == Vector3i.ZERO:
			_key = ""
			return
		ctx.mark_actor_touched(a)
		_target_cell = a.cell() + dir
		_did_move = true
		var m := a.motion()
		if m is GridMotion:
			_key = (m as GridMotion).step_keyed(dir)
		else:
			m.step(dir)
			_key = ""

	func tick(_delta: float) -> int:
		return Status.DONE if _key == "" or runner.latch.consume(_key) else Status.RUNNING

	func flow_port() -> String:
		if not _did_move:
			return "blocked"
		var a := actor()
		return "next" if a != null and a.cell() == _target_cell else "blocked"

	func own_key() -> String:
		return _key

	## `toward`/`away` collapse to a single cardinal step along whichever axis has the
	## larger gap, x before z on a tie - the same "pick one axis" rule facing-toward
	## commands elsewhere in this codebase use, rather than a diagonal a 4-direction
	## actor cannot face.
	func _pick_direction(a: Actor, mode: String) -> Vector3i:
		match mode:
			"toward", "away":
				var target := ctx.resolve(str(args.get("target", "@player")))
				if target == null:
					return Vector3i.ZERO
				var delta := target.cell() - a.cell()
				if delta == Vector3i.ZERO:
					return Vector3i.ZERO
				var dir: Vector3i
				if abs(delta.x) >= abs(delta.z):
					dir = Vector3i(int(sign(delta.x)), 0, 0)
				else:
					dir = Vector3i(0, 0, int(sign(delta.z)))
				return dir if mode == "toward" else -dir
			"random":
				return _CARDINALS[randi() % _CARDINALS.size()]
			_:
				return Vector3i.ZERO


static func table() -> Dictionary:
	return {
		"route_step": RouteStep,
		"route_move_to": RouteMoveTo,
		"route_seek": RouteSeek,
	}
