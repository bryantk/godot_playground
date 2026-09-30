## Camera-control executors: [code]camera_follow[/code], [code]camera_to[/code],
## [code]camera_move_by[/code] and [code]camera_bounds[/code] (event_command.gd). Every
## one drives [method EventCommandExec.camera_rig] - never a concrete [RoomCamera2D]/
## [OrthoPixelRig] directly, so a page authored against one game keeps working if its
## map's rig is ever swapped for the other's shape.
##
## [b]"speed" throughout is a rate[/b] (world units - px in 2D, metres in 3D - per
## second), not a duration: the pan takes longer over a farther cell and shorter over a
## near one, the same reason an actor's own [code]move_by[/code] speed (actor_execs.gd)
## is a rate and not a fixed time. Omitted or non-positive reads as "instant", matching
## every other optional duration in this vocabulary that treats zero as "do not animate
## this."


## Have the camera follow an actor - sets [member CameraRig.follow_target] going
## forward, paced by "speed" (or placed on the target immediately, "instant"). The
## ongoing following after this command finishes continues regardless of either, until
## something else claims the camera; what "block" (default true) actually waits for is
## only the initial catch-up.
class CameraFollow extends EventCommandExec:
	var _key := ""

	func start() -> void:
		var rig := camera_rig()
		if rig == null:
			return
		var target := ctx.resolve(str(args.get("actor", "")))
		if target == null:
			return
		ctx.mark_actor_touched(target)
		_key = rig.follow(target.actor_id, float(args.get("speed", 0.0)),
			bool(args.get("instant", false)))
		if not bool(args.get("block", true)):
			_key = ""

	func tick(_delta: float) -> int:
		return Status.DONE if _key == "" or runner.latch.consume(_key) else Status.RUNNING

	func own_key() -> String:
		return _key

	func resumable() -> bool:
		return true


## Shakes the camera through [method CameraRig.shake] - "strength" is the peak offset in
## screen px, "seconds" how long it takes to fade out (defaults 4 and 0.5). Two flow
## ports like [code]camera_to[/code]: "reached" once the shake has finished, "immediate"
## the moment it starts (wired, the graph does not wait).
class Shake extends EventCommandExec:
	var _key := ""

	func start() -> void:
		var rig := camera_rig()
		if rig == null:
			return
		_key = rig.shake(float(args.get("strength", 4.0)), float(args.get("seconds", 0.5)))

	func tick(_delta: float) -> int:
		return reached_immediate_tick()

	func flow_port() -> String:
		return reached_immediate_flow_port()

	func own_key() -> String:
		return _key

	func cancel() -> void:
		var rig := camera_rig()
		if rig != null:
			rig.shake(0.0, 0.0)


## Pans the camera to a cell - two flow ports rather than the generic per-node
## [code]"blocking"[/code] override (which the graph editor has no toggle for yet -
## [method EventGraphNode._add_blocking_indicator] only ever displays it). Wiring
## "immediate" takes the pan out of the runner's way the instant it starts; wiring only
## "reached" (or neither) waits for it to actually finish. [method
## EventCommand.validate_node] requires exactly as many outputs as flow ports, so wiring
## both is legal - "immediate" is checked first and always wins then, and "reached"
## never fires, the graph reading left to right exactly as it looks.
class CameraTo extends EventCommandExec:
	var _key := ""

	func start() -> void:
		var rig := camera_rig()
		if rig == null:
			return

		var cell := Vector3i(args.get("cell", Vector3i.ZERO))
		var seconds := 0.0
		if not bool(args.get("instant", false)):
			var map_ctx := rig.context()
			if map_ctx != null:
				var distance := (map_ctx.cell_centre(cell) - rig.world_position()).length()
				seconds = seconds_for_speed(distance, float(args.get("speed", 0.0)))
		_key = rig.move_to(cell, seconds)

	func tick(_delta: float) -> int:
		return reached_immediate_tick()

	func flow_port() -> String:
		return reached_immediate_flow_port()

	func own_key() -> String:
		return _key


