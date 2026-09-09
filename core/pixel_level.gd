class_name PixelLevel

## Builds demo geometry from an ASCII grid, with exact control over texel density per
## face. Quads rather than boxes, because a [BoxMesh] gives no per-face UV control and
## per-face UV control is the whole point: horizontal surfaces are authored at one
## density and vertical faces at another.
##
## Grid characters: [code].[/code] floor, [code]#[/code] a one-unit block,
## [code]X[/code] a two-unit block. Anything else is floor.

## Source textures are 32x32 and the world is 16 texels per unit, so one unit covers
## half the texture and it repeats every 2 units.
const SOURCE_TEXELS := 32.0


class Opts extends RefCounted:
	var floor_texture: Texture2D = null
	var wall_texture: Texture2D = null
	## Texels per world unit on horizontal surfaces.
	var texels_per_unit: int = 16
	## Texels per world unit of height on vertical faces. 14 at pitch 30, so art
	## authored for the projection lands near 1:1 instead of losing one row in seven.
	var texels_per_unit_vertical: int = 14
	## Add collision. Off for a purely visual demo, on when something walks around.
	var collision: bool = true


static func build(parent: Node3D, grid: Array[String], opts: Opts) -> void:
	var depth := grid.size()
	var width := 0
	for row in grid:
		width = maxi(width, row.length())

	_add_floor(parent, width, depth, opts)

	for z in depth:
		var row: String = grid[z]
		for x in row.length():
			var ch := row[x]
			var height := 0
			if ch == "#":
				height = 1
			elif ch == "X":
				height = 2
			if height > 0:
				_add_block(parent, grid, x, z, height, opts)


## The floor is one plane rather than a quad per cell: nothing needs per-cell UVs down
## here, and a single mesh keeps the draw count honest.
static func _add_floor(parent: Node3D, width: int, depth: int, opts: Opts) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(float(width), float(depth))
	# Orientation is already +Y for PlaneMesh.
	var mesh := MeshInstance3D.new()
	mesh.name = "Floor"
	mesh.mesh = plane
	mesh.position = Vector3(float(width) * 0.5, 0.0, float(depth) * 0.5)

	var repeat := float(opts.texels_per_unit) / SOURCE_TEXELS
	mesh.material_override = _material(opts.floor_texture,
		Vector3(float(width) * repeat, float(depth) * repeat, 1.0))
	parent.add_child(mesh)

	if opts.collision:
		var body := StaticBody3D.new()
		body.name = "FloorBody"
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(float(width), 1.0, float(depth))
		shape.shape = box
		# Sunk so its top face is exactly y = 0.
		shape.position = Vector3(float(width) * 0.5, -0.5, float(depth) * 0.5)
		body.add_child(shape)
		parent.add_child(body)


static func _add_block(parent: Node3D, grid: Array[String], x: int, z: int,
		height: int, opts: Opts) -> void:
	var holder := Node3D.new()
	holder.name = "Block_%d_%d" % [x, z]
	parent.add_child(holder)

	var h := float(height)
	var per_unit_h := float(opts.texels_per_unit) / SOURCE_TEXELS
	var per_unit_v := float(opts.texels_per_unit_vertical) / SOURCE_TEXELS

	# Only faces nobody can see are skipped - two coincident faces between adjacent
	# blocks would z-fight, which reads as flickering seams rather than as a bug.
	var sides := [
		{"dir": Vector3i(0, 0, -1), "pos": Vector3(x + 0.5, h * 0.5, z), "yaw": PI, "tint": TINT_SIDE},
		{"dir": Vector3i(0, 0, 1), "pos": Vector3(x + 0.5, h * 0.5, z + 1), "yaw": 0.0, "tint": TINT_SIDE},
		{"dir": Vector3i(-1, 0, 0), "pos": Vector3(x, h * 0.5, z + 0.5), "yaw": -PI * 0.5, "tint": TINT_SIDE},
		{"dir": Vector3i(1, 0, 0), "pos": Vector3(x + 1, h * 0.5, z + 0.5), "yaw": PI * 0.5, "tint": TINT_SIDE},
	]

	for side: Dictionary in sides:
		var d: Vector3i = side["dir"]
		if _height_at(grid, x + d.x, z + d.z) >= height:
			continue
		var quad := QuadMesh.new()
		quad.size = Vector2(1.0, h)
		var mesh := MeshInstance3D.new()
		mesh.mesh = quad
		mesh.position = side["pos"]
		mesh.rotation = Vector3(0.0, side["yaw"], 0.0)
		mesh.material_override = _material(opts.wall_texture,
			Vector3(per_unit_h, h * per_unit_v, 1.0), side["tint"])
		holder.add_child(mesh)

	# Top face, horizontal, so it takes the horizontal density.
	var top := QuadMesh.new()
	top.size = Vector2(1.0, 1.0)
	var top_mesh := MeshInstance3D.new()
	top_mesh.name = "Top"
	top_mesh.mesh = top
	top_mesh.position = Vector3(x + 0.5, h, z + 0.5)
	top_mesh.rotation = Vector3(-PI * 0.5, 0.0, 0.0)
	top_mesh.material_override = _material(opts.wall_texture,
		Vector3(per_unit_h, per_unit_h, 1.0), TINT_TOP)
	holder.add_child(top_mesh)

	if opts.collision:
		var body := StaticBody3D.new()
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.0, h, 1.0)
		shape.shape = box
		shape.position = Vector3(x + 0.5, h * 0.5, z + 0.5)
		body.add_child(shape)
		holder.add_child(body)


static func _height_at(grid: Array[String], x: int, z: int) -> int:
	if z < 0 or z >= grid.size():
		return 0
	var row: String = grid[z]
	if x < 0 or x >= row.length():
		return 0
	match row[x]:
		"#": return 1
		"X": return 2
		_: return 0


# Per-face brightness. Unshaded geometry with one texture on every face has no depth
# cue whatsoever - the first build of this demo read as a flat top-down maze because a
# block's top and its sides were pixel-identical. A fixed multiplier per orientation is
# how pixel-art games get form without lighting, and it keeps the palette predictable:
# two known tints rather than whatever a light happens to produce.
#
# One tint for all four sides, which falls out of the 90-degree yaw stops: an
# orthographic camera at an axis-aligned yaw sees X-facing quads edge-on, so only one
# side orientation is ever visible at a time. Giving Z and X different tints therefore
# does not add form - it just makes the whole scene change brightness as the view
# rotates, which is what the first pass did.
const TINT_TOP := 1.0
const TINT_SIDE := 0.72


## Unshaded, nearest-filtered, repeating. Unshaded matters for pixel art: the colours
## on screen are then exactly the source colours scaled by one known constant, with no
## light term drifting them off the palette.
static func _material(texture: Texture2D, uv_scale: Vector3,
		tint: float = 1.0) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_texture = texture
	mat.albedo_color = Color(tint, tint, tint)
	mat.texture_filter = BaseMaterial3D.TEXTURE_FILTER_NEAREST
	mat.texture_repeat = true
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.uv1_scale = uv_scale
	return mat
