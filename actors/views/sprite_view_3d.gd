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

## Round the rendered position to whole texels. The only reason to turn this off is
## to see what the shimmer looks like.
@export var quantise_to_texels: bool = true

var _sprite: AnimatedSprite3D = null
var _anim: StringName = &"idle"
var _facing: Vector3i = Vector3i(0, 0, 1)
var _camera_yaw: float = 0.0
var _base_position: Vector3 = Vector3.ZERO


func _ready() -> void:
	super()
	_sprite = _visual as AnimatedSprite3D
	if _visual is Node3D:
		_base_position = (_visual as Node3D).position
	_refresh()


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
	if _sprite == null or _sprite.sprite_frames == null:
		return
	var named := StringName("%s_%s" % [_anim, DIR_NAMES[frame_index()]])
	if _sprite.sprite_frames.has_animation(named):
		_sprite.play(named)
	elif _sprite.sprite_frames.has_animation(_anim):
		_sprite.play(_anim)


## The render rounds; the logical position does not. The sub-texel remainder is what
## the camera rig spends on its viewport offset, which is why the followed actor looks
## perfectly smooth and everything else snaps texel to texel.
func _write_offset() -> void:
	if not (_visual is Node3D):
		return
	var target := _base_position + _offset
	if quantise_to_texels and texels_per_unit > 0:
		var t := float(texels_per_unit)
		target = Vector3(round(target.x * t) / t, round(target.y * t) / t, round(target.z * t) / t)
	(_visual as Node3D).position = target