## Moves the camera a relative number of cells, from wherever [method
## CameraRig.world_position] says it already is - a "token:N" cells value walks N legs of a
## step rolled once, the same chained-legs shape [method actor_execs.MoveBy] has, "or
## something blocked" included: a leg whose target falls outside whatever
## [code]camera_bounds[/code] last set (see [method CameraRig.in_bounds]) stops the
## chain there, the camera's own version of a grid actor finding a wall - see [method
## was_blocked]. [member _chain_key] is what [method own_key]/a joining [code]
## wait_for[/code] actually waits on - a leg's own key resolves the instant that leg's
## pan finishes, long before the whole chain is.
class CameraMoveBy extends EventCommandExec:
	var _key := ""
	var _remaining := 1
	var _blocked := false
	## The one step (or whole literal delta) every leg moves by - see [method start].
	var _leg_delta := Vector3i.ZERO
	## Never cleared once minted - see actor_execs.MoveBy's own [member
	## MoveBy._chain_key] doc for why, and why [method _finish_chain] emitting against
	## it more than once is correct rather than a double-fire bug.
	var _chain_key := ""

	static var _chain_counter := 0

	func start() -> void:
		_remaining = 1
		_leg_delta = Vector3i.ZERO
		var rig := camera_rig()
		var map_ctx := rig.context() if rig != null else null
		if rig != null and map_ctx != null:
			# Rolled once, same as actor_execs.MoveBy - "forward" has no camera facing, so
			# it is north.
			var player := ctx.resolve("@player")
			var plan := EventCommand.resolve_move_plan(args.get("cells", Vector3i.ZERO),
				Vector3i(0, 0, -1), map_ctx.cell_of(rig.world_position()),
				player.cell() if player != null else null)
			_leg_delta = plan["delta"]
			_remaining = int(plan["legs"])
		_chain_key = _mint_chain_key()
		_begin_leg()

	func _begin_leg() -> void:
		var rig := camera_rig()
		var map_ctx := rig.context() if rig != null else null
		if rig == null or map_ctx == null:
			_finish_chain()
			return

		var target_cell := map_ctx.cell_of(rig.world_position()) + _leg_delta
		var target_world := map_ctx.cell_centre(target_cell)
		if not rig.in_bounds(target_world):
			_blocked = true
			_finish_chain()
			return

		var distance := (target_world - rig.world_position()).length()
		_key = rig.move_to(target_cell, seconds_for_speed(distance, float(args.get("speed", 0.0))))
		# See actor_execs.MoveBy's own _await_leg doc: an instant pan can resolve its key
		# before move_to even returns it, and runner.latch has been listening since long
		# before this leg started, so it is what catches that case rather than missing it.
		if _key == "" or runner.latch.consume(_key):
			_on_leg_done()
		else:
			EventBus.command_finished.connect(_on_leg_key_resolved)

	func _on_leg_key_resolved(key: String) -> void:
		if key != _key:
			return
		EventBus.command_finished.disconnect(_on_leg_key_resolved)
		_on_leg_done()

	func _on_leg_done() -> void:
		_remaining -= 1
		if _remaining > 0:
			_begin_leg()
		else:
			_finish_chain()

	func _finish_chain() -> void:
		if _chain_key != "":
			EventBus.command_finished.emit(_chain_key)

	static func _mint_chain_key() -> String:
		_chain_counter += 1
		return "cammovechain:%d" % _chain_counter

	func tick(_delta: float) -> int:
		return reached_immediate_tick()

	func flow_port() -> String:
		return reached_immediate_flow_port()

	func own_key() -> String:
		return _chain_key

	## True the moment a leg's target fell outside the current [code]camera_bounds[/code]
	## - informational (nothing composes this into a runner-level retry the way [Actor]'s
	## own [method EventCommandExec.was_blocked] can, since there is no [code]
	## define_route[/code] equivalent for a camera), but reported anyway rather than
	## silently swallowed, for anything that wants to know whether the chain finished
	## the count it was given or stopped short.
	func was_blocked() -> bool:
		return _blocked

	func cancel() -> void:
		if EventBus.command_finished.is_connected(_on_leg_key_resolved):
			EventBus.command_finished.disconnect(_on_leg_key_resolved)
		_finish_chain()


## Constrains the camera to a named [CameraBounds] placed somewhere under the current
## map, or clears whatever bound is already set ([code]""[/code], or a name nothing
## resolves to). Instant and non-blocking - there is nothing to travel, only a limit to
## start or stop respecting.
class CameraBoundsCmd extends EventCommandExec:
	func start() -> void:
		var rig := camera_rig()
		if rig == null:
			return

		var bounds_name := StringName(str(args.get("bounds", "")))
		if bounds_name == &"":
			rig.set_bounds(Rect2())
			return

		var map_ctx := rig.context()
		var map_root := map_ctx.get_parent() if map_ctx != null else null
		var found := _find_bounds(map_root, bounds_name) if map_root != null else null
		if found == null:
			push_warning("camera_bounds: no CameraBounds named \"%s\" under this map." % bounds_name)
			return
		rig.set_bounds(found.global_rect())

	## The [CameraBounds] anywhere under [param root] named [param bounds_name], or null -
	## recursive rather than one fixed path, the same "search, don't assume a path"
	## reasoning [method map_execs.ChangeMapMarker._find_marker] already follows for
	## [MapMarker2D]/[MapMarker3D].
	static func _find_bounds(root: Node, bounds_name: StringName) -> CameraBounds:
		if root is CameraBounds and (root as CameraBounds).bounds_name == bounds_name:
			return root as CameraBounds
		for child in root.get_children():
			var found := _find_bounds(child, bounds_name)
			if found != null:
				return found
		return null


static func table() -> Dictionary:
	return {
		"shake": Shake,
		"camera_follow": CameraFollow,
		"camera_to": CameraTo,
		"camera_move_by": CameraMoveBy,
		"camera_bounds": CameraBoundsCmd,
	}
