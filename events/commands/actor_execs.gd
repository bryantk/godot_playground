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
		_key = a.motion().move_to(Vector3i(args.get("cell", Vector3i.ZERO)), opts)

	func tick(_delta: float) -> int:
		return Status.DONE if _key == "" or runner.latch.consume(_key) else Status.RUNNING

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
		var keys := (m as GridMotion).from_save(state.get("motion", {}))
		_key = str(keys.get("route_key", ""))


## Walks a relative number of cells - the same executor as [code]move_to[/code], since
## [method MotionController.move_by] is [code]move_to(cell() + delta)[/code].
class MoveBy extends EventCommandExec:
	var _key := ""

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
		_key = a.motion().move_by(Vector3i(args.get("cells", Vector3i.ZERO)), opts)

	func tick(_delta: float) -> int:
		return Status.DONE if _key == "" or runner.latch.consume(_key) else Status.RUNNING

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
		var keys := (m as GridMotion).from_save(state.get("motion", {}))
		_key = str(keys.get("route_key", ""))


## One grid cell in a direction - question 40's defect (a): [method GridMotion.step]
## returns a bare bool, so this reaches for [method GridMotion.step_keyed] where the
## motion actually is a [GridMotion], and falls back to the bare call (no key to join)
## on [FreeMotion], where a "step" is just a nudge to intent.
class StepCmd extends EventCommandExec:
	var _key := ""

	func start() -> void:
		var a := actor()
		if a == null:
			return
		ctx.mark_actor_touched(a)
		var dir := EventCommand.direction_of(args.get("direction"))
		var m := a.motion()
		if m is GridMotion:
			_key = (m as GridMotion).step_keyed(dir)
		else:
			m.step(dir)
			_key = ""

	func tick(_delta: float) -> int:
		return Status.DONE if _key == "" or runner.latch.consume(_key) else Status.RUNNING

	func own_key() -> String:
		return _key

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
	}
