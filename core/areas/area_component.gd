class_name AreaComponent extends Node

## Something an [AreaZone] does to the actors crossing it. A child of the zone, one per
## behaviour, so that a tile which slows you down, plays a sound and fires an event is
## three components on one shape rather than one script that does three things.
##
## The zone reports crossings and decides nothing; this decides. In particular
## [b]the direction rules and the speed number live here, not on the zone[/b] - they are
## what one component means by a crossing, and another component on the same shape has no
## use for them.
##
## Subclasses override the four handlers they care about. The base connects all four and
## applies [member affects] first, so no subclass repeats the filter.

## Which actors this component acts on. Every actor gets the zone's signals regardless;
## this is only about who is affected by what the component does, which is why it is here
## and not on [AreaZone].
enum Affects {
	ALL,     ## Every actor that crosses.
	PLAYER,  ## The player only - a [PlayerBrain], or failing that the id "player".
	TARGET,  ## The one actor or event named by [member target_id].
}

@export var affects: Affects = Affects.ALL

## The actor id or event id [constant Affects.TARGET] means. Ignored otherwise.
@export var target_id: StringName = &""

var _zone: AreaZone = null


func _ready() -> void:
	_zone = _resolve_zone()
	if _zone == null:
		push_warning("AreaComponent('%s'): no AreaZone on or beside its parent." % name)
		return

	_zone.actor_entered.connect(func (a: Actor) -> void: _dispatch(a, _on_entered))
	_zone.actor_arrived.connect(func (a: Actor) -> void: _dispatch(a, _on_arrived))
	_zone.actor_leaving.connect(func (a: Actor) -> void: _dispatch(a, _on_leaving))
	# Unfiltered, deliberately - see _on_exited.
	_zone.actor_exited.connect(_on_exited)


func zone() -> AreaZone:
	return _zone


## The zone this component belongs to: its parent, or a sibling under the same area.
##
## Both layouts are accepted because both are what someone actually builds. Nesting the
## component under the zone says "this belongs to that" and is the arrangement to prefer;
## dropping the zone and the component side by side under the [Area2D] is what dragging
## two nodes onto a shape in the editor produces, and it is not worth a silent no-op.
func _resolve_zone() -> AreaZone:
	var parent := get_parent()
	if parent is AreaZone:
		return parent as AreaZone
	if parent == null:
		return null
	for sibling in parent.get_children():
		if sibling is AreaZone:
			return sibling as AreaZone
	return null


## Does this component act on [param actor]?
func applies_to(actor: Actor) -> bool:
	if actor == null:
		return false
	match affects:
		Affects.PLAYER:
			return actor.brain() is PlayerBrain or actor.actor_id == &"player"
		Affects.TARGET:
			return actor.actor_id == target_id
		_:
			return true


func _dispatch(actor: Actor, handler: Callable) -> void:
	if applies_to(actor):
		handler.call(actor)


# -- To implement -------------------------------------------------------------

func _on_entered(_actor: Actor) -> void:
	pass


func _on_arrived(_actor: Actor) -> void:
	pass


func _on_leaving(_actor: Actor) -> void:
	pass


func _on_exited(_actor: Actor) -> void:
	pass
