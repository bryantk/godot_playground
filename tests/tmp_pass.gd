extends Node
func _ready() -> void:
	var demo := (load("res://games/jrpg/jrpg_demo.tscn") as PackedScene).instantiate()
	add_child(demo)
	for i in 20:
		await get_tree().process_frame
	var player: Actor = demo.get("_player")
	var ctx := player.context()
	var walls := ctx.get_node(ctx.collision_node) as TileMapLayer
	print("  collision_node -> %s (%s)" % [ctx.collision_node, walls])
	for cell in [Vector3i(14, 0, 12), Vector3i(14, 0, 13), Vector3i(0, 0, 9), Vector3i(14, 0, 9)]:
		var td := walls.get_cell_tile_data(Vector2i(cell.x, cell.z))
		var raw = td.get_custom_data(Passability.DATA_PASSABLE) if td != null else "<no tile>"
		print("   %s  tile=%s passable_data=%s  can_enter=%s" % [
			cell, td != null, raw, Passability.can_enter(ctx, cell, player)])
	Input.action_press("move_down")
	await get_tree().create_timer(2.5).timeout
	Input.action_release("move_down")
	print("  walked down to %s (row 13 is solid wall)" % player.cell())
	get_tree().quit(0)
