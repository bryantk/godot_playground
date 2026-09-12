extends Node

## One-time bootstrap: turns the demos' _build() factories into real scenes and
## resources, then gets deleted. The scenes it writes are the source of truth from then
## on - re-running this would clobber anything edited in the editor.
##
##     godot --headless --path . res://tools/make_demo_scenes.tscn

const SHEET := "res://resources/Test_SpriteSheet_D_U_Side.png"
const FLOOR_TEX := "res://art/test_floor_tile.png"
const WALL_TEX := "res://art/test_wall_tile.png"

const TILE := 16
const ATLAS := Vector2i(2, 2)
const SOURCE_TEXELS := 32.0

const JRPG_GRID: Array[String] = [
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

const ISO_GRID: Array[String] = [
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

# MeshLibrary item ids. Floors are four UV variants of one tile, so a painted floor has
# the same 2x2 texture cycle the single big plane used to get from its tiled UVs.
const FLOOR_ITEMS := [0, 1, 2, 3]
const BLOCK_1 := 4
const BLOCK_2 := 5

var _failed := 0


func _ready() -> void:
	_write(_jrpg_tileset(), "res://games/jrpg/jrpg_tiles.tres")
	_write(_block_library(), "res://games/isoish/pixel_blocks.tres")
	_write(_grid_input_profile(), "res://games/isoish/isoish_grid_input.tres")

	_pack(_player_jrpg(), "res://games/jrpg/player_jrpg.tscn")
	_pack(_npc_jrpg(), "res://games/jrpg/npc_jrpg.tscn")
	_pack(_player_isoish(false), "res://games/isoish/player_isoish.tscn")
	_pack(_player_isoish(true), "res://games/isoish/player_isoish_grid.tscn")
	_pack(_npc_isoish(), "res://games/isoish/npc_isoish.tscn")

	_pack(_jrpg_demo(), "res://games/jrpg/jrpg_demo.tscn")
	_pack(_iso_demo(false), "res://games/isoish/isoish_demo.tscn")
	_pack(_iso_demo(true), "res://games/isoish/isoish_grid_demo.tscn")

	get_tree().quit(_failed)


# -- Resources -----------------------------------------------------------------

## One [TileSet], two atlas sources: 0 is floor, 1 is wall. Each 32x32 source is cut
## into 16x16 tiles - a 2x2 atlas - which keeps the decided 16 px per tile and yields
## four variants of each for free.
func _jrpg_tileset() -> TileSet:
	var tileset := TileSet.new()
	tileset.tile_size = Vector2i(TILE, TILE)
	tileset.add_custom_data_layer()
	tileset.set_custom_data_layer_name(0, Passability.DATA_PASSABLE)
	tileset.set_custom_data_layer_type(0, TYPE_BOOL)

	for entry: Array in [[FLOOR_TEX, true, 0], [WALL_TEX, false, 1]]:
		var source := TileSetAtlasSource.new()
		source.texture = load(str(entry[0]))
		source.texture_region_size = Vector2i(TILE, TILE)
		for y in ATLAS.y:
			for x in ATLAS.x:
				source.create_tile(Vector2i(x, y))
		tileset.add_source(source, int(entry[2]))
		for y in ATLAS.y:
			for x in ATLAS.x:
				source.get_tile_data(Vector2i(x, y), 0).set_custom_data(
					Passability.DATA_PASSABLE, bool(entry[1]))
	return tileset


## Floor variants plus one- and two-unit blocks, authored so a [GridMap] with
## [code]cell_center_y = false[/code] puts a cell's floor exactly on y = 0.
func _block_library() -> MeshLibrary:
	var lib := MeshLibrary.new()
	var floor_tex: Texture2D = load(FLOOR_TEX)
	var wall_tex: Texture2D = load(WALL_TEX)
	var per_unit_h := float(PixelLevel.Opts.new().texels_per_unit) / SOURCE_TEXELS

	for i in FLOOR_ITEMS.size():
		var plane := PlaneMesh.new()
		plane.size = Vector2.ONE
		var mat := _material(floor_tex, Vector3(per_unit_h, per_unit_h, 1.0))
		# One quadrant of the source per variant, so a painted floor cycles through the
		# whole 32x32 texture the way one big tiled plane used to.
		mat.uv1_offset = Vector3(float(i % 2) * 0.5, float(i / 2) * 0.5, 0.0)
		plane.material = mat
		lib.create_item(i)
		lib.set_item_name(i, "floor_%d" % i)
		lib.set_item_mesh(i, plane)
		lib.set_item_shapes(i, [_box(Vector3(1.0, 1.0, 1.0)), Transform3D(Basis(), Vector3(0.0, -0.5, 0.0))])

	for h in [1, 2]:
		var id: int = BLOCK_1 if h == 1 else BLOCK_2
		lib.create_item(id)
		lib.set_item_name(id, "block_%d" % h)
		lib.set_item_mesh(id, _block_mesh(float(h), wall_tex))
		lib.set_item_shapes(id, [_box(Vector3(1.0, float(h), 1.0)),
			Transform3D(Basis(), Vector3(0.0, float(h) * 0.5, 0.0))])
	return lib


func _box(size: Vector3) -> BoxShape3D:
	var s := BoxShape3D.new()
	s.size = size
	return s


## Four sides and a top, as two surfaces so each can carry its own texel density: 16 per
## unit horizontally, 14 per unit of height. Culling is off because adjacent blocks keep
## their touching faces - the seams that costs were accepted deliberately, and disabling
## the cull means no face can go missing to a winding mistake.
func _block_mesh(h: float, tex: Texture2D) -> ArrayMesh:
	var opts := PixelLevel.Opts.new()
	var per_unit_h := float(opts.texels_per_unit) / SOURCE_TEXELS
	var per_unit_v := float(opts.texels_per_unit_vertical) / SOURCE_TEXELS

	var sides := SurfaceTool.new()
	sides.begin(Mesh.PRIMITIVE_TRIANGLES)
	_quad(sides, Vector3(-0.5, 0.0, 0.5), Vector3(0.5, 0.0, 0.5), h)      # +Z
	_quad(sides, Vector3(0.5, 0.0, -0.5), Vector3(-0.5, 0.0, -0.5), h)    # -Z
	_quad(sides, Vector3(0.5, 0.0, 0.5), Vector3(0.5, 0.0, -0.5), h)      # +X
	_quad(sides, Vector3(-0.5, 0.0, -0.5), Vector3(-0.5, 0.0, 0.5), h)    # -X
	sides.generate_normals()
	var mesh := sides.commit()
	mesh.surface_set_material(0, _material(tex, Vector3(per_unit_h, h * per_unit_v, 1.0),
		PixelLevel.TINT_SIDE))

	var top := SurfaceTool.new()
	top.begin(Mesh.PRIMITIVE_TRIANGLES)
	_face(top, Vector3(-0.5, h, -0.5), Vector3(0.5, h, -0.5), Vector3(0.5, h, 0.5),
		Vector3(-0.5, h, 0.5))
	top.generate_normals()
	var top_mesh := top.commit()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, top_mesh.surface_get_arrays(0))
	mesh.surface_set_material(1, _material(tex, Vector3(per_unit_h, per_unit_h, 1.0),
		PixelLevel.TINT_TOP))
	return mesh


## A vertical face from [param a] to [param b] along the ground, [param h] tall.
func _quad(st: SurfaceTool, a: Vector3, b: Vector3, h: float) -> void:
	_face(st, a + Vector3.UP * h, b + Vector3.UP * h, b, a)


func _face(st: SurfaceTool, v0: Vector3, v1: Vector3, v2: Vector3, v3: Vector3) -> void:
	var uv := [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1), Vector2(0, 1)]
	var v := [v0, v1, v2, v3]
	for i in [0, 1, 2, 0, 2, 3]:
		st.set_uv(uv[i])
		st.add_vertex(v[i])


