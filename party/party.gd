extends Node

## The player's whole roster, gold and inventory - structured records, not scalar
## flags, which is why this is its own autoload rather than another entry in
## [GameState]'s manifest. Autoloaded as [code]Party[/code].
##
## Seeded with a small starter roster/inventory on [method _ready] so there is
## something to open a menu or a battle onto immediately - swap [method _seed_demo_data]
## for real authored [PartyMember]/[Equipment] [code].tres[/code] resources once the
## loose numbers here have been played with enough to hone in on.

signal changed()

## Battle can only ever hold so many at once - [BattleState.begin] reads exactly this
## many from the front of [member active].
const MAX_ACTIVE := 4

var active: Array[PartyMember] = []
var reserve: Array[PartyMember] = []
var gold: int = 0

## item id -> count. Anything with an entry here and no matching [BattleAction] of
## [constant BattleAction.Kind.ITEM] is just an inventory curiosity - unused, not
## invalid, since a shop may sell items no battle action reads yet.
var items: Dictionary = {}

## Unequipped [Equipment] sitting in inventory, id -> count. Equipping moves one unit
## from here onto a member (see [method equip_from_inventory]); unequipping puts it
## back.
var owned_equipment: Dictionary = {}

## id -> resource, for every [PartyMember]/[Equipment] this run knows about - what
## [method from_save] resolves a saved id back through, and what a shop/equipment menu
## lists from. Registering is additive; [method _seed_demo_data] is the one caller
## today.
var _member_catalogue: Dictionary = {}
var _equipment_catalogue: Dictionary = {}


func _ready() -> void:
	_seed_demo_data()


func register_member(member: PartyMember) -> void:
	_member_catalogue[member.id] = member


func register_equipment(item: Equipment) -> void:
	_equipment_catalogue[item.id] = item


func equipment_catalogue() -> Array[Equipment]:
	var out: Array[Equipment] = []
	for id: Variant in _equipment_catalogue:
		out.append(_equipment_catalogue[id])
	return out


## Every currently-fightable member, [constant MAX_ACTIVE] at most - what
## [method BattleState.begin] builds the player side from.
func active_members() -> Array[PartyMember]:
	return active.slice(0, MAX_ACTIVE)


func add_gold(amount: int) -> void:
	gold = maxi(0, gold + amount)
	changed.emit()


func add_item(item_id: StringName, count: int = 1) -> void:
	items[item_id] = int(items.get(item_id, 0)) + count
	changed.emit()


## True and consumes one if [param item_id] is in stock; false and consumes nothing
## otherwise - the same "check by doing" shape [method Occupancy.place] already uses,
## so a caller never has to ask twice.
func consume_item(item_id: StringName) -> bool:
	var count := int(items.get(item_id, 0))
	if count <= 0:
		return false
	if count == 1:
		items.erase(item_id)
	else:
		items[item_id] = count - 1
	changed.emit()
	return true


## Moves one unit of [param item_id] from [member owned_equipment] onto [param member]'s
## own [method PartyMember.equip], returning whatever it replaced to inventory. False
## (no change) if none are in stock.
func equip_from_inventory(member: PartyMember, item_id: StringName) -> bool:
	var count := int(owned_equipment.get(item_id, 0))
	if count <= 0:
		return false
	var item: Equipment = _equipment_catalogue.get(item_id)
	if item == null:
		return false

	if count == 1:
		owned_equipment.erase(item_id)
	else:
		owned_equipment[item_id] = count - 1

	var replaced := member.equip(item)
	if replaced != null:
		owned_equipment[replaced.id] = int(owned_equipment.get(replaced.id, 0)) + 1

	changed.emit()
	return true


func unequip_to_inventory(member: PartyMember, slot: Equipment.Slot) -> void:
	var removed := member.unequip(slot)
	if removed != null:
		owned_equipment[removed.id] = int(owned_equipment.get(removed.id, 0)) + 1
		changed.emit()


func to_save() -> Dictionary:
	var active_ids: Array = []
	for m in active:
		active_ids.append(m.to_save())
	var reserve_ids: Array = []
	for m in reserve:
		reserve_ids.append(m.to_save())
	return {
		"gold": gold,
		"items": _stringify_keys(items),
		"owned_equipment": _stringify_keys(owned_equipment),
		"active": active_ids,
		"reserve": reserve_ids,
	}


