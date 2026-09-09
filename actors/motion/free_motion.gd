class_name FreeMotion extends MotionController

## Continuous movement with gravity and jumping, for games 2 and 3. 3D only.
##
## Free actors do not own cells, so there is no occupancy reservation and no
## commit - [method Actor.cell] is computed on demand purely so events can address
## them, which is the whole reason event coordinates are cells even here.

@export var gravity: float = 24.0
@export var jump_strength: float = 8.0
@export var acceleration: float = 60.0

## How close counts as arrived, in world units.
@export var arrive_radius: float = 0.15

## Directions an intent snaps to before it becomes velocity. 8 for game 2, 0 for the
## fully analog game 3.
@export_range(0, 8, 4) var direction_count: int = 0

var _velocity: Vector3 = Vector3.ZERO
var _intent: Vector3 = Vector3.ZERO
var _target: Variant = null
var _target_key: String = ""
var _jump_key: String = ""
var _was_on_floor: bool = true


func is_busy() -> bool:
	return _target != null


## Per-frame steering, in world space and already basis-corrected by [InputProfile].
func set_intent(dir: Vector3) -> void:
	_intent = Space.flatten(dir)
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
	if _target_key != "":
		var key := _target_key
		_target_key = ""
		EventBus.command_finished.emit(key)


func _physics_process(delta: float) -> void:
	var adapt := adapter()
	if adapt == null or ModeStack.pauses_physics():
		return

	var desired := _intent
	if _target != null:
		var to_target := Space.flatten(_target as Vector3 - adapt.world_position())
		if to_target.length() <= arrive_radius:
			var key := _target_key
			_target = null
			_target_key = ""
			if key != "":
				EventBus.command_finished.emit(key)
			desired = Vector3.ZERO
		else:
			desired = to_target.normalized()

	var wanted := desired * speed
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

	var view := _actor.view() if _actor != null else null
	if view is MeshView3D:
		(view as MeshView3D).face_toward(Space.flatten(_velocity))
	elif _actor != null and desired.length_squared() > 0.0001:
		_actor.set_facing(Space.quantise(desired, _actor.facing_count))
