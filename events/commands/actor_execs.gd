## Actor-motion executors. Every one resolves its actor via [method
## EventCommandExec.actor] (args.actor, defaulting to @self) and drives
## [method Actor.motion] - never a controller subclass directly, so a page authored
## against a grid actor keeps working if that actor is later given [FreeMotion].
##
## Each also calls [method EventContext.mark_actor_touched] once it actually commits to
## moving or turning the actor - a no-op unless that actor is this run's own [code]@self[/code],
## which is what [GameEvent] reads afterward to decide whether a facing it captured
## before the interaction should be restored (a graph that faced or moved its own actor
## on purpose is left as is).
##
## [code]follow[/code] has no executor yet: it is background and continuous, and
## nothing to suspend it against a lease exists before segment 6/7's scheduler policy.


## Walks to a cell. Blocking, RESUME_STATE - backed by [method GridMotion.to_save]/
## [method GridMotion.from_save] (segment 5b) when the actor is a grid one; a
## [FreeMotion] actor has no mid-flight capture yet, so it restarts instead (a legal
## downgrade, question 39).
class MoveTo extends EventCommandExec:
	var _key := ""
	## Where this move meant to land - a teleport ("path": "raw") always lands exactly
	## here, so [method was_blocked] never trips for one; an ordinary move that stopped
	## short is what it exists to catch, for [code]define_route[/code]'s own benefit
	## (see event_command_exec.gd's own doc on it).
	var _target_cell := Vector3i.ZERO

	func start() -> void:
		var a := actor()
		if a == null:
			return
		ctx.mark_actor_touched(a)
		var opts := {}
		if args.has("speed"):
			opts["speed"] = args["speed"]
		if args.has("path"):
			opts["path"] = args["path"]
		_target_cell = Vector3i(args.get("cell", Vector3i.ZERO))
		_key = a.motion().move_to(_target_cell, opts)

	func tick(_delta: float) -> int:
		return Status.DONE if _key == "" or runner.latch.consume(_key) else Status.RUNNING

	func was_blocked() -> bool:
		var a := actor()
		return a != null and a.cell() != _target_cell

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


## Walks a relative number of cells - the same executor as [code]move_to[/code], since
## [method MotionController.move_by] is [code]move_to(cell() + delta)[/code].
class MoveBy extends EventCommandExec:
	var _key := ""
	## See [member MoveTo._target_cell] - the same idea, relative to wherever the actor
	## stood at [method start] rather than an absolute cell.
	var _target_cell := Vector3i.ZERO

	func start() -> void:
		var a := actor()
		if a == null:
			return
		ctx.mark_actor_touched(a)
		var opts := {}
		if args.has("speed"):
			opts["speed"] = args["speed"]
		if args.has("path"):
			opts["path"] = args["path"]
		var delta := Vector3i(args.get("cells", Vector3i.ZERO))
		_target_cell = a.cell() + delta
		_key = a.motion().move_by(delta, opts)

	func tick(_delta: float) -> int:
		return Status.DONE if _key == "" or runner.latch.consume(_key) else Status.RUNNING

	func was_blocked() -> bool:
		var a := actor()
		return a != null and a.cell() != _target_cell

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
		var out := {"motion": (m as GridMotion).to_save()} if m is GridMotion else {}
		# _target_cell is relative to wherever the actor stood when this move started,
		# not to wherever it happens to be now - which a mid-flight capture (a route
		# preempted by a triggered graph, then resumed) already is not the same cell.
		# Captured explicitly rather than recomputed from args at restore time, or
		# was_blocked() would compare against a target shifted by however much of this
		# move had already committed before the interruption, reading a move that in
		# fact finished exactly where it meant to as blocked anyway.
		out["target_cell"] = [_target_cell.x, _target_cell.y, _target_cell.z]
		return out

	func restore(state: Dictionary) -> void:
		var a := actor()
		if a == null:
			return
		var m := a.motion()
		if not (m is GridMotion):
			start()
			return
		ctx.mark_actor_touched(a)
		_target_cell = saved_cell_or(state.get("target_cell"),
			a.cell() + Vector3i(args.get("cells", Vector3i.ZERO)))
		var keys := (m as GridMotion).from_save(state.get("motion", {}))
		_key = str(keys.get("route_key", ""))


## One grid cell in a direction - question 40's defect (a): [method GridMotion.step]
## returns a bare bool, so this reaches for [method GridMotion.step_keyed] where the
## motion actually is a [GridMotion], and falls back to the bare call (no key to join)
## on [FreeMotion], where a "step" is just a nudge to intent.
class StepCmd extends EventCommandExec:
	var _key := ""
	## See [member MoveBy._target_cell] - meaningful for a grid actor, which is the only
	## kind this command declares itself for ([code]SPACE_GRID[/code]).
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

	func was_blocked() -> bool:
		var a := actor()
		return a != null and a.cell() != _target_cell

	func own_key() -> String:
		return _key

	func resumable() -> bool:
		return true

	func capture() -> Dictionary:
		var a := actor()
		var m := a.motion() if a != null else null
		var out := {"motion": (m as GridMotion).to_save()} if m is GridMotion else {}
		# See MoveBy.capture()'s own comment - the identical reasoning one direction
		# token over.
		out["target_cell"] = [_target_cell.x, _target_cell.y, _target_cell.z]
		return out

	func restore(state: Dictionary) -> void:
		var a := actor()
		if a == null:
			return
		var m := a.motion()
		if not (m is GridMotion):
			start()
			return
		ctx.mark_actor_touched(a)
		_target_cell = saved_cell_or(state.get("target_cell"),
			a.cell() + EventCommand.direction_of(args.get("direction")))
		var keys := (m as GridMotion).from_save(state.get("motion", {}))
		_key = str(keys.get("step_key", ""))


