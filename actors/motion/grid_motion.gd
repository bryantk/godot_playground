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
##
## [b]Height, on a 3D map that declares a floor [GridMap].[/b] [Terrain] decides where a
## step in a direction actually lands - up a ramp, onto a ladder, off a ledge - so [code]
## Y[/code] stops being something the caller supplies and becomes something the map
## answers. A fall is then a chain of ordinary one-cell steps downward, paid out from
## [method _settle], with its depth fixed before the step off the ledge committed.
## [b]None of it reaches a flat map or [FreeMotion][/b]: without a floor GridMap
## [method Terrain.resolve_step] returns [code]from + dir[/code] and every expression
## here collapses to the one it was before height existed.

## How many world directions a step may take. 4 for game 1.
@export_range(4, 8, 4) var direction_count: int = 4

## Seconds this actor hangs in the air before a fall starts.
##
## [b]Per actor, because it is characterisation rather than physics.[/b] How far anything
## may fall is the map's business ([member MapContext.max_fall_cells]); how long *this*
## actor dangles first is a property of the actor - a heavy thing drops at once, a light
## one hovers, and the player probably wants a beat the monsters do not get.
##
## [b]It is also the choreography window.[/b] [signal Actor.falling] fires when the fall
## is announced, [i]before[/i] this is waited out, so a listener is told where the actor
## is, where it will land and how long it has to do something about it. At the default of
## zero the fall starts in the same frame the step off the ledge settles, which is what it
## did before this existed.
##
## Counted in [method _process] rather than by a [Timer] so it pauses with the rest of
## physics and dies with [method cancel].
@export_range(0.0, 2.0, 0.05, "or_greater") var fall_delay: float = 0.0

var _moving: bool = false
var _step_key: String = ""
var _queue: Array[Vector3i] = []
var _route_key: String = ""
var _step_intent: Vector3i = Vector3i.ZERO
var _run_scale: float = 1.0

## The step in flight, and how much of it is left, in cells: 1 at commit, 0 at settle.
## The sprite's offset is this fraction of [member _step_back], so the remaining distance
## is the state and the elapsed time is not - which is what lets the speed change mid-cell.
var _step_from: Vector3i = Vector3i.ZERO
var _step_to: Vector3i = Vector3i.ZERO
var _step_back: Vector3 = Vector3.ZERO
var _step_left: float = 0.0

## Where the sprite sits when it has caught up, which is the cell centre for everything
## except a ramp - a ramp's logical cell is its lower end, so standing on one leaves the
## body half a cell below the surface the eye can see (see [constant Terrain.RAMP_RISE]).
##
## Zero on every flat map, which is what makes this invisible to game 1: the offset walks
## from [member _step_back] to this rather than to zero, and on a flat map the two
## expressions are the same one.
var _rest: Vector3 = Vector3.ZERO

## Cells still to fall, paid out one step at a time from [method _settle]
## (open-questions 37). The depth was measured before the step that started the fall
## committed, so this only ever counts down.
var _falling: int = 0

## Seconds left of [member fall_delay] before the drop begins, and whether this fall has
## already been announced. The flag is what keeps [signal Actor.falling] and the hang to
## the *start* of a fall rather than repeating them for every cell of it.
var _fall_wait: float = 0.0
var _fall_begun: bool = false


func _ready() -> void:
	super()
	# Only while a step is in flight. A map of standing NPCs should cost nothing.
	set_process(false)


## A falling actor is busy, and so is one still hanging before a fall. Without this the
## round would close mid-drop and a brain could steer an actor through the air, which is
## neither what a round means nor what falling looks like.
func is_busy() -> bool:
	return _moving or _falling > 0 or _fall_wait > 0.0 or not _queue.is_empty()


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


## A run, as a multiplier on this actor's speed. Set per frame by [Brain] from
## [member InputIntent.run]; 1.0 is a walk.
##
## [b]A grid run is a shorter step, not a longer one.[/b] A step always crosses exactly
## one cell - that is the invariant the whole controller is built on - so the only thing
## a run can change is how long the crossing takes. It therefore goes in beside
## [member MotionController.speed] and the zone modifiers rather than anywhere near the
## distance, and [method step_duration] answers with it included.
##
## [b]It applies to the player's own steps, not to a commanded route.[/b] A [code]
## move_to[/code] in flight runs at the command's speed whatever the player is leaning
## on - see [method _process].
##
## Read fresh every frame like everything else here, so letting go of the key halfway
## across a cell slows the rest of that cell rather than the next one. Same reason the
## remaining distance is the state and the elapsed time is not.
func set_run_scale(scale: float) -> void:
	_run_scale = maxf(0.0, scale)


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
## The run multiplier, or 1.0 while a commanded route is in flight - a [code]move_to[/code]
## crosses its cells at the speed the command asked for, not at the speed the player
## happens to be holding down.
##
## [b]Known limit:[/b] a single scripted [method step] carries no route key, so a cutscene
## that nudges the player one cell while they lean on the run key crosses that one cell
## fast. One cell, once, and the alternative is the brain having to know whether anything
## else is driving its actor - which is the coupling [Brain] exists to avoid.
func _step_rate_scale() -> float:
	return 1.0 if _route_key != "" else _run_scale


