@tool
class_name MapMarker2D extends Node2D

## A named teleport point a map author drops anywhere under a 2D map root - what
## [code]change_map_marker[/code] (events/commands/map_execs.gd) reads a destination
## position and an optional facing from, instead of a hand-typed cell. See
## [MapMarker3D] for the 3D game's own twin - one script per space, the same
## [DebugArea2D]/[DebugArea3D] split, rather than one script fighting both base classes.
##
## [member facing] is this marker's own opinion; "(unset)" means it has none.
## [code]change_map_marker[/code]'s own [code]facing[/code] argument always wins when
## both are given - see [method resolved_facing] and that command's own doc for the
## "override or defer" rule.

@export var marker_name: StringName = &""
@export_enum("(unset)", "n", "e", "s", "w", "ne", "se", "sw", "nw") var facing: String = "(unset)"


## [member facing] resolved to a direction, or [constant Vector3i.ZERO] for "(unset)" -
## the same "no opinion" reading [method EventCommand.direction_of] already gives any
## token it does not recognise.
func resolved_facing() -> Vector3i:
	return EventCommand.direction_of(facing)
