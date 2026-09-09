class_name OrthoPixelRig extends CameraRig

## Game 2's camera: orthographic, pixel-quantised, yaw snapped to four 90-degree
## stops, pitch 30.
##
## [b]Why 90-degree stops.[/b] All four views are congruent, so ground tiles stay
## axis-aligned at every stop and there is exactly one tile geometry to draw. With
## eight stops at 45 degrees the odd stops render tiles as diamonds and the even stops
## render them axis-aligned, and those are not congruent at any pitch - so eight stops
## costs two distinct tile presentations, not merely twice the sprite art.
##
## [b]Why 30 degrees.[/b] A ground tile projects to
## [code]TEXELS_PER_TILE x TEXELS_PER_TILE * sin(pitch)[/code] px. If that height is
## not a whole number the tile grid drifts against the pixel grid and rows come out
## unequal. Only the angles where it lands on an integer are usable at all - 30.00,
## 34.23, 38.68, 43.43, 48.59, 54.34, 61.04, 69.64 - and every round number that looks
## like a natural choice (45, 60) is fractional. 30 gives an exact 16x8 tile, and being
## the shallowest of them it shows height best, which suits the game that has jumping.

const TEXELS_PER_TILE := 16

## Vertical faces are 13.856 px per world unit at 30 degrees, so art authored at 16
## texels loses ~14% of its rows unevenly. Author vertical faces at 14 instead.
const TEXELS_PER_UNIT_VERTICAL := 14

const STOPS := 4

## 16 * sin(pitch) must be a whole number. See the class note.
@export_range(20.0, 80.0, 0.01) var pitch_degrees: float = 30.0

@export var yaw_stop: int = 0 : set = _set_yaw_stop

## Seconds an animated snap between stops takes. "Rotatable live" is this, not a free
## spin - which also reads better.
@export var snap_seconds: float = 0.22

## Texels per world unit. Sets both the orthographic size (so one texel is one screen
## pixel) and the grid the camera snaps to.
@export var texels_per_unit: int = TEXELS_PER_TILE

## Snap the camera to whole texels each frame. Without this everything shimmers as it
## moves, because the world-to-pixel mapping drifts continuously.
@export var quantise_camera: bool = true

## How far back along the view axis to sit. Orthographic, so this changes nothing but
## clipping - it just has to clear the geometry.
@export var distance: float = 40.0

## Raised so the camera frames a standing character rather than its feet.
@export var target_height: float = 0.5

var _camera: Camera3D = null
var _yaw: float = 0.0
var _tween: Tween = null
var _subtexel := Vector2.ZERO


func _ready() -> void:
	super()
	_camera = _find_camera()
	_apply_pitch()
	fit_viewport()


func _find_camera() -> Camera3D:
	if get_parent() is Camera3D:
		return get_parent() as Camera3D
	for child in get_children():
		if child is Camera3D:
			return child as Camera3D
	return null


func yaw() -> float:
	return _yaw


## Size the orthographic frustum so one texel is exactly one viewport pixel. Godot's
## orthographic [member Camera3D.size] is the vertical extent in world units, so that
## is simply the viewport height divided by the texel density.
func fit_viewport() -> void:
	if _camera == null or not is_inside_tree():
		return
	var vp := get_viewport()
	if vp == null:
		return
	var height := vp.get_visible_rect().size.y
	if height <= 0.0 or texels_per_unit <= 0:
		return
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.size = height / float(texels_per_unit)


## The part of the camera's position that quantisation threw away, in screen pixels.
##
## This is the other half of sub-pixel movement: the logical position stays
## continuous, the camera snaps to whole texels, and the remainder is handed to the
## viewport to offset by - which is what makes the followed actor look perfectly
## smooth. There is only one offset to spend, so everything else snaps texel to texel.
func subtexel_offset() -> Vector2:
	return _subtexel


