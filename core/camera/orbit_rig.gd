class_name OrbitRig extends CameraRig

## Game 3's camera: player-driven yaw and pitch on a spring arm, with collision.
## The only rig where the player owns the camera, which is what the
## [code]player_camera[/code] capability names.

@export var sensitivity: Vector2 = Vector2(2.5, 1.8)
@export var pitch_limits: Vector2 = Vector2(-1.2, 0.45)
@export var arm_length: float = 4.5

var _arm: SpringArm3D = null
var _yaw: float = 0.0
var _pitch: float = -0.35


func _ready() -> void:
	super()
	_arm = _find_arm(self)
	if _arm != null:
		_arm.spring_length = arm_length
	_apply()


func yaw() -> float:
	return _yaw


## Fed from [member InputIntent.look]. Ignored while an event has borrowed the camera,
## so a cutscene is not fought by a player leaning on the stick.
func look(delta_look: Vector2, delta: float) -> void:
	if is_locked():
		return
	_yaw -= delta_look.x * sensitivity.x * delta
	_pitch = clampf(_pitch - delta_look.y * sensitivity.y * delta, pitch_limits.x, pitch_limits.y)
	_apply()
	yaw_changed.emit(_yaw)


func rotate_to(target_yaw: float, seconds: float = 0.0) -> String:
	var key := _next_key("yaw")
	if seconds <= 0.0 or not is_inside_tree():
		_yaw = target_yaw
		_apply()
		yaw_changed.emit(_yaw)
		EventBus.command_finished.emit(key)
		return key

	var tween := create_tween()
	tween.tween_method(func (v: float) -> void:
		_yaw = v
		_apply()
		yaw_changed.emit(v), _yaw, target_yaw, seconds).set_trans(Tween.TRANS_SINE)
	tween.finished.connect(func () -> void: EventBus.command_finished.emit(key))
	return key


func zoom_to(z: float, seconds: float = 0.0) -> String:
	if _arm == null:
		return ""
	var key := _next_key("zoom")
	if seconds <= 0.0 or not is_inside_tree():
		_arm.spring_length = z
		EventBus.command_finished.emit(key)
		return key
	var tween := create_tween()
	tween.tween_property(_arm, "spring_length", z, seconds)
	tween.finished.connect(func () -> void: EventBus.command_finished.emit(key))
	return key


func _process(delta: float) -> void:
	if _arm == null or _target_id == &"" or _ctx == null:
		return
	var actor := _ctx.actor(_target_id)
	if actor == null:
		return
	_arm.position = _arm.position.lerp(actor.world_position(), minf(1.0, follow_speed * delta))


func _apply() -> void:
	if _arm == null:
		return
	_arm.rotation = Vector3(_pitch, _yaw, 0.0)


static func _find_arm(root: Node) -> SpringArm3D:
	if root.get_parent() is SpringArm3D:
		return root.get_parent() as SpringArm3D
	for child in root.get_children():
		if child is SpringArm3D:
			return child as SpringArm3D
	return null
