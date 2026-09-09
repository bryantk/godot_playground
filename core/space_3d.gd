class_name Space3D extends SpaceAdapter

## [SpaceAdapter] over a [CharacterBody3D]. The canonical case - positions pass
## through untouched, since [Vector3] is already the shared vocabulary.
##
## Works without a body too, for the same reason [Space2D] does: a headless test
## needs to drive movement with no physics server running.

var _body: Node3D = null
var _char: CharacterBody3D = null


func _bind(body: Node) -> void:
	_body = body as Node3D
	_char = body as CharacterBody3D


func world_position() -> Vector3:
	if _body == null:
		return Vector3.ZERO
	return _body.position


func set_world_position(p: Vector3) -> void:
	if _body == null:
		return
	_body.position = p


func set_facing(dir: Vector3) -> void:
	# Meshes rotate to face; sprites do not. MeshView3D overrides this by asking the
	# adapter, so a SpriteView3D actor simply never calls it.
	pass


func body_test_move(from: Vector3, motion: Vector3) -> bool:
	if _char == null:
		return false
	var xf := Transform3D(Basis.IDENTITY, from)
	return _char.test_move(xf, motion)


func move_and_slide(velocity: Vector3, _delta: float) -> Vector3:
	if _char == null:
		return Vector3.ZERO
	var before := _char.position
	_char.velocity = velocity
	_char.move_and_slide()
	return _char.position - before


func supports_height() -> bool:
	return true
