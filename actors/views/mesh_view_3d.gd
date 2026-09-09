class_name MeshView3D extends ActorView

## Game 3's presentation: a skeletal mesh that rotates to its actual continuous
## heading. No direction count applies here, which is why "how many sprite
## directions?" was only ever a question about games 1 and 2.

## Radians per second the model turns to face a new heading. Zero snaps.
@export var turn_speed: float = 12.0

var _tree: AnimationTree = null
var _player: AnimationPlayer = null
var _target_yaw: float = 0.0
var _has_target: bool = false


func _ready() -> void:
	super()
	_tree = _find_node_of_type(self, "AnimationTree") as AnimationTree
	_player = _find_node_of_type(self, "AnimationPlayer") as AnimationPlayer


func set_facing(dir: Vector3i) -> void:
	if dir == Vector3i.ZERO:
		return
	# atan2(x, z) rather than the DIRS_* convention: a mesh faces a real angle, so
	# there is no index to agree with.
	_target_yaw = atan2(float(dir.x), float(dir.z))
	_has_target = true
	if turn_speed <= 0.0 and _visual is Node3D:
		(_visual as Node3D).rotation.y = _target_yaw


## Steer the model toward its heading. A continuous heading is the one thing here that
## cannot be set and forgotten.
func face_toward(velocity: Vector3) -> void:
	if velocity.length_squared() < 0.0001:
		return
	_target_yaw = atan2(velocity.x, velocity.z)
	_has_target = true


func _process(delta: float) -> void:
	if not _has_target or turn_speed <= 0.0 or not (_visual is Node3D):
		return
	var node := _visual as Node3D
	node.rotation.y = lerp_angle(node.rotation.y, _target_yaw, minf(1.0, turn_speed * delta))


func play(anim: StringName) -> String:
	if _player == null or not _player.has_animation(anim):
		return ""
	_keys += 1
	var key := "anim:%s:%d" % [anim, _keys]
	_player.play(anim)
	_player.animation_finished.connect(
		func (_a: StringName) -> void: EventBus.command_finished.emit(key), CONNECT_ONE_SHOT)
	return key


func _write_offset() -> void:
	# A free-motion actor has no step offset to apply; the body itself moves. This is
	# left deliberately empty rather than removed, so a grid actor in a 3D town can
	# still use a mesh.
	if _visual is Node3D and _offset != Vector3.ZERO:
		(_visual as Node3D).position = _offset


static func _find_node_of_type(root: Node, type_name: String) -> Node:
	for child in root.get_children():
		if child.is_class(type_name):
			return child
		var found := _find_node_of_type(child, type_name)
		if found != null:
			return found
	return null
