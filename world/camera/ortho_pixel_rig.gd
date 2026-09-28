class_name OrthoPixelRig extends CameraRig

## Game 2's camera: orthographic, pixel-quantised, yaw snapped to four 90-degree stops,
## pitch free between a flat-on elevation and top-down.
##
## [b]Why 90-degree stops.[/b] All four views are congruent, so ground tiles stay
## axis-aligned at every stop and there is exactly one tile geometry to draw. With
## eight stops at 45 degrees the odd stops render tiles as diamonds and the even stops
## render them axis-aligned, and those are not congruent at any pitch - so eight stops
## costs two distinct tile presentations, not merely twice the sprite art.
##
## [b]Why pitch is a slider and yaw is not.[/b] The yaw stops are a correctness
## constraint: the tile geometry has to be congruent at every stop or the art doubles.
## Pitch changes nothing about which art is needed, only how tall the same tile draws, so
## it is free to be a creative control - and it is the one dial that carries this camera
## across the whole range from an elevation to a top-down map. What a fractional angle
## costs is pixel cleanliness, not correctness; see [member pitch_degrees].
##
## [b]Why 30 is the default.[/b] It gives an exact 16x8 tile, and being the shallowest
## pixel-clean angle it shows height best, which suits the game that has jumping.

const TEXELS_PER_TILE := 16

## Vertical faces are 13.856 px per world unit at 30 degrees, so art authored at 16
## texels loses ~14% of its rows unevenly. Author vertical faces at 14 instead.
const TEXELS_PER_UNIT_VERTICAL := 14

const STOPS := 4

## The camera's tilt, and the main creative control on this rig: 0 is a flat-on
## elevation where walls read at full height and the floor vanishes to a line, 90 is
## straight down where the floor is square and walls vanish entirely. 30 is the default
## and the angle the rest of this file's arithmetic is written around.
##
## [b]Pixel-clean angles.[/b] A ground tile projects to
## [code]TEXELS_PER_TILE x TEXELS_PER_TILE * sin(pitch)[/code] px, and when that height
## is not a whole number the tile grid drifts against the pixel grid and rows come out
## unequal. The angles where it lands on an integer are 0, 30.00, 34.23, 38.68, 43.43,
## 48.59, 54.34, 61.04, 69.64 and 90 - every round number that looks like a natural
## choice (45, 60) is fractional. Set whatever reads best; [method is_pixel_clean]
## reports whether the angle landed on one of them, and [method _ready] warns once if a
## scene was authored at one that did not.
##
## [b]Two things move with it.[/b] Depth compensation reads [code]sin(pitch)[/code] off
## the camera basis, so walking speed re-balances on its own as this changes - bounded by
## [constant MotionController.MAX_DEPTH_BOOST], which is what stops a near-flat camera
## launching actors across the map. And vertical faces are [code]16 * cos(pitch)[/code]
## px per world unit, so art authored for 30 degrees is wrong at any other angle; see
## [constant TEXELS_PER_UNIT_VERTICAL].
@export_range(0.0, 90.0, 0.01) var pitch_degrees: float = 30.0 : set = _set_pitch

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

## What the camera actually chases, a step behind [method focus_of] - see
## [method _track]. A real node rather than a bare field so it is one thing other
## systems can point at later (a debug draw, a second camera), not just an
## implementation detail of this one.
var _camera_target: Node3D = null
var _camera_target_ready := false


func _ready() -> void:
	super()
	_camera = _find_camera()
	_camera_target = Node3D.new()
	_camera_target.name = "CameraTarget"
	# This rig sits under the [Camera3D] it drives (see the scene), and that camera's
	# own transform is rewritten every frame below - a plain child's global_position
	# would round-trip through it, so the local offset _track() stored last frame gets
	# reinterpreted against this frame's already-moved camera before it is ever read
	# back. top_level makes the target's transform independent of its parent chain, so
	# it is genuinely the fixed point in world space _track() needs it to be.
	_camera_target.top_level = true
	add_child(_camera_target)
	if not upscale_path.is_empty():
		_upscale = get_node_or_null(upscale_path) as Control
	_apply_pitch()
	# Once, here, for a pitch that was authored into the scene and saved. The setter
	# stays quiet so a live sweep does not flood the log - see _set_pitch.
	if not is_pixel_clean():
		push_warning("OrthoPixelRig: pitch %.2f gives a floor depth of %.3f px, which is not a whole number - the tile grid will drift against the pixel grid. The clean angles are 0, 30.00, 34.23, 38.68, 43.43, 48.59, 54.34, 61.04, 69.64 and 90." % [pitch_degrees, floor_depth_px()])
	_apply_clip()
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
	_apply_clip()


