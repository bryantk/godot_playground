@tool
class_name MapMarker3D extends Node3D

## The 3D game's twin of [MapMarker2D] - see that class's own doc for what this is and
## why it is a second script rather than one shared base.

@export var marker_name: StringName = &""
@export_enum("(unset)", "n", "e", "s", "w", "ne", "se", "sw", "nw") var facing: String = "(unset)"


func resolved_facing() -> Vector3i:
	return EventCommand.direction_of(facing)
