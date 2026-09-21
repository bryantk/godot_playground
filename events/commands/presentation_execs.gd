## Presentation executors.
##
## [code]play_anim[/code], [code]play_sound[/code] and [code]play_music[/code] have no
## executor yet - there is no animation hookup and no audio subsystem at all today.
## Left to the generic fallback.


## Shows or hides an actor's visual, through [method ActorView.set_visible].
class SetVisible extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a != null:
			a.view().set_visible(bool(args.get("visible", true)))


## Changes an actor's draw order relative to other actors and sprites on the map,
## through [method ActorView.set_y_level]. Higher draws over lower; a map's floor and
## "above" tile layers bracket the whole range with their own z_index, so this alone
## cannot draw an actor over the trees or under the floor.
class SetYLevel extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a != null:
			a.view().set_y_level(int(args.get("y_level", 0)))


static func table() -> Dictionary:
	return {
		"set_visible": SetVisible,
		"set_y_level": SetYLevel,
	}