## Turns to face a direction or a relative turn (question 41) - resolved against the
## actor's own facing count, so `turn_cw` lands on a facing that actor actually has art
## for. Completes in the tick it starts (RESUME_RESTART): a turn is instantaneous.
class FaceDirection extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a == null:
			return
		ctx.mark_actor_touched(a)
		var count: int = a.facing_count
		var m := a.motion()
		if m is GridMotion:
			count = (m as GridMotion).direction_count
		var dir := EventCommand.resolve_turn(args.get("direction"), a.facing(), count)
		if dir != Vector3i.ZERO:
			m.face(dir)


## Turns to face another actor's cell.
class FaceTo extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a == null:
			return
		var target := ctx.resolve(str(args.get("target", "")))
		if target == null:
			return
		var delta := Vector3(target.cell() - a.cell())
		if delta.length_squared() > 0.0001:
			ctx.mark_actor_touched(a)
			a.motion().face(Space.quantise(delta, a.facing_count))


## Jump - dead in a grid game except a ladder release (question 38); real in free
## motion. [code]toward[/code] is accepted by the schema and not read here yet - no
## caller needs an aimed jump before [FreeMotion]'s own steering exists to aim one.
class JumpCmd extends EventCommandExec:
	var _key := ""

	func start() -> void:
		var a := actor()
		if a == null:
			return
		ctx.mark_actor_touched(a)
		_key = a.motion().jump(float(args.get("strength", -1.0)))

	func tick(_delta: float) -> int:
		return Status.DONE if _key == "" or runner.latch.consume(_key) else Status.RUNNING

	func own_key() -> String:
		return _key

	func cancel() -> void:
		var a := actor()
		if a != null:
			a.motion().cancel()

	## Grid only: the one case a grid game's [code]jump[/code] has - a ladder release,
	## paid out as a fall chain [method GridMotion.to_save] already captures. [FreeMotion]'s
	## own real jump has no mid-flight capture yet, so it restarts.
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
		var keys := (m as GridMotion).from_save(state.get("motion", {}))
		_key = str(keys.get("fall_key", ""))


## Instant, no animation - [code]path: "raw"[/code] on [method MotionController.move_to],
## which lands on an occupied cell rather than silently refusing (question 34).
class TeleportCmd extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a == null:
			return
		ctx.mark_actor_touched(a)
		a.motion().move_to(Vector3i(args.get("cell", Vector3i.ZERO)), {"path": "raw"})


## Pauses until the actor is no longer mid-step - the land-on-it moment, joining
## [signal EventBus.actor_settled] indirectly through [method Actor.is_moving].
class WaitSettle extends EventCommandExec:
	func tick(_delta: float) -> int:
		var a := actor()
		return Status.DONE if a == null or not a.is_moving() else Status.RUNNING


## Changes an actor's movement speed. Non-blocking, takes effect immediately.
class SetSpeed extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a != null:
			a.motion().speed = float(args.get("speed", a.motion().speed))


## Removes an actor's whole placement - itself, its [GameEvent] if it has one, its
## view, everything - from both the running game and the scene, the same shape a
## page-authored region trigger, a one-time pickup or a defeated patrol wants gone for
## good. Actor and [GameEvent] are always siblings under one placement root
## (event-pages.md §4.3's two authored shapes); [method Node.queue_free] on that root
## is what takes both at once, rather than freeing the [Actor] and leaving an orphaned
## [GameEvent] node (or the reverse) behind.
##
## [b]Safe on [code]@self[/code][/b], the default and overwhelmingly common case:
## [method Node.queue_free] defers the actual removal to the end of the frame, well
## after this graph has already moved past this node, so there is nothing to untangle
## here about a runner freeing the very node driving it. [method GameEvent._exit_tree]
## is what actually stops whatever runner or lease the erased placement was holding,
## the moment that removal lands - hardened alongside this command, not a special
## case for it, since any other way a [GameEvent] leaves the tree needs the same
## teardown.
class EraseEvent extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a == null:
			return
		var root := a.get_parent()
		if root != null:
			root.queue_free()


static func table() -> Dictionary:
	return {
		"move_to": MoveTo,
		"move_by": MoveBy,
		"step": StepCmd,
		"face_direction": FaceDirection,
		"face_to": FaceTo,
		"jump": JumpCmd,
		"teleport": TeleportCmd,
		"wait_settle": WaitSettle,
		"set_speed": SetSpeed,
		"erase_event": EraseEvent,
	}
