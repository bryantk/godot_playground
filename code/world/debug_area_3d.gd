@tool
class_name DebugArea3D extends Node3D

## Draws a wireframe cube - the [Node3D] counterpart to [DebugArea2D]; see its class
## doc for why this is a scene-authored sibling of [GameEvent] under the placement
## root rather than something [GameEvent] builds for itself, why there is no label,
## and how [member target] picks a [CollisionShape3D] or an [Actor] to size itself
## from.
##
## [b]Reading a collider[/b] ([method _size_from_collider]) covers [BoxShape3D],
## [SphereShape3D] and [CapsuleShape3D] as a bounding box; anything else ([b]not[/b]
## a footprint-style ground-corner anchor - a collider's own [member
## CollisionShape3D.position] is read as its centre, same as the shape's own physics
## meaning) is read as "nothing found", the same as no collider at all.
##
## [b]While editing[/b], [method _sync_visibility] leaves [member Node3D.visible]
## alone - toggling a box off with the Scene dock's own eye icon sticks, instead of
## snapping back on every frame. [b]At runtime, [member Node3D.visible] instead
## follows [method DebugFlags.is_box_type_visible] for [member type] - one of six
## categories the debug menu ([code]~[/code], then keys 1-6) toggles independently.

## The sibling this sizes itself from - a [CollisionShape3D] or an [Actor]. Set by
## hand to resolve a conflict, or by [method _sync_target] the first time this node
## with neither picks one automatically.
@export var target: Node = null

## What this box is marking, purely to pick a starting [member color] from [constant
## DebugFlags.BOX_TYPE_COLORS] - nothing else reads it. Changing it overwrites [member
## color]; changing [member color] afterward (by hand, or a second [member type]
## change) is what wins from then on, the same one-shot-default relationship [member
## area_size]'s own setter note describes for the mesh. Also which of [DebugFlags]'s
## six debug-menu categories [method _sync_visibility] follows at runtime.
##
## A plain [code]@export_enum[/code] int, not [enum DebugFlags.BoxType] by static type
## - Godot has no clean way to spell "an autoload's own nested enum" as a cross-file
## type - kept in the exact same order by hand: None, Event, Area, Transfer Marker,
## Actor.
@export_enum("None", "Event", "Area", "Transfer Marker", "Actor") var type: int = 0:
	set(value):
		type = value
		color = DebugFlags.BOX_TYPE_COLORS[value]

@export var area_size: Vector3 = Vector3.ONE:
	set(value):
		area_size = value
		# Guarded rather than always calling _rebuild(): this setter also fires while
		# the scene is still being deserialized, before this node has entered the tree
		# at all - _ready() picks up whatever area_size ends up holding by then, and
		# calling _rebuild() this early would be building a mesh nobody can see yet
		# for no reason. Once _box exists, a later edit (the inspector, live) is the
		# case this rebuilds for. Position too, not just the mesh: _box_position()
		# reads area_size.y.
		if _box != null:
			_rebuild()
			_reposition()

@export var offset: Vector3 = Vector3.ZERO:
	set(value):
		offset = value
		if _box != null:
			_reposition()

@export var color: Color = Color(0.85, 0.3, 0.25, 0.9):
	set(value):
		color = value
		if _material != null:
			_material.albedo_color = color
		if _fill_material != null:
			_fill_material.albedo_color = _fill_color()

## Also fills the box, in [member color] at a quarter of its own alpha - see [method
## _fill_color]. Off by default, matching [member DebugArea2D.fill]'s own reasoning.
@export var fill: bool = false:
	set(value):
		fill = value
		if _fill_box != null:
			_fill_box.visible = fill

var _box: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _fill_box: MeshInstance3D = null
var _fill_material: StandardMaterial3D = null

## X/Z correction for a multi-cell footprint - see [method _sync_footprint]. Zero for
## a bodiless event (no [Actor] beside this node) or a plain 1x1x1 one, which is every
## placement before footprints existed.
var _footprint_offset := Vector2.ZERO

