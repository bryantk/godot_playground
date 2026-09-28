class_name DebugInteractMarker3D extends Node3D

## The [Node3D] counterpart to [DebugInteractMarker2D] - a flat wireframe X on the
## ground plane, fading out and freeing itself over [member lifetime].

@export var size: float = 1.0
@export var color: Color = Color.WHITE
@export var lifetime: float = 3.0

var _age := 0.0
var _material: StandardMaterial3D


func _ready() -> void:
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.albedo_color = color

	var mesh_instance := MeshInstance3D.new()
	mesh_instance.mesh = _build_x_mesh(size)
	mesh_instance.material_override = _material
	add_child(mesh_instance)


func _process(delta: float) -> void:
	_age += delta
	if _age >= lifetime:
		queue_free()
		return
	var a := 1.0 - _age / lifetime
	_material.albedo_color = Color(color.r, color.g, color.b, a)


## Two diagonals across a [param s]-wide square, flat on X/Z - a wireframe [BoxMesh]-
## style line mesh, the same technique [DebugArea3D._build_wire_box] uses for its box.
func _build_x_mesh(s: float) -> ArrayMesh:
	var h := s * 0.5
	var points := PackedVector3Array([
		Vector3(-h, 0.0, -h), Vector3(h, 0.0, h),
		Vector3(-h, 0.0, h), Vector3(h, 0.0, -h),
	])

	var arrays := []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = points

	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_LINES, arrays)
	return mesh
