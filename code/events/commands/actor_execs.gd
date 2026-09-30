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
	## Where this move meant to land - [code]teleport[/code] (its own command, not this
	## one - see [code]TeleportCmd[/code] below) always lands exactly here, so [method
	## was_blocked] never trips for one; an ordinary move that stopped short is what it
	## exists to catch, for [code]define_route[/code]'s own benefit (see
	## event_command_exec.gd's own doc on it).
	var _target_cell := Vector3i.ZERO

	func start() -> void:
		var a := actor()
		if a == null:
			return
		ctx.mark_actor_touched(a)
		var opts := {}
		if args.has("speed"):
			opts["speed"] = args["speed"]
		# Unset means "use current" (event_command.gd's own note on this argument) -
		# only ever touched when actually authored, same as the page field it mirrors.
		if args.has("animation_speed"):
			a.view().set_animation_speed_scale(float(args["animation_speed"]))
		_target_cell = Vector3i(args.get("cell", Vector3i.ZERO))
		_key = a.motion().move_to(_target_cell, opts)

	func tick(_delta: float) -> int:
		return reached_immediate_tick()

	func flow_port() -> String:
		return reached_immediate_flow_port()

	func was_blocked() -> bool:
		var a := actor()
		return a != null and a.cell() != _target_cell

	func supports_blocked_flow() -> bool:
		return true

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
## [method MotionController.move_by] is [code]move_to(cell() + delta)[/code] - repeated
## N times over for a "token:N" cells value (a bare token or literal delta is one leg).
##
## [b]Each repeat is its own leg[/b], chained through [signal EventBus.command_finished]
## rather than a single bigger delta handed to the motion controller in one go: a leg
## that comes up blocked stops the whole chain right there (see [method _on_leg_done]),
## the same "or something blocked" a single-leg move already reads as [method
## was_blocked]. [member _chain_key] - not any one leg's own key - is what [method
## own_key]/a joining [code]wait_for[/code] actually waits on, since a leg's own key
## resolves the instant [i]that leg[/i] settles, long before the chain as a whole is done.
class MoveBy extends EventCommandExec:
	var _key := ""
	## See [member MoveTo._target_cell] - the same idea, relative to wherever the actor
	## stood at the start of whichever leg is currently in flight.
	var _target_cell := Vector3i.ZERO
	var _remaining := 1
	## The one-cell step a "forward"/"random"/"wander" token resolved to at [method
	## start], reused by every leg of the chain - see [member _fixed_leg].
	var _leg_delta := Vector3i.ZERO
	var _fixed_leg := false
	## Never cleared, unlike a single leg's own [member _key] (which is read once each
	## way) - [EventRunner] reads [method own_key] for its own key-alias bookkeeping
	## right after [method start] returns, and a chain that finishes synchronously
	## inside [method start] (a viewless actor, [member _remaining] of 1) would
	## otherwise already have cleared it by the time anyone asks. [method _finish_chain]
	## may emit against this same string more than once in one command's life - see its
	## own doc for why that is correct rather than a double-fire bug.
	var _chain_key := ""

	static var _chain_counter := 0

	func start() -> void:
		var a := actor()
		if a == null:
			return
		# Once for the whole chain, not re-applied per leg the way "cells" is - unlike
		# a symbolic direction, there is no "current" animation pace to re-derive fresh
		# each leg, only whatever was authored here. Unset means "use current"
		# (event_command.gd's own note on this argument).
		if args.has("animation_speed"):
			a.view().set_animation_speed_scale(float(args["animation_speed"]))
		# "token:N" walks N one-cell legs of a step rolled once, here - every token,
		# "towards_player"/"away_from_player" included, so a chase keeps the heading it
		# had at the start rather than re-aiming each leg.
		var player := ctx.resolve("@player")
		var plan := EventCommand.resolve_move_plan(args.get("cells", Vector3i.ZERO),
			a.facing(), a.cell(), player.cell() if player != null else null)
		_leg_delta = plan["delta"]
		_fixed_leg = true
		_remaining = int(plan["legs"])
		_chain_key = _mint_chain_key()
		_begin_leg()

	## Starts the next leg - the first, from [method start], or another one [method
	## _on_leg_done] decided the chain still has left. The authored "cells" is
	## resolved fresh every leg via [method EventCommand.resolve_move_delta] - a literal
	## delta always comes out the same, but a symbolic one ("towards_player", "random")
	## is deliberately re-derived from wherever the actor (and @player) actually stand
	## at the start of *this* leg, not accumulated or computed once for the whole chain.
	func _begin_leg() -> void:
		var a := actor()
		if a == null:
			_finish_chain()
			return
		ctx.mark_actor_touched(a)
		var player := ctx.resolve("@player")
		var player_cell: Variant = null
		if player != null:
			player_cell = player.cell()
		var delta: Vector3i = _leg_delta if _fixed_leg else EventCommand.resolve_move_delta(
			args.get("cells", Vector3i.ZERO), a.facing(), a.cell(), player_cell)
		_target_cell = a.cell() + delta
		_key = a.motion().move_by(delta, _opts())
		_await_leg()

	## Whatever [member _key] this leg just minted, resolved already or not - the same
	## check [method reached_immediate_tick] makes for a single-leg move, since a
	## viewless actor's own move can settle synchronously before [method
	## MotionController.move_by]/[code]move_to[/code] even returns it. [member
	## runner]'s [KeyLatch] is what makes that safe to ask about after the fact: it has
	## been listening for [signal EventBus.command_finished] since long before this leg
	## started, so an already-resolved key is sitting in it rather than lost - connecting
	## [method _on_leg_key_resolved] straight to the signal instead would miss exactly
	## that case, waiting forever on a key that already fired.
	func _await_leg() -> void:
		if _key == "" or runner.latch.consume(_key):
			_on_leg_done()
		else:
			EventBus.command_finished.connect(_on_leg_key_resolved)

	func _on_leg_key_resolved(key: String) -> void:
		if key != _key:
			return
		EventBus.command_finished.disconnect(_on_leg_key_resolved)
		_on_leg_done()

	## One leg just settled - continues the chain if it landed clean and there is any
	## left, otherwise ends it. A blocked leg ends the chain here regardless of how much
	## [member _remaining] is left; [method was_blocked] then reads it the same way a
	## single-leg move already would, and [EventRunner]'s own [code]define_route[/code]
	## retry (see [method retry]) re-attempts exactly this leg, not the whole chain over.
	func _on_leg_done() -> void:
		var a := actor()
		if a == null or a.cell() != _target_cell:
			_finish_chain()
			return
		_remaining -= 1
		if _remaining > 0:
			_begin_leg()
		else:
			_finish_chain()

	## Reports this attempt settled - the whole chain done, or one leg come up blocked
	## with [EventRunner]'s own [code]define_route[/code] retry (see [method retry]) yet
	## to decide whether that is final. A retried leg that blocks again calls this again,
	## against the same [member _chain_key] - deliberately, since each call is a distinct
	## "this attempt just settled" a fresh [method Node._process] poll of [method
	## reached_immediate_tick]/[member EventRunner.latch] needs to see, not a single
	## one-shot completion guarded against repeating.
	func _finish_chain() -> void:
		if _chain_key != "":
			EventBus.command_finished.emit(_chain_key)

	static func _mint_chain_key() -> String:
		_chain_counter += 1
		return "movechain:%d" % _chain_counter

	func flow_port() -> String:
		return reached_immediate_flow_port()

	## The same target this leg already committed to at its own first [method _begin_leg],
	## approached from wherever the actor now stands via [method MotionController.move_to]
	## rather than [method MotionController.move_by] re-applying "cells" a second time -
	## see [method EventCommandExec.retry]'s own doc for why re-deriving a fresh relative
	## delta here would overshoot past a target this already made partial progress on.
	## [member _remaining] is untouched - a retried leg is still the same leg.
	func retry() -> void:
		var a := actor()
		if a == null:
			return
		ctx.mark_actor_touched(a)
		_key = a.motion().move_to(_target_cell, _opts())
		_await_leg()

	func _opts() -> Dictionary:
		var opts := {}
		if args.has("speed"):
			opts["speed"] = args["speed"]
		return opts

	func tick(_delta: float) -> int:
		return reached_immediate_tick()

	func was_blocked() -> bool:
		var a := actor()
		return a != null and a.cell() != _target_cell

	func supports_blocked_flow() -> bool:
		return true

	func own_key() -> String:
		return _chain_key

	func cancel() -> void:
		if EventBus.command_finished.is_connected(_on_leg_key_resolved):
			EventBus.command_finished.disconnect(_on_leg_key_resolved)
		var a := actor()
		if a != null:
			a.motion().cancel()
		# Orphaned otherwise - a wait_for joined on the chain's own key (not any one
		# leg's) would wait forever past whatever seized the actor mid-chain.
		_finish_chain()

	func resumable() -> bool:
		return true

	func capture() -> Dictionary:
		var a := actor()
		var m := a.motion() if a != null else null
		var out := {"motion": (m as GridMotion).to_save()} if m is GridMotion else {}
		# _target_cell is relative to wherever the actor stood when this leg started,
		# not to wherever it happens to be now - which a mid-flight capture (a route
		# preempted by a triggered graph, then resumed) already is not the same cell.
		# Captured explicitly rather than recomputed from args at restore time, or
		# was_blocked() would compare against a target shifted by however much of this
		# leg had already committed before the interruption, reading a leg that in fact
		# finished exactly where it meant to as blocked anyway. "remaining"/"chain_key"
		# ride along so a reload resumes the rest of the count, not just this one leg.
		out["target_cell"] = [_target_cell.x, _target_cell.y, _target_cell.z]
		out["remaining"] = _remaining
		out["chain_key"] = _chain_key
		if _fixed_leg:
			out["leg_delta"] = [_leg_delta.x, _leg_delta.y, _leg_delta.z]
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
		var cells: Variant = args.get("cells", Vector3i.ZERO)
		_target_cell = saved_cell_or(state.get("target_cell"),
			a.cell() + (Vector3i.ZERO if cells is String else Vector3i(cells)))
		_remaining = maxi(1, int(state.get("remaining", 1)))
		_fixed_leg = state.has("leg_delta")
		if _fixed_leg:
			_leg_delta = saved_cell_or(state["leg_delta"], Vector3i.ZERO)
		_chain_key = str(state.get("chain_key", ""))
		if _chain_key == "":
			_chain_key = _mint_chain_key()
		var keys := (m as GridMotion).from_save(state.get("motion", {}))
		_key = str(keys.get("route_key", ""))
		_await_leg()


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