func _material(tex: Texture2D, uv_scale: Vector3, tint: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = tex
	mat.albedo_color = Color(tint, tint, tint)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	mat.uv1_scale = uv_scale
	return mat


## Game 1's 4-way committed step, but resolved through the camera - the combination
## neither shipped profile has, and the one the iso grid map wants.
func _grid_input_profile() -> InputProfile:
	var ip := InputProfile.new()
	ip.direction_count = 4
	ip.view_relative = true
	ip.discrete_steps = true
	ip.tap_turns_in_place = true
	return ip


# -- Role scenes ---------------------------------------------------------------

func _player_jrpg() -> Node:
	var body := Node2D.new()
	body.name = "PlayerJrpg"
	var actor := _actor(body, &"player", 4, true)
	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = 4
	motion.speed = 6.0             # cells per second, so a step is ~167 ms
	motion.publishes_pulse = true  # the player's steps are the pulse
	_own(actor, motion, body)
	_own(actor, Space2D.new(), body, "Space")
	_own(actor, SpriteView2D.new(), body, "View").visual_path = ^"../../Sprite"
	# Two frames of the four-frame cycle per step, so the walk reads as one stride per
	# cell rather than drifting against the movement.
	_own(body, _sheet_2d(motion.step_duration() * 0.5), body)
	return body


func _npc_jrpg() -> Node:
	var body := Node2D.new()
	body.name = "NpcJrpg"
	var actor := _actor(body, &"npc", 4, true)
	_own(actor, Space2D.new(), body, "Space")
	_own(actor, SpriteView2D.new(), body, "View").visual_path = ^"../../Sprite"
	var sprite := _sheet_2d(0.25)
	sprite.modulate = Color(0.65, 0.8, 1.0)
	_own(body, sprite, body)
	return body


func _player_isoish(grid: bool) -> Node:
	var body := CharacterBody3D.new()
	body.name = "PlayerIsoishGrid" if grid else "PlayerIsoish"
	var shape := CollisionShape3D.new()
	shape.name = "Collision"
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.3
	capsule.height = 1.2
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.6, 0.0)
	_own(body, shape, body)

	# Grid actors own the cell they stand in; free ones do not reserve at all.
	var actor := _actor(body, &"player", 8 if not grid else 4, grid)
	_own(actor, Space3D.new(), body, "Space")

	if grid:
		var motion := GridMotion.new()
		motion.name = "Motion"
		motion.direction_count = 4
		motion.speed = 4.0
		motion.publishes_pulse = true
		_own(actor, motion, body)
	else:
		var motion := FreeMotion.new()
		motion.name = "Motion"
		motion.speed = 4.0
		motion.direction_count = 8
		motion.jump_strength = 6.0
		motion.gravity = 20.0
		_own(actor, motion, body)

	var view := _own(actor, SpriteView3D.new(), body, "View") as SpriteView3D
	view.visual_path = ^"../../Sprite"
	view.texels_per_unit = 16
	_own(body, _sheet_3d(0.125 if grid else 0.12, Color.WHITE), body)

	# A grid actor's body teleports a cell at commit and its sprite tweens after it, so
	# the shadow has to follow the sprite or it arrives at the destination square a whole
	# step early. A free actor's body is already where the eye thinks it is.
	_own(body, _shadow(^"../Sprite" if grid else NodePath()), body, "Shadow")
	return body


