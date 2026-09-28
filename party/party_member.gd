class_name PartyMember extends Resource

## One playable character - identity, base stats, equipped gear and the actions it
## knows. [member Party] holds these (active and reserve); a [Battler] wraps one for
## the length of a fight rather than this carrying its own current hp/mp, so a
## mid-battle knockout never risks corrupting the save-shaped data underneath it.

@export var id: StringName = &""
@export var display_name: String = ""
@export var base_stats: Stats = null
@export var actions: Array[BattleAction] = []

@export var equipped: Dictionary = {
	Equipment.Slot.WEAPON: null,
	Equipment.Slot.ARMOR: null,
	Equipment.Slot.ACCESSORY: null,
}

## Carried between fights, so damage (and healing) actually means something across a
## whole dungeon rather than every battle starting fresh at full health. -1 means "never
## fought yet" - [method Battler.for_member] reads that as full [member effective_stats]
## rather than clamping a real 0 into it.
@export var current_hp: int = -1
@export var current_mp: int = -1


## [member base_stats] plus every equipped slot's own [member Equipment.bonus] -
## nothing else touches a member's stats yet (no level curve, no buffs); a [Battler]
## reads this once at the start of a fight.
func effective_stats() -> Stats:
	var out := base_stats
	for slot: Variant in equipped:
		var item: Equipment = equipped[slot]
		if item != null and item.bonus != null:
			out = Stats.added(out, item.bonus)
	return out


func equip(item: Equipment) -> Equipment:
	var previous: Equipment = equipped.get(item.slot, null)
	equipped[item.slot] = item
	return previous


func unequip(slot: Equipment.Slot) -> Equipment:
	var previous: Equipment = equipped.get(slot, null)
	equipped[slot] = null
	return previous


func to_save() -> Dictionary:
	var equip_ids := {}
	for slot: Variant in equipped:
		var item: Equipment = equipped[slot]
		equip_ids[int(slot)] = str(item.id) if item != null else ""
	return {
		"id": str(id),
		"equipped": equip_ids,
		"current_hp": current_hp,
		"current_mp": current_mp,
	}


## The inverse of [method to_save] - [param resolve_equipment] turns an id back into
## the real [Equipment] resource (the shop/inventory catalogue's own job, not this
## file's), since a save only ever carries ids, never whole resources.
func from_save(state: Dictionary, resolve_equipment: Callable) -> void:
	var equip_ids: Dictionary = state.get("equipped", {})
	for slot_key: Variant in equip_ids:
		var item_id := str(equip_ids[slot_key])
		equipped[int(slot_key)] = resolve_equipment.call(item_id) if item_id != "" else null
	current_hp = int(state.get("current_hp", -1))
	current_mp = int(state.get("current_mp", -1))
