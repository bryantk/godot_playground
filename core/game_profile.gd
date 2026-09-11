class_name GameProfile extends Resource

## Which game this build is. A [Resource] rather than code, because the event dock's
## validation runs inside the Godot editor and must read it without the game running.
##
## Each game ships as its own executable with exactly one profile compiled in - there
## is no runtime selection, no launcher and no swap. That is what makes capability
## tags a purely authoring-time concern: nothing at runtime ever asks whether a
## command is available to it, because a build only ever contains one game.
##
## Two profiles exist: [code]jrpg[/code] and [code]isoish[/code].

## What a profile provides and a command may require.
##
## A closed enum, not the free strings this started as. With a growing command set,
## free strings drift into near-duplicates that silently never match a requirement -
## and a capability that never matches fails [i]open[/i], so the validator simply
## stops warning. Seven values is the cheapest moment to close it.
enum Capability {
	GRID_MOTION,
	FREE_MOTION,
	HEIGHT,
	PATHFINDER,
	STEP_PULSE,
	ROTATABLE_VIEW,
	BATTLE_SCENE,
}

## Empty by default deliberately. Defaulting to a real game's name would mean a new
## profile silently claims to be that game, and - because Godot omits properties that
## match their default - the claim would not even appear in the .tres to notice.
@export var id: StringName = &""

## Human-facing name, for a window title and the dock's header.
@export var display_name: String = "Untitled"

@export var capabilities: Array[Capability] = []

@export var input_profile: InputProfile = null

## Which modes this game has at all. Game 1 has a battle scene; game 2 does not.
@export var modes: Array[StringName] = [&"field", &"cutscene", &"menu"]

## Default for a map that does not override it.
@export var default_cell_size: Vector3 = Vector3.ONE

## Pixels per world unit horizontally. 16 for both games.
@export var texels_per_unit: int = 16

## Vertical faces get their own density: at pitch 30 a face is 13.856 px per world
## unit, so art authored at 16 loses about 14% of its rows unevenly. 14 maps to a 1%
## squash instead. Horizontal stays [member texels_per_unit].
@export var texels_per_unit_vertical: int = 14

## Maximum round duration before the gate is force-closed and the offending actor
## logged. Generously above any legitimate action. Only consulted in a mode that has
## rounds - see [method ModeStack.rounds_active].
@export var round_watchdog_seconds: float = 2.0

# -- The four axes ------------------------------------------------------------
#
# Named rather than merely documented, so the axis table is executable and
# ActorFactory can build an actor's children from data. MapContext.default_motion
# takes precedence over motion_script, which is what keeps "grid movement in a 3D
# town" possible.

@export var space_script: Script = null
@export var motion_script: Script = null
@export var view_script: Script = null
@export var camera_script: Script = null


func has(capability: Capability) -> bool:
	return capabilities.has(capability)


## Does this profile provide everything in [param required]? The event dock's
## validation reports the first missing one by name rather than letting the command
## fail silently at runtime.
func missing(required: Array[Capability]) -> Array[Capability]:
	var out: Array[Capability] = []
	for cap in required:
		if not has(cap):
			out.append(cap)
	return out


static func capability_name(capability: Capability) -> String:
	return Capability.keys()[capability].to_lower()
