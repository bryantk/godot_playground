class_name RestrictToArea extends GameEventModifier

## A [GameEventModifier] that fences its own [Actor] inside one [AreaZone]: any step
## that would land outside it is refused exactly like a wall - [MotionController]
## step_allowed and [signal EventBus.actor_blocked] both fire the ordinary way, so
## every existing bump/touch trigger keeps working with no special case for "left the
## area" at all.
##
## Registers itself on [method MotionController.add_step_restrictor] rather than
## reacting to a crossing signal - this has nothing to do with entering or leaving a
## zone by walking through it, and everything to do with a standing rule that is true
## for as long as this node is in the tree.
##
## Grid actors only: [method MotionController.step_allowed] is [GridMotion]'s own
## call, and a free-moving actor's continuous motion has no discrete step to veto.

## The zone [member GameEventModifier.actor] may not step outside of.
@export var target_zone: AreaZone = null


func _ready() -> void:
	super._ready()
	var a := actor()
	if a != null:
		a.motion().add_step_restrictor(self)


func _exit_tree() -> void:
	var a := actor()
	if a != null:
		a.motion().remove_step_restrictor(self)


## Every cell in [param to_cells] must already be covered by [member target_zone] - the
## same cell-centre point query [method AreaZone.zones_at] answers for crossing
## detection, asked here before the step instead of after it.
func allows(who: Actor, to_cells: Array[Vector3i]) -> bool:
	if target_zone == null:
		return true
	for cell in to_cells:
		if not AreaZone.zones_at(who, cell).has(target_zone):
			return false
	return true