## The collider's own local centre, read straight off [member CollisionShape3D.position]
## - only meaningful while [member _use_collider_center] is true.
var _collider_center := Vector3.ZERO
var _use_collider_center := false


func _ready() -> void:
	refresh()


## Re-derives everything from [member target] (resolving it first if unset), then
## rebuilds the mesh - [method _ready]'s own body, pulled out so [method
## MapContext.refresh_debug_areas] can re-run it on demand for a box already sized at
## whatever it was when the scene loaded.
func refresh() -> void:
	_sync_target()
	_sync_footprint()
	_rebuild()
	_sync_visibility()


func _process(_delta: float) -> void:
	_sync_visibility()


## Leaves [member target] alone if it already names something live; otherwise looks
## for a sibling [CollisionShape3D] first, then a sibling [Actor], among this node's
## own parent's children (the placement root) - see [method
## DebugArea2D._sync_target], the identical reasoning one dimension over - and writes
## whichever it finds back into [member target].
func _sync_target() -> void:
	if target != null and is_instance_valid(target):
		return

	var parent := get_parent()
	if parent == null:
		return

	for child in parent.get_children():
		if child is CollisionShape3D:
			target = child
			return
	for child in parent.get_children():
		if child is Actor:
			target = child
			return


## Derives [member area_size]'s X/Z (never its Y for the footprint path - [member
## Actor.footprint]'s own height is reserved, unused occupancy today) and either
## [member _footprint_offset] (footprint path) or [member _collider_center]/[member
## _use_collider_center] (collider path) from [member target]. Neither resolving
## leaves [member area_size] exactly as authored.
func _sync_footprint() -> void:
	if target is CollisionShape3D:
		var collider := target as CollisionShape3D
		var size: Variant = _size_from_collider(collider)
		if size != null:
			_use_collider_center = true
			_collider_center = collider.position
			area_size = size
			return
		_use_collider_center = false
		_footprint_offset = Vector2.ZERO
		return

	_use_collider_center = false
	var actor := target as Actor if target is Actor else null
	var ctx := MapContext.of(self) if actor != null else null
	if actor == null or ctx == null:
		_footprint_offset = Vector2.ZERO
		return

	var cell := Vector2(ctx.cell_size.x, ctx.cell_size.z)
	var footprint_xz := Vector2(actor.footprint.x, actor.footprint.z)
	area_size = Vector3(footprint_xz.x * cell.x, area_size.y, footprint_xz.y * cell.y)
	_footprint_offset = (footprint_xz - Vector2.ONE) * cell * 0.5


## A bounding size for [param collider]'s own [member CollisionShape3D.shape], or
## [code]null[/code] for no shape, a disabled collider, or a shape this does not
## bother reading ([ConvexPolygonShape3D]/[ConcavePolygonShape3D] and anything else
## uncommon) - read the same as no collider at all.
func _size_from_collider(collider: CollisionShape3D) -> Variant:
	if collider.disabled:
		return null

	var shape := collider.shape
	if shape is BoxShape3D:
		return (shape as BoxShape3D).size
	if shape is SphereShape3D:
		var d: float = (shape as SphereShape3D).radius * 2.0
		return Vector3(d, d, d)
	if shape is CapsuleShape3D:
		var c := shape as CapsuleShape3D
		return Vector3(c.radius * 2.0, c.height, c.radius * 2.0)
	return null


## Leaves [member Node3D.visible] alone while editing - the Scene dock's own eye icon
## (or the Inspector's "Visible" checkbox) is the only thing that should touch it
## there, so toggling a box off sticks instead of snapping back on next frame/[method
## refresh]. At runtime, [member Node3D.visible] never was hand-authored, so this
## drives it from [method DebugFlags.is_box_type_visible] for [member type] instead.
func _sync_visibility() -> void:
	if Engine.is_editor_hint():
		return
	visible = DebugFlags.is_box_type_visible(type)


