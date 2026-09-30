@tool
class_name Ability extends Resource

## One thing a [Battler] can do on its turn - an attack, a skill, an item, guarding. Heroes
## and enemies list these in [member Combatant.abilities]; a hero starts with [method attack]
## and [method guard], an enemy with [method attack].
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

## Status effects this ability puts on each target it hits, each with a
## [member effect_chance] chance. An ability with a [member power] of 0 or less does no
## damage at all and only applies these - a pure buff or debuff.
@export var effects: Array[StatusEffect] = []
@export_range(0.0, 1.0, 0.01) var effect_chance: float = 1.0


## Whether resolving this deals (or, negative, heals) hp damage. A guard, or a skill with
## [member power] 0 that only applies [member effects], does not.
func deals_damage() -> bool:
	return kind != Kind.GUARD and power > 0.0


# -- The two every combatant starts with ------------------------------------------

const ATTACK_PATH := "res://data/abilities/attack.tres"
const GUARD_PATH := "res://data/abilities/guard.tres"


## The shared Attack ability: a plain physical hit on one enemy. Loaded from
## [constant ATTACK_PATH] so every hero and enemy that lists it holds the [i]same[/i]
## resource (edit it once, every one of them changes); built in code only if that file is
## missing, so a bare test or a fresh checkout still has something to attack with.
static func attack() -> Ability:
	if ResourceLoader.exists(ATTACK_PATH):
		var loaded := load(ATTACK_PATH) as Ability
		if loaded != null:
			return loaded
	var built := Ability.new()
	built.id = &"attack"
	built.display_name = "Attack"
	built.kind = Kind.ATTACK
	built.target = Target.SINGLE_ENEMY
	built.power = 1.0
	return built


## The shared Guard ability: the user takes half damage until its next turn. Same loading
## rule as [method attack].
static func guard() -> Ability:
	if ResourceLoader.exists(GUARD_PATH):
		var loaded := load(GUARD_PATH) as Ability
		if loaded != null:
			return loaded
	var built := Ability.new()
	built.id = &"guard"
	built.display_name = "Guard"
	built.kind = Kind.GUARD
	built.target = Target.SELF
	built.power = 0.0
	return built