func _npc_isoish() -> Node:
	var body := Node3D.new()
	body.name = "NpcIsoish"
	var actor := _actor(body, &"npc", 4, true)
	_own(actor, Space3D.new(), body, "Space")
	var view := _own(actor, SpriteView3D.new(), body, "View") as SpriteView3D
	view.visual_path = ^"../../Sprite"
	view.texels_per_unit = 16
	_own(body, _sheet_3d(0.25, Color(0.65, 0.8, 1.0)), body)
	# No motion node, so this one never moves and has nothing to lag behind.
	_own(body, _shadow(NodePath()), body, "Shadow")
	return body


## The blob shadow, a sibling of the sprite under the body - never under the view, per
## the transform-root trap [ActorView] documents.
func _shadow(target: NodePath) -> ActorShadow:
	var shadow := ActorShadow.new()
	shadow.name = "Shadow"
	shadow.target_path = target
	shadow.texels_per_unit = 16
	return shadow


func _actor(body: Node, id: StringName, facings: int, solid: bool) -> Actor:
	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = id
	actor.facing_count = facings
	actor.solid = solid
	# Left on INHERIT so the map's default_motion decides, which is the precedence rule
	# that keeps "grid movement in a 3D town" possible.
	actor.motion_mode = Actor.MotionMode.INHERIT
	_own(body, actor, body)
	return actor


