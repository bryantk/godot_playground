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

## Spend the snap remainder by sliding the upscaled image, which halves the size of the
## world's scroll steps.
##
## [b]Off by default, and the reason is worth keeping.[/b] The slide moves the whole
## image, and the followed actor is in that image - so it buys a smoother world scroll
## by making the one thing the eye is locked onto jitter. Measured over a second of
## walking at 4 cells/s:
##
## [codeblock]
##             followed actor          world scroll step
##   off       still, 0 px             0-2 px per frame
##   on        2 px, 47 frames in 60   0-1 px per frame
## [/codeblock]
##
## Whole-texel scrolling is what every game of this look did, and at any ordinary walk
## speed the world is already advancing about a texel a frame, so there is very little
## to win and a visibly unsteady player to lose. Worth turning on only if something
## moves far slower than a texel per frame, where the steps would otherwise stutter.
@export var subtexel_smoothing: bool = false

## The [SubViewportContainer] the remainder is spent on. See [method bind_upscale].
@export var upscale_path: NodePath = NodePath()

## How far back along the view axis to sit. Orthographic, so this changes nothing but
## clipping - it just has to clear the geometry.
@export var distance: float = 40.0

## Raised so the camera frames a standing character rather than its feet.
@export var target_height: float = 0.5

var _camera: Camera3D = null
var _yaw: float = 0.0
var _tween: Tween = null
var _subtexel := Vector2.ZERO
var _upscale: Control = null


func _ready() -> void:
	super()
	_camera = _find_camera()
	if not upscale_path.is_empty():
		_upscale = get_node_or_null(upscale_path) as Control
	_apply_pitch()
	fit_viewport()


## Hand the rig the container that upscales the low-res viewport, so it can spend its
## own snap remainder on it.
##
## The rig applies this rather than exposing [method subtexel_offset] for a caller to
## apply, because a caller doing it in its own [method Node._process] reads whatever
## remainder the rig computed [i]last[/i] frame - the rig lives deep in the scene and
## processes after the map root. One stale frame is a full texel of error at walking
## speed, which is a visible wobble on the one actor this is supposed to hold still.
func bind_upscale(container: Control) -> void:
	_upscale = container


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

	# Snap the followed actor's position, not the camera's, and hang the camera off the
	# result at a fixed offset. That is what lets a sprite land on an exact pixel: the
	# view snaps the same quantity through the same helper, so the two rounds are
	# identical rather than merely similar, and the actor sits perfectly still in the
	# low-res buffer while the world stays crisp underneath it.
	var focus := focus_of(who)
	var snapped := focus
	if quantise_camera and texels_per_unit > 0:
		var t := float(texels_per_unit)
		snapped = Space.snap_to_basis(focus, basis, t)
		# Screen-space remainder: one world unit along a screen axis is t pixels.
		var lost := focus - snapped
		_subtexel = Vector2(lost.dot(basis.x) * t, lost.dot(basis.y) * t)
	else:
		_subtexel = Vector2.ZERO

	_camera.global_position = snapped + Vector3.UP * target_height + basis.z * distance
	_camera.global_basis = basis
	_push_camera_frame(basis)
	_apply_subtexel()


## Hand every actor in the map the frame the camera is looking through: to its sprite,
## the grid the camera just snapped to, so it rounds the way the camera did; to its
## mover, the basis, so it can cancel the depth compression out of its speed.
##
## Both are the same fact - where the camera is looking from - and doing either anywhere
## else would mean something downstream guessing at the camera's pitch. Cheap enough to
## do per frame at these actor counts, and one walk of the list covers both.
func _push_camera_frame(basis: Basis) -> void:
	if _ctx == null:
		return
	for who: Actor in _ctx.actors():
		var v := who.view()
		if v is SpriteView3D:
			(v as SpriteView3D).set_pixel_grid(basis, texels_per_unit, quantise_camera)
		var m := who.motion()
		if m != null:
			m.set_view_basis(basis)


## Shift the upscaled image back by the remainder the camera snap threw away.
##
## Rounded to whole [i]screen[/i] pixels, which is not a detail: a Control drawn at a
## fractional position resamples its texture, so with nearest filtering some texels get
## one screen pixel more than their neighbours and the split moves every frame. That is
## the shimmer this whole mechanism exists to remove, reintroduced at the last step. At
## a shrink of 2 the rounding still leaves half-texel granularity, so the followed actor
## lands within a quarter of a low-res pixel of where it should be - and the error does
## not accumulate.
func _apply_subtexel() -> void:
	if _upscale == null:
		return
	if not (subtexel_smoothing and quantise_camera):
		_upscale.position = Vector2.ZERO
		return

	var shrink := 1.0
	if _upscale is SubViewportContainer:
		shrink = float(maxi(1, (_upscale as SubViewportContainer).stretch_shrink))
	# Screen y grows downward and the camera's up axis does not, hence the one flip.
	_upscale.position = (Vector2(-_subtexel.x, _subtexel.y) * shrink).round()


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
