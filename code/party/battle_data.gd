class_name BattleData

## Every authored piece of battle data, by kind, and where it lives. The Battle Data editor
## dock (addons/battle_data) lists and edits these; at run time [method apply_to_game]
## hands them to the catalogues the game already reads ([Party], [BattleTransfer]).
##
## One folder per kind under [constant ROOT], one [code].tres[/code] per entry, identified by
## its [code]id[/code] (not its filename, which only has to be unique).
##
## [codeblock]
## res://data/heroes/     PartyMember    who can be in the party
## res://data/enemies/    EnemyDef       what a troop is made of
## res://data/troops/     Troop          one fight's worth of enemies
## res://data/items/      Item           consumables
## res://data/abilities/  Ability   what anyone can do on a turn
## res://data/effects/    StatusEffect   buffs and debuffs
## res://data/equipment/  Equipment      gear a member can wear
## res://data/party.tres  PartySetup     the starting party (see Party.SETUP_PATH)
## [/codeblock]

const ROOT := "res://data"

const HEROES := &"heroes"
const ENEMIES := &"enemies"
const TROOPS := &"troops"
const ITEMS := &"items"
const ABILITIES := &"abilities"
const EFFECTS := &"effects"
const EQUIPMENT := &"equipment"

const KINDS: Array[StringName] = [HEROES, ENEMIES, TROOPS, ITEMS, ABILITIES, EFFECTS, EQUIPMENT]

## kind -> {id -> Resource}. Filled by [method load_all] and by anything registered in
## code (the demo data), so a lookup does not care which a resource came from.
static var _registry: Dictionary = {}


## The class each kind's resources must be.
static func script_for(kind: StringName) -> Script:
	match kind:
		HEROES: return PartyMember
		ENEMIES: return EnemyDef
		TROOPS: return Troop
		ITEMS: return Item
		ABILITIES: return Ability
		EFFECTS: return StatusEffect
		EQUIPMENT: return Equipment
	return null


## The singular of a kind's name, for a new entry's default id ("new_hero", not "new_heroe").
static func singular(kind: StringName) -> String:
	match kind:
		HEROES: return "hero"
		ENEMIES: return "enemy"
		TROOPS: return "troop"
		ITEMS: return "item"
		ABILITIES: return "ability"
		EFFECTS: return "effect"
		EQUIPMENT: return "equipment"
	return str(kind)


static func folder(kind: StringName) -> String:
	return "%s/%s" % [ROOT, kind]


static func register(kind: StringName, resource: Resource) -> void:
	if resource == null or str(resource.get("id")) == "":
		return
	if not _registry.has(kind):
		_registry[kind] = {}
	(_registry[kind] as Dictionary)[StringName(str(resource.get("id")))] = resource


static func find(kind: StringName, id: StringName) -> Resource:
	return (_registry.get(kind, {}) as Dictionary).get(id)


static func all(kind: StringName) -> Array[Resource]:
	var out: Array[Resource] = []
	for id: Variant in (_registry.get(kind, {}) as Dictionary):
		out.append(_registry[kind][id])
	return out


static func effect(id: StringName) -> StatusEffect:
	return find(EFFECTS, id) as StatusEffect


static func ability(id: StringName) -> Ability:
	return find(ABILITIES, id) as Ability


static func item(id: StringName) -> Item:
	return find(ITEMS, id) as Item


## Every [code].tres[/code] under [param kind]'s folder, sorted by filename - what the
## editor dock lists, whether or not it has been registered (a file with a blank id still
## needs to show up to be fixed).
static func files(kind: StringName) -> PackedStringArray:
	var out := PackedStringArray()
	var dir := DirAccess.open(folder(kind))
	if dir == null:
		return out
	dir.list_dir_begin()
	var entry_name := dir.get_next()
	while entry_name != "":
		if not dir.current_is_dir() and (entry_name.ends_with(".tres") or entry_name.ends_with(".res")):
			out.append("%s/%s" % [folder(kind), entry_name])
		entry_name = dir.get_next()
	dir.list_dir_end()
	out.sort()
	return out


## Loads every file of every kind into the registry. Files of the wrong class for their
## folder are skipped with a warning rather than registered.
static func load_all() -> void:
	for kind in KINDS:
		var expected := script_for(kind)
		for path in files(kind):
			var loaded := load(path) as Resource
			if loaded == null or loaded.get_script() != expected:
				push_warning("BattleData: %s is not a %s - skipped." % [path, kind])
				continue
			register(kind, loaded)


## Hands everything already in the registry to the catalogues the rest of the game reads.
## [method apply_to_game] does this after loading from disk; [method Party.load_setup] does
## it again after rebuilding the party, so a new game keeps the authored gear and heroes.
static func register_loaded() -> void:
	for hero in all(HEROES):
		Party.register_member(hero as PartyMember)
	for enemy in all(ENEMIES):
		BattleTransfer.register_enemy(enemy as EnemyDef)
	for troop in all(TROOPS):
		BattleTransfer.register_troop(troop as Troop)
	for gear in all(EQUIPMENT):
		Party.register_equipment(gear as Equipment)
	for piece in all(ITEMS):
		Party.register_item(piece as Item)


## Loads every file from disk and hands it to the game's catalogues - what the game does
## once at start-up.
static func apply_to_game() -> void:
	load_all()
	register_loaded()


## What is wrong with the data as authored: a hero or enemy with no stats, an ability list
## holding nothing, a troop with no enemies, an item with no action, an AI file that is not
## there, two entries sharing an id. One line each, for the editor dock to show.
static func validate() -> Array[String]:
	var problems: Array[String] = []

	for kind in KINDS:
		var seen := {}
		for path in files(kind):
			var entry := load(path) as Resource
			if entry == null:
				problems.append("%s could not be loaded." % path)
				continue
			if entry.get_script() != script_for(kind):
				problems.append("%s is not a %s." % [path, kind])
				continue
			var id := str(entry.get("id"))
			if id == "":
				problems.append("%s has no id." % path)
			elif seen.has(id):
				problems.append("%s repeats id \"%s\" (also %s)." % [path, id, seen[id]])
			seen[id] = path

			match kind:
				HEROES, ENEMIES:
					var who := entry as Combatant
					if who.base_stats == null:
						problems.append("%s has no base stats." % path)
					for ability in who.abilities:
						if ability == null:
							problems.append("%s lists an empty ability slot." % path)
							break
					if kind == ENEMIES:
						var ai_path := (entry as EnemyDef).ai_path
						if ai_path != "" and not FileAccess.file_exists(ai_path):
							problems.append("%s names an AI file that does not exist: %s." % [path, ai_path])
				TROOPS:
					var troop := entry as Troop
					if troop.enemies.is_empty():
						problems.append("%s has no enemies." % path)
					for group: Dictionary in troop.enemies:
						if group.get("enemy") == null:
							problems.append("%s has a group with no enemy." % path)
				ITEMS:
					if (entry as Item).action == null:
						problems.append("%s has no action, so using it does nothing." % path)
	return problems
