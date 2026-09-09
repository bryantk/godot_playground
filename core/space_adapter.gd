class_name SpaceAdapter extends Node

## The only place [Vector2] and [Vector3] meet. Everything above this speaks
## [Vector3] world positions and [Vector3i] cells and never names a [Node2D] or
## [Node3D] type.
##
## GDScript has no interfaces and [Node2D]/[Node3D] share no useful base, so this is a
## plain [Node] child of the actor root that reaches up to its parent body.
## [Space2D] and [Space3D] implement it with identical signatures.
##
## Keep it thin. Every method added here has to be written twice and can drift; when
## something can be computed above the adapter from [Vector3]s, compute it there. In
## particular the grid-step tween's visual offset is deliberately NOT here - it lives
## on [ActorView], which owns what an actor looks like.

## The body this adapter drives. Left null it takes its parent, which is the normal
## arrangement; an explicit value is for tests that drive a body from outside the tree.
@export var body_path: NodePath = NodePath()


func _ready() -> void:
	_bind(_resolve_body())


## Resolve the node this adapter should drive.
##
## The adapter is a child of [Actor], and [Actor] is itself a child of the body - so
## "reach up to the parent" means walking up to the first spatial ancestor, not taking
## [method Node.get_parent]. Walking also means an extra grouping node between the two
## does not break the binding.
func _resolve_body() -> Node:
	if not body_path.is_empty():
		return get_node_or_null(body_path)

	var n := get_parent()
	while n != null:
		if n is Node2D or n is Node3D:
			return n
		n = n.get_parent()
	return null


# -- To implement -------------------------------------------------------------

## Called once the body is known, so an implementation can cache typed references
## instead of casting on every call.
func _bind(_body: Node) -> void:
	pass


func world_position() -> Vector3:
	return Vector3.ZERO


func set_world_position(_p: Vector3) -> void:
	pass


func set_facing(_dir: Vector3) -> void:
	pass


## Would moving [param motion] from [param from] hit something? This is the escape
## hatch in [Passability] for objects that carry no tile data - a pushed crate, a door
## body, a temporary barrier.
func body_test_move(_from: Vector3, _motion: Vector3) -> bool:
	return false


## Applies [param velocity] for one frame and returns the motion actually achieved,
## so a caller can tell a blocked slide from a clean one without touching physics.
func move_and_slide(_velocity: Vector3, _delta: float) -> Vector3:
	return Vector3.ZERO


## False for [Space2D]. This is how a command carrying a non-zero Y on a flat map
## produces a warning instead of a silent no-op.
func supports_height() -> bool:
	return true
