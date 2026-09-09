class_name Space2D extends SpaceAdapter

## [SpaceAdapter] over a [CharacterBody2D]. Truncates on the way out and lifts on the
## way in, always through [Space], so the Y a caller hands us is dropped in exactly
## one place.
##
## Works without a body too: an [Actor] under a plain [Node2D] keeps a position and
## reports it, which is what lets a headless test drive movement with no physics.

var _body: Node2D = null
var _char: CharacterBody2D = null


func _bind(body: Node) -> void:
	_body = body as Node2D
	_char = body as CharacterBody2D


func world_position() -> Vector3:
	if _body == null:
		return Vector3.ZERO
	return Space.as_v3(_body.position)


func set_world_position(p: Vector3) -> void:
	if _body == null:
		return
	# Y is dropped here rather than warned about: a command that means to change floor
	# on a flat map is caught by the validator through supports_height(), and a step
	# that merely carries y = 0 must stay silent.
	_body.position = Space.as_v2(p)


func set_facing(dir: Vector3) -> void:
	# 2D actors are drawn, not rotated - rotating the sprite would break the facing
	# frames ActorView picks. Facing is presentation, so it belongs there.
	pass


func body_test_move(from: Vector3, motion: Vector3) -> bool:
	if _char == null:
		return false
	var xf := Transform2D(0.0, Space.as_v2(from))
	return _char.test_move(xf, Space.as_v2(motion))


func move_and_slide(velocity: Vector3, _delta: float) -> Vector3:
	if _char == null:
		return Vector3.ZERO
	var before := _char.position
	_char.velocity = Space.as_v2(velocity)
	_char.move_and_slide()
	return Space.as_v3(_char.position - before)


func supports_height() -> bool:
	return false
