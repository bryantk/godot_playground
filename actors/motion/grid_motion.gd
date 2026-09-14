class_name GridMotion extends MotionController

## Cell-to-cell stepping. Works in either space - which is what makes grid movement
## in a 3D town a change of one field rather than a new controller.
##
## The body is authoritative and always exactly on a cell; the sprite is a lie that
## catches up. Physics queries, occupancy and event triggers therefore never see a
## half-cell state, and a cutscene that teleports an actor mid-step just cancels the
## tween.
##
## Everything happens at commit: the occupancy commit and [signal EventBus.actor_stepped],
## fired unconditionally for every grid actor. One moment when a step happened, so
## monsters and traps observe identical state - there is no per-actor flag or mode that
## silences it; a listener that only wants some actors' steps filters them itself. The
## land-on-it feel is [signal EventBus.actor_settled] / [code]wait_settle[/code] joining
## the key this returns, not a flag on the trigger.

## How many world directions a step may take. 4 for game 1.
@export_range(4, 8, 4) var direction_count: int = 4

var _moving: bool = false
var _step_key: String = ""
var _queue: Array[Vector3i] = []
var _route_key: String = ""
var _step_intent: Vector3i = Vector3i.ZERO

## The step in flight, and how much of it is left, in cells: 1 at commit, 0 at settle.
## The sprite's offset is this fraction of [member _step_back], so the remaining distance
## is the state and the elapsed time is not - which is what lets the speed change mid-cell.
var _step_from: Vector3i = Vector3i.ZERO
var _step_to: Vector3i = Vector3i.ZERO
var _step_back: Vector3 = Vector3.ZERO
var _step_left: float = 0.0


func _ready() -> void:
	super()
	# Only while a step is in flight. A map of standing NPCs should cost nothing.
	set_process(false)


func is_busy() -> bool:
	return _moving or not _queue.is_empty()


## The direction to take the instant the current step settles, or ZERO for none.
##
## Set every frame by whatever is driving the actor, and set back to ZERO the moment it
## stops asking. This is what makes a held direction continuous: the next step commits
## inside [method _settle], in the same frame the tween ended, rather than a frame later
## when the driver's [method Node._process] next runs. A single dropped frame per cell
## is a visible hitch at these durations.
##
## It is an intent rather than a queue on purpose - a queue would let a released key buy
## one more step, and would replay a stale direction after a cutscene took control.
func set_step_intent(dir: Vector3i) -> void:
	_step_intent = dir


## How long one step takes. A step always crosses exactly one cell, so compensation
## cannot change the distance - it shortens the [i]time[/i] instead, which comes to the
## same screen pixels per second. At pitch 30 with full compensation a north step takes
## half as long as an east one and both advance the image 16 px per step duration.
##
## [param dir] of ZERO asks for the uncompensated duration, which is what a caller that
## just wants the nominal cadence means.
##
## Speed modifiers are included, so this is what a step in [param dir] would take right
## now rather than what it would take on open ground. It is a prediction either way: the
## step in flight is advanced frame by frame in [method _process] and re-reads the scale
## every frame, so a modifier that arrives mid-cell changes the step this returned a
## duration for.
func step_duration(dir: Vector3i = Vector3i.ZERO) -> float:
	var base := 1.0 / maxf(0.01, speed * speed_scale(Vector3(dir)))
	if dir == Vector3i.ZERO:
		return base
	var d := Vector3(dir)
	return base * d.length() / maxf(0.01, compensate(d).length())