func step_duration(dir: Vector3i = Vector3i.ZERO) -> float:
	var base := 1.0 / maxf(0.01, speed * _step_rate_scale() * speed_scale(Vector3(dir)))
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

	# Where a step in this direction actually lands. On a flat map that is from + d and
	# always has been; on a height map [Terrain] resolves ramps, ladders and ledges, and
	# tells us how far the actor falls afterwards.
	#
	# A through-terrain actor is the exception and owns its own Y (open-questions 35), so
	# it neither climbs nor falls and its step is the flat one.
	var plan: Dictionary
	if _actor.through_terrain:
		plan = {"ok": true, "cell": from + d, "fall": 0, "on_ladder": false}
	else:
		plan = Terrain.resolve_step(ctx, from, d, ctx.max_fall_cells)

	var to: Vector3i = plan["cell"]
	if not plan["ok"] or not Passability.can_enter(ctx, to, _actor):
		_actor.report_blocked(to)
		return false

	# Set before committing, not after: a viewless actor settles synchronously inside
	# _commit_step, and _settle is where the fall is paid out.
	_falling = int(plan["fall"])
	_fall_begun = false
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
	# A cancelled fall stops where it is, hang included. A cutscene that seizes an actor
	# mid-drop has said where it wants that actor, and finishing the fall underneath it
	# would move the actor out from under the thing that just took control.
	_falling = 0
	_fall_wait = 0.0
	_fall_begun = false
	_cancel_visual()
	if _route_key != "":
		var key := _route_key
		_route_key = ""
		EventBus.command_finished.emit(key)


## Dead in a grid game, with one exception: [b]on a ladder, jump is the release[/b]
## (open-questions 38). The actor lets go and falls the whole way,
## [member MapContext.max_fall_cells] notwithstanding - the limit is there so a player
## does not walk off a lethal ledge by accident, and letting go of a ladder is the
## opposite of an accident.
func jump(_strength: float) -> String:
	var ctx := context()
	if ctx != null and _actor != null and not is_busy() \
			and Terrain.has_ladder(ctx, _actor.cell()):
		var drop := Terrain.drop_from_ladder(ctx, _actor.cell())
		if drop > 0:
			_falling = drop
			_fall_begun = false
			# Announced like any other fall, but never delayed. fall_delay is the hang
			# an actor does after walking off something by accident; letting go of a
			# ladder is the one fall that was asked for, and it drops at once.
			_begin_fall(ctx, false)
		return ""

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
		# A fall whose landing cell is taken stops in the air above it rather than
		# continuing into someone. Clearing the remaining depth is what makes that a
		# stop and not a hang: a pending fall counts as busy (see is_busy), and nothing
		# would ever pay it out from here, so a round joining on this actor would never
		# close. The actor is left standing on air, which is visible and recoverable -
		# an unclosable round is neither.
		_falling = 0
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

	# 5. The visual is pushed back and walks to its resting offset under _process. This
	#    is the only thing that takes time, and its key is what wait_settle joins.
	#    Started last so that a viewless actor - a headless test, or a settled teleport -
	#    cannot settle the step before actor_stepped above has been published.
	_rest = Vector3(0.0, Terrain.surface_offset(ctx, to), 0.0)

	var view := _actor.view()
	if view == null:
		_settle()
		return

	_step_from = from
	_step_to = to
	# Between the two *surfaces*, not the two cell centres. They are the same thing
	# everywhere except a ramp, whose cell is its lower end - so on a ramp this is what
	# makes the sprite travel up the slope instead of along the floor under it and then
	# pop.
	_step_back = _surface_of(ctx, from) - _surface_of(ctx, to)
	_step_left = 1.0
	view.set_step_offset(_rest + _step_back)
	set_process(true)


