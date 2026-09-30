@tool
class_name Combatant extends Resource

## What a hero and an enemy have in common: an identity, base [Stats], and the
## abilities ([Ability]s) they can use. [PartyMember] (heroes) and [EnemyDef]
## (enemies) extend this and add only what is theirs - gear and carried-over hp for a
## hero, a gold reward and an AI graph for an enemy - so anything written against one
## (effects, formulas, the Battle Data editor) works on both.

@export var id: StringName = &""
@export var display_name: String = ""
@export var base_stats: Stats = null

## The abilities this combatant can choose from on its turn, by [member Ability.id]. A new
## hero starts with Attack and Guard, a new enemy with Attack - see [method
## _default_abilities].
@export var abilities: Array[Ability] = []


func _init() -> void:
	abilities = _default_abilities()


## What a fresh one of these starts with, before anything authored replaces it - a
## subclass overrides this (a hero gets Attack and Guard, an enemy Attack). A saved
## resource's own list wins over it on load.
func _default_abilities() -> Array[Ability]:
	return []


## The stats a fight starts from. A hero adds gear and any active effects on top; an
## enemy is its base.
func effective_stats() -> Stats:
	return base_stats
