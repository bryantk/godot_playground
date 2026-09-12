extends Node
func _shot(path: String, act: String, out: String) -> void:
	var demo := (load(path) as PackedScene).instantiate()
	add_child(demo)
	for i in 30:
		await get_tree().process_frame
	var player: Actor = demo.get("_player")
	if act != "":
		Input.action_press(act)
		while not player.is_travelling():
			await get_tree().process_frame
		await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	get_viewport().get_texture().get_image().save_png(out)
	if act != "":
		Input.action_release(act)
	demo.queue_free()
	await get_tree().process_frame
	print("saved ", out)

func _ready() -> void:
	await _shot("res://demos/demo_launcher.tscn", "", "user://s0.png")
	await _shot("res://games/jrpg/jrpg_demo.tscn", "move_down", "user://s1.png")
	await _shot("res://games/isoish/isoish_grid_demo.tscn", "move_left", "user://s2.png")
	get_tree().quit(0)
