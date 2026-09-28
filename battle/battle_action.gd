class_name BattleAction extends Resource

## One thing a [Battler] can do on its turn - an attack, a skill, an item, guarding.
## Plain data, read by [BattleFormula] and [BattleState]; nothing here decides who it
## targets or resolves anything itself.

enum Kind { ATTACK, SKILL, ITEM, GUARD }
enum Target { SINGLE_ENEMY, ALL_ENEMIES, SINGLE_ALLY, ALL_ALLIES, SELF }

@export var id: StringName = &""
@export var display_name: String = ""
@export var kind: Kind = Kind.ATTACK
@export var target: Target = Target.SINGLE_ENEMY

## What [method BattleFormula.damage] scales off - [member Stats.atk] for a physical
## attack, [member Stats.mag] for most skills. Multiplied against a flat [member power]
## rather than a fixed formula per action, so honing in on a new action is picking a
## number, not writing a new function.
@export var power: float = 1.0
@export var uses_magic: bool = false
@export var element: StringName = &""
@export var mp_cost: int = 0

## Only meaningful for [constant Kind.ITEM] - the [member Party.items] key this action
## consumes one of.
@export var item_id: StringName = &""
