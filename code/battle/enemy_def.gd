@tool
class_name EnemyDef extends Combatant

## One enemy type - a [Troop]'s own building block, the enemy-side twin of
## [PartyMember]. Identity, stats and abilities are [Combatant]'s; what is added here is
## what only an enemy has: a gold reward and how it decides what to do. See
## [BattleState._choose_enemy_command] for how it picks.

## Gold/items a [Troop] entry naming this enemy hands over on victory - split per
## enemy rather than per troop, so a troop that mixes enemy types adds up naturally.
@export var gold_reward: int = 0

## An AI graph - an ordinary event graph file, built in the graph editor from the battle
## commands ([code]if_round[/code], [code]if_stat[/code], [code]choose_target[/code],
## [code]use_ability[/code], ...). Empty means the old behaviour: a random ability on a
## random target.
@export_file("*.event.json") var ai_path: String = ""

## The name this field had before [Combatant]: the same [member base_stats].
var stats: Stats:
	get:
		return base_stats
	set(value):
		base_stats = value


## An enemy starts able to Attack.
func _default_abilities() -> Array[Ability]:
	return [Ability.attack()]
