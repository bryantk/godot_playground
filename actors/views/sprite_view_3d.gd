class_name SpriteView3D extends ActorView

## Game 2's presentation: a billboarded sprite in a rotating 3D world, 8 facings.
##
## Two things make this the interesting view. First, the frame depends on the camera
## as well as the actor - which is what makes live rotation work - and with 8 facings
## against 4 yaw stops the arithmetic is exact: frames sit 45 degrees apart and each
## stop is 90, so a stop is worth exactly two frames, with no rounding and no yaw at
## which some frame has no art.
##
## Second, this is where sub-pixel motion is reconciled with a pixel-perfect
## viewport. The logical position stays continuous and the [i]render[/i] rounds to
## whole texels. Doing it the other way round - quantising the position - silently
## turns sub-pixel movement into 16px stepping.

const FACING_COUNT := 8
const DIR_NAMES: Array[StringName] = [&"n", &"ne", &"e", &"se", &"s", &"sw", &"w", &"nw"]

## Texels per world unit. Matches GameProfile.texels_per_unit; exported so a test
## scene can be built without a profile.
@export var texels_per_unit: int = 16

## Round the rendered position to whole texels, on the grid [OrthoPixelRig] pushes via
## [method set_pixel_grid].
##
## The grid has to come from the camera. Rounding on world X/Y/Z is the version of this
## that looks right and is not: at any pitch the camera's up axis is not world Y, so the
## two rounds land on different grids, and for the actor the camera is following the
## remainders beat against each other into a visible wobble instead of cancelling.
##
## With no grid pushed - a 2D map, or a rig that does not quantise - this does nothing
## and the position stays continuous.
@export var quantise_to_texels: bool = true

var _sprite: AnimatedSprite3D = null
var _sheet: SpriteSheet3D = null
var _anim: StringName = &"idle"
var _facing: Vector3i = Vector3i(0, 0, 1)
var _camera_yaw: float = 0.0
var _base_position: Vector3 = Vector3.ZERO
var _grid_basis := Basis.IDENTITY
var _grid_active := false


func _after_bind() -> void:
	super()
	_sprite = _visual as AnimatedSprite3D
	_sheet = _visual as SpriteSheet3D
	if _visual is Node3D:
		_base_position = (_visual as Node3D).position
	_refresh()


## A [SpriteSheet3D] runs its own cycle and only needs to be told whether to. Polled
## rather than driven from a signal because it has to be right for both motions: a grid
## step has a clean start and end to hook, and free movement has neither.
func _process(_delta: float) -> void:
	if _sheet == null:
		return
	var who := get_parent() as Actor
	if who != null:
		_sheet.animating(who.is_travelling())


## Called by [CameraRig] whenever the view rotates. Every sprite in the map re-picks
## its frame on a yaw change; nothing else about the world cares.
func set_camera_yaw(yaw_radians: float) -> void:
	if is_equal_approx(yaw_radians, _camera_yaw):
		return
	_camera_yaw = yaw_radians
	_refresh()


func set_facing(dir: Vector3i) -> void:
	_facing = dir
	_refresh()


## The frame index this actor shows right now. Exposed because it is exactly the kind
## of integer arithmetic that is worth asserting on in a headless test.
func frame_index() -> int:
	return Space.view_frame(Vector3(_facing), _camera_yaw, FACING_COUNT)


func play(anim: StringName) -> String:
	_anim = anim
	_refresh()
	if _sprite == null:
		return ""
	_keys += 1
	var key := "anim:%s:%d" % [anim, _keys]
	_sprite.animation_finished.connect(
		func () -> void: EventBus.command_finished.emit(key), CONNECT_ONE_SHOT)
	return key


func apply_art(art: Dictionary) -> void:
	if _sprite != null and art.has("frames"):
		var frames: SpriteFrames = load(str(art["frames"])) as SpriteFrames
		if frames != null:
			_sprite.sprite_frames = frames
	_refresh()


func _refresh() -> void:
	if _sheet != null:
		# The sheet has four directions and this view has eight, so a diagonal shows the
		# nearer cardinal. Reducing the camera-relative frame rather than the world
		# facing is what keeps the sprite correct as the view rotates.
		var cardinal := posmod(roundi(frame_index() / 2.0), 4)
		_sheet.facing = FacingUtils.from_compass(cardinal) as FacingUtils.Facings
		return
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var named := StringName("%s_%s" % [_anim, DIR_NAMES[frame_index()]])
	if _sprite.sprite_frames.has_animation(named):
		_sprite.play(named)
	elif _sprite.sprite_frames.has_animation(_anim):
		_sprite.play(_anim)


## The grid the camera is snapping to, pushed by [OrthoPixelRig] every frame.
##
## Pushed rather than pulled because the view has no business knowing which camera is
## looking at it, and because the grid changes every frame as the camera moves - a value
## read once at bind time would be stale immediately.
func set_pixel_grid(basis: Basis, texels: int, active: bool) -> void:
	_grid_basis = basis
	texels_per_unit = texels
	_grid_active = active
	_write_offset()


## While a grid is active the rig writes this sprite's transform once per frame, from
## the same offset sample it built the camera from. Writing again here - mid-tween,
## between the rig's sample and the next - would leave the sprite a tween step ahead of
## the camera, which is a whole texel of disagreement at walking speed and exactly the
## wobble the shared grid is there to remove.
func _set_offset(v: Vector3) -> void:
	_offset = v
	if not _grid_active:
		_write_offset()


## The render rounds; the logical position does not. The sub-texel remainder is what the
## rig spends on its viewport offset, which is what makes the motion smooth rather than
## a texel at a time.
##
## What is rounded is the [b]actor's[/b] world position, not the sprite's - the rig
## rounds exactly that, so rounding the same quantity here makes the two agree exactly
## and the followed actor sits on one pixel and stays there. The sprite's own pedestal
## offset goes on afterwards, unrounded, because including it would shift the value
## being rounded and put the two grids back out of step.
func _write_offset() -> void:
	if not (_visual is Node3D):
		return
	var node := _visual as Node3D
	var body := node.get_parent_node_3d()
	var who := get_parent() as Actor

	if not (quantise_to_texels and _grid_active and texels_per_unit > 0
			and body != null and who != null):
		node.position = _base_position + _offset
		return

	var logical := who.world_position() + _offset
	var snapped := Space.snap_to_basis(logical, _grid_basis, float(texels_per_unit))
	node.position = _base_position + (snapped - body.global_position)
