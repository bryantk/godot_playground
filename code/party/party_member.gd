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

## Where this member is in their growth. Level and experience are saved; everything else a
## level gives (stats, learned abilities) is worked out from them each time, so changing
## [member growth] or [member learnset] in the inspector re-levels every save consistently.
@export var level: int = 1
@export var xp: int = 0

## Stat gains per level above 1: stat name -> amount ("max_hp": 6, "atk": 2). Keys are the
## six stat names (see [constant StatusEffect.STATS]).
@export var growth: Dictionary = {}

## Abilities learned on reaching a level: level -> ability. Available from that level on, in
## addition to [member abilities].
@export var learnset: Dictionary[int, Ability] = {}

const MAX_LEVEL := 99


## Experience needed to go from [param from_level] to the next.
static func xp_needed(from_level: int) -> int:
	return 10 * from_level * from_level


## Adds [param amount] experience, raising the level (possibly several times) as it passes
## each threshold. Returns a log line for each level reached and ability learned.
func grant_xp(amount: int) -> Array[String]:
	var log: Array[String] = []
	if amount <= 0:
		return log
	xp += amount
	while level < MAX_LEVEL and xp >= xp_needed(level):
		xp -= xp_needed(level)
		level += 1
		log.append("%s reaches level %d!" % [display_name, level])
		var learned: Ability = learnset.get(level)
		if learned != null:
			log.append("%s learns %s!" % [display_name, learned.display_name])
	return log


## [member abilities] plus every ability in [member learnset] at or below the current level,
## without repeats - what a fight offers this member.
func all_abilities() -> Array[Ability]:
	var out: Array[Ability] = abilities.duplicate()
	var levels := learnset.keys()
	levels.sort()
	for gained: int in levels:
		var learned: Ability = learnset[gained]
		if gained <= level and learned != null and not out.has(learned):
			out.append(learned)
	return out


## [member base_stats] plus every equipped slot's own [member Equipment.bonus], then any
## running [member effects] - what a [Battler] starts a fight from.
func effective_stats() -> Stats:
	return EffectList.effective(gear_stats(), effects)


## [member base_stats] plus gear only, before effects - what a [Battler] rebuilds from each
## time its own effects change.
func gear_stats() -> Stats:
	var out := base_stats
	if not growth.is_empty() and level > 1:
		out = _with_growth(out)
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
		"level": level,
		"xp": xp,
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
	level = int(state.get("level", level))
	xp = int(state.get("xp", xp))
	effects = EffectList.from_save(state.get("effects", []) as Array,
			func(effect_id: StringName) -> StatusEffect: return BattleData.effect(effect_id))


## A hero starts able to Attack and Guard.
func _default_abilities() -> Array[Ability]:
	return [Ability.attack(), Ability.guard()]


## [param base] plus [member growth] for every level above 1 - a new [Stats], [param base]
## untouched.
func _with_growth(base: Stats) -> Stats:
	var out := Stats.new()
	out.max_hp = base.max_hp
	out.max_mp = base.max_mp
	out.atk = base.atk
	out.def = base.def
	out.mag = base.mag
	out.spd = base.spd
	out.elements = base.elements.duplicate()
	for stat in StatusEffect.STATS:
		out.set(stat, int(out.get(stat)) + int(growth.get(stat, 0)) * (level - 1))
	return out


## Removes the effects [param mode] ([enum Ability.Dispel]) names from this member - a cleanse
## from an item or a spell used outside a fight. Returns what came off.
func remove_effects(mode: int) -> Array[StatusEffect]:
	var removed: Array[StatusEffect] = []
	if mode == Ability.Dispel.NONE:
		return removed
	for active in effects.duplicate():
		var is_buff: bool = active.effect.beneficial
		if mode == Ability.Dispel.ALL or (mode == Ability.Dispel.BUFFS and is_buff) \
				or (mode == Ability.Dispel.DEBUFFS and not is_buff):
			effects.erase(active)
			removed.append(active.effect)
	return removed
