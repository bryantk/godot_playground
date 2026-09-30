class_name ActiveEffect extends RefCounted

## One [StatusEffect] running on one combatant: how many stacks, and how long it has left.

var effect: StatusEffect
var stacks: int = 1

## Units left ([member StatusEffect.unit]); meaningless for an effect whose duration is 0.
var remaining: int = 0


func _init(a_effect: StatusEffect = null) -> void:
	effect = a_effect
	remaining = a_effect.duration if a_effect != null else 0


func to_save() -> Dictionary:
	return {"id": str(effect.id), "stacks": stacks, "remaining": remaining}
