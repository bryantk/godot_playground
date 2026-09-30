@tool
class_name PartyMember extends Combatant

## One playable character. Identity, base stats and abilities are [Combatant]'s; what is
## added here is what only a hero has - equipped gear, the sprite it walks behind the
## player with, and hp/mp and effects carried between fights. [member Party] holds these
## (active and reserve); a [Battler] wraps one for the length of a fight rather than this
## carrying its own current hp/mp, so a mid-battle knockout never risks corrupting the
## save-shaped data underneath it.

## The sprite sheet this member walks behind the player with (the party caterpillar -
## see [FollowerChain]). Same sheet layout as the player's own art. Null means no
## follower: the member is in the party but not seen trailing the player.
@export var follower_sheet: Texture2D = null

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

## Effects running on this member - picked up in the field (an item, an event) or left
## over from a fight - counted down by [method tick_steps] and by battle rounds, and
## saved. A [Battler] copies these in and writes them back.
var effects: Array[ActiveEffect] = []


## [member base_stats] plus every equipped slot's own [member Equipment.bonus], then any
## running [member effects] - what a [Battler] starts a fight from.
func effective_stats() -> Stats:
	return EffectList.effective(gear_stats(), effects)


## [member base_stats] plus gear only, before effects - what a [Battler] rebuilds from each
## time its own effects change.
func gear_stats() -> Stats:
	var out := base_stats
	for slot: Variant in equipped:
		var item: Equipment = equipped[slot]
		if item != null and item.bonus != null:
			out = Stats.added(out, item.bonus)
	return out


## Puts [param effect] on this member (field use). Returns false when it was ignored by its
## own stacking rule.
func add_effect(effect: StatusEffect) -> bool:
	return EffectList.add(effects, effect) != null


## One player step: counts down every STEPS effect. Returns what ran out.
func tick_steps() -> Array[StatusEffect]:
	return EffectList.tick(effects, StatusEffect.Unit.STEPS)


func clear_effects() -> void:
	effects.clear()


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
		"effects": EffectList.to_save(effects),
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
	effects = EffectList.from_save(state.get("effects", []) as Array,
			func(effect_id: StringName) -> StatusEffect: return BattleData.effect(effect_id))


## A hero starts able to Attack and Guard.
func _default_abilities() -> Array[Ability]:
	return [Ability.attack(), Ability.guard()]
