extends Node

## Writes the example game data under res://data/ (and the two example AI graphs under
## res://events/ai/): status effects, abilities, items, equipment, three heroes, four
## enemies, four troops, and the [PartySetup] that starts the party (res://data/party.tres).
## Run rather than hand-authored, so Godot writes the typed arrays and dictionaries exactly
## as it reads them back:
##
##     godot --headless --path . res://tools/make_party_data.tscn
##
## Only needed to regenerate the examples - once the files exist, edit them in the Battle
## Data dock and the inspector instead. Re-running overwrites them.

var _effects := {}
var _abilities := {}


func _ready() -> void:
	_make_effects()
	_make_abilities()
	var items := _make_items_and_gear()
	var heroes := _make_heroes()
	var enemies := _make_enemies(items)
	_make_troops(enemies)
	_make_ai_graphs()

	var setup := PartySetup.new()
	setup.active = [heroes["hero"], heroes["mage"], heroes["cleric"]]
	setup.gold = 50
	setup.items = {&"potion": 3, &"antidote": 1}
	var err := ResourceSaver.save(setup, Party.SETUP_PATH)
	print("party setup -> %s (%s)" % [Party.SETUP_PATH, error_string(err)])
	get_tree().quit(0 if err == OK else 1)


# -- Status effects ------------------------------------------------------------------

func _make_effects() -> void:
	_effect(&"haste", "Haste", {}, {"spd": 50}, 3)
	_effect(&"rage", "Rage", {}, {"atk": 50}, 3)
	_effect(&"regen", "Regen", {}, {}, 4, true, 4)
	_effect(&"sunder", "Sundered", {}, {"def": -50}, 3, false)
	_effect(&"slow", "Slow", {}, {"spd": -40}, 3, false)
	_effect(&"poison", "Poison", {}, {}, 4, false, -3)
	# A field effect: counts steps walked, not battle rounds.
	var fortify := _effect(&"fortify", "Fortified", {"def": 4}, {}, 40)
	fortify.unit = StatusEffect.Unit.STEPS
	_save(fortify, BattleData.EFFECTS, "fortify")


func _effect(id: StringName, label: String, flat: Dictionary, percent: Dictionary,
		duration: int, beneficial: bool = true, hp_per_round: int = 0) -> StatusEffect:
	var effect := StatusEffect.new()
	effect.id = id
	effect.display_name = label
	effect.flat = flat
	effect.percent = percent
	effect.duration = duration
	effect.beneficial = beneficial
	effect.hp_per_round = hp_per_round
	_save(effect, BattleData.EFFECTS, str(id))
	_effects[id] = effect
	return effect


# -- Abilities -----------------------------------------------------------------------

func _make_abilities() -> void:
	var fireball := _ability(&"fireball", "Fireball", Ability.Target.SINGLE_ENEMY, 1.4, 4)
	fireball.uses_magic = true
	fireball.element = &"fire"
	_save(fireball, BattleData.ABILITIES, "fireball")

	var heal := _ability(&"heal", "Heal", Ability.Target.SINGLE_ALLY, 0.0, 3)
	heal.heal_amount = 10
	heal.heal_mag_scale = 1.5
	_save(heal, BattleData.ABILITIES, "heal")

	var cure := _ability(&"cure", "Cure", Ability.Target.SINGLE_ALLY, 0.0, 2)
	cure.dispel = Ability.Dispel.DEBUFFS
	_save(cure, BattleData.ABILITIES, "cure")

	_ability(&"haste_spell", "Haste", Ability.Target.SINGLE_ALLY, 0.0, 3, [&"haste"])
	_ability(&"regen_spell", "Regen", Ability.Target.SINGLE_ALLY, 0.0, 4, [&"regen"])
	_ability(&"rally", "Rally", Ability.Target.ALL_ALLIES, 0.0, 5, [&"rage"])
	_ability(&"slow_spell", "Slow", Ability.Target.SINGLE_ENEMY, 0.0, 2, [&"slow"])
	_ability(&"sunder_strike", "Sunder", Ability.Target.SINGLE_ENEMY, 0.8, 2, [&"sunder"], 0.9)
	_ability(&"poison_bite", "Poison Bite", Ability.Target.SINGLE_ENEMY, 0.7, 0, [&"poison"], 0.8)
	_ability(&"howl", "Howl", Ability.Target.SELF, 0.0, 0, [&"rage"])
	_ability(&"tackle", "Tackle", Ability.Target.SINGLE_ENEMY, 0.8, 0)


