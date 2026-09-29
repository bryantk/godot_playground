class_name GameEventModifier extends Node

## A tag/behaviour a [GameEvent] carries as a sibling or child - a pushable crate, an
## NPC fenced to its own patrol area, and whatever comes after them. Each one hooks
## into whichever signal its own behaviour actually needs (a physics bus signal, a
## motion hook, a zone crossing); this base class exists only for the one thing every
## one of them has in common - finding the [GameEvent] and [Actor] it acts on.
##
## [b]Sibling or child, same as [DebugArea2D]/[DebugArea3D] and for the same
## reason[/b]: whichever a scene's own author finds more convenient to drag under a
## placement. Resolved once in [method _ready] via [method _resolve_event], not
## searched for on every use.

## Set by hand to resolve a conflict (more than one [GameEvent] sibling under the same
## placement root); left unset, [method _resolve_event] finds one automatically.
@export var event: GameEvent = null

var _actor: Actor = null


func _ready() -> void:
	_resolve_event()
	_actor = event.actor() if event != null else null
	if event == null:
		push_warning("%s('%s'): no sibling GameEvent found - this modifier does nothing."
			% [get_script().get_global_name(), name])


## Leaves [member event] alone if it already names something live; otherwise looks for
## a [GameEvent] on the parent itself, then among the parent's own children (a sibling
## of this modifier) - the same "GameEvent is the parent, or its sibling" shape [method
## GameEvent._find_actor] uses for its own [Actor].
func _resolve_event() -> void:
	if event != null and is_instance_valid(event):
		return

	var parent := get_parent()
	if parent == null:
		return

	if parent is GameEvent:
		event = parent
		return

	for child in parent.get_children():
		if child is GameEvent:
			event = child
			return


func actor() -> Actor:
	return _actor
