class_name BattleFormula

## The one damage formula every action goes through. Deliberately a single small
## function rather than a formula-authoring system of its own - honing in on a real
## curve means editing this body, not building a DSL first.
##
## [code](power * (atk or mag)) - def[/code], times the defender's own element
## multiplier, clamped to at least 1 so an attack always does *something* rather than
## reading as a silent miss - unless that multiplier is itself zero or negative (immune
## or absorbing the element), in which case the clamp would silently paper over exactly
## the thing an author picked that multiplier to express. A negative result is
## intentional - [method BattleState._apply_damage] reads it as healing.
static func damage(attacker: Stats, defender: Stats, action: BattleAction) -> int:
	var offense := float(attacker.mag if action.uses_magic else attacker.atk)
	var raw := action.power * offense - float(defender.def)
	var multiplier := defender.element_multiplier(action.element)
	if multiplier <= 0.0:
		return roundi(raw * multiplier)
	return maxi(1, roundi(raw * multiplier))
