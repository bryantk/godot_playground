class_name FreeMotion extends MotionController

## Continuous movement with gravity and jumping, for game 2. 3D only.
##
## Free actors do not own cells, so there is no occupancy reservation and no
## commit - [method Actor.cell] is computed on demand purely so events can address
## them, which is the whole reason event coordinates are cells even here.

@export var gravity: float = 24.0
@export var jump_strength: float = 8.0
@export var acceleration: float = 60.0

## How close counts as arrived, in world units.
@export var arrive_radius: float = 0.15

## Directions an intent snaps to before it becomes velocity. 8 for game 2; 0 leaves
## the intent analog, which nothing ships today.
@export_range(0, 8, 4) var direction_count: int = 0

var _velocity: Vector3 = Vector3.ZERO
var _intent: Vector3 = Vector3.ZERO
var _intent_scale: float = 1.0
var _target: Variant = null
var _target_key: String = ""

## The player's own jump button, [method jump] - not [member _jump_key], which is
## [method jump_to]'s. Two keys because the two are independent presses/commands that
## can never be in flight at once (see [method jump]'s own guard), but read cleanest as
## two named fields rather than one meaning two things.
var _hop_key: String = ""
var _was_on_floor: bool = true

var _jump_key: String = ""

## An aimed jump in flight - see [method jump_to]. [code]null[/code] means no jump is
## in progress, the same "Variant that is either a real value or null" shape [member
## _target] already uses.
var _jump_target: Variant = null
var _jump_start: Vector3 = Vector3.ZERO
## The vertical speed [method jump_to] launches at, computed once so gravity alone
## carries the rest of the arc - see that method's own doc for the two-piece kinematics.
var _jump_v0: float = 0.0
var _jump_duration: float = 0.0
var _jump_elapsed: float = 0.0


func is_busy() -> bool:
	return _target != null or _jump_target != null


## Horizontal speed, not [member _target]: steering with the stick moves the actor
## without any command being in flight, so [method is_busy] is false the whole time it
## is walking. Vertical motion is excluded so that falling or jumping on the spot does
## not read as walking.
func is_travelling() -> bool:
	return _target != null or _jump_target != null \
		or Space.flatten(_velocity).length_squared() > 0.01


## Per-frame steering, in world space and already basis-corrected by [InputProfile].
##
## [b]Speed is [param scale], not the length of [param dir].[/b] A run cannot ride in the
## vector's magnitude, because this is where the intent is quantised to
## [member direction_count] - snapping to one of eight headings means normalising, which
## throws any magnitude above 1 away. That is exactly what happened to [member
## PlayerController.run_speed_scale] until 2026-09-14: the controller multiplied the
## direction by 3 and this method discarded it on the next line, so holding run did
## nothing in either demo
## and only an actor left analog ([code]direction_count == 0[/code], which nothing ships)
## ever ran. Direction and speed are separate arguments so that cannot recur.
func set_intent(dir: Vector3, scale: float = 1.0) -> void:
	_intent = Space.flatten(dir)
	_intent_scale = maxf(0.0, scale)
	if direction_count > 0 and _intent.length_squared() > 0.0001:
		var snapped := Space.quantise(_intent, direction_count)
		_intent = Vector3(snapped).normalized() * minf(1.0, _intent.length())


## The player's own jump button - straight up (or [param strength] worth of it), with
## whatever horizontal velocity is already carrying. No target, unlike [method jump_to];
## [PlayerController]'s own caller.
func jump(strength: float = -1.0) -> String:
	var adapt := adapter()
	if adapt == null or not adapt.supports_height():
		push_warning("FreeMotion: jump needs a space with height.")
		return ""
	_velocity.y = jump_strength if strength <= 0.0 else strength
	_hop_key = _next_key("jump")
	_was_on_floor = false
	return _hop_key


func step(dir: Vector3i) -> bool:
	# A free actor has no cells to step between, but an event that says "step north"
	# should still nudge it, so this reads as one cell of intent rather than a warning.
	set_intent(Vector3(dir))
	face(dir)
	return true


func move_to(cell: Vector3i, opts: Dictionary = {}) -> String:
	if _actor == null:
		return ""
	if opts.has("speed"):
		speed = float(opts["speed"])
	var ctx := context()
	if ctx == null:
		return ""
	_target = ctx.cell_centre(cell)
	_target_key = _next_key("move")
	return _target_key


