class_name EnemyDef extends Resource

## One enemy type - a [Troop]'s own building block, the enemy-side twin of
## [PartyMember]. No equipment (nothing to hone there yet): just a name, stats and the
## actions it picks from - see [BattleState._enemy_turn] for how it picks.

@export var id: StringName = &""
@export var display_name: String = ""
@export var stats: Stats = null
@export var actions: Array[BattleAction] = []

## Gold/items a [Troop] entry naming this enemy hands over on victory - split per
## enemy rather than per troop, so a troop that mixes enemy types adds up naturally.
@export var gold_reward: int = 0