## Three frames across, and down / up / side down. The side row serves both left and
## right, mirrored, which is why facing_offsets carries a negative entry.
func _sheet_2d(rate: float) -> SpriteSheet:
	var sprite := SpriteSheet.new()
	sprite.name = "Sprite"
	sprite.texture = load(SHEET)
	sprite.hframes = 3
	sprite.vframes = 3
	sprite.rate = rate
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	# 16x24 art on a 16px grid: shift up so the feet sit on the cell.
	sprite.offset = Vector2(0, -4)
	return sprite


func _sheet_3d(rate: float, tint: Color) -> SpriteSheet3D:
	var sprite := SpriteSheet3D.new()
	sprite.name = "Sprite"
	sprite.texture = load(SHEET)
	sprite.hframes = 3
	sprite.vframes = 3
	sprite.rate = rate
	sprite.pixel_size = 1.0 / 16.0
	sprite.billboard = BaseMaterial3D.BILLBOARD_FIXED_Y
	sprite.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	sprite.shaded = false
	sprite.transparent = true
	# Writing depth rather than pure billboarding is what lets it sort against walls.
	sprite.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
	sprite.modulate = tint
	sprite.position = Vector3(0.0, 0.75, 0.0)
	return sprite


# -- Demo scenes ---------------------------------------------------------------

func _jrpg_demo() -> Node:
	var root := Node2D.new()
	root.name = "JrpgDemo"
	root.set_script(load("res://games/jrpg/jrpg_demo.gd"))

	var ctx := MapContext.new()
	ctx.name = "MapContext"
	ctx.map_id = &"jrpg_demo"
	# Pixels, not metres. Nothing compares a distance across maps.
	ctx.cell_size = Vector3(TILE, 0, TILE)
	ctx.supports_height = false
	ctx.default_motion = Actor.MotionMode.GRID
	ctx.collision_node = ^"../Collision"
	_own(root, ctx, root)

	# Behind everything, so past the map edge reads as deliberate rather than grey.
	var bg := ColorRect.new()
	bg.name = "Background"
	bg.color = Color(0.05, 0.06, 0.09)
	bg.position = Vector2(-2048, -2048)
	bg.size = Vector2(4096, 4096)
	bg.z_index = -100
	_own(root, bg, root)

	var tileset: TileSet = load("res://games/jrpg/jrpg_tiles.tres")
	var floor_layer := _tile_layer("Floor", tileset)
	var wall_layer := _tile_layer("Collision", tileset)
	_own(root, floor_layer, root)
	_own(root, wall_layer, root)
	for z in JRPG_GRID.size():
		var row: String = JRPG_GRID[z]
		for x in row.length():
			# Deterministic variant from the position, so the floor has texture without
			# a seed that changes between runs.
			var variant := Vector2i(posmod(x, ATLAS.x), posmod(z, ATLAS.y))
			if row[x] == "#":
				wall_layer.set_cell(Vector2i(x, z), 1, variant)
			else:
				floor_layer.set_cell(Vector2i(x, z), 0, variant)

	var actors := Node2D.new()
	actors.name = "Actors"
	_own(root, actors, root)

	# The most open cell on this map: two clear tiles north, three south, four east,
	# three west. A spawn wedged against scenery is indistinguishable from broken
	# movement when you first press a key.
	var player := _instance("res://games/jrpg/player_jrpg.tscn", "Player") as Node2D
	player.position = _cell_2d(Vector3i(14, 0, 9))
	_own(actors, player, root)
	actors.set_editable_instance(player, true)

	# Both on open floor. One used to sit on a wall tile, reserving a cell nothing could
	# reach and drawing a sprite inside the scenery.
	for cell: Vector3i in [Vector3i(17, 0, 9), Vector3i(8, 0, 12)]:
		var npc := _instance("res://games/jrpg/npc_jrpg.tscn",
			"Npc_%d_%d" % [cell.x, cell.z]) as Node2D
		npc.position = _cell_2d(cell)
		(npc.get_node("Actor") as Actor).actor_id = StringName("npc_%d_%d" % [cell.x, cell.z])
		_own(actors, npc, root)
		actors.set_editable_instance(npc, true)

	var cam := Camera2D.new()
	cam.name = "Camera"
	# 2x, so a 16px tile is 32 screen px. Integer zoom only - a fractional one resamples
	# the tiles and undoes the nearest-neighbour filtering.
	cam.zoom = Vector2(2, 2)
	_own(root, cam, root)
	var rig := RoomCamera2D.new()
	rig.name = "Rig"
	rig.style = RoomCamera2D.Style.FOLLOW
	rig.deadzone = Vector2(32, 24)
	rig.bounds = Rect2(Vector2.ZERO, Vector2(20 * TILE, 14 * TILE))
	rig.follow_target = &"player"
	_own(cam, rig, root)

	var driver := InputDriver.new()
	driver.name = "Input"
	driver.actor_id = &"player"
	driver.profile = load("res://games/jrpg/jrpg_input.tres")
	# No camera_rig: a fixed 2D camera means screen up is always world north.
	_own(root, driver, root)

	_own(root, _hud(Vector2(6, 4), 10, 3), root)
	return root