func _ability(id: StringName, label: String, target: Ability.Target, power: float, mp: int,
		effect_ids: Array = [], chance: float = 1.0) -> Ability:
	var ability := Ability.new()
	ability.id = id
	ability.display_name = label
	ability.kind = Ability.Kind.SKILL if mp > 0 or not effect_ids.is_empty() else Ability.Kind.ATTACK
	ability.target = target
	ability.power = power
	ability.mp_cost = mp
	var applied: Array[StatusEffect] = []
	for effect_id in effect_ids:
		applied.append(_effects[effect_id])
	ability.effects = applied
	ability.effect_chance = chance
	_save(ability, BattleData.ABILITIES, str(id))
	_abilities[id] = ability
	return ability


# -- Items and gear ------------------------------------------------------------------

func _make_items_and_gear() -> Dictionary:
	var sword := Equipment.new()
	sword.id = &"rusty_sword"
	sword.display_name = "Rusty Sword"
	sword.slot = Equipment.Slot.WEAPON
	sword.bonus = _stats(0, 0, 3, 0, 0, 0)
	sword.price = 20
	_save(sword, BattleData.EQUIPMENT, "rusty_sword")

	var robe := Equipment.new()
	robe.id = &"cloth_robe"
	robe.display_name = "Cloth Robe"
	robe.slot = Equipment.Slot.ARMOR
	robe.bonus = _stats(0, 0, 0, 2, 1, 0)
	robe.price = 15
	_save(robe, BattleData.EQUIPMENT, "cloth_robe")

	var items := {}
	items["potion"] = _item(&"potion", "Potion", "Restores 15 HP.", 10, 15.0)
	items["antidote"] = _item(&"antidote", "Antidote", "Clears poison and other ailments.", 8,
		0.0, [], Ability.Dispel.DEBUFFS)
	items["fortify_tonic"] = _item(&"fortify_tonic", "Fortify Tonic",
		"+4 defence for 40 steps (or the rest of a fight).", 25, 0.0, [&"fortify"])
	return items


func _item(id: StringName, label: String, text: String, price: int, power: float,
		effect_ids: Array = [], dispel: int = Ability.Dispel.NONE) -> Item:
	var action := Ability.new()
	action.id = id
	action.display_name = label
	action.kind = Ability.Kind.ITEM
	action.target = Ability.Target.SINGLE_ALLY
	action.power = power
	action.item_id = id
	action.dispel = dispel
	var applied: Array[StatusEffect] = []
	for effect_id in effect_ids:
		applied.append(_effects[effect_id])
	action.effects = applied

	var item := Item.new()
	item.id = id
	item.display_name = label
	item.description = text
	item.price = price
	item.action = action
	_save(item, BattleData.ITEMS, str(id))
	return item


# -- Heroes --------------------------------------------------------------------------

