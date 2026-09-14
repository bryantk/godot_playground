extends Node

## Derives capped-off variants of [code]block_1[/code] in the isoish mesh library: the
## same block with its top removed and only some of its side faces kept.
##
##     godot --headless --path . res://tools/make_block_variants.tscn
##
## [b]Why: a block buried in a cliff draws five faces nobody can see.[/b] A run of wall
## shows one side, an outside corner shows two, a spur shows three, and every one of them
## has a floor tile sitting on its top. Those hidden faces are not free - at this texel
## density the wall texture is the expensive one, and overdraw on a plateau is most of
## the map.
##
## [b]Three variants plus rotation covers every case.[/b] The faces kept are adjacent and
## named from north, and the GridMap's own cell orientation turns them anywhere:
## [codeblock]
## block_1_n     one face,    north          -> a run of wall, 4 rotations
## block_1_ne    two faces,   north + east   -> an outside corner, 4 rotations
## block_1_nes   three faces, N + E + S      -> a spur or pier end, 4 rotations
## [/codeblock]
##
## The two-face variant is the [i]corner[/i] pair, not the opposite pair. A one-cell-thick
## freestanding wall showing north and south is a real case and is not generated here -
## say so and it becomes a fourth.
##
## [b]Nothing is modelled.[/b] The triangles, UVs and materials are lifted from
## [code]block_1[/code] itself and filtered by facing, so a variant cannot drift from the
## block it came from - re-run this after editing [code]block_1[/code] and the variants
## follow. Collision is copied whole: which faces are drawn says nothing about what is
## solid, and a wall with one face is still a wall.
##
## Re-running is safe; items are matched by name and overwritten.

const LIBRARY := "res://games/isoish/pixel_blocks.tres"
const SOURCE := "block_1"

## North is -Z, as everywhere else in this project.
const N := Vector3i(0, 0, -1)
const E := Vector3i(1, 0, 0)
const S := Vector3i(0, 0, 1)

## Anything this far off an axis is not a side face. The block's sides are axis-aligned,
## so this only has to reject the top and bottom, not resolve anything subtle.
const AXIS_MIN := 0.7


func _ready() -> void:
	var lib: MeshLibrary = load(LIBRARY)
	if lib == null:
		push_error("make_block_variants: could not load %s" % LIBRARY)
		get_tree().quit(1)
		return

	var source := _find(lib, SOURCE)
	if source < 0:
		push_error("make_block_variants: '%s' is not in the library" % SOURCE)
		get_tree().quit(1)
		return

	var mesh := lib.get_item_mesh(source) as ArrayMesh
	if mesh == null:
		push_error("make_block_variants: '%s' has no ArrayMesh" % SOURCE)
		get_tree().quit(1)
		return

	print("")
	print("  from %s (%d surfaces)" % [SOURCE, mesh.get_surface_count()])

	_variant(lib, source, mesh, "block_1_n", [N])
	_variant(lib, source, mesh, "block_1_ne", [N, E])
	_variant(lib, source, mesh, "block_1_nes", [N, E, S])

	var err := ResourceSaver.save(lib, LIBRARY)
	if err != OK:
		push_error("make_block_variants: save failed (%d)" % err)
		get_tree().quit(1)
		return

	print("")
	print("  wrote 3 variants into %s" % LIBRARY)
	print("  rotate each cell in the GridMap to point its faces outward.")
	print("")
	get_tree().quit(0)


