@tool
class_name Equipment extends Resource

## One piece of gear - a plain stat bonus added on top of a [PartyMember]'s base
## [Stats] while it sits in one of that slot's own equip fields (see [method
## PartyMember.effective_stats]). No special effects of its own yet - honing in on
## those is a later pass, once flat bonuses have been played with.

enum Slot { WEAPON, ARMOR, ACCESSORY }

@export var id: StringName = &""
@export var display_name: String = ""
@export var slot: Slot = Slot.WEAPON
@export var bonus: Stats = null
@export var price: int = 0