func _process(_delta: float) -> void:
	if _camera == null or _target_id == &"" or _ctx == null:
		return
	var who := _ctx.actor(_target_id)
	if who == null:
		return

	var basis := Basis.from_euler(Vector3(-deg_to_rad(pitch_degrees), _yaw, 0.0))
	var focus := who.world_position() + Vector3.UP * target_height
	var desired := focus + basis.z * distance

	if quantise_camera and texels_per_unit > 0:
		# Decompose along the camera's own axes and snap the two that map to screen.
		# The basis is orthonormal, so the dot products are an exact change of basis.
		var t := float(texels_per_unit)
		var r := desired.dot(basis.x)
		var u := desired.dot(basis.y)
		var f := desired.dot(basis.z)
		var rq: float = round(r * t) / t
		var uq: float = round(u * t) / t
		# Screen-space remainder: one world unit along a screen axis is t pixels.
		_subtexel = Vector2((r - rq) * t, (u - uq) * t)
		desired = basis.x * rq + basis.y * uq + basis.z * f
	else:
		_subtexel = Vector2.ZERO

	_camera.global_position = desired
	_camera.global_basis = basis


## Ground tile depth on screen, in px. Whole number by construction at a valid pitch.
func floor_depth_px() -> float:
	return float(TEXELS_PER_TILE) * sin(deg_to_rad(pitch_degrees))


## Screen px per world unit of height. Never a whole number when the floor is one -
## 256 has no Pythagorean pair, so floors and walls cannot both land clean. Floors
## tile across the whole screen and walls once per structure, so the floor wins.
func wall_px_per_unit() -> float:
	return float(TEXELS_PER_TILE) * cos(deg_to_rad(pitch_degrees))


## Is the current pitch pixel-clean? Worth asserting in a test, since the failure is
## subtle on screen and invisible in code.
func is_pixel_clean() -> bool:
	var depth := floor_depth_px()
	return absf(depth - round(depth)) < 0.005


func rotate_to(target_yaw: float, seconds: float = -1.0) -> String:
	var stop := Space.yaw_index(target_yaw)
	return _snap_to(stop, snap_seconds if seconds < 0.0 else seconds)


## Turn one stop. This is what a rotate-view button calls.
func rotate_by_stops(delta: int) -> String:
	return _snap_to(posmod(yaw_stop + delta, STOPS), snap_seconds)


func _set_yaw_stop(value: int) -> void:
	yaw_stop = posmod(value, STOPS)
	_yaw = float(yaw_stop) * PI * 0.5
	_apply_yaw()
	yaw_changed.emit(_yaw)


func _snap_to(stop: int, seconds: float) -> String:
	stop = posmod(stop, STOPS)
	if stop == yaw_stop:
		return ""

	var key := _next_key("yaw")
	if _tween != null and _tween.is_valid():
		_tween.kill()

	if seconds <= 0.0 or not is_inside_tree():
		yaw_stop = stop
		EventBus.command_finished.emit(key)
		return key

	# Tween the angle, then land exactly on the stop - so the sprite frames re-pick
	# once, at the end, rather than flickering through intermediate values.
	var from := _yaw
	var to := float(stop) * PI * 0.5
	# Shortest way round, so turning from stop 3 to stop 0 does not spin backwards.
	if absf(to - from) > PI:
		to += TAU if to < from else -TAU

	_tween = create_tween()
	_tween.tween_method(_set_yaw_radians, from, to, seconds) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_IN_OUT)
	_tween.finished.connect(func () -> void:
		yaw_stop = stop
		EventBus.command_finished.emit(key))
	return key


func _set_yaw_radians(v: float) -> void:
	_yaw = v
	_apply_yaw()
	yaw_changed.emit(_yaw)


func _apply_yaw() -> void:
	if _camera != null:
		_camera.rotation.y = _yaw


func _apply_pitch() -> void:
	if _camera == null:
		return
	_camera.projection = Camera3D.PROJECTION_ORTHOGONAL
	_camera.rotation.x = -deg_to_rad(pitch_degrees)
	if not is_pixel_clean():
		push_warning("OrthoPixelRig: pitch %.2f gives a floor depth of %.3f px, which is not a whole number - the tile grid will drift against the pixel grid." % [pitch_degrees, floor_depth_px()])
