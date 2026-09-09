extends Node

## Game 2 MVP: pixel-perfect orthographic 3D, pitch 30, four 90-degree yaw stops,
## billboarded sprite with 8 facings, free movement with jumping.
##
## The scene is built in code rather than authored as a .tscn, so every number that
## matters - texel density, ortho size, UV scale per face - is visible next to the
## reasoning for it.
##
## Controls: WASD move, Space jump, Shift run, Q/E rotate the view,
## 1 camera texel snap, 2 sub-texel smoothing, 3 vertical texel density, Esc back.

const LOW_RES := Vector2i(320, 160)
const SHRINK := 2

const GRID: Array[String] = [
	"XXXXXXXXXXXXXXXXXXXX",
	"X..................X",
	"X...##....X........X",
	"X...##....X....##..X",
	"X.........X....##..X",
	"X..XX.....X........X",
	"X..XX........####..X",
	"X..................X",
	"X....##...X........X",
	"X....##...X...XX...X",
	"X.........X...XX...X",
	"X........###.......X",
	"X..................X",
	"XXXXXXXXXXXXXXXXXXXX",
]

var _rig: OrthoPixelRig = null
var _container: SubViewportContainer = null
var _hud: Label = null
var _player: Actor = null
var _view: SpriteView3D = null
var _level: Node3D = null
var _opts := PixelLevel.Opts.new()

var _smooth_subtexel := true


func _ready() -> void:
	var profile: GameProfile = load("res://games/isoish/isoish.tres")
	_build(profile)


func _build(profile: GameProfile) -> void:
	# -- The low-res viewport ------------------------------------------------
	# The whole scene renders at the pixel-art resolution and is scaled up with
	# nearest-neighbour. This is what makes 3D geometry read as pixel art, and it is a
	# different technique from compositing 2D actors into a 3D scene - which is the
	# thing architecture.md rules out.
	_container = SubViewportContainer.new()
	_container.name = "Upscale"
	_container.stretch = true
	_container.stretch_shrink = SHRINK
	# Sized explicitly rather than by anchor preset. This Control's parent is a plain
	# Node, so there is no parent rect to anchor against and the resulting size is not
	# what you would predict - it came back 640x640, which made the SubViewport
	# 320x320 and the orthographic frustum twice as tall as intended.
	_container.position = Vector2.ZERO
	_container.size = Vector2(LOW_RES * SHRINK)
	_container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_container)

	var vp := SubViewport.new()
	vp.name = "World"
	vp.size = LOW_RES
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	vp.transparent_bg = false
	_container.add_child(vp)

	var world := Node3D.new()
	world.name = "Map"
	vp.add_child(world)

	# An explicit background, so anything past the level edge reads as deliberate
	# rather than as Godot's default grey.
	var env := WorldEnvironment.new()
	env.name = "Env"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	env.environment = e
	world.add_child(env)

	# -- Map context ---------------------------------------------------------
	var ctx := MapContext.new()
	ctx.name = "MapContext"
	ctx.map_id = &"isoish_demo"
	ctx.cell_size = profile.default_cell_size
	ctx.supports_height = true
	ctx.default_motion = Actor.MotionMode.FREE
	world.add_child(ctx)

	# -- Geometry ------------------------------------------------------------
	_opts.floor_texture = load("res://art/test_floor_tile.png")
	_opts.wall_texture = load("res://art/test_wall_tile.png")
	_opts.texels_per_unit = profile.texels_per_unit
	_opts.texels_per_unit_vertical = profile.texels_per_unit_vertical
	_opts.collision = true

	_level = Node3D.new()
	_level.name = "Level"
	world.add_child(_level)
	PixelLevel.build(_level, GRID, _opts)

	# -- Player --------------------------------------------------------------
	var body := CharacterBody3D.new()
	body.name = "Player"
	body.position = Vector3(7.5, 0.0, 7.5)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.2
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.6, 0.0)
	body.add_child(shape)
	world.add_child(body)

	_player = Actor.new()
	_player.name = "Actor"
	_player.actor_id = &"player"
	_player.solid = false          # free actors do not own cells
	_player.motion_mode = Actor.MotionMode.FREE
	_player.facing_count = 8
	body.add_child(_player)

	var adapter := Space3D.new()
	adapter.name = "Space"
	_player.add_child(adapter)

	var motion := FreeMotion.new()
	motion.name = "Motion"
	motion.speed = 4.0
	motion.direction_count = 8
	motion.jump_strength = 6.0
	motion.gravity = 20.0
	_player.add_child(motion)

	_view = SpriteView3D.new()
	_view.name = "View"
	_view.texels_per_unit = profile.texels_per_unit
	_player.add_child(_view)

	# The sprite is 16x24 at 16 texels per unit, so 1.0 x 1.5 world units. A billboard
	# that yaws to the camera but keeps its own pitch is a vertical quad in world
	# space, so it foreshortens by cos(pitch) exactly like a wall does.
	#
	# Parented to the body, NOT to the view: ActorView is a plain Node with no
	# transform, so a Sprite3D under it would become its own transform root and render
	# at the world origin.
	var sprite := Sprite3D.new()
	sprite.name = "Sprite"
	sprite.texture = load("res://art/test_sprite.png")
	sprite.pixel_size = 1.0 / float(profile.texels_per_unit)
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.transparent = true
	# Writing depth rather than pure billboarding is what lets it sort against walls;
	# a pure billboard intersects geometry badly.
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.position = Vector3(0.0, 0.75, 0.0)
	body.add_child(sprite)
	_view.bind_visual(sprite)

	# -- Camera --------------------------------------------------------------
	var cam := Camera3D.new()
	cam.name = "Camera"
	world.add_child(cam)

	_rig = OrthoPixelRig.new()
	_rig.name = "Rig"
	_rig.pitch_degrees = 30.0
	_rig.texels_per_unit = profile.texels_per_unit
	_rig.quantise_camera = true
	cam.add_child(_rig)
	_rig.follow(&"player")

	_rig.yaw_changed.connect(_on_yaw_changed)

	# -- Input ---------------------------------------------------------------
	var driver := InputDriver.new()
	driver.name = "Input"
	driver.actor_id = &"player"
	driver.profile = profile.input_profile
	driver.camera_rig = _rig
	world.add_child(driver)

	# -- HUD -----------------------------------------------------------------
	# Outside the low-res viewport deliberately: at 320x160 a readable font would eat
	# a third of the screen, and the point is to look at the art.
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(6, 232)
	_hud.add_theme_font_size_override("font_size", 12)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)