func _rebuild() -> void:
	if _box == null or not is_instance_valid(_box):
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.albedo_color = color

		_box = MeshInstance3D.new()
		_box.name = "WireBox"
		_box.material_override = _material
		_box.position = _box_position()
		add_child(_box)

	if _fill_box == null or not is_instance_valid(_fill_box):
		_fill_material = StandardMaterial3D.new()
		_fill_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_fill_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_fill_material.albedo_color = _fill_color()

		_fill_box = MeshInstance3D.new()
		_fill_box.name = "FillBox"
		_fill_box.mesh = BoxMesh.new()
		_fill_box.material_override = _fill_material
		_fill_box.position = _box_position()
		_fill_box.visible = fill
		add_child(_fill_box)

	_box.mesh = _build_wire_box(area_size)
	(_fill_box.mesh as BoxMesh).size = area_size


## [member color] at a quarter of its own alpha - the same wash-under-the-outline
## reasoning [method DebugArea2D._fill_color] uses.
func _fill_color() -> Color:
	return Color(color.r, color.g, color.b, color.a * 0.25)


## Moves both [member _box] and [member _fill_box] to [method _box_position] - the two
## always share a position, so nothing calls either in isolation.
func _reposition() -> void:
	_box.position = _box_position()
	_fill_box.position = _box_position()


## [b]Collider path[/b]: [member offset] plus the collider's own centre - a
## [CollisionShape3D]'s [member CollisionShape3D.position] already means "the shape's
## centre," so this reads it straight, no ground-resting correction.
##
## [b]Footprint path[/b]: [member offset] plus half [member area_size]'s own height:
## an actor's own [member Node3D.position], which [Actor.world_position]'s own doc
## calls the ground it stands on, not its middle - the same convention [method
## DebugPassabilityView._wire_box_instance] rests its box on with a hardcoded
## [code]Vector3(0.0, 0.5, 0.0)[/code]. Deriving it from [member area_size] instead of
## a fixed 0.5 is what keeps the box resting on the ground rather than sinking half
## into it when [member area_size]'s own height is not 1. [member _footprint_offset]
## rides along on X/Z for the same reason [method GameEvent._footprint_visual_offset]
## exists for the sprite: the anchor is the footprint's own corner, not its centre,
## once it is bigger than 1x1x1.
##
## [b]Neither path[/b] (authored, no target resolved): same as the footprint path
## with [member _footprint_offset] left at zero.
func _box_position() -> Vector3:
	if _use_collider_center:
		return offset + _collider_center
	return offset + Vector3(_footprint_offset.x, area_size.y * 0.5, _footprint_offset.y)


## The 12 edges of a [param size] box, centred on the origin, as line-primitive
## geometry - a wireframe [BoxMesh] is not a thing Godot 4 ships. Identical to
## [method DebugPassabilityView._build_wire_box]; kept as its own small copy rather
## than a shared static helper, since neither side has a natural home for one that
## does not make the other reach across files for a four-line function.
func _build_wire_box(size: Vector3) -> ArrayMesh:
	var h := size * 0.5
	var corners: Array[Vector3] = [
		Vector3(-h.x, -h.y, -h.z), Vector3(h.x, -h.y, -h.z),
		Vector3(h.x, -h.y, h.z), Vector3(-h.x, -h.y, h.z),
		Vector3(-h.x, h.y, -h.z), Vector3(h.x, h.y, -h.z),
		Vector3(h.x, h.y, h.z), Vector3(-h.x, h.y, h.z),
	]
	var edges: Array[Vector2i] = [
		Vector2i(0, 1), Vector2i(1, 2), Vector2i(2, 3), Vector2i(3, 0),
		Vector2i(4, 5), Vector2i(5, 6), Vector2i(6, 7), Vector2i(7, 4),
		Vector2i(0, 4), Vector2i(1, 5), Vector2i(2, 6), Vector2i(3, 7),
	]

	var points := PackedVector3Array()
	for edge in edges:
		points.append(corners[edge.x])
		points.append(corners[edge.y])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh
