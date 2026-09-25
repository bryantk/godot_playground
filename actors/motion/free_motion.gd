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
var _jump_key: String = ""
var _was_on_floor: bool = true


func is_busy() -> bool:
	return _target != null


## Horizontal speed, not [member _target]: steering with the stick moves the actor
## without any command being in flight, so [method is_busy] is false the whole time it
## is walking. Vertical motion is excluded so that falling or jumping on the spot does
## not read as walking.
func is_travelling() -> bool:
	return _target != null or Space.flatten(_velocity).length_squared() > 0.01


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


func jump(strength: float = -1.0) -> String:
	var adapt := adapter()
	if adapt == null or not adapt.supports_height():
		push_warning("FreeMotion: jump needs a space with height.")
		return ""
	_velocity.y = jump_strength if strength <= 0.0 else strength
	_jump_key = _next_key("jump")
	_was_on_floor = false
	return _jump_key


func cancel() -> void:
	_target = null
	_intent = Vector3.ZERO
	_intent_scale = 1.0
	if _target_key != "":
		var key := _target_key
		_target_key = ""
		EventBus.command_finished.emit(key)


func _physics_process(delta: float) -> void:
	var adapt := adapter()
	if adapt == null or ModeStack.pauses_physics():
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

	# Landing resolves the jump key, so a cutscene can await a jump the same way it
	# awaits a step.
	var on_floor := absf(applied.y) < 0.0001 and _velocity.y < 0.0
	if on_floor:
		_velocity.y = 0.0
		if not _was_on_floor and _jump_key != "":
			var key := _jump_key
			_jump_key = ""
			EventBus.command_finished.emit(key)
	_was_on_floor = on_floor

	if _actor != null and desired.length_squared() > 0.0001:
		_actor.set_facing(Space.quantise(desired, _actor.facing_count))
