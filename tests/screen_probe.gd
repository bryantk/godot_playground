extends Node

## Samples where a followed sprite lands on screen, once per frame, after the camera rig
## has run - [code]process_priority[/code] is set high by whoever adds it. Used by
## [code]demo_scenes_test.gd[/code]: a pinned actor's spread across the samples is zero,
## and any drift means the rig let it slide.

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
