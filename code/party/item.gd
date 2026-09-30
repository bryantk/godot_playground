@tool
class_name Item extends Resource

## A consumable: what it is called, what it costs, and what it does when used - described
## by an ordinary [Ability] (flat healing in [member Ability.power], and any
## [member Ability.effects]), so an item in a fight and an item from the menu are the
## same thing resolved twice. [member Party.items] holds how many of each the party has, by
## [member id].

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""
@export var price: int = 0

## What using it does. Its [member Ability.kind] is read as ITEM.
@export var action: Ability = null

@export var usable_in_battle: bool = true
@export var usable_in_field: bool = true
