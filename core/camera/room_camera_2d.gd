class_name RoomCamera2D extends CameraRig

## Game 1's camera: follows with a deadzone and clamps to map bounds, or snaps a
## screen at a time for the classic room scroll.

enum Style { FOLLOW, ROOM_SNAP }

@export var style: Style = Style.FOLLOW

## Half-extents of the box the target may move inside before the camera moves, in px.
@export var deadzone: Vector2 = Vector2(24, 16)

## Map bounds in px. Zero size means unclamped.
@export var bounds: Rect2 = Rect2()

var _camera: Camera2D = null


func _ready() -> void:
	super()
	_camera = _find_camera()


func _find_camera() -> Camera2D:
	if get_parent() is Camera2D:
		return get_parent() as Camera2D
	for child in get_children():
		if child is Camera2D:
			return child as Camera2D
	return null


func _process(delta: float) -> void:
	if _camera == null or is_locked() or _target_id == &"" or _ctx == null:
		return
	var actor := _ctx.actor(_target_id)
	if actor == null:
		return

	var target := Space.as_v2(focus_of(actor))
	match style:
		Style.ROOM_SNAP:
			_camera.position = _room_origin(target)
		_:
			_camera.position = _clamp_to_bounds(_follow(target, delta))


func _follow(target: Vector2, delta: float) -> Vector2:
	var offset := target - _camera.position
	var pull := Vector2.ZERO
	if absf(offset.x) > deadzone.x:
		pull.x = offset.x - signf(offset.x) * deadzone.x
	if absf(offset.y) > deadzone.y:
		pull.y = offset.y - signf(offset.y) * deadzone.y
	return _camera.position + pull * minf(1.0, follow_speed * delta)


## How much world the camera actually shows. Divided by zoom, because a zoomed-in
## camera sees less world, not more - clamping and room-snapping against the raw
## viewport size would both be wrong by exactly the zoom factor.
func _visible_world_size() -> Vector2:
	var size := Vector2(get_viewport().get_visible_rect().size)
	var zoom := _camera.zoom
	if zoom.x <= 0.0 or zoom.y <= 0.0:
		return size
	return size / zoom


## Which screenful [param target] is in, snapped to that screen's origin.
func _room_origin(target: Vector2) -> Vector2:
	var size := _visible_world_size()
	if size.x <= 0.0 or size.y <= 0.0:
		return _camera.position
	return (target / size).floor() * size + size * 0.5


func _clamp_to_bounds(p: Vector2) -> Vector2:
	if bounds.size == Vector2.ZERO:
		return p
	var half := _visible_world_size() * 0.5
	# A map smaller than the screen on an axis centres on that axis rather than
	# clamping to a range that runs backwards.
	var lo := bounds.position + half
	var hi := bounds.end - half
	return Vector2(
		(bounds.position.x + bounds.end.x) * 0.5 if lo.x > hi.x else clampf(p.x, lo.x, hi.x),
		(bounds.position.y + bounds.end.y) * 0.5 if lo.y > hi.y else clampf(p.y, lo.y, hi.y),
	)


func move_to(cell: Vector3i, seconds: float = 0.0) -> String:
	if _camera == null or _ctx == null:
		return ""
	var to := Space.as_v2(_ctx.cell_centre(cell))
	var key := _next_key("move")
	if seconds <= 0.0 or not is_inside_tree():
		_camera.position = to
		EventBus.command_finished.emit(key)
		return key

	var tween := create_tween()
	tween.tween_property(_camera, "position", to, seconds) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	tween.finished.connect(func () -> void: EventBus.command_finished.emit(key))
	return key


func zoom_to(z: float, seconds: float = 0.0) -> String:
	if _camera == null:
		return ""
	var key := _next_key("zoom")
	var to := Vector2(z, z)
	if seconds <= 0.0 or not is_inside_tree():
		_camera.zoom = to
		EventBus.command_finished.emit(key)
		return key
	var tween := create_tween()
	tween.tween_property(_camera, "zoom", to, seconds)
	tween.finished.connect(func () -> void: EventBus.command_finished.emit(key))
	return key
