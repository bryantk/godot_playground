class_name SpeedModifier extends AreaComponent

## Scales the movement speed of actors inside an [AreaZone] - mud, ice, a staircase, a
## conveyor's drag.
##
## [b]It is a provider, not a value.[/b] Entering registers this component with the
## actor's [MotionController]; leaving unregisters it. In between, the controller asks it
## for a scale every frame, handing it the direction being travelled. That is what makes a
## per-direction rule work without anything storing a modified speed that then has to be
## put back: the actor's own [member MotionController.speed] is never written, so there is
## nothing to restore and nothing a route's own speed change can clobber.
##
## Asking every frame rather than once per step is also what lets a scale change mid-cell.
##
## [b]Directions are the actor's heading, not the side it crossed.[/b] Leave all four
## false and the zone slows every direction, which is the ordinary mud case; check
## [member north] alone and only northward movement is affected, which is the staircase
## that is slow to climb and ordinary to descend. An actor that turns round inside the
## zone is re-evaluated on its next step - the rule is not latched at entry.

enum Match {
	ANY,  ## Affected if the heading includes any checked direction. North-west is slowed by a north zone.
	ALL,  ## Affected only if every cardinal of the heading is checked. North-west needs north and west both.
}

## Which step this applies to, relative to the zone. The default catches both the step
## coming in and the step going out, which is what mud is; [constant On.DESTINATION] is
## the one to pick when only the arrival should be slow.
enum On {
	BOTH,         ## The step in, the steps within, and the step out.
	DESTINATION,  ## Only steps that end inside the zone.
	ORIGIN,       ## Only steps that begin inside the zone.
}

## Multiplied into the actor's speed. Below 1 is slower; above 1 is faster, which is the
## same component with a different number rather than a second one.
@export var scale: float = 0.8

@export_group("Directions")
@export var north: bool = false
@export var east: bool = false
@export var south: bool = false
@export var west: bool = false
@export var match_mode: Match = Match.ANY
@export_group("")

@export var applies_on: On = On.BOTH


## The scale for an actor travelling [param dir], or 1.0 when this component has nothing
## to say about that step. Called by [MotionController]; [param dir] is a world direction,
## so a grid step and an analog heading ask the same question.
func scale_for(actor: Actor, dir: Vector3) -> float:
	if _zone == null or not _zone.has_actor(actor):
		return 1.0
	if not _applies_to_step(actor):
		return 1.0
	if not _matches(dir):
		return 1.0
	return scale


## Whether this step's ends put it in scope, asked of the zone rather than recomputed:
## the zone already knows whether the step it is mid-way through came in or is going out.
func _applies_to_step(actor: Actor) -> bool:
	match applies_on:
		On.DESTINATION:
			return _zone.step_enters(actor)
		On.ORIGIN:
			return _zone.step_leaves(actor)
		_:
			return true


## Does [param dir] count, per the four bools?
##
## No direction checked means every direction, for the same reason an unpainted pathing
## cell is open ground: the neutral setting has to be the one that does the obvious thing
## on a shape someone just dropped into a map.
func _matches(dir: Vector3) -> bool:
	var wanted := _wanted()
	if wanted == 0:
		return true

	var heading := Passability.cardinals(dir)
	if heading == 0:
		return false

	if match_mode == Match.ALL:
		return (heading & wanted) == heading
	return (heading & wanted) != 0


func _wanted() -> int:
	var mask := 0
	if north:
		mask |= Passability.NORTH
	if east:
		mask |= Passability.EAST
	if south:
		mask |= Passability.SOUTH
	if west:
		mask |= Passability.WEST
	return mask


# -- Registration -------------------------------------------------------------

func _on_entered(actor: Actor) -> void:
	var motion := actor.motion()
	if motion != null:
		motion.add_speed_provider(self)


## Registered until the actor is [i]wholly[/i] out, not until its body leaves. That is
## what keeps [constant On.BOTH] honest: the step carrying the actor out of the mud is
## still a step out of mud, and it is still slow.
func _on_exited(actor: Actor) -> void:
	var motion := actor.motion()
	if motion != null:
		motion.remove_speed_provider(self)
