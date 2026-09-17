## Map executors. Only [code]change_map[/code] has one so far.
##
## [code]fade[/code], [code]shake[/code], [code]camera_to[/code] and
## [code]camera_follow[/code] have no executor yet - there is no camera rig hookup for
## events to drive today (segment 6). Left to the generic fallback.


## Leaves for another map (question 51). Gained a real [code]"next"[/code] port so an
## exclusive runner can be chained across the load and keep running on the far side -
## but the load itself, and the [EventContext] rebind that goes with it, need a map
## loader that does not exist yet. This is a placeholder: it says so once and resolves
## immediately rather than hanging a graph that has one on a system nothing has built.
class ChangeMap extends EventCommandExec:
	func start() -> void:
		push_warning("EventRunner: change_map to \"%s\" - no map loader yet, staying put."
			% str(args.get("map", "")))


static func table() -> Dictionary:
	return {
		"change_map": ChangeMap,
	}