func _variant(lib: MeshLibrary, source: int, mesh: ArrayMesh, item_name: String,
		keep: Array) -> void:
	var built := _filtered(mesh, keep)
	if built.mesh == null:
		push_error("make_block_variants: '%s' kept no faces" % item_name)
		return

	var id := _find(lib, item_name)
	if id < 0:
		id = lib.get_last_unused_item_id()
		lib.create_item(id)

	lib.set_item_name(id, item_name)
	lib.set_item_mesh(id, built.mesh)
	lib.set_item_mesh_transform(id, lib.get_item_mesh_transform(source))
	lib.set_item_mesh_cast_shadow(id, lib.get_item_mesh_cast_shadow(source))
	# Copied, not derived. A block with one visible face still blocks on all six.
	lib.set_item_shapes(id, lib.get_item_shapes(source))
	lib.set_item_navigation_mesh(id, lib.get_item_navigation_mesh(source))
	lib.set_item_navigation_mesh_transform(id, lib.get_item_navigation_mesh_transform(source))
	lib.set_item_navigation_layers(id, lib.get_item_navigation_layers(source))

	print("  item %-3d %-14s %d tris, %d dropped" % [
		id, item_name, built.kept, built.dropped])


## [param mesh] with every triangle that does not face one of [param keep] removed.
##
## Works per surface and rebuilds through a [SurfaceTool] per surface, which is what
## preserves the two-material split [code]block_1[/code] has - the sides and the top cap
## are different materials, and the top is simply the surface that keeps no triangles.
func _filtered(mesh: ArrayMesh, keep: Array) -> Dictionary:
	var out := ArrayMesh.new()
	var kept := 0
	var dropped := 0

	for s in mesh.get_surface_count():
		var arrays := mesh.surface_get_arrays(s)
		var verts: PackedVector3Array = arrays[Mesh.ARRAY_VERTEX]
		var norms: PackedVector3Array = arrays[Mesh.ARRAY_NORMAL]
		var uvs: PackedVector2Array = arrays[Mesh.ARRAY_TEX_UV]
		var idx: PackedInt32Array = arrays[Mesh.ARRAY_INDEX] if arrays[Mesh.ARRAY_INDEX] != null \
			else PackedInt32Array()

		# One code path for indexed and unindexed surfaces: without an index buffer the
		# vertices are already in triangle order, so a trivial 0..n index does the job.
		if idx.is_empty():
			idx.resize(verts.size())
			for i in verts.size():
				idx[i] = i

		var st := SurfaceTool.new()
		st.begin(Mesh.PRIMITIVE_TRIANGLES)
		var wrote := 0

		for t in range(0, idx.size() - 2, 3):
			var a := idx[t]
			var b := idx[t + 1]
			var c := idx[t + 2]
			var facing := _facing(verts, norms, a, b, c)
			if facing == Vector3i.ZERO or not keep.has(facing):
				dropped += 1
				continue
			for v in [a, b, c]:
				if v < norms.size():
					st.set_normal(norms[v])
				if v < uvs.size():
					st.set_uv(uvs[v])
				st.add_vertex(verts[v])
			wrote += 1

		kept += wrote
		if wrote == 0:
			continue

		st.set_material(mesh.surface_get_material(s))
		st.commit(out)

	return {
		"mesh": out if out.get_surface_count() > 0 else null,
		"kept": kept,
		"dropped": dropped,
	}


## Which cardinal a triangle faces, or ZERO for a top, a bottom or anything slanted.
##
## The stored normal is preferred and the winding is the fallback, because a mesh
## authored with flat shading has the answer already and one without still has geometry.
func _facing(verts: PackedVector3Array, norms: PackedVector3Array,
		a: int, b: int, c: int) -> Vector3i:
	var n := Vector3.ZERO
	if a < norms.size():
		n = norms[a]
	if n.length_squared() < 0.001:
		n = (verts[b] - verts[a]).cross(verts[c] - verts[a])
	n = n.normalized()

	if absf(n.x) >= AXIS_MIN:
		return E if n.x > 0.0 else Vector3i(-1, 0, 0)
	if absf(n.z) >= AXIS_MIN:
		return S if n.z > 0.0 else N
	return Vector3i.ZERO


func _find(lib: MeshLibrary, item_name: String) -> int:
	for id in lib.get_item_list():
		if lib.get_item_name(id) == item_name:
			return id
	return -1