## One cell in [param dir]. Returns false if the destination is not enterable, having
## changed nothing but the actor's facing.
##
## Facing changes even on a blocked step, deliberately: turning to look at the wall
## you walked into is what every game of this kind does, and turning changes no cell
## so it opens no round.
##
## Neither half of a refused step is silent, though: the turn publishes
## [signal EventBus.actor_turned] and the refusal [signal EventBus.actor_blocked]
## (open-questions 6 and 7). Published, not pulsed - they drive nothing.
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
		_actor.report_blocked(to)
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
			# place(), not commit_step(): a teleport is a statement, so it lands on an
			# occupied cell rather than silently failing to move (open-questions 34).
			ctx.occupancy.place(_actor.actor_id, cell)
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
	# Dropped too, or a cutscene that cancels the player's movement would immediately
	# take one more step in whatever direction was last held.
	_step_intent = Vector3i.ZERO
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
	# Every grid actor commits, through or not - the table records presence, and a
	# phasing actor's claim is simply never refused. Gating the call on the flag would
	# lose the through actor from the cell it is standing on.
	if not ctx.occupancy.commit_step(_actor.actor_id, from, to):
		_actor.report_blocked(to)
		return

	# 2. The body snaps. It is authoritative from here on.
	var adapt := adapter()
	if adapt != null:
		adapt.set_world_position(ctx.cell_centre(to))

	_moving = true
	_step_key = _next_key("step")

	# 3. actor_stepped, at commit rather than at settle, so monsters move *with* the
	#    player rather than a beat behind - for whichever listener chooses to act on it.
	#    Unconditional: no per-actor flag, no mode-stack check. Anything that must not
	#    react during a cutscene (a future StepResponder) asks ModeStack itself; the bus
	#    does not decide that on every listener's behalf.
	EventBus.actor_stepped.emit(_actor.actor_id, from, to)
	if _actor.is_player():
		EventBus.player_stepped.emit(from, to)
	_actor.step_committed.emit(from, to)

	# 4. Zones, asked of the physics server now that the body is where it is going.
	#    Synchronous on purpose: an overlap signal would arrive next physics frame,
	#    which is after this step has already been given its speed. A SpeedModifier
	#    registering here is registered before the first frame of the step is advanced,
	#    so the step that enters the mud is itself slow.
	_actor.update_areas(AreaZone.zones_at(_actor, to))

	# 5. The visual is pushed back and walks to zero under _process. This is the only
	#    thing that takes time, and its key is what wait_settle joins. Started last so
	#    that a viewless actor - a headless test, or a settled teleport - cannot settle
	#    the step before actor_stepped above has been published.
	var view := _actor.view()
	if view == null:
		_settle()
		return

	_step_from = from
	_step_to = to
	_step_back = ctx.cell_centre(from) - ctx.cell_centre(to)
	_step_left = 1.0
	view.set_step_offset(_step_back)
	set_process(true)


## The step in flight, advanced by distance rather than by elapsed time.
##
## [b]Why distance.[/b] The remaining fraction of a cell is the state; the speed is read
## fresh every frame and only decides how much of it is spent this frame. A duration fixed
## at commit - which is what a [Tween] is - cannot express an actor that slows down
## halfway across a tile, so an actor stepping into mud would have finished that step at
## its old speed and only slowed on the next one. This is also why [ActorView] no longer
## owns the interpolation.
func _process(delta: float) -> void:
	if not _moving:
		set_process(false)
		return
	if ModeStack.pauses_physics():
		return

	var d := Vector3(_step_to - _step_from)
	var rate := maxf(0.0, speed) * speed_scale(d)
	if d.length_squared() > 0.0:
		# The same depth compensation the nominal duration uses, re-read each frame
		# because the camera's yaw stop can change mid-step.
		rate *= compensate(d).length() / d.length()
	if rate <= 0.0:
		# A scale of zero is an actor held in place mid-cell. Deliberate, and it stops
		# here rather than being clamped to a crawl, because a zone that means "you
		# cannot move" should mean it.
		return

	_step_left -= rate * delta
	var view := _actor.view() if _actor != null else null

	if _step_left <= 0.0:
		_step_left = 0.0
		if view != null:
			view.set_step_offset(Vector3.ZERO)
		_settle()
		return

	if view != null:
		view.set_step_offset(_step_back * _step_left)


func _settle() -> void:
	_moving = false
	set_process(false)

	# The sprite is where the body is, so the zones the body left a step ago are now
	# also visually left. This is the moment "completely exited" means.
	if _actor != null:
		_actor.settle_areas()

	if _step_key != "":
		var key := _step_key
		_step_key = ""
		EventBus.command_finished.emit(key)
	# actor_settled after command_finished resolves: wait_settle joins the step key
	# above, and a listener reacting to the signal should see that join already able
	# to have happened rather than racing it.
	if _actor != null:
		_actor.report_settled(_actor.cell())

	# A route in progress owns the actor, so it wins over whatever is holding a
	# direction - otherwise player input would steer an actor mid-cutscene.
	_advance()

	# Consumed rather than left standing, which also bounds this: a zero-duration view
	# settles synchronously, so an intent that survived being taken would recurse until
	# the actor hit a wall. The driver re-asserts it next frame if the key is still down.
	if not _moving and _step_intent != Vector3i.ZERO:
		var again := _step_intent
		_step_intent = Vector3i.ZERO
		step(again)


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


## Drop the step in flight and put the sprite on the body. The zones are re-asked rather
## than carried over: a teleport can land anywhere, so the membership a half-finished step
## was building is not evidence of anything.
func _cancel_visual() -> void:
	set_process(false)
	_step_left = 0.0
	var view := _actor.view() if _actor != null else null
	if view != null:
		view.cancel_step_offset()
	if _actor != null:
		_actor.update_areas(AreaZone.zones_at(_actor, _actor.cell()))
		_actor.settle_areas()
