extends Node

## Loads a scene, lets it settle, and saves a PNG of the root viewport. Needs a real
## renderer, so run it windowed rather than headless - a headless run draws nothing
## and saves a blank frame.
##
##     godot --path . res://tools/shoot.tscn -- <scene> <out.png> [frames] [yaw_stop]
##
## The optional yaw stop pokes an OrthoPixelRig directly and instantly, so a sequence
## of shots can show the four views without waiting on the snap tween.

func _ready() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("usage: -- <scene> <out.png> [frames] [yaw_stop]")
		get_tree().quit(2)
		return

	var scene_path := args[0]
	var out_path := args[1]
	var frames := int(args[2]) if args.size() > 2 else 40

	if not ResourceLoader.exists(scene_path):
		printerr("no such scene: %s" % scene_path)
		get_tree().quit(2)
		return

	var scene: Node = (load(scene_path) as PackedScene).instantiate()
	add_child(scene)

	# A couple of frames for _ready to build the world before poking at it.
	for _i in 3:
		await get_tree().process_frame

	if args.size() > 3:
		var rig := _find_rig(scene)
		if rig != null:
			rig.yaw_stop = int(args[3])
			if rig.get_parent() is Node3D:
				# Let the rig reposition the camera for the new yaw.
				await get_tree().process_frame

	for _i in frames:
		await get_tree().process_frame

	# Wait for the frame to actually be drawn, or the texture read is a frame stale
	# and a SubViewport can come back empty.
	await RenderingServer.frame_post_draw

	var image := get_viewport().get_texture().get_image()
	var err := image.save_png(out_path)
	if err != OK:
		printerr("save failed (%d)" % err)
		get_tree().quit(1)
		return
	print("shot %s -> %s (%dx%d)" % [scene_path, out_path, image.get_width(), image.get_height()])
	get_tree().quit(0)


func _find_rig(root: Node) -> OrthoPixelRig:
	if root is OrthoPixelRig:
		return root as OrthoPixelRig
	for child in root.get_children():
		var found := _find_rig(child)
		if found != null:
			return found
	# SubViewports are children, but their contents hang off the viewport node, which
	# get_children already covers - so nothing extra is needed here.
	return null
