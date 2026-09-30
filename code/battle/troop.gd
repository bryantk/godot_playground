class_name Troop extends Resource

## What [code]start_battle[/code]'s own [code]troop[/code] argument names (events/
## event_command.gd) - which enemies show up, and how many of each. Resolved to real
## [Battler]s by [method BattleState.begin] the moment battle starts.

@export var id: StringName = &""

## One entry per enemy group - [code]{"enemy": EnemyDef, "count": int}[/code]. A plain
## typed array of a shape rather than a second resource class: nothing about "how many
## of this enemy" earns fields of its own yet.
@export var enemies: Array[Dictionary] = []