## Where the sprite stands on [param cell], in world units - the cell centre plus
## whatever the terrain there lifts it by. One expression for flat ground and ramps,
## because on flat ground the lift is zero.
func _surface_of(ctx: MapContext, cell: Vector3i) -> Vector3:
	return ctx.cell_centre(cell) + Vector3(0.0, Terrain.surface_offset(ctx, cell), 0.0)


## Announces a fall and starts it, after [member fall_delay] if this actor has one.
##
## Called once per fall rather than once per cell: the announcement and the hang belong
## to the fall, and repeating them every cell would turn a long drop into a stutter.
##
## [param delayed] false skips [member fall_delay] and drops immediately. That is what
## letting go of a ladder does - the hang is for an actor that walked off something
## without meaning to, and a release is the one fall nobody is surprised by.
func _begin_fall(ctx: MapContext, delayed: bool = true) -> void:
	_fall_begun = true
	_actor.report_falling(_actor.cell() - Vector3i(0, _falling, 0))

	if delayed and fall_delay > 0.0:
		_fall_wait = fall_delay
		set_process(true)
		return

	_fall_one(ctx)


## One cell of a fall, as an ordinary step straight down. Ordinary on purpose: it goes
## through [method _commit_step] like every other step, so it commits occupancy, moves
## the body, publishes the same signals and takes the same time to look at. "Falling is
## repeated one-cell steps" (open-questions 37) is meant literally.
func _fall_one(ctx: MapContext) -> void:
	_falling -= 1
	var at := _actor.cell()
	_commit_step(ctx, at, at - Vector3i(0, 1, 0))


## The step in flight, advanced by distance rather than by elapsed time.
##
## [b]Why distance.[/b] The remaining fraction of a cell is the state; the speed is read
## fresh every frame and only decides how much of it is spent this frame. A duration fixed
## at commit - which is what a [Tween] is - cannot express an actor that slows down
## halfway across a tile, so an actor stepping into mud would have finished that step at
## its old speed and only slowed on the next one. This is also why [ActorView] no longer
## owns the interpolation.
func _process(delta: float) -> void:
	# Checked before anything else, so a paused game pauses the hang before a fall as
	# well as the step in flight.
	if ModeStack.pauses_physics():
		return

	# The hang. Counted here rather than with a Timer for the same reason the step is:
	# one clock, which pauses and cancels with everything else this controller owns.
	if _fall_wait > 0.0:
		_fall_wait -= delta
		if _fall_wait > 0.0:
			return
		_fall_wait = 0.0
		var falling_ctx := context()
		if falling_ctx == null:
			_falling = 0
			set_process(false)
			return
		_fall_one(falling_ctx)
		return

	if not _moving:
		set_process(false)
		return

	# Flattened, because a step crosses exactly one cell horizontally whatever it does
	# vertically. Without this a climb reads as sqrt(2) cells and takes half again as
	# long as the flat step beside it, and a fall - which is horizontally zero - would
	# divide by zero in the compensation below.
	var d := Space.flatten(Vector3(_step_to - _step_from))
	var rate := maxf(0.0, speed) * _step_rate_scale() * speed_scale(d)
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
			view.set_step_offset(_rest)
		_settle()
		return

	if view != null:
		view.set_step_offset(_rest + _step_back * _step_left)


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

	# The next cell of a fall, before anything else may act. A fall is a chain of
	# ordinary one-cell steps (open-questions 37), so each drop publishes its own
	# actor_stepped and actor_settled and a monster watching the player fall sees every
	# cell of it - but nothing else gets a turn until the actor is on the ground, which
	# is what is_busy() reporting a fall as busy is for.
	#
	# The depth was fixed before the step off the ledge committed, so this only counts
	# down: it cannot discover a deeper hole partway and strand the actor mid-air.
	if _falling > 0 and _actor != null:
		var ctx := context()
		if ctx != null:
			if _fall_begun:
				_fall_one(ctx)
			else:
				_begin_fall(ctx)
			return
		_falling = 0

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
		# Cleared and then re-seated, rather than simply cleared. On a ramp the resting
		# offset is not zero, so a teleport onto one that left the offset at zero would
		# drop the sprite through the slope it is standing on.
		view.cancel_step_offset()
		var ctx := context()
		if ctx != null and _actor != null:
			_rest = Vector3(0.0, Terrain.surface_offset(ctx, _actor.cell()), 0.0)
			if _rest != Vector3.ZERO:
				view.set_step_offset(_rest)
	if _actor != null:
		_actor.update_areas(AreaZone.zones_at(_actor, _actor.cell()))
		_actor.settle_areas()
