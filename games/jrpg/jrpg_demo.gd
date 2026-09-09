extends Node2D

## Game 1 MVP: 2D grid movement, 4-way, snap-and-tween, a real [TileMapLayer] with a
## [code]passable[/code] custom data layer so [Passability] step 1 runs against actual
## tile data rather than the open-ground fallback.
##
## The 32x32 source tiles are read as a 2x2 atlas of 16x16 tiles, which keeps the
## decided 16 px per tile and gives four variants of each for free.
##
## Controls: WASD/arrows step, tap to turn in place, . wait a step, Esc back.

const TILE := 16
const ATLAS := Vector2i(2, 2)

const GRID: Array[String] = [
	"####################",
	"#..................#",
	"#..###....#........#",
	"#....#....#...####.#",
	"#....#....#......#.#",
	"#..###....#......#.#",
	"#.........#..###.#.#",
	"#...####..#....#...#",
	"#......#..#....#####",
	"#......#..#........#",
	"#..#####..####..##.#",
	"#..............##..#",
	"#..................#",
	"####################",
]

var _player: Actor = null
var _rig: RoomCamera2D = null
var _hud: Label = null
var _floor: TileMapLayer = null
var _walls: TileMapLayer = null


func _ready() -> void:
	var profile: GameProfile = load("res://games/jrpg/jrpg.tres")
	_build(profile)


func _build(profile: GameProfile) -> void:
	var ctx := MapContext.new()
	ctx.name = "MapContext"
	ctx.map_id = &"jrpg_demo"
	# Pixels, not metres. Nothing compares a distance across maps, so the two units
	# never have to agree.
	ctx.cell_size = profile.default_cell_size
	ctx.supports_height = false
	ctx.default_motion = Actor.MotionMode.GRID
	add_child(ctx)

	# Behind everything, so past the map edge reads as deliberate rather than as
	# Godot's default grey.
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.05, 0.06, 0.09)
	bg.position = Vector2(-2048, -2048)
	bg.size = Vector2(4096, 4096)
	bg.z_index = -100
	add_child(bg)

	_floor = _make_layer("Floor", load("res://art/test_floor_tile.png"), true)
	add_child(_floor)
	_walls = _make_layer("Collision", load("res://art/test_wall_tile.png"), false)
	add_child(_walls)

	# Passability reads this layer's "passable" custom data. Wiring it by NodePath
	# rather than by name search means the lookup is one resolve, not a tree walk per
	# step.
	ctx.collision_node = ctx.get_path_to(_walls)

	_paint()

	# -- Player --------------------------------------------------------------
	var body := Node2D.new()
	body.name = "Player"
	body.position = Space.as_v2(ctx.cell_centre(Vector3i(2, 0, 12)))
	add_child(body)

	_player = Actor.new()
	_player.name = "Actor"
	_player.actor_id = &"player"
	_player.facing_count = 4
	body.add_child(_player)

	var adapter := Space2D.new()
	adapter.name = "Space"
	_player.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = 4
	motion.speed = 6.0            # cells per second, so a step is ~167ms
	motion.publishes_pulse = true # the player's steps are the pulse
	_player.add_child(motion)

	var view := SpriteView2D.new()
	view.name = "View"
	_player.add_child(view)

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	sprite.texture = load("res://art/test_sprite.png")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 16x24 art on a 16px grid: shift up so the feet sit on the cell rather than the
	# middle of the sprite.
	sprite.offset = Vector2(0, -4)
	body.add_child(sprite)
	view.bind_visual(sprite)

	# -- An NPC to bump into, so occupancy is visible ------------------------
	_add_npc(ctx, Vector3i(8, 0, 12))
	_add_npc(ctx, Vector3i(14, 0, 6))

	# -- Camera --------------------------------------------------------------
	var cam := Camera2D.new()
	cam.name = "Camera"
	# 2x, so a 16px tile is 32 screen px and the map scrolls rather than sitting in the
	# middle of the window. Integer zoom only - a fractional one resamples the tiles
	# and undoes the nearest-neighbour filtering.
	cam.zoom = Vector2(2, 2)
	add_child(cam)

	_rig = RoomCamera2D.new()
	_rig.name = "Rig"
	_rig.style = RoomCamera2D.Style.FOLLOW
	_rig.deadzone = Vector2(32, 24)
	_rig.bounds = Rect2(Vector2.ZERO, Vector2(20 * TILE, 14 * TILE))
	cam.add_child(_rig)
	_rig.follow(&"player")

	var driver := InputDriver.new()
	driver.name = "Input"
	driver.actor_id = &"player"
	driver.profile = profile.input_profile
	# No camera_rig: a fixed 2D camera means screen up is always world north, and
	# passing the rig would resolve input through a yaw that never changes.
	add_child(driver)

	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(6, 4)
	_hud.add_theme_font_size_override("font_size", 10)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 3)
	layer.add_child(_hud)

	EventBus.actor_stepped.connect(_on_stepped)


