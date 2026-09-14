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
	# The body does not turn. Facing is a presentation concern: SpriteView3D picks a
	# frame from the facing and the camera yaw, and never asks the adapter.
	pass


func body_test_move(from: Vector3, motion: Vector3) -> bool:
	if _char == null:
		return false
	var xf := Transform3D(Basis.IDENTITY, from)
	return _char.test_move(xf, motion)


## The full [Vector3], Y included: a grid map in 3D has floors, and a zone painted on the
## upper storey must not answer for the cell below it.
func areas_at(world: Vector3) -> Array[Node]:
	var out: Array[Node] = []
	if _body == null or not _body.is_inside_tree():
		return out

	var params := PhysicsPointQueryParameters3D.new()
	params.position = world
	params.collide_with_areas = true
	params.collide_with_bodies = false
	params.collision_mask = AreaZone.LAYER

	for hit in _body.get_world_3d().direct_space_state.intersect_point(params, 32):
		var collider: Node = hit.get("collider")
		if collider != null:
			out.append(collider)
	return out


func move_and_slide(velocity: Vector3, _delta: float) -> Vector3:
	if _char == null:
		return Vector3.ZERO
	var before := _char.position
	_char.velocity = velocity
	_char.move_and_slide()
	return _char.position - before


func supports_height() -> bool:
	return true