func _iso_demo(grid: bool) -> Node:
	var root := Node.new()
	root.name = "IsoishGridDemo" if grid else "IsoishDemo"
	root.set_script(load("res://games/isoish/isoish_grid_demo.gd" if grid
		else "res://games/isoish/isoish_demo.gd"))
	var input_path := "res://games/isoish/isoish_grid_input.tres" if grid \
		else "res://games/isoish/isoish_input.tres"

	# The whole scene renders at the pixel-art resolution and is scaled up with
	# nearest-neighbour. Sized explicitly rather than by anchor preset: this Control's
	# parent is a plain Node, so there is no parent rect to anchor against.
	var container := SubViewportContainer.new()
	container.name = "Upscale"
	container.stretch = true
	container.stretch_shrink = 2
	container.position = Vector2.ZERO
	container.size = Vector2(640, 320)
	container.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_own(root, container, root)

	var vp := SubViewport.new()
	vp.name = "World"
	vp.size = Vector2i(320, 160)
	vp.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_own(container, vp, root)

	var world := Node3D.new()
	world.name = "Map"
	_own(vp, world, root)

	var env := WorldEnvironment.new()
	env.name = "Env"
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.05, 0.06, 0.09)
	env.environment = e
	_own(world, env, root)

	var ctx := MapContext.new()
	ctx.name = "MapContext"
	ctx.map_id = StringName("isoish_grid_demo" if grid else "isoish_demo")
	ctx.cell_size = Vector3.ONE
	ctx.supports_height = true
	# The one line that makes the grid map a different game from its neighbour: the
	# profile's motion_script says FreeMotion and the map overrides it.
	ctx.default_motion = Actor.MotionMode.GRID if grid else Actor.MotionMode.FREE
	ctx.collision_node = ^"../Blocks"
	_own(world, ctx, root)

	var lib: MeshLibrary = load("res://games/isoish/pixel_blocks.tres")
	var floor_map := _grid_map("Floor", lib)
	var blocks := _grid_map("Blocks", lib)
	_own(world, floor_map, root)
	_own(world, blocks, root)
	for z in ISO_GRID.size():
		var row: String = ISO_GRID[z]
		for x in row.length():
			var at := Vector3i(x, 0, z)
			var ch := row[x]
			if ch == "#":
				blocks.set_cell_item(at, BLOCK_1)
			elif ch == "X":
				blocks.set_cell_item(at, BLOCK_2)
			else:
				floor_map.set_cell_item(at, FLOOR_ITEMS[posmod(x, 2) + posmod(z, 2) * 2])

	var actors := Node3D.new()
	actors.name = "Actors"
	_own(world, actors, root)
	var player := _instance("res://games/isoish/player_isoish_grid.tscn" if grid
		else "res://games/isoish/player_isoish.tscn", "Player") as Node3D
	# Four clear cells in every direction, which is the most this map offers.
	player.position = Vector3(7.5, 0.0, 7.5)
	_own(actors, player, root)
	actors.set_editable_instance(player, true)
	if grid:
		# Solid grid neighbours, so occupancy is visible: one in the doorway through the
		# dividing wall, one a few cells north.
		for cell: Vector3i in [Vector3i(10, 0, 7), Vector3i(7, 0, 4)]:
			var npc := _instance("res://games/isoish/npc_isoish.tscn",
				"Npc_%d_%d" % [cell.x, cell.z]) as Node3D
			npc.position = Vector3(cell.x + 0.5, 0.0, cell.z + 0.5)
			(npc.get_node("Actor") as Actor).actor_id = StringName("npc_%d_%d" % [cell.x, cell.z])
			_own(actors, npc, root)
			actors.set_editable_instance(npc, true)

	var cam := Camera3D.new()
	cam.name = "Camera"
	_own(world, cam, root)
	var rig := OrthoPixelRig.new()
	rig.name = "Rig"
	rig.pitch_degrees = 30.0
	rig.texels_per_unit = 16
	rig.quantise_camera = true
	rig.follow_target = &"player"
	# Up out of the SubViewport to the container it spends its snap remainder on.
	rig.upscale_path = ^"../../../.."
	_own(cam, rig, root)

	var driver := InputDriver.new()
	driver.name = "Input"
	driver.actor_id = &"player"
	driver.profile = load(input_path)
	_own(world, driver, root)
	driver.camera_rig = rig

	# Outside the low-res viewport deliberately: at 320x160 a readable font would eat a
	# third of the screen, and the point is to look at the art.
	_own(root, _hud(Vector2(6, 226 if grid else 232), 12, 4), root)
	return root


