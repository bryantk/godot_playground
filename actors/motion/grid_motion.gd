class_name GridMotion extends MotionController

## Cell-to-cell stepping. Works in either space - which is what makes grid movement
## in a 3D town a change of one field rather than a new controller.
##
## The body is authoritative and always exactly on a cell; the sprite is a lie that
## catches up. Physics queries, occupancy and event triggers therefore never see a
## half-cell state, and a cutscene that teleports an actor mid-step just cancels the
## tween.
##
## Everything happens at commit: the occupancy commit, the step pulse, and any cell
## trigger on the destination. One moment when a step happened, so monsters and traps
## observe identical state. The land-on-it feel is [code]wait_settle[/code] joining
## the key this returns, not a flag on the trigger.

## How many world directions a step may take. 4 for game 1.
@export_range(4, 8, 4) var direction_count: int = 4

## Does a committed step publish [signal EventBus.actor_stepped]? The player's does;
## most NPCs' do not, or every patrolling guard would drive the monsters.
@export var publishes_pulse: bool = false

var _moving: bool = false
var _step_key: String = ""
var _queue: Array[Vector3i] = []
var _route_key: String = ""


func is_busy() -> bool:
	return _moving or not _queue.is_empty()


func step_duration() -> float:
	return 1.0 / maxf(0.01, speed)


## One cell in [param dir]. Returns false if the destination is not enterable, having
## changed nothing but the actor's facing.
##
## Facing changes even on a blocked step, deliberately: turning to look at the wall
## you walked into is what every game of this kind does, and turning changes no cell
## so it opens no round.
func step(dir: Vector3i) -> bool:
	if _actor == null or dir == Vector3i.ZERO:
		return false

	var d := Space.quantise(Vector3(dir), direction_count)
	face(d)

	if _moving:
		return false

	var ctx := context()
	if ctx == null:
		return false

	var from := _actor.cell()
	var to := from + d

	if not Passability.can_enter(ctx, to, _actor):
		_actor.blocked.emit(to)
		return false

	_commit_step(ctx, from, to)
	return true


## Walk to [param cell]. Straight-line-then-stop: the actor takes single steps toward
## the target and stops when one is refused. [code]path: "astar"[/code] is accepted in
## the schema and not yet implemented, so adding it later is not a format change.
func move_to(cell: Vector3i, opts: Dictionary = {}) -> String:
	if _actor == null:
		return ""

	if opts.has("speed"):
		speed = float(opts["speed"])

	if str(opts.get("path", "line")) == "raw":
		# Teleport-like: no passability, no pulse. teleport() is the command that
		# wants this; keeping it here means one code path sets position.
		var ctx := context()
		if ctx != null:
			ctx.occupancy.commit_step(_actor.actor_id, _actor.cell(), cell)
			adapter().set_world_position(ctx.cell_centre(cell))
			_cancel_visual()
		return ""

	_queue = _line_to(cell)
	_route_key = _next_key("move")
	if _queue.is_empty():
		EventBus.command_finished.emit(_route_key)
		var done := _route_key
		_route_key = ""
		return done

	_advance()
	return _route_key


func cancel() -> void:
	_queue.clear()
	_moving = false
	_cancel_visual()
	if _route_key != "":
		var key := _route_key
		_route_key = ""
		EventBus.command_finished.emit(key)


func jump(_strength: float) -> String:
	push_warning("GridMotion('%s'): jump needs free motion." % _actor.actor_id if _actor != null else "?")
	return ""


# -- Internals ----------------------------------------------------------------

## The single moment a step happens.
func _commit_step(ctx: MapContext, from: Vector3i, to: Vector3i) -> void:
	# 1. Occupancy, transactionally - even though this is two changes and could have
	#    been two writes. Push needs the multi-cell form, and if the ordinary step did
	#    not already use it, push would be a rewrite.
	if _actor.solid and not ctx.occupancy.commit_step(_actor.actor_id, from, to):
		_actor.blocked.emit(to)
		return

	# 2. The body snaps. It is authoritative from here on.
	var adapt := adapter()
	if adapt != null:
		adapt.set_world_position(ctx.cell_centre(to))

	_moving = true
	_step_key = _next_key("step")

	# 3. The pulse, at commit rather than at settle, so monsters move *with* the
	#    player rather than a beat behind.
	if publishes_pulse and not ModeStack.suppresses_pulse():
		EventBus.actor_stepped.emit(_actor.actor_id, from, to)

	# 4. Cell triggers, at the same moment, so a trap and a monster see one world.
	EventBus.cell_entered.emit(_actor.actor_id, to)

	# 5. The visual is pushed back and tweens to zero. This is the only thing that
	#    takes time, and its key is what wait_settle joins. Started last so that a
	#    zero-duration view - a headless test, or a settled teleport - cannot settle
	#    the step before the pulse above has been published.
	var view := _actor.view()
	if view != null:
		var back := ctx.cell_centre(from) - ctx.cell_centre(to)
		var visual_key := view.apply_step_offset(back, step_duration())
		if visual_key == "":
			_settle()
		else:
			_await_visual(visual_key)
	else:
		_settle()


func _await_visual(visual_key: String) -> void:
	if visual_key == "":
		_settle()
		return
	while true:
		var finished: String = await EventBus.command_finished
		if finished == visual_key:
			break
	_settle()


func _settle() -> void:
	_moving = false
	if _step_key != "":
		var key := _step_key
		_step_key = ""
		EventBus.command_finished.emit(key)
	if _actor != null:
		_actor.arrived.emit(_actor.cell())
	_advance()


func _advance() -> void:
	if _queue.is_empty():
		if _route_key != "":
			var key := _route_key
			_route_key = ""
			EventBus.command_finished.emit(key)
		return

	var next := _queue.pop_front() as Vector3i
	if not step(next):
		# Blocked mid-route. Stop rather than retry - on_blocked policy belongs to the
		# route that issued this, not here.
		_queue.clear()
		if _route_key != "":
			var key := _route_key
			_route_key = ""
			EventBus.command_finished.emit(key)


## Single steps from the actor's cell toward [param target]: the larger axis first,
## so the path reads as a walk rather than a stair.
func _line_to(target: Vector3i) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	var at := _actor.cell()
	var guard := 0
	while at != target and guard < 512:
		guard += 1
		var delta := target - at
		var d: Vector3i
		if absi(delta.x) >= absi(delta.z) and delta.x != 0:
			d = Vector3i(signi(delta.x), 0, 0)
		elif delta.z != 0:
			d = Vector3i(0, 0, signi(delta.z))
		else:
			break
		out.append(d)
		at += d
	return out


func _cancel_visual() -> void:
	var view := _actor.view() if _actor != null else null
	if view != null:
		view.cancel_step_offset()