## A [TileSet] whose 32x32 source is cut into 16x16 tiles - a 2x2 atlas. The decided
## density is 16 px per tile, so reading the art this way uses it at native resolution
## instead of scaling it, and yields four variants per texture.
func _make_layer(node_name: String, texture: Texture2D, passable: bool) -> TileMapLayer:
	var source := TileSetAtlasSource.new()
	source.texture = texture
	source.texture_region_size = Vector2i(TILE, TILE)
	for y in ATLAS.y:
		for x in ATLAS.x:
			source.create_tile(Vector2i(x, y))

	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_custom_data_layer()
	tileset.set_custom_data_layer_name(0, Passability.DATA_PASSABLE)
	tileset.set_custom_data_layer_type(0, TYPE_BOOL)
	tileset.add_source(source, 0)

	for y in ATLAS.y:
		for x in ATLAS.x:
			var data := source.get_tile_data(Vector2i(x, y), 0)
			data.set_custom_data(Passability.DATA_PASSABLE, passable)

	var layer := TileMapLayer.new()
	layer.name = node_name
	layer.tile_set = tileset
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return layer


func _paint() -> void:
	for z in GRID.size():
		var row: String = GRID[z]
		for x in row.length():
			var at := Vector2i(x, z)
			# Deterministic variant from the position, so the floor has texture
			# without a random seed changing between runs.
			var variant := Vector2i(posmod(x, ATLAS.x), posmod(z, ATLAS.y))
			if row[x] == "#":
				_walls.set_cell(at, 0, variant)
			else:
				_floor.set_cell(at, 0, variant)


func _add_npc(ctx: MapContext, cell: Vector3i) -> void:
	var body := Node2D.new()
	body.name = "Npc_%d_%d" % [cell.x, cell.z]
	body.position = Space.as_v2(ctx.cell_centre(cell))
	add_child(body)

	var actor := Actor.new()
	actor.actor_id = StringName("npc_%d_%d" % [cell.x, cell.z])
	actor.facing_count = 4
	body.add_child(actor)

	var adapter := Space2D.new()
	actor.add_child(adapter)

	var view := SpriteView2D.new()
	actor.add_child(view)
	var sprite := Sprite2D.new()
	sprite.texture = load("res://art/test_sprite.png")
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.offset = Vector2(0, -4)
	sprite.modulate = Color(0.65, 0.8, 1.0)
	body.add_child(sprite)
	view.bind_visual(sprite)


var _steps := 0

func _on_stepped(_id: StringName, _from: Vector3i, _to: Vector3i) -> void:
	_steps += 1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and event.is_action("back"):
		DemoLauncher.back_to_menu(self)


func _process(_delta: float) -> void:
	if _player == null:
		return
	var ctx := _player.context()
	_hud.text = "\n".join([
		"JRPG   cell %s   facing %s   %s" % [
			_player.cell(), _player.facing(),
			"stepping" if _player.is_moving() else "idle"],
		"pulses %d   occupied cells %d   tile %d px, 4-way" % [
			_steps, ctx.occupancy.size(), TILE],
		"WASD/arrows step, tap to turn   . wait   Esc back",
	])
