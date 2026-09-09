extends Node

## Loads a scene and prints what the camera and the followed actor actually resolved
## to. Diagnostics only - a still frame tells you the framing is wrong but not why.
##
##     godot --path . res://tools/probe.tscn -- <scene>

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	var scene: Node = (load(args[0]) as PackedScene).instantiate()
	add_child(scene)

	for _i in 20:
		await get_tree().process_frame

	var ctx := _find(scene, "MapContext") as MapContext
	print("ctx: ", ctx)
	if ctx != null:
		print("  map_id      : ", ctx.map_id)
		print("  actor ids   : ", ctx.actor_ids())
		var who := ctx.actor(&"player")
		print("  player      : ", who)
		if who != null:
			print("  player pos  : ", who.world_position())
			print("  player cell : ", who.cell())

	var rig := _find(scene, "OrthoPixelRig") as OrthoPixelRig
	print("rig: ", rig)
	if rig != null:
		print("  target      : ", rig.target())
		print("  ctx         : ", rig.context())
		print("  yaw stop    : ", rig.yaw_stop)
		var cam := _find(scene, "Camera3D") as Camera3D
		if cam != null:
			print("  cam pos     : ", cam.global_position)
			print("  cam rot deg : ", cam.global_rotation_degrees)
			print("  cam size    : ", cam.size, "  proj ", cam.projection)
			var spr := _find(scene, "Sprite3D") as Sprite3D
			if spr != null:
				print("  sprite pos  : ", spr.global_position)
				print("  sprite vis  : ", spr.is_visible_in_tree())
				print("  sprite px   : ", cam.unproject_position(spr.global_position))
				print("  behind cam  : ", cam.is_position_behind(spr.global_position))
			var cont := _find(scene, "SubViewportContainer") as SubViewportContainer
			if cont != null:
				print("  container   : pos ", cont.position, " size ", cont.size,
					" shrink ", cont.stretch_shrink, " stretch ", cont.stretch)

	var vp := _find(scene, "SubViewport") as SubViewport
	if vp != null:
		print("subviewport size: ", vp.size)

	get_tree().quit(0)


func _find(root: Node, cls: String) -> Node:
	if root.is_class(cls) or _script_named(root, cls):
		return root
	for child in root.get_children():
		var found := _find(child, cls)
		if found != null:
			return found
	return null


func _script_named(node: Node, cls: String) -> bool:
	var s: Script = node.get_script()
	while s != null:
		if s.get_global_name() == StringName(cls):
			return true
		s = s.get_base_script()
	return false
