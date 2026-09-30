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
var stats: Stats
var actions: Array[BattleAction]
var hp: int
var mp: int

## Set for exactly one turn by the [constant BattleAction.Kind.GUARD] action -
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
	b.stats = a_member.effective_stats()
	b.actions = a_member.actions
	b.hp = a_member.current_hp if a_member.current_hp >= 0 else b.stats.max_hp
	b.mp = a_member.current_mp if a_member.current_mp >= 0 else b.stats.max_mp
	return b


## Writes this fight's ending hp/mp back onto [member member] - a no-op for an enemy
## [Battler]. Called once per player [Battler] when [method BattleState.is_over]
## becomes true, so a party that survives carries its wounds into the next fight and one
## that does not is left exactly as it fell (nothing here revives anyone).
func sync_to_member() -> void:
	if member == null:
		return
	member.current_hp = hp
	member.current_mp = mp


static func for_enemy(a_enemy: EnemyDef, distinguish: int = 0) -> Battler:
	var b := Battler.new()
	b.side = Side.ENEMY
	b.enemy = a_enemy
	b.display_name = a_enemy.display_name if distinguish == 0 \
		else "%s %d" % [a_enemy.display_name, distinguish + 1]
	b.stats = a_enemy.stats
	b.actions = a_enemy.actions
	b.hp = b.stats.max_hp
	b.mp = b.stats.max_mp
	return b


func is_alive() -> bool:
	return hp > 0


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
