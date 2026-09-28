## Map executors.
##
## [code]shake[/code], [code]camera_to[/code] and [code]camera_follow[/code] have no
## executor yet - there is no camera rig hookup for events to drive today (segment 6).
## Left to the generic fallback.

## How long to wait for a freshly loaded scene to register its own [MapContext] before
## giving up - [code]core/save_game.gd[/code]'s own guard (600 ticks, ~10s at 60fps),
## mirrored here rather than shared: that file polls from a [Node]'s own [method
## Node._process] loop, this from a tick-driven executor with no [SceneTree] of its own
## to [code]await[/code] (event_command_exec.gd's "commands never await" rule).
const _MAP_WAIT_TICKS := 600


## Shared machinery for [code]change_map[/code]/[code]change_map_marker[/code]: fade out
## (if asked), swap the scene, wait for the new [MapContext] to register, place the
## player (each subclass's own [method _place]), fade in (if asked). Question 51's
## "next" port is what lets an exclusive runner ride this out and keep going on the far
## side - owned by [EventScheduler], not whatever [GameEvent]/[Actor] spawned it, since
## either may no longer exist once the old scene is gone.
##
## [b]Always the player, never [code]@self[/code][/b]: a map transfer's whole point is
## "where do I, the player, end up" - [code]@self[/code] might be a door or a bodiless
## trigger that has no equivalent, or any equivalent at all, on the destination map.
class ChangeMapBase extends EventCommandExec:
	enum _Phase { FADE_OUT, WAIT_MAP, FADE_IN, DONE }
	var _phase: int = _Phase.DONE
	var _guard := 0

	func start() -> void:
		_guard = 0
		var seconds := float(args.get("fade_out", 0.0))
		if seconds > 0.0:
			GameUI.fade_to(0.0, seconds, load_texture_arg(args.get("texture", "")))
			_phase = _Phase.FADE_OUT
		else:
			_swap_scene()

	func _swap_scene() -> void:
		var tree := Engine.get_main_loop() as SceneTree
		tree.change_scene_to_file(str(args.get("map", "")))
		_phase = _Phase.WAIT_MAP
		_guard = 0

	func _begin_fade_in() -> void:
		var seconds := float(args.get("fade_in", 0.0))
		if seconds > 0.0:
			GameUI.fade_to(1.0, seconds, load_texture_arg(args.get("texture", "")))
			_phase = _Phase.FADE_IN
		else:
			_phase = _Phase.DONE

	func tick(_delta: float) -> int:
		if _phase == _Phase.FADE_OUT:
			if GameUI.is_fading():
				return Status.RUNNING
			_swap_scene()

		if _phase == _Phase.WAIT_MAP:
			var tree := Engine.get_main_loop() as SceneTree
			var found: MapContext = tree.get_first_node_in_group(&"map_context")
			if found == null:
				_guard += 1
				if _guard > _MAP_WAIT_TICKS:
					push_warning(
						"EventRunner: change_map to \"%s\" - the new scene never registered a MapContext."
						% str(args.get("map", "")))
					_phase = _Phase.DONE
					return Status.DONE
				return Status.RUNNING
			# Identity (map_id/event_id) is untouched - only the live map reference moves
			# (question 51). @player below resolves fresh against it rather than a
			# pointer into whatever map just went away.
			ctx.rebind_map(found)
			_place(found)
			_begin_fade_in()

		if _phase == _Phase.FADE_IN:
			if GameUI.is_fading():
				return Status.RUNNING
			_phase = _Phase.DONE

		return Status.DONE if _phase == _Phase.DONE else Status.RUNNING

	## Places the player on the newly loaded, already-rebound map. The base does
	## nothing; each concrete command below reads its own args to find where.
	func _place(_map_ctx: MapContext) -> void:
		pass


## Leaves for another map (question 51), placing the player at an explicit cell/facing -
## the "just tell me where" half of map transfer. See [ChangeMapMarker] for the "a named
## point in the destination scene" half. Both cell and facing are optional: omitted,
## each is left exactly as the destination scene's own authored placement already has it.
class ChangeMap extends ChangeMapBase:
	func _place(_map_ctx: MapContext) -> void:
		var player := ctx.resolve("@player")
		if player == null:
			return
		if args.has("cell"):
			player.motion().move_to(Vector3i(args.get("cell", Vector3i.ZERO)), {"path": "raw"})
		if args.has("facing"):
			var dir := Vector3i(args.get("facing", Vector3i.ZERO))
			if dir != Vector3i.ZERO:
				player.motion().face(dir)


## Leaves for another map, placing the player at a named [MapMarker2D]/[MapMarker3D]
## nested somewhere under the destination scene - "a linked scene and a named teleport
## location" - instead of a hand-typed cell. This command's own [code]facing[/code]
## argument overrides the marker's; with neither set, the player's facing is left
## exactly as it was.
class ChangeMapMarker extends ChangeMapBase:
	func _place(map_ctx: MapContext) -> void:
		var player := ctx.resolve("@player")
		if player == null:
			return

		var marker_name := StringName(str(args.get("marker", "")))
		var marker := _find_marker(map_ctx.get_parent(), marker_name)
		if marker == null:
			push_warning("EventRunner: change_map_marker - no marker named \"%s\" under \"%s\"."
				% [str(marker_name), str(args.get("map", ""))])
			return

		var world: Vector3
		var marker_facing := Vector3i.ZERO
		if marker is MapMarker2D:
			var m2 := marker as MapMarker2D
			world = Space.as_v3(m2.global_position)
			marker_facing = m2.resolved_facing()
		elif marker is MapMarker3D:
			var m3 := marker as MapMarker3D
			world = m3.global_position
			marker_facing = m3.resolved_facing()
		else:
			return

		player.motion().move_to(map_ctx.cell_of(world), {"path": "raw"})

		var dir := Vector3i(args.get("facing", Vector3i.ZERO))
		if dir == Vector3i.ZERO:
			dir = marker_facing
		if dir != Vector3i.ZERO:
			player.motion().face(dir)

	## The [MapMarker2D]/[MapMarker3D] anywhere under [param root] named
	## [param marker_name], or null. Recursive rather than one fixed path: event-pages.md
	## leaves exactly where a marker sits under the map root up to the author, the same
	## "search, don't assume a path" reasoning [code]graph_editor_panel.gd[/code]'s own
	## actor/GameEvent lookups already follow.
	static func _find_marker(root: Node, marker_name: StringName) -> Node:
		if (root is MapMarker2D or root is MapMarker3D) and root.marker_name == marker_name:
			return root
		for child in root.get_children():
			var found := _find_marker(child, marker_name)
			if found != null:
				return found
		return null


static func table() -> Dictionary:
	return {
		"change_map": ChangeMap,
		"change_map_marker": ChangeMapMarker,
	}
