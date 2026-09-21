@tool
class_name DebugArea3D extends Node3D

## Draws a wireframe cube - the [Node3D] counterpart to [DebugArea2D]; see its class
## doc for why this is a scene-authored child of [GameEvent] rather than something
## [GameEvent] builds for itself, why there is no label, and why [method _process]
## copies [member Node3D.global_position] off the nearest real [Node3D] ancestor by
## hand ([method _find_anchor]) instead of trusting the transform chain.
##
## [b]Always visible while editing.[/b] [b]At runtime, only while [method
## DebugFlags.show_debug_view] is on[/b] - the same flag [DebugPassabilityView] reads.

@export var area_size: Vector3 = Vector3.ONE:
	set(value):
		area_size = value
		# Guarded rather than always calling _rebuild(): this setter also fires while
		# the scene is still being deserialized, before this node has entered the tree
		# at all - _ready() picks up whatever area_size ends up holding by then, and
		# calling _rebuild() this early would be building a mesh nobody can see yet
		# for no reason. Once _box exists, a later edit (the inspector, live) is the
		# case this rebuilds for.
		if _box != null:
			_rebuild()

@export var offset: Vector3 = Vector3.ZERO:
	set(value):
		offset = value
		if _box != null:
			_box.position = offset

@export var color: Color = Color(0.35, 0.55, 1.0, 0.9):
	set(value):
		color = value
		if _material != null:
			_material.albedo_color = color

var _box: MeshInstance3D = null
var _material: StandardMaterial3D = null
var _anchor: Node3D = null


func _ready() -> void:
	_anchor = _find_anchor()
	_rebuild()
	_sync_visibility()
	_sync_position()


func _process(_delta: float) -> void:
	_sync_visibility()
	_sync_position()


## The nearest [Node3D] above this node's own parent - see [method
## DebugArea2D._find_anchor], the identical reasoning one dimension over.
func _find_anchor() -> Node3D:
	var n := get_parent()
	n = n.get_parent() if n != null else null
	while n != null:
		if n is Node3D:
			return n as Node3D
		n = n.get_parent()
	return null


func _sync_position() -> void:
	if _anchor != null and is_instance_valid(_anchor):
		global_position = _anchor.global_position


func _sync_visibility() -> void:
	visible = true if Engine.is_editor_hint() else DebugFlags.show_debug_view()


func _rebuild() -> void:
	if _box == null or not is_instance_valid(_box):
		_material = StandardMaterial3D.new()
		_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_material.albedo_color = color

		_box = MeshInstance3D.new()
		_box.name = "WireBox"
		_box.material_override = _material
		_box.position = offset
		add_child(_box)

	_box.mesh = _build_wire_box(area_size)


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