## Jumps to a cell, arcing a height above it - a real projectile in [FreeMotion]
## ([method FreeMotion.jump_to]), a straight-line commit with an arced sprite catch-up
## in [GridMotion] ([method GridMotion.jump_to]). "reached"/"immediate" like every other
## travelling command (see [method EventCommandExec.reached_immediate_tick]); no
## mid-flight capture yet for either controller, so a save taken mid-jump restarts it
## from wherever the actor now stands (a legal downgrade, question 39) rather than
## resuming the arc.
class JumpCmd extends EventCommandExec:
	var _key := ""
	## The landing cell is held by another actor - the jump never starts, and [method
	## was_blocked] reports it (see [method supports_blocked_flow]). Terrain is arced
	## over, so occupancy is the only thing that refuses a jump.
	var _blocked := false

	func start() -> void:
		var a := actor()
		if a == null:
			return
		var target := Vector3i(args.get("cell", Vector3i.ZERO))
		var map := a.context()
		_blocked = map != null and not map.occupancy.is_free_for(target, a.actor_id)
		if _blocked:
			_key = ""
			return
		ctx.mark_actor_touched(a)
		_key = a.motion().jump_to(target, float(args.get("height", 0.0)))

	func tick(_delta: float) -> int:
		return reached_immediate_tick()

	func flow_port() -> String:
		return reached_immediate_flow_port()

	func was_blocked() -> bool:
		return _blocked

	func supports_blocked_flow() -> bool:
		return true

	func own_key() -> String:
		return _key

	func cancel() -> void:
		var a := actor()
		if a != null:
			a.motion().cancel()


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


## Toggles [member Actor.facing_locked] mid-graph, without waiting for the next page
## switch to reapply the page's own [code]lock_facing[/code] (see [method
## GameEvent._apply_actor_flags]) - the same "runtime override, until the next page
## activation reasserts the authored default" relationship [code]set_visible[/code]
## already has with a page's own [code]art[/code].
class SetLockFacing extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a != null:
			a.facing_locked = bool(args.get("lock_facing", false))


## Toggles [member Actor.through_actors] mid-graph, the same runtime-override
## relationship [method SetLockFacing] has with [code]lock_facing[/code]. Also pushes
## [Occupancy]'s own phasing table, same as [method GameEvent._apply_actor_flags] does -
## [method Actor._claim_spawn_cell] only reads the export once, at spawn, so pathing
## itself would not see a mid-graph flip without this.
class SetThrough extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a == null:
			return
		var through := bool(args.get("through", false))
		a.through_actors = through
		if ctx.map != null:
			ctx.map.occupancy.set_phasing(a.actor_id, through)


## Toggles [member Actor.through_terrain] mid-graph, the same runtime-override
## relationship [method SetLockFacing] has with [code]lock_facing[/code].
class SetThroughTerrain extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a != null:
			a.through_terrain = bool(args.get("through_terrain", false))


## Toggles [member Actor.show_shadow_override] mid-graph, the same runtime-override
## relationship [method SetLockFacing] has with [code]lock_facing[/code] - [ActorShadow]
## reads the flag every frame, so nothing else needs to be poked for this to take effect.
class SetShowShadowOverride extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a != null:
			a.show_shadow_override = bool(args.get("show_shadow_override", false))


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
##
## [b]Durable, but only for as long as the map stays the one you're on[/b]: [method
## GameState.set_erased] records the actor's id against [member EventContext.map_id],
## which [SaveGame] persists and consults on load ([method SaveGame.load]) to keep this
## placement gone rather than resurrecting it fresh off the scene file. Leaving the map
## clears that record ([method MapContext._exit_tree]) - the removal is not meant to
## outlast the visit it happened on, only a save/load taken during it.
class EraseEvent extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a == null:
			return
		if a.actor_id == &"":
			push_warning("erase_event: actor has no actor_id, so its removal cannot be saved - it will reappear on the next load.")
		else:
			GameState.set_erased(ctx.map_id, a.actor_id)
		var root := a.get_parent()
		if root != null:
			root.queue_free()


## Computes a path to a cell with A* ([method GridMotion.find_path]), stores it on the
## actor as JSON move commands ([member Actor.move_route] - replaced by the next
## [code]move_route[/code] on that actor, and saved), and walks it one cell at a time.
##
## Flows: "reached" at the end of a complete route; "blocked" if a step is refused (wired,
## it is taken and the route is abandoned; unwired, the runner waits a frame and retries,
## which re-plans from wherever the actor stopped - see [method
## EventCommandExec.supports_blocked_flow]); "immediate" the moment it starts (wired, the
## graph does not wait); "no_path_found" straight away, without moving at all, when the
## search cannot reach the target (walled off, or over [code]max_nodes[/code]) - the
## actor's stored route is cleared so a stale one is not left behind. A target already
## under the actor is simply reached.
##
## Grid actors only - a free-motion actor has no cells to plan over, so it reads as no
## path found.
class MoveRoute extends EventCommandExec:
	var _cells: Array[Vector3i] = []
	var _index := 0
	var _key := ""
	var _leg_cell := Vector3i.ZERO
	var _blocked := false
	var _no_path := false
	var _chain_key := ""

	static var _chain_counter := 0

	func start() -> void:
		_blocked = false
		_no_path = false
		_cells = []
		_index = 0
		_chain_key = _mint_chain_key()

		var a := actor()
		if a == null:
			_finish_chain()
			return
		var m := a.motion()
		if not (m is GridMotion):
			_no_path = true
			_finish_chain()
			return

		ctx.mark_actor_touched(a)
		if args.has("animation_speed"):
			a.view().set_animation_speed_scale(float(args["animation_speed"]))
		if args.has("speed"):
			m.speed = float(args["speed"])

		var found: Dictionary = (m as GridMotion).find_path(
			Vector3i(args.get("cell", Vector3i.ZERO)), maxi(1, int(args.get("max_nodes", 2000))))
		if not bool(found["complete"]):
			_no_path = true
			a.move_route = []
			_finish_chain()
			return
		_cells.assign(found["path"])
		a.move_route = _route_json(_cells)
		_begin_leg()

	static func _route_json(cells: Array[Vector3i]) -> Array:
		var out: Array = []
		for cell in cells:
			out.append({"command": "move_to", "args": {"cell": [cell.x, cell.y, cell.z]}})
		return out

	func _begin_leg() -> void:
		var a := actor()
		if a == null or _index >= _cells.size():
			_finish_chain()
			return
		_leg_cell = _cells[_index]
		var delta := _leg_cell - a.cell()
		var dir := Vector3i(signi(delta.x), 0, signi(delta.z))
		_key = (a.motion() as GridMotion).step_keyed(dir)
		if _key == "":
			# Refused outright, before anything moved.
			_blocked = true
			_finish_chain()
			return
		_await_leg()

	func _await_leg() -> void:
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
		var a := actor()
		if a == null or a.cell() != _leg_cell:
			_blocked = true
			_finish_chain()
			return
		_index += 1
		_begin_leg()

	func _finish_chain() -> void:
		if _chain_key != "":
			EventBus.command_finished.emit(_chain_key)

	static func _mint_chain_key() -> String:
		_chain_counter += 1
		return "moveroute:%d" % _chain_counter

	func tick(_delta: float) -> int:
		return reached_immediate_tick()

	func flow_port() -> String:
		if immediate_wired():
			return EventCommand.FLOW_IMMEDIATE
		return EventCommand.FLOW_NO_PATH_FOUND if _no_path and not _blocked \
			else EventCommand.FLOW_REACHED

	func was_blocked() -> bool:
		return _blocked

	func supports_blocked_flow() -> bool:
		return true

	func own_key() -> String:
		return _chain_key

	func cancel() -> void:
		if EventBus.command_finished.is_connected(_on_leg_key_resolved):
			EventBus.command_finished.disconnect(_on_leg_key_resolved)
		var a := actor()
		if a != null:
			a.motion().cancel()
		_finish_chain()

	func resumable() -> bool:
		return true

	func capture() -> Dictionary:
		var a := actor()
		var m := a.motion() if a != null else null
		var out := {"motion": (m as GridMotion).to_save()} if m is GridMotion else {}
		out["index"] = _index
		out["no_path"] = _no_path
		return out

	## Picks the stored [member Actor.move_route] back up at the leg that was in flight.
	## With no stored route (or a motion that cannot resume) it just starts over.
	func restore(state: Dictionary) -> void:
		var a := actor()
		if a == null:
			return
		var m := a.motion()
		if not (m is GridMotion) or a.move_route.is_empty():
			start()
			return
		ctx.mark_actor_touched(a)
		_cells = []
		for step: Variant in a.move_route:
			var cell: Variant = ((step as Dictionary).get("args", {}) as Dictionary).get("cell")
			if cell is Array and (cell as Array).size() >= 3:
				_cells.append(Vector3i(int(cell[0]), int(cell[1]), int(cell[2])))
		_index = clampi(int(state.get("index", 0)), 0, _cells.size())
		_no_path = bool(state.get("no_path", false))
		_blocked = false
		_chain_key = _mint_chain_key()
		_leg_cell = _cells[_index] if _index < _cells.size() else a.cell()
		var keys := (m as GridMotion).from_save(state.get("motion", {}))
		_key = str(keys.get("step_key", ""))
		_await_leg()


static func table() -> Dictionary:
	return {
		"move_route": MoveRoute,
		"move_to": MoveTo,
		"move_by": MoveBy,
		"face_direction": FaceDirection,
		"face_to": FaceTo,
		"jump": JumpCmd,
		"teleport": TeleportCmd,
		"wait_settle": WaitSettle,
		"set_speed": SetSpeed,
		"set_lock_facing": SetLockFacing,
		"set_through": SetThrough,
		"set_through_terrain": SetThroughTerrain,
		"set_show_shadow_override": SetShowShadowOverride,
		"erase_event": EraseEvent,
	}
