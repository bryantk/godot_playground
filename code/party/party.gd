extends Node

## The player's whole roster, gold and inventory - structured records, not scalar
## flags, which is why this is its own autoload rather than another entry in
## [GameState]'s manifest. Autoloaded as [code]Party[/code].
##
## Populated on [method _ready] from a [PartySetup] resource ([constant SETUP_PATH]) - who is
## in the party, the gold and the bags are all edited in the inspector, not written in
## code. A member is a [PartyMember] resource, so the starting party is an ordinary .tres
## edit. Saves remember members by id and look them up in the catalogue built here.

signal changed()

## Battle can only ever hold so many at once - [BattleState.begin] reads exactly this
## many from the front of [member active].
const MAX_ACTIVE := 4

var active: Array[PartyMember] = []
var reserve: Array[PartyMember] = []
var gold: int = 0

## item id -> count. Anything with an entry here and no matching [Ability] of
## [constant Ability.Kind.ITEM] is just an inventory curiosity - unused, not
## invalid, since a shop may sell items no battle action reads yet.
var items: Dictionary = {}

## Unequipped [Equipment] sitting in inventory, id -> count. Equipping moves one unit
## from here onto a member (see [method equip_from_inventory]); unequipping puts it
## back.
var owned_equipment: Dictionary = {}

## id -> resource, for every [PartyMember]/[Equipment] this run knows about - what
## [method from_save] resolves a saved id back through, and what a shop/equipment menu
## lists from. Registering is additive; [method apply_setup] is the main caller
## today.
var _member_catalogue: Dictionary = {}
var _equipment_catalogue: Dictionary = {}


func _ready() -> void:
	load_setup()
	# A player step counts down every STEPS effect on the roster - the field half of
	# StatusEffect durations (a battle round is BattleState's).
	EventBus.player_stepped.connect(func(_from: Vector3i, _to: Vector3i) -> void: tick_field_steps())


## Registers [param item] so [method use_item_in_field] and the battle scene can find it by
## [member Item.id].
func register_item(item: Item) -> void:
	BattleData.register(BattleData.ITEMS, item)


## One step walked: counts down the STEPS effects on every member, active or reserve.
func tick_field_steps() -> void:
	for member in active + reserve:
		member.tick_steps()


## Uses one [param item_id] on [param member] from the menu or an event, outside a fight:
## flat healing from the item's action [member Ability.power], and any
## [member Ability.effects] put on the member. Returns what happened as a line of
## text, or "" when it could not be used (unknown item, not usable in the field, none
## left).
func use_item_in_field(item_id: StringName, member: PartyMember) -> String:
	var item := BattleData.item(item_id)
	if item == null or item.action == null or member == null or not item.usable_in_field:
		return ""
	if not consume_item(item_id):
		return ""

	var stats := member.effective_stats()
	var text := "%s uses %s." % [member.display_name, item.display_name]
	var heal := roundi(item.action.power)
	if heal > 0:
		var current := member.current_hp if member.current_hp >= 0 else stats.max_hp
		member.current_hp = mini(current + heal, stats.max_hp)
		text += " %s recovers %d HP." % [member.display_name, member.current_hp - current]
	for effect in member.remove_effects(item.action.dispel):
		text += " %s's %s is removed." % [member.display_name, effect.display_name]
	for effect in item.action.effects:
		if effect != null and member.add_effect(effect):
			text += " %s gains %s." % [member.display_name, effect.display_name]
	changed.emit()
	return text


func register_member(member: PartyMember) -> void:
	_member_catalogue[member.id] = member


func register_equipment(item: Equipment) -> void:
	_equipment_catalogue[item.id] = item


func equipment_catalogue() -> Array[Equipment]:
	var out: Array[Equipment] = []
	for id: Variant in _equipment_catalogue:
		out.append(_equipment_catalogue[id])
	return out


## Every [PartyMember] this run has ever registered - active, reserve, or neither
## (a template nobody has recruited yet). What the battle sandbox tool
## (tools/battle_sandbox.gd) lists allies from, since a sandbox test should not be
## limited to whoever happens to be in the active party right now.
func member_catalogue() -> Array[PartyMember]:
	var out: Array[PartyMember] = []
	for id: Variant in _member_catalogue:
		out.append(_member_catalogue[id])
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
	load_setup()

## Where the starting party is authored - a [PartySetup] resource, edited in the inspector
## (the Battle Data dock's "Party setup" button opens it).
const SETUP_PATH := "res://data/party.tres"


## Builds the party from [constant SETUP_PATH]. With no such file the party is simply empty
## (and says so), rather than quietly inventing one.
func load_setup() -> void:
	_member_catalogue.clear()
	_equipment_catalogue.clear()
	active.clear()
	reserve.clear()
	gold = 0
	items.clear()
	owned_equipment.clear()

	if not ResourceLoader.exists(SETUP_PATH):
		push_warning("Party: no party setup at %s - starting with an empty party." % SETUP_PATH)
		return
	var setup := load(SETUP_PATH) as PartySetup
	if setup == null:
		push_warning("Party: %s is not a PartySetup." % SETUP_PATH)
		return
	apply_setup(setup)
	BattleData.register_loaded()


## Makes [param setup] the party. Each listed member is registered as a template and the
## running party gets a copy, so nothing that happens during play writes back into the
## resource.
func apply_setup(setup: PartySetup) -> void:
	for piece in setup.equipment:
		if piece != null:
			register_equipment(piece)

	for member in setup.active:
		if member != null:
			register_member(member)
			_register_gear_of(member)
			active.append(member.duplicate(true))
	for member in setup.reserve:
		if member != null:
			register_member(member)
			_register_gear_of(member)
			reserve.append(member.duplicate(true))

	gold = setup.gold
	for id in setup.items:
		items[id] = setup.items[id]
	for id in setup.owned_equipment:
		owned_equipment[id] = setup.owned_equipment[id]
	changed.emit()


## Gear a member arrives wearing must be in the catalogue too, or a saved game could not
## resolve its id.
func _register_gear_of(member: PartyMember) -> void:
	for slot: Variant in member.equipped:
		var piece: Equipment = member.equipped[slot]
		if piece != null:
			register_equipment(piece)