## [StringName] keys round-trip through [JSON.stringify] as their [code]&"..."[/code]
## literal text rather than the bare string a save file should read back - the same
## reason [code]save_game.gd[/code] itself calls [code]str(a.actor_id)[/code] before
## using an actor id as a save key.
func _stringify_keys(dict: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in dict:
		out[str(key)] = dict[key]
	return out


## The inverse of [method _stringify_keys] - a saved item/equipment table's keys are
## plain strings; every other reader in this file (including [Equipment.id] itself)
## expects the [StringName] they started as.
func _string_name_keys(dict: Dictionary) -> Dictionary:
	var out := {}
	for key: Variant in dict:
		out[StringName(key)] = dict[key]
	return out


func from_save(state: Dictionary) -> void:
	gold = int(state.get("gold", 0))
	items = _string_name_keys(state.get("items", {}))
	owned_equipment = _string_name_keys(state.get("owned_equipment", {}))

	var resolve_equipment := func(id: String) -> Equipment:
		return _equipment_catalogue.get(StringName(id))

	active = _restore_members(state.get("active", []), resolve_equipment)
	reserve = _restore_members(state.get("reserve", []), resolve_equipment)
	changed.emit()


func _restore_members(saved: Array, resolve_equipment: Callable) -> Array[PartyMember]:
	var out: Array[PartyMember] = []
	for entry: Variant in saved:
		var id := StringName(str((entry as Dictionary).get("id", "")))
		var template: PartyMember = _member_catalogue.get(id)
		if template == null:
			continue
		# A fresh copy off the catalogue template, not the template itself - two
		# members must never share one Resource's equipped dictionary.
		var member: PartyMember = template.duplicate(true)
		member.from_save(entry, resolve_equipment)
		out.append(member)
	return out


func clear() -> void:
	active.clear()
	reserve.clear()
	gold = 0
	items.clear()
	owned_equipment.clear()
	_seed_demo_data()


## A tiny starter roster so a fresh run has party members to look at, equip and fight
## with before any real content is authored - see the class doc.
func _seed_demo_data() -> void:
	_member_catalogue.clear()
	_equipment_catalogue.clear()
	active.clear()
	reserve.clear()

	var sword := Equipment.new()
	sword.id = &"rusty_sword"
	sword.display_name = "Rusty Sword"
	sword.slot = Equipment.Slot.WEAPON
	sword.bonus = _stats(0, 0, 3, 0, 0, 0)
	sword.price = 20
	register_equipment(sword)

	var robe := Equipment.new()
	robe.id = &"cloth_robe"
	robe.display_name = "Cloth Robe"
	robe.slot = Equipment.Slot.ARMOR
	robe.bonus = _stats(0, 0, 0, 2, 1, 0)
	robe.price = 15
	register_equipment(robe)

	var attack := BattleAction.new()
	attack.id = &"attack"
	attack.display_name = "Attack"
	attack.kind = BattleAction.Kind.ATTACK
	attack.target = BattleAction.Target.SINGLE_ENEMY
	attack.power = 1.0

	var fireball := BattleAction.new()
	fireball.id = &"fireball"
	fireball.display_name = "Fireball"
	fireball.kind = BattleAction.Kind.SKILL
	fireball.target = BattleAction.Target.SINGLE_ENEMY
	fireball.power = 1.4
	fireball.uses_magic = true
	fireball.element = &"fire"
	fireball.mp_cost = 4

	var hero := PartyMember.new()
	hero.id = &"hero"
	hero.display_name = "Hero"
	hero.base_stats = _stats(28, 8, 7, 5, 4, 6)
	hero.actions = [attack, fireball]
	register_member(hero)
	active.append(hero)

	var mage := PartyMember.new()
	mage.id = &"mage"
	mage.display_name = "Mage"
	mage.base_stats = _stats(18, 16, 3, 3, 8, 5)
	mage.actions = [attack, fireball]
	register_member(mage)
	active.append(mage)

	gold = 50
	items = {&"potion": 3}
	owned_equipment = {}


static func _stats(hp: int, mp: int, atk: int, def: int, mag: int, spd: int) -> Stats:
	var s := Stats.new()
	s.max_hp = hp
	s.max_mp = mp
	s.atk = atk
	s.def = def
	s.mag = mag
	s.spd = spd
	return s