func _on_yaw_changed(yaw: float) -> void:
	# Every sprite re-picks its frame on a yaw change; nothing else about the world
	# cares that the view rotated.
	if _view != null:
		_view.set_camera_yaw(yaw)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return

	if event.is_action("yaw_ccw"):
		_rig.rotate_by_stops(-1)
	elif event.is_action("yaw_cw"):
		_rig.rotate_by_stops(1)
	elif event.is_action("toggle_a"):
		_rig.quantise_camera = not _rig.quantise_camera
	elif event.is_action("toggle_b"):
		_smooth_subtexel = not _smooth_subtexel
	elif event.is_action("toggle_c"):
		_cycle_vertical_density()
	elif event.is_action("back"):
		DemoLauncher.back_to_menu(self)


## 14 texels per unit is the pitch-30 correction; 16 is what the art was drawn at.
## Toggling between them is the clearest way to see what the correction buys.
func _cycle_vertical_density() -> void:
	_opts.texels_per_unit_vertical = 16 if _opts.texels_per_unit_vertical == 14 else 14
	for child in _level.get_children():
		child.queue_free()
	PixelLevel.build(_level, GRID, _opts)


func _process(_delta: float) -> void:
	if _rig == null or _player == null:
		return

	# Sub-texel smoothing: the camera snapped to a whole texel and threw away a
	# remainder; shifting the upscaled image by that remainder is what puts the
	# smoothness back for the followed actor. Everything else still snaps texel to
	# texel, because there is only one offset to spend.
	if _smooth_subtexel:
		var off := _rig.subtexel_offset()
		_container.position = Vector2(-off.x, off.y) * float(SHRINK)
	else:
		_container.position = Vector2.ZERO

	var frame := _view.frame_index() if _view != null else 0
	_hud.text = "\n".join([
		# roundi, not int: 16 * sin(30 deg) is 7.99999... in floating point, and
		# truncating it reports a 7 px tile for a pitch chosen precisely to give 8.
		"ISO-ISH   pitch %.2f  |  yaw stop %d of 4  |  tile %d x %d px" % [
			_rig.pitch_degrees, _rig.yaw_stop, _rig.texels_per_unit,
			roundi(_rig.floor_depth_px())],
		"facing %s  frame %d of 8   (one frame of art, so the index is the proof)" % [
			_player.facing(), frame],
		"wall face %.3f px/unit   vertical density %d texels/unit" % [
			_rig.wall_px_per_unit(), _opts.texels_per_unit_vertical],
		"",
		"WASD move   Space jump   Shift run   Q/E rotate",
		"1 texel snap: %s   2 sub-texel smooth: %s   3 vertical density: %d   Esc back" % [
			"on" if _rig.quantise_camera else "OFF",
			"on" if _smooth_subtexel else "OFF",
			_opts.texels_per_unit_vertical],
	])