func _make_heroes() -> Dictionary:
	var heroes := {}
	heroes["hero"] = _hero(&"hero", "Hero", _stats(28, 8, 7, 5, 4, 6),
		[&"sunder_strike"], {"max_hp": 6, "max_mp": 1, "atk": 2, "def": 1, "spd": 1},
		{3: &"rally"})
	heroes["mage"] = _hero(&"mage", "Mage", _stats(18, 16, 3, 3, 8, 5),
		[&"fireball", &"slow_spell"], {"max_hp": 3, "max_mp": 3, "mag": 2, "def": 1},
		{3: &"haste_spell"})
	heroes["cleric"] = _hero(&"cleric", "Cleric", _stats(22, 14, 4, 4, 6, 5),
		[&"heal", &"cure"], {"max_hp": 4, "max_mp": 2, "mag": 2, "def": 1},
		{2: &"regen_spell"})
	return heroes


func _hero(id: StringName, label: String, stats: Stats, ability_ids: Array, growth: Dictionary,
		learns: Dictionary) -> PartyMember:
	var hero := PartyMember.new()
	hero.id = id
	hero.display_name = label
	hero.base_stats = stats
	var list: Array[Ability] = [Ability.attack(), Ability.guard()]
	for ability_id in ability_ids:
		list.append(_abilities[ability_id])
	hero.abilities = list
	hero.growth = growth
	var learnset: Dictionary[int, Ability] = {}
	for gained: int in learns:
		learnset[gained] = _abilities[learns[gained]]
	hero.learnset = learnset
	_save(hero, BattleData.HEROES, str(id))
	return hero


# -- Enemies and troops --------------------------------------------------------------

func _make_enemies(items: Dictionary) -> Dictionary:
	var enemies := {}

	var slime := _enemy(&"slime", "Slime", _stats(10, 0, 3, 2, 1, 3), [&"tackle"], 8, 5)
	slime.base_stats.elements = {&"fire": 2.0}
	slime.drops = [_drop(items["potion"], 0.3)]
	_save(slime, BattleData.ENEMIES, "slime")
	enemies["slime"] = slime

	var awakened := _enemy(&"slime_awakened", "Awakened Slime", _stats(22, 0, 5, 3, 2, 4),
		[&"tackle"], 20, 14)
	awakened.base_stats.elements = {&"fire": 2.0}
	awakened.drops = [_drop(items["potion"], 0.5)]
	_save(awakened, BattleData.ENEMIES, "slime_awakened")
	enemies["slime_awakened"] = awakened

	var wolf := _enemy(&"wolf", "Wolf", _stats(24, 6, 6, 2, 2, 7),
		[&"poison_bite", &"howl"], 12, 10)
	wolf.ai_path = "res://events/ai/wolf.event.json"
	_save(wolf, BattleData.ENEMIES, "wolf")
	enemies["wolf"] = wolf

	var bandit := _enemy(&"bandit", "Bandit", _stats(30, 0, 7, 4, 2, 5), [&"sunder_strike"], 25, 16)
	bandit.ai_path = "res://events/ai/bandit.event.json"
	bandit.drops = [_drop(items["antidote"], 0.25)]
	_save(bandit, BattleData.ENEMIES, "bandit")
	enemies["bandit"] = bandit
	return enemies


func _enemy(id: StringName, label: String, stats: Stats, ability_ids: Array, gold: int,
		xp: int) -> EnemyDef:
	var enemy := EnemyDef.new()
	enemy.id = id
	enemy.display_name = label
	enemy.base_stats = stats
	var list: Array[Ability] = [Ability.attack()]
	for ability_id in ability_ids:
		list.append(_abilities[ability_id])
	# The slime's own "tackle" replaces the generic attack rather than sitting beside it.
	if ability_ids.has(&"tackle"):
		list.remove_at(0)
	enemy.abilities = list
	enemy.gold_reward = gold
	enemy.xp_reward = xp
	return enemy


func _drop(item: Item, chance: float) -> DropEntry:
	var drop := DropEntry.new()
	drop.item = item
	drop.chance = chance
	return drop


func _make_troops(enemies: Dictionary) -> void:
	_troop(&"slime_pair", [[enemies["slime"], 2]])
	_troop(&"slime_awakened", [[enemies["slime_awakened"], 1]])
	_troop(&"wolf_pack", [[enemies["wolf"], 1], [enemies["slime"], 1]])
	_troop(&"bandit_gang", [[enemies["bandit"], 1], [enemies["wolf"], 1]])


