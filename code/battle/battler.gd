class_name Battler extends RefCounted

## One combat participant for the length of one fight - wraps a [PartyMember] or an
## [EnemyDef] rather than either carrying its own current hp/mp, so a knockout mid-fight
## can never corrupt the save-shaped data underneath it (see [PartyMember]'s own doc).

enum Side { PLAYER, ENEMY }

## Plain [int], not [enum Side] - a [Battler] built by its own static factory
## ([method for_member]/[method for_enemy]) assigning [code]Side.PLAYER[/code] onto a
## freshly-constructed [code]Battler.new()[/code] trips a GDScript static-analysis bug
## where the property's declared enum type and the enum literal's own type are treated
## as distinct despite being the same enum. Untyped avoids it; every comparison
## ([code]battler.side == Battler.Side.PLAYER[/code]) still reads correctly since an
## enum is an int underneath.
var side: int = Side.PLAYER
var display_name: String
var abilities: Array[Ability]
var hp: int
var mp: int

## What this battler fights with right now: its base (set by assigning, as the factories do)
## with every running [member effects] applied. Recomputed whenever they change, so anything
## reading [code]battler.stats[/code] - the damage formula, turn order, the scene's labels -
## sees a buff or debuff without knowing one exists.
var stats: Stats:
	get:
		if _effective == null:
			refresh_stats()
		return _effective
	set(value):
		_base = value
		refresh_stats()

var _base: Stats = null
var _effective: Stats = null

## Running [StatusEffect]s. A hero's are copied in from [member PartyMember.effects] and
## written back by [method sync_to_member]; an enemy's live only for the fight.
var effects: Array[ActiveEffect] = []

## Set for exactly one turn by the [constant Ability.Kind.GUARD] action -
## [method BattleState._resolve_action] halves incoming damage while it is true, then
## clears it the next time this battler acts (see [method BattleState._begin_round]).
var guarding: bool = false

## Which [PartyMember] this came from - null for an enemy [Battler]. What
## [method BattleState.finish] writes hp/mp loss back onto, and what a defeat-screen
## reads for "who fell".
var member: PartyMember = null

## Which [EnemyDef] this came from - null for a player [Battler]. [member
## EnemyDef.gold_reward] is read off this on victory.
var enemy: EnemyDef = null


## [member PartyMember.current_hp]/[member PartyMember.current_mp] carry over from the
## last fight this member survived - -1 (never fought) reads as full, the same "no
## opinion yet" sentinel [member MapMarker2D.facing]'s own "(unset)" is for facing.
static func for_member(a_member: PartyMember) -> Battler:
	var b := Battler.new()
	b.side = Side.PLAYER
	b.member = a_member
	b.display_name = a_member.display_name
	b.abilities = a_member.abilities
	for active in a_member.effects:
		var copy := ActiveEffect.new(active.effect)
		copy.stacks = active.stacks
		copy.remaining = active.remaining
		b.effects.append(copy)
	b.stats = a_member.gear_stats()
	b.hp = a_member.current_hp if a_member.current_hp >= 0 else b.stats.max_hp
	b.mp = a_member.current_mp if a_member.current_mp >= 0 else b.stats.max_mp
	return b


## Writes this fight's ending hp/mp and effects back onto [member member] - a no-op for an
## enemy [Battler]. Called once per player [Battler] when [method BattleState.is_over]
## becomes true, so a party that survives carries its wounds (and what is still on it) into
## the next fight and one that does not is left exactly as it fell (nothing here revives
## anyone).
func sync_to_member() -> void:
	if member == null:
		return
	member.current_hp = hp
	member.current_mp = mp
	member.effects.clear()
	for active in effects:
		var copy := ActiveEffect.new(active.effect)
		copy.stacks = active.stacks
		copy.remaining = active.remaining
		member.effects.append(copy)


static func for_enemy(a_enemy: EnemyDef, distinguish: int = 0) -> Battler:
	var b := Battler.new()
	b.side = Side.ENEMY
	b.enemy = a_enemy
	b.display_name = a_enemy.display_name if distinguish == 0 \
		else "%s %d" % [a_enemy.display_name, distinguish + 1]
	b.stats = a_enemy.stats
	b.abilities = a_enemy.abilities
	b.hp = b.stats.max_hp
	b.mp = b.stats.max_mp
	return b


func is_alive() -> bool:
	return hp > 0


# -- Effects -------------------------------------------------------------------------

## Puts [param effect] on this battler and refreshes [member stats]. Returns false when its
## stacking rule ignored it.
func add_effect(effect: StatusEffect) -> bool:
	var applied := EffectList.add(effects, effect) != null
	refresh_stats()
	return applied


func has_effect(effect_id: StringName) -> bool:
	return EffectList.has(effects, effect_id)


## End of a battle round: counts every ROUNDS effect down. Returns what wore off.
func tick_round() -> Array[StatusEffect]:
	var expired := EffectList.tick(effects, StatusEffect.Unit.ROUNDS)
	refresh_stats()
	return expired


## Rebuilds [member stats] from the base and the running effects, keeping hp/mp inside the
## new maximums (a debuff that lowers max hp can leave a battler at less than it had, never
## above the cap).
func refresh_stats() -> void:
	if _base == null:
		return
	_effective = EffectList.effective(_base, effects)
	hp = mini(hp, _effective.max_hp)
	mp = mini(mp, _effective.max_mp)


## [param amount] positive damages, negative heals - [BattleFormula.damage]'s own
## negative-multiplier (an absorbed element) reads exactly this way. Guarding halves a
## positive amount, never a heal.
func apply_damage(amount: int) -> int:
	var applied := amount
	if applied > 0 and guarding:
		applied = maxi(1, roundi(applied * 0.5))
	hp = clampi(hp - applied, 0, stats.max_hp)
	return applied


func spend_mp(amount: int) -> bool:
	if mp < amount:
		return false
	mp -= amount
	return true