## The part of the camera's position that quantisation threw away, in screen pixels.
##
## This is the other half of sub-pixel movement: the logical position stays
## continuous, the camera snaps to whole texels, and the remainder is handed to the
## viewport to offset by - which is what makes the followed actor look perfectly
## smooth. There is only one offset to spend, so everything else snaps texel to texel.
func subtexel_offset() -> Vector2:
	return _subtexel


## Eases [member _camera_target] toward [param focus]'s height at [member follow_speed],
## and returns [param focus] with that eased height in place of its own - [i]height
## only[/i]. [b]followed actor pinned on screen[/b] (demo_scenes_test.gd) is a real
## invariant this rig has always kept exactly: [method Space.snap_to_basis] is what makes
## a walking sprite land on the same screen pixel every frame, and smoothing X/Z as well
## would put a permanent frame of lag on that during ordinary continuous movement, which
## the test catches immediately. Height is the one axis nothing before this checked pixel-
## exactly, and the one axis [GridMotion._ground_clearance] can now move in a single jump
## between two adjacent frames' raycasts on a ramp or stairs cell - smoothing only it is
## what absorbs that without loosening the horizontal pin at all.
##
## Exponential rather than a fixed step, so it has no "arrived" discontinuity to manage -
## it just gets closer forever, which reads as smooth and never needs a snap-to-target
## special case. Snaps straight there on the very first call instead of easing in from
## [constant Vector3.ZERO], which is where a freshly-created [Node3D] starts - a scene
## opening on a map would otherwise show the camera rising from the floor.
func _track(focus: Vector3, delta: float) -> Vector3:
	if not _camera_target_ready:
		_camera_target_ready = true
		_camera_target.global_position = focus
		return focus

	var rate := 1.0 - exp(-follow_speed * delta)
	var eased_y := lerpf(_camera_target.global_position.y, focus.y, rate)
	_camera_target.global_position = Vector3(focus.x, eased_y, focus.z)
	return _camera_target.global_position


func _process(delta: float) -> void:
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
	#
	# What the camera chases is _camera_target, not focus_of directly - see _track. A
	# grid step's own tween is already smooth; what is not is a ramp or stairs
	# clearance correction ([GridMotion._ground_clearance]) reacting to real geometry
	# frame by frame, which can legitimately jump between two adjacent frames' raycasts.
	# The lag this adds is invisible at an ordinary walk and is exactly what absorbs that.
	var focus := _track(focus_of(who), delta)
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


## Applied immediately, so the angle can be swept live - which is the point of opening
## the range up.
##
## Deliberately silent about pixel cleanliness. A live sweep passes through hundreds of
## fractional angles on its way somewhere, and warning at each would bury every other
## message in the log. [method _ready] carries the warning instead, where it catches the
## case that actually matters: a scene saved at an angle nobody checked.
func _set_pitch(value: float) -> void:
	pitch_degrees = clampf(value, 0.0, 90.0)
	_apply_pitch()


## Pull the far plane in to something the map actually occupies.
##
## [b]This is what makes directional shadows work at all here.[/b] Godot fits the
## directional shadow map to the camera's frustum, and an orthographic camera keeps the
## default far plane of 4000 unless told otherwise. Fitting a shadow map across 4000
## units to light a 20x14 map spends essentially all of its depth precision on empty
## space, and what reaches the screen is not "no shadows" but something worse to
## diagnose: every lit surface self-shadows faintly, the whole floor dims by a few
## percent, and raising [member DirectionalLight3D.shadow_bias] to clear the acne erases
## the real shadows first. Measured on the iso grid map, far 4000 darkened 17% of the
## frame by at most 0.23; far 80 darkens 6% by 0.44 - fewer pixels, and actually shaped
## like the blocks casting them.
##
## It also explains the symptom that gives this away: shadows look right in the editor,
## whose viewport uses its own perspective camera, and wrong the moment the game runs
## through this one.
##
## Twice [member distance] because the camera sits exactly that far back along the view
## axis, so this leaves as much room in front of the focus as behind it. [member
## Camera3D.near] is deliberately left alone - tightening it buys almost nothing here
## (6.41% to 6.25% measured) and risks clipping anything tall near the camera.
func _apply_clip() -> void:
	if _camera == null:
		return
	_camera.far = maxf(1.0, distance * 2.0)
