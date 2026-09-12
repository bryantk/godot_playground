extends Node
var cam: Camera3D
var sprite: Node3D
var container: SubViewportContainer
var t: float
var shrink: float
var samples: Array[float] = []
var armed := false

func _process(_d: float) -> void:
	if not armed or cam == null:
		return
	var b := cam.global_basis
	samples.append(round((sprite.global_position - cam.global_position).dot(b.x) * t)
		* shrink + container.position.x)
