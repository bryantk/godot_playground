extends Node

## Adds placeholder [b]ramp[/b], [b]stairs[/b] and [b]ladder[/b] items to the isoish
## mesh library, so the height terrain can be painted into a demo map before any real
## art exists.
##
##     godot --headless --path . res://tools/make_height_items.tscn
##
## [b]Placeholders, and meant to be replaced.[/b] The geometry here is primitives - a
## wedge, three boxes, a thin slab - UV-mapped by nothing and laid out with no regard for
## the texel density two-games.md 3.6 sets out (16 px per tile across, 14 texels per world
## unit up a vertical face). They borrow the floor and wall [i]materials[/i] off existing
## items so they are at least textured and lit like the map around them, but the mapping
## is arbitrary. Replacing the meshes is the whole job; [b]the item names are not
## cosmetic[/b] and must survive it, because [Terrain] reads the kind off the name.
##
## Re-running is safe. Items are matched by name and overwritten, so this can be run
## again after the library is edited by hand without stacking up duplicates.
##
## [b]Collision is a trimesh built off the mesh itself[/b], not a hand-placed box - a
## ramp is a slope and stairs are steps, and a box could only ever approximate one height
## for the whole tile. [method Terrain.surface_offset] and [GridMotion]'s per-frame
## clearance check (the raycast question "how tall is the ground really, here") both read
## real geometry now instead of an idealised guess, so the two cannot disagree.
##
## [b]Multi-tile runs[/b], for a slope authored to rise one cell over more than one tile:
## [constant RUN_LENGTHS] also builds a [code]<kind>_<length>_<index>[/code] item for
## every tile of each length in it - [code]ramp_3_2[/code] is the middle third of a
## three-tile ramp. [method Terrain.ramp_run] reads the suffix back; a bare
## [code]"ramp"[/code]/[code]"stairs"[/code] is the length-1 case. Add a length to
## [constant RUN_LENGTHS] and re-run this to build gentler variants; nothing above
## [Terrain] needs to know how many exist.
##
## [b]What an author still has to do[/b], because none of it can be guessed from here:
## place the cells in the Floor GridMap, rotate each one so it faces the way it rises or
## is climbed, and point [member MapContext.floor_node] at that GridMap. See
## [method Terrain.resolve_step] for what each kind then does.

const LIBRARY := "res://games/isoish/pixel_blocks.tres"

## One cell, so the wedge and the rungs match the grid they are placed on.
const CELL := 1.0

## Multi-tile run lengths to build alongside the plain one-tile [code]ramp[/code] and
## [code]stairs[/code] - see the class doc. Empty would still build the two one-tile
## items; it is not a switch for whether height terrain exists at all.
const RUN_LENGTHS: Array[int] = [2, 3]


func _ready() -> void:
	var lib: MeshLibrary = load(LIBRARY)
	if lib == null:
		push_error("make_height_items: could not load %s" % LIBRARY)
		get_tree().quit(1)
		return

	# Borrowed rather than invented, so a placeholder looks like the map around it and
	# carries the texel density two-games.md 3.6 sets - the wall material's uv1_scale.y of
	# 0.4375 is that 14-texels-per-unit, and a fresh StandardMaterial3D would lose it.
	var ground := _material_of(lib, "floor_0")
	var wall := _material_of(lib, "block_1")

	_upsert_run(lib, "ramp", ground, 1, 1)
	_upsert_run(lib, "stairs", ground, 1, 1)
	for length in RUN_LENGTHS:
		for index in range(1, length + 1):
			_upsert_run(lib, "ramp", ground, length, index)
			_upsert_run(lib, "stairs", ground, length, index)
	_upsert(lib, "ladder", _ladder_mesh(), wall, null)

	var err := ResourceSaver.save(lib, LIBRARY)
	if err != OK:
		push_error("make_height_items: save failed (%d)" % err)
		get_tree().quit(1)
		return

	print("")
	print("  wrote ramp, stairs, ladder and their multi-tile runs into %s" % LIBRARY)
	print("  place them in the Floor GridMap and rotate each to face the way it rises.")
	print("")
	get_tree().quit(0)


## One tile of a ramp or stairs run - [param index] of [param length], length 1 meaning
## the plain single-tile item - built and upserted under the name [method Terrain.ramp_run]
## expects.
func _upsert_run(lib: MeshLibrary, kind: String, material: Material,
		length: int, index: int) -> void:
	var low := float(index - 1) / float(length)
	var high := float(index) / float(length)
	var mesh := _ramp_mesh(low, high) if kind == "ramp" else _stairs_mesh(low, high)
	var item_name := kind if length == 1 else "%s_%d_%d" % [kind, length, index]
	# The trimesh shape is exact to this mesh, so no offset transform is needed - unlike
	# the placeholder box this replaces, which had to be told where the slab it stood in
	# for actually sat.
	_upsert(lib, item_name, mesh, material, mesh.create_trimesh_shape())


## Replaces the item of this name, or appends one if the library has none. Matching on
## the name rather than a remembered id is what makes re-running safe after a human has
## reordered the library.
func _upsert(lib: MeshLibrary, item_name: String, mesh: ArrayMesh, material: Material,
		shape: Shape3D = null) -> void:
	var id := -1
	for existing in lib.get_item_list():
		if lib.get_item_name(existing) == item_name:
			id = existing
			break
	if id < 0:
		id = lib.get_last_unused_item_id()
		lib.create_item(id)

	if material != null:
		for s in mesh.get_surface_count():
			mesh.surface_set_material(s, material)

	lib.set_item_name(id, item_name)
	lib.set_item_mesh(id, mesh)
	lib.set_item_mesh_cast_shadow(id, RenderingServer.SHADOW_CASTING_SETTING_ON)
	if shape == null:
		lib.set_item_shapes(id, [])
	else:
		lib.set_item_shapes(id, [shape, Transform3D.IDENTITY])
	print("  item %d  %s" % [id, item_name])


