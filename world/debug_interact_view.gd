extends Node

## One transient X per player interact attempt, for whichever grid-movement map is
## currently loaded - green on the cell that actually fired, red on the cell faced if
## nothing did. Autoloaded, the same reasoning as [DebugPassabilityView]: one instance
## for the whole game, found by [MapContext]'s own group membership rather than a
## [NodePath], so it follows whichever map is loaded without anything wiring it in.
##
## [b]Spawns nothing while [method DebugFlags.show_debug_view] is off[/b] - same flag
## every other debug overlay in the project answers to.

const FOUND_COLOR := Color(0.25, 0.95, 0.35, 0.95)
const MISS_COLOR := Color(0.95, 0.2, 0.2, 0.95)


func _ready() -> void:
	EventBus.interact_attempted.connect(_on_interact_attempted)


func _on_interact_attempted(cell: Vector3i, found: bool) -> void:
	if not DebugFlags.show_debug_view():
		return

	var ctx := get_tree().get_first_node_in_group(&"map_context") as MapContext
	if ctx == null:
		return

	var root := ctx.get_parent()
	if root == null:
		return

	var color := FOUND_COLOR if found else MISS_COLOR
	var world := ctx.cell_centre(cell)

	if root is Node3D:
		var marker := DebugInteractMarker3D.new()
		marker.color = color
		marker.size = maxf(ctx.cell_size.x, ctx.cell_size.z) * 0.6
		marker.position = world + Vector3(0.0, 0.05, 0.0)
		root.add_child(marker)
	elif root is Node2D:
		var marker := DebugInteractMarker2D.new()
		marker.color = color
		marker.size = Vector2(ctx.cell_size.x, ctx.cell_size.z) * 0.6
		marker.position = Space.as_v2(world)
		root.add_child(marker)