func _troop(id: StringName, groups: Array) -> void:
	var troop := Troop.new()
	troop.id = id
	var list: Array[Dictionary] = []
	for group in groups:
		list.append({"enemy": group[0], "count": group[1]})
	troop.enemies = list
	_save(troop, BattleData.TROOPS, str(id))


# -- Enemy AI graphs -----------------------------------------------------------------

func _make_ai_graphs() -> void:
	# Wolf: opens with a poison bite on anyone; later howls when badly hurt; otherwise goes
	# for whoever has the least hp.
	_graph("wolf", [
		_node("s", "start", {}, {"next": "r1"}, 0, 0),
		_node("r1", "if_round", {"op": "==", "value": 1}, {"true": "pick_any", "false": "hurt"}, 1, 0),
		_node("pick_any", "choose_target", {"rule": "random"}, {"next": "bite"}, 2, -1),
		_node("bite", "use_ability", {"ability": "poison_bite"}, {}, 3, -1),
		_node("hurt", "if_stat", {"who": "self", "stat": "hp", "op": "<", "value": 35, "percent": true},
			{"true": "howl", "false": "pick_low"}, 2, 1),
		_node("howl", "use_ability", {"ability": "howl"}, {}, 3, 0),
		_node("pick_low", "choose_target", {"rule": "lowest_hp"}, {"next": "hit"}, 3, 2),
		_node("hit", "use_ability", {"ability": "attack"}, {}, 4, 2),
	])
	# Bandit: sunders the sturdiest hero first, then hits them once their defence is down.
	_graph("bandit", [
		_node("s", "start", {}, {"next": "pick"}, 0, 0),
		_node("pick", "choose_target", {"rule": "highest_def"}, {"next": "check"}, 1, 0),
		_node("check", "if_status", {"who": "target", "status": "sunder"},
			{"true": "hit", "false": "sunder"}, 2, 0),
		_node("hit", "use_ability", {"ability": "attack"}, {}, 3, -1),
		_node("sunder", "use_ability", {"ability": "sunder_strike"}, {}, 3, 1),
	])


func _node(id: String, command: String, args: Dictionary, wires: Dictionary, col: int,
		row: int) -> Dictionary:
	var outputs: Array = []
	for flow in EventCommand.flows_of({"command": command, "args": args}):
		outputs.append({"flow": flow, "target": wires.get(flow, "")})
	return {"id": id, "title": command, "position": {"x": col * 300, "y": row * 180},
		"command": command, "args": args, "outputs": outputs}


func _graph(file_id: String, nodes: Array) -> void:
	var raw := {"format": 1, "id": file_id, "pages": [{"graph": nodes}]}
	var parsed := EventDocument.parse(JSON.stringify(raw))
	var path := "res://events/ai/%s.event.json" % file_id
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(EventDocument.stringify(parsed))
	file.close()
	print("%s (%d problem(s))" % [path, (parsed.get("problems", []) as Array).size()])


# -- Helpers -------------------------------------------------------------------------

func _save(resource: Resource, kind: StringName, file: String) -> void:
	DirAccess.make_dir_recursive_absolute(BattleData.folder(kind))
	var path := "%s/%s.tres" % [BattleData.folder(kind), file]
	var err := ResourceSaver.save(resource, path)
	print("%s (%s)" % [path, error_string(err)])
	# So anything that references this next saves a link to the file, not a copy.
	resource.take_over_path(path)


func _stats(hp: int, mp: int, atk: int, def: int, mag: int, spd: int) -> Stats:
	var s := Stats.new()
	s.max_hp = hp
	s.max_mp = mp
	s.atk = atk
	s.def = def
	s.mag = mag
	s.spd = spd
	return s
