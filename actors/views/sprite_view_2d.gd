class_name SpriteView2D extends ActorView

## Game 1's presentation: an [AnimatedSprite2D] with 4 directions, Y-sorted by the 2D
## engine. The simplest of the three - no camera yaw to account for, no texel
## rounding, because in a 2D map the pixels already are the units.

const DIR_NAMES: Array[StringName] = [&"north", &"east", &"south", &"west"]

@export var facing_count: int = 4

var _sprite: AnimatedSprite2D = null
var _anim: StringName = &"idle"
var _dir_index: int = 2


func _after_bind() -> void:
	super()
	_sprite = _visual as AnimatedSprite2D
	_refresh()


func set_facing(dir: Vector3i) -> void:
	_dir_index = Space.facing_index(Vector3(dir), facing_count)
	_refresh()


func play(anim: StringName) -> String:
	_anim = anim
	_refresh()
	if _sprite == null:
		return ""

	_keys += 1
	var key := "anim:%s:%d" % [anim, _keys]
	if not _sprite.animation_finished.is_connected(_on_anim_finished):
		_sprite.animation_finished.connect(_on_anim_finished.bind(key), CONNECT_ONE_SHOT)
	return key


func apply_art(art: Dictionary) -> void:
	if _sprite == null:
		return
	if art.has("frames"):
		var frames: SpriteFrames = load(str(art["frames"])) as SpriteFrames
		if frames != null:
			_sprite.sprite_frames = frames
	if art.has("directions"):
		facing_count = int(art["directions"])
	_refresh()


func _refresh() -> void:
	if _sprite == null or _sprite.sprite_frames == null:
		return
	# "walk_east", falling back to the bare animation name so a single-direction
	# placeholder sprite still animates instead of silently showing nothing.
	var named := StringName("%s_%s" % [_anim, DIR_NAMES[_dir_index % DIR_NAMES.size()]])
	if _sprite.sprite_frames.has_animation(named):
		_sprite.play(named)
	elif _sprite.sprite_frames.has_animation(_anim):
		_sprite.play(_anim)


func _on_anim_finished(key: String) -> void:
	EventBus.command_finished.emit(key)


func _write_offset() -> void:
	if _visual is Node2D:
		(_visual as Node2D).position = Space.as_v2(_offset)
