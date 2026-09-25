class_name SpriteView2D extends ActorView

## Game 1's presentation: an [AnimatedSprite2D] with 4 directions, Y-sorted by the 2D
## engine. The simplest of the three - no camera yaw to account for, no texel
## rounding, because in a 2D map the pixels already are the units.

const DIR_NAMES: Array[StringName] = [&"north", &"east", &"south", &"west"]

@export var facing_count: int = 4

var _sprite: AnimatedSprite2D = null
var _sheet: SpriteSheet = null
var _anim: StringName = &"idle"
var _dir_index: int = 2


func _after_bind() -> void:
	super()
	_sprite = _visual as AnimatedSprite2D
	_sheet = _visual as SpriteSheet
	_refresh()


## A [SpriteSheet] runs its own cycle and only needs to be told whether to. Polled
## rather than driven from a signal because it has to be right for both motions: a grid
## step has a clean start and end to hook, and free movement has neither.
func _process(_delta: float) -> void:
	if _sheet == null:
		return
	var who := get_parent() as Actor
	if who != null:
		_sheet.animating(who.is_travelling())


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


## Reconciled with the two visuals this view can actually bind to (segment 6):
## [code]"sheet"[/code] is a texture path, for a [SpriteSheet] visual - the sheet the
## worked examples in docs/events/ actually author, and the shape every actor prefab in
## this project uses today. [code]"frames"[/code] is a [SpriteFrames] resource path,
## for a plain [AnimatedSprite2D] visual. Both keys are read unconditionally and each
## is applied only to the visual kind it matches, so a document does not need to know
## which visual an actor happens to have - and neither early-returns before reaching
## the other, which is the defect this replaces: a [SpriteSheet]-backed actor (every
## one of them, in the current demos) used to get no art applied at all, because the
## old code only ever looked for [code]_sprite[/code] and gave up the moment it found
## none.
## [b]No `sheet`/`frames` at all means no sprite[/b] - a page authored with an empty
## [code]art[/code] (a bodiless region trigger, or a placement not revealed yet) is shown
## or hidden by this alone rather than needing its own `visible: false` worked around by
## hand (event-pages.md's `y_test` did exactly that before this existed). Re-applied
## every page switch, same as everything else here, so a chest whose later page finally
## carries art is revealed by activating that page and needs no separate `set_visible`.
func apply_art(art: Dictionary) -> void:
	if art.has("directions"):
		facing_count = int(art["directions"])
	if art.has("idle"):
		_anim = StringName(str(art["idle"]))

	if art.has("sheet") and _visual is Sprite2D:
		var texture: Texture2D = load(str(art["sheet"])) as Texture2D
		if texture != null:
			(_visual as Sprite2D).texture = texture

	if art.has("frames") and _sprite != null:
		var frames: SpriteFrames = load(str(art["frames"])) as SpriteFrames
		if frames != null:
			_sprite.sprite_frames = frames

	set_visible(art.has("sheet") or art.has("frames"))
	_refresh()


func _refresh() -> void:
	if _sheet != null:
		# The sheet thinks in screen directions and the engine in compass ones, and the
		# two orders do not line up - hence the explicit conversion.
		_sheet.facing = FacingUtils.from_compass(_dir_index) as FacingUtils.Facings
		return
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


func _write_y_level() -> void:
	if _visual is CanvasItem:
		(_visual as CanvasItem).z_index = y_level