## Jumps to [param cell], arcing [param height] above it before landing - a real
## projectile. [param height]'s peak sets the launch speed
## ([code]v0 = sqrt(2 * gravity * rise)[/code], [param rise] being how far up from here
## that peak actually is); solving [code]y(t) = target.y[/code] for the later root (past
## the peak, coming back down) gives the total flight time, and dividing the horizontal
## distance by that time gives a constant horizontal velocity that lands exactly on the
## cell the instant time runs out. Horizontal steering is suspended for the duration - a
## jump is an aim-and-commit toss, not something a stick nudges mid-air - and resumes
## the moment it lands.
func jump_to(cell: Vector3i, height: float) -> String:
	var adapt := adapter()
	var ctx := context()
	if adapt == null or ctx == null or not adapt.supports_height():
		push_warning("FreeMotion: jump needs a space with height.")
		return ""

	if _target_key != "":
		var stale := _target_key
		_target_key = ""
		EventBus.command_finished.emit(stale)
	_target = null

	_jump_start = adapt.world_position()
	var target: Vector3 = ctx.cell_centre(cell)
	var rise := maxf(0.01, target.y + maxf(0.0, height) - _jump_start.y)
	_jump_v0 = sqrt(2.0 * gravity * rise)
	_jump_duration = (_jump_v0 + sqrt(2.0 * gravity * maxf(0.0, height))) / gravity
	_jump_elapsed = 0.0
	_jump_target = target

	_velocity = Space.flatten(target - _jump_start) / maxf(0.0001, _jump_duration)
	_velocity.y = _jump_v0
	_jump_key = _next_key("jump")
	return _jump_key


func cancel() -> void:
	_target = null
	_intent = Vector3.ZERO
	_intent_scale = 1.0
	if _target_key != "":
		var key := _target_key
		_target_key = ""
		EventBus.command_finished.emit(key)

	if _jump_target != null:
		_jump_target = null
		_velocity = Vector3.ZERO
		if _jump_key != "":
			var jkey := _jump_key
			_jump_key = ""
			EventBus.command_finished.emit(jkey)

	if _hop_key != "":
		var hkey := _hop_key
		_hop_key = ""
		EventBus.command_finished.emit(hkey)


func _physics_process(delta: float) -> void:
	var adapt := adapter()
	if adapt == null or ModeStack.pauses_physics():
		return

	if _jump_target != null:
		_jump_elapsed += delta
		_velocity.y -= gravity * delta
		adapt.move_and_slide(_velocity, delta)

		if _jump_elapsed >= _jump_duration:
			var landed: Vector3 = _jump_target
			adapt.set_world_position(landed)
			_jump_target = null
			_velocity = Vector3.ZERO
			if _actor != null:
				var dir := Space.flatten(landed - _jump_start)
				if dir.length_squared() > 0.0001:
					_actor.set_facing(Space.quantise(dir, _actor.facing_count))
			var key := _jump_key
			_jump_key = ""
			if key != "":
				EventBus.command_finished.emit(key)
		return

	var desired := _intent
	# A commanded move runs at the command's own speed. Whatever the player happens to
	# be holding is steering input, and steering is not what is driving this actor while
	# a `move_to` is in flight.
	var scale := _intent_scale
	if _target != null:
		scale = 1.0
		var to_target := Space.flatten(_target as Vector3 - adapt.world_position())
		# Arrival scales with the compensation, because the approach speed does. A
		# depth-bound actor at pitch 30 crosses twice the ground per frame, and a
		# tolerance sized for the uncompensated speed is one it can step over and back
		# across forever.
		var reach := arrive_radius
		if to_target.length_squared() > 0.0001:
			reach *= compensate(to_target.normalized()).length()
		if to_target.length() <= reach:
			var key := _target_key
			_target = null
			_target_key = ""
			if key != "":
				EventBus.command_finished.emit(key)
			desired = Vector3.ZERO
		else:
			desired = to_target.normalized()

	# Compensated after the speed multiply and before acceleration, so acceleration
	# stays in honest world units and only the velocity it is chasing is stretched.
	#
	# Zone modifiers go in with the speed rather than into the velocity afterwards, so
	# that walking into mud decelerates over the acceleration ramp instead of dropping
	# the actor's speed in one frame. They are asked with the heading, so a zone that
	# only slows northward movement answers a free actor the same way it answers a grid
	# one - Passability.cardinals resolves a diagonal to the two cardinals it lies
	# between.
	var wanted := compensate(desired * speed * scale * speed_scale(desired))
	_velocity.x = move_toward(_velocity.x, wanted.x, acceleration * delta)
	_velocity.z = move_toward(_velocity.z, wanted.z, acceleration * delta)
	_velocity.y -= gravity * delta

	var applied := adapt.move_and_slide(_velocity, delta)

	# Landing resolves the hop key, so a cutscene can await a player-triggered jump the
	# same way it awaits a step - jump_to's own key is resolved in its own branch above
	# and never reaches here.
	var on_floor := absf(applied.y) < 0.0001 and _velocity.y < 0.0
	if on_floor:
		_velocity.y = 0.0
		if not _was_on_floor and _hop_key != "":
			var key := _hop_key
			_hop_key = ""
			EventBus.command_finished.emit(key)
	_was_on_floor = on_floor

	if _actor != null and desired.length_squared() > 0.0001:
		_actor.set_facing(Space.quantise(desired, _actor.facing_count))