## A wedge rising toward -Z, from [param low] to [param high] of the cell's height (both
## 0..1, the whole cell by default) - the direction [constant Terrain.MODELLED_FACING]
## expects an unrotated ramp to climb. Rotating the cell in the GridMap editor is what
## points it anywhere else; [param low]/[param high] are what let a run of these span
## several tiles instead of one - see [method Terrain.ramp_run].
##
## [b]Winding matters and is easy to get backwards.[/b] Godot takes a triangle's facing
## from [code](v0 - v2).cross(v0 - v1)[/code], so a quad listed in the wrong order faces
## into the ground: the slope renders from underneath, which reads in the editor as a
## ramp you can see through from above. The first version of this function had every one
## of its faces inverted [i]and[/i] was missing both triangular sides - the two it called
## sides were both the tall north end.
func _ramp_mesh(low: float = 0.0, high: float = 1.0) -> ArrayMesh:
	var h := CELL * 0.5
	var y0 := CELL * low
	var y1 := CELL * high
	# Base square, counter-clockwise from the north-west corner...
	var a := Vector3(-h, y0, -h)
	var b := Vector3(h, y0, -h)
	var c := Vector3(h, y0, h)
	var d := Vector3(-h, y0, h)
	# ...and the high edge, at the north side.
	var e := Vector3(-h, y1, -h)
	var f := Vector3(h, y1, -h)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	# Flat, not smooth. SurfaceTool welds matching vertices on commit and averages their
	# normals, which on a wedge blends the slope into the sides and lights it as if it
	# were rounded - and on a stair turns every tread and riser into one soft lump.
	st.set_smooth_group(-1)
	_quad(st, e, f, c, d)   # the slope, facing up and south
	_quad(st, d, c, b, a)   # the underside, facing down
	_quad(st, b, f, e, a)   # the tall north end
	_tri(st, a, e, d)       # west side
	_tri(st, b, c, f)       # east side
	st.generate_normals()
	return st.commit()


## [param steps] steps in a cell, spanning [param low] to [param high] of the cell's
## height and climbing toward -Z. Mechanically identical to the ramp - see
## [method Terrain._kind_of_item] - so this differs in nothing but what the eye gets.
func _stairs_mesh(low: float = 0.0, high: float = 1.0, steps: int = 3) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat, or the treads and risers blend into one soft lump
	var y0 := CELL * low
	var span := CELL * (high - low)
	for i in steps:
		var depth := CELL / float(steps)
		var rise := y0 + span * float(i + 1) / float(steps)
		var z0 := CELL * 0.5 - depth * float(i + 1)
		var z1 := CELL * 0.5 - depth * float(i)
		_box(st, Vector3(-CELL * 0.5, y0, z0), Vector3(CELL * 0.5, rise, z1))
	st.generate_normals()
	return st.commit()


## A thin slab against the -Z face of the cell, so a column of these reads as a ladder
## mounted on a wall to the north of it. No collision shape: a ladder is climbed, and a
## collider would only be something for the actor's own body to catch on.
func _ladder_mesh() -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	st.set_smooth_group(-1)   # flat, so the slab reads as a slab
	_box(st, Vector3(-0.3, 0.0, -0.5), Vector3(0.3, CELL, -0.4))
	st.generate_normals()
	return st.commit()


## The material an existing library item already uses, so a placeholder inherits the
## project's texture and texel density instead of inventing a flat grey one.
func _material_of(lib: MeshLibrary, item_name: String) -> Material:
	for id in lib.get_item_list():
		if lib.get_item_name(id) != item_name:
			continue
		# Mesh, not ArrayMesh: the floor items are PlaneMeshes, and a cast to ArrayMesh
		# quietly returns null for them. surface_get_material is on the base class.
		var mesh := lib.get_item_mesh(id)
		if mesh != null and mesh.get_surface_count() > 0:
			return mesh.surface_get_material(0)
	push_warning("make_height_items: no material found on '%s'" % item_name)
	return null


func _box(st: SurfaceTool, lo: Vector3, hi: Vector3) -> void:
	var p := [
		Vector3(lo.x, lo.y, lo.z), Vector3(hi.x, lo.y, lo.z),
		Vector3(hi.x, lo.y, hi.z), Vector3(lo.x, lo.y, hi.z),
		Vector3(lo.x, hi.y, lo.z), Vector3(hi.x, hi.y, lo.z),
		Vector3(hi.x, hi.y, hi.z), Vector3(lo.x, hi.y, hi.z),
	]
	_quad(st, p[4], p[5], p[6], p[7])   # top
	_quad(st, p[3], p[2], p[1], p[0])   # bottom
	_quad(st, p[0], p[1], p[5], p[4])   # -Z
	_quad(st, p[2], p[3], p[7], p[6])   # +Z
	_quad(st, p[1], p[2], p[6], p[5])   # +X
	_quad(st, p[3], p[0], p[4], p[7])   # -X


func _quad(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3, d: Vector3) -> void:
	_tri(st, a, b, c)
	_tri(st, a, c, d)


func _tri(st: SurfaceTool, a: Vector3, b: Vector3, c: Vector3) -> void:
	st.add_vertex(a)
	st.add_vertex(b)
	st.add_vertex(c)
