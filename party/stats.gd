class_name Stats extends Resource

## The numbers a formula (battle/battle_formula.gd) actually reads - shared by a
## [PartyMember] and an [EnemyDef], and by [Equipment]'s own bonus, so all three add
## together the same way (see [method PartyMember.effective_stats]).
##
## Loose on purpose: six flat numbers and an elements table, no derived formulas of its
## own. Honing in on a real curve (level scaling, diminishing returns, whatever) means
## changing [BattleFormula] and what feeds these fields, not this shape.

@export var max_hp: int = 20
@export var max_mp: int = 10
@export var atk: int = 5
@export var def: int = 5
@export var mag: int = 5
@export var spd: int = 5

## element token ("fire", "water", ...) -> multiplier: 0 immune, 0.5 resist, 1 normal
## (the default for anything not listed), 2 weak, negative absorbs.
@export var elements: Dictionary = {}


func element_multiplier(element: StringName) -> float:
	if element == &"" or not elements.has(element):
		return 1.0
	return float(elements[element])


## A new [Stats] with every numeric field summed - [param a] plus [param b]. Elements
## come from [param a] alone: they are a battler's own affinity, not something an
## equipment bonus (the usual [param b] in this call) is expected to shift in this
## first pass - see [method PartyMember.effective_stats].
static func added(a: Stats, b: Stats) -> Stats:
	var out := Stats.new()
	out.max_hp = a.max_hp + b.max_hp
	out.max_mp = a.max_mp + b.max_mp
	out.atk = a.atk + b.atk
	out.def = a.def + b.def
	out.mag = a.mag + b.mag
	out.spd = a.spd + b.spd
	out.elements = a.elements.duplicate()
	return out