# -- Helpers -------------------------------------------------------------------

func _tile_layer(node_name: String, tileset: TileSet) -> TileMapLayer:
	var layer := TileMapLayer.new()
	layer.name = node_name
	layer.tile_set = tileset
	layer.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	return layer


## [code]cell_center_y = false[/code] is what puts a cell's floor on y = 0 rather than
## half a unit up, so GridMap coordinates and [method MapContext.cell_centre] agree.
func _grid_map(node_name: String, lib: MeshLibrary) -> GridMap:
	var gm := GridMap.new()
	gm.name = node_name
	gm.mesh_library = lib
	gm.cell_size = Vector3.ONE
	gm.cell_center_x = true
	gm.cell_center_y = false
	gm.cell_center_z = true
	return gm


func _hud(pos: Vector2, size: int, outline: int) -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "HUD"
	var label := Label.new()
	label.name = "Label"
	label.position = pos
	label.add_theme_font_size_override("font_size", size)
	label.add_theme_color_override("font_color", Color(1, 1, 1))
	label.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	label.add_theme_constant_override("outline_size", outline)
	# Owner is left unset: _reown assigns the scene root, which is what pack() needs -
	# a node owned by anything other than the packed root is skipped entirely.
	layer.add_child(label)
	return layer


func _cell_2d(cell: Vector3i) -> Vector2:
	return Vector2((cell.x + 0.5) * TILE, (cell.z + 0.5) * TILE)


func _instance(path: String, node_name: String) -> Node:
	var node := (load(path) as PackedScene).instantiate()
	node.name = node_name
	return node


## Add [param child] under [param parent] and give it to [param owner], which is what
## makes [method PackedScene.pack] record it rather than skip it.
func _own(parent: Node, child: Node, owner_node: Node, node_name: String = "") -> Node:
	if node_name != "":
		child.name = node_name
	parent.add_child(child)
	if child != owner_node:
		child.owner = owner_node
	return child


func _write(res: Resource, path: String) -> void:
	var err := ResourceSaver.save(res, path)
	if err != OK:
		printerr("failed to write %s (%d)" % [path, err])
		_failed += 1
	else:
		print("wrote %s" % path)


func _pack(root: Node, path: String) -> void:
	# The HUD's Label is owned by the CanvasLayer above, which packs it as part of that
	# branch; everything else was owned by the scene root as it was added.
	_reown(root, root)
	var scene := PackedScene.new()
	var err := scene.pack(root)
	if err == OK:
		err = ResourceSaver.save(scene, path)
	if err != OK:
		printerr("failed to pack %s (%d)" % [path, err])
		_failed += 1
	else:
		print("packed %s" % path)
	root.free()


## Anything added by a helper without an owner still needs one, but never inside an
## instanced sub-scene - those keep their own ownership or pack() inlines their guts.
func _reown(node: Node, root: Node) -> void:
	for child in node.get_children():
		if child.scene_file_path != "":
			continue
		if child.owner == null:
			child.owner = root
		_reown(child, root)
