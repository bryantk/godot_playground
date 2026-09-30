extends Node

## Headless assertions over [BattleData] and the Battle Data dock's list: authored
## resources round-trip through .tres files in res://data/<kind>/, load into the registry,
## reach the game's catalogues, and [method BattleData.validate] reports what is broken.
## Files are written under res://data/ with a "_test_" prefix and removed afterwards.
##
##     godot --headless --path . res://tests/battle_data_test.tscn

const PanelScript := preload("res://addons/battle_data/battle_data_panel.gd")

var _passed := 0
var _failed := 0
var _written: Array[String] = []


func _ready() -> void:
	print("")
	print("battle -- BattleData, the Battle Data dock")
	print("")

	_test_round_trip_and_registry()
	_test_validation()
	_test_dock_list()
	_test_default_abilities()
	_test_party_setup()

	for path in _written:
		DirAccess.remove_absolute(path)
	BattleData._registry.clear()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _save(kind: StringName, resource: Resource, file: String) -> String:
	DirAccess.make_dir_recursive_absolute(BattleData.folder(kind))
	var path := "%s/%s.tres" % [BattleData.folder(kind), file]
	ResourceSaver.save(resource, path)
	_written.append(path)
	return path


func _stats() -> Stats:
	var s := Stats.new()
	s.max_hp = 12
	return s


func _test_round_trip_and_registry() -> void:
	_section("authored resources save, load, register and reach the game's catalogues")

	var slash := Ability.new()
	slash.id = &"_test_slash"
	slash.display_name = "Slash"
	slash.power = 1.5
	_save(BattleData.ABILITIES, slash, "_test_slash")

	var poison := StatusEffect.new()
	poison.id = &"_test_poison"
	poison.flat = {"def": -2}
	_save(BattleData.EFFECTS, poison, "_test_poison")

	var wolf := EnemyDef.new()
	wolf.id = &"_test_wolf"
	wolf.display_name = "Test Wolf"
	wolf.base_stats = _stats()
	wolf.abilities = [slash]
	wolf.gold_reward = 7
	_save(BattleData.ENEMIES, wolf, "_test_wolf")

	var pack := Troop.new()
	pack.id = &"_test_pack"
	pack.enemies = [{"enemy": wolf, "count": 2}]
	_save(BattleData.TROOPS, pack, "_test_pack")

	var hero := PartyMember.new()
	hero.id = &"_test_hero"
	hero.display_name = "Test Hero"
	hero.base_stats = _stats()
	_save(BattleData.HEROES, hero, "_test_hero")

	var tonic := Item.new()
	tonic.id = &"_test_tonic"
	tonic.action = slash
	_save(BattleData.ITEMS, tonic, "_test_tonic")

	BattleData.apply_to_game()
	_ok(BattleData.find(BattleData.EFFECTS, &"_test_poison") != null, "an effect file registers")
	_eq((BattleData.find(BattleData.ENEMIES, &"_test_wolf") as EnemyDef).gold_reward, 7,
		"an enemy keeps its fields through the file")
	_ok(BattleTransfer.troop(&"_test_pack") != null, "the troop reaches BattleTransfer's catalogue")
	_eq(BattleTransfer.troop(&"_test_pack").enemies.size(), 1, "with its groups")
	_ok(Party.member_catalogue().any(func(m: PartyMember) -> bool: return m.id == &"_test_hero"),
		"the hero reaches Party's catalogue")
	_ok(BattleData.item(&"_test_tonic") != null, "the item is findable by id")
	_eq(BattleData.ability(&"_test_slash").display_name, "Slash", "and abilities by id")
	_eq(BattleData.validate().size(), 0, "well-formed data has no problems")


func _test_validation() -> void:
	_section("validate reports what is broken")
	var no_stats := PartyMember.new()
	no_stats.id = &"_test_bare"
	_save(BattleData.HEROES, no_stats, "_test_bare")

	var nameless := EnemyDef.new()
	nameless.base_stats = _stats()
	_save(BattleData.ENEMIES, nameless, "_test_nameless")

	var lost_ai := EnemyDef.new()
	lost_ai.id = &"_test_lost_ai"
	lost_ai.base_stats = _stats()
	lost_ai.ai_path = "res://data/_nowhere.event.json"
	_save(BattleData.ENEMIES, lost_ai, "_test_lost_ai")

	var empty_troop := Troop.new()
	empty_troop.id = &"_test_empty"
	_save(BattleData.TROOPS, empty_troop, "_test_empty")

	var dud := Item.new()
	dud.id = &"_test_dud"
	_save(BattleData.ITEMS, dud, "_test_dud")

	var twin := PartyMember.new()
	twin.id = &"_test_bare"
	twin.base_stats = _stats()
	_save(BattleData.HEROES, twin, "_test_twin")

	var text := "\n".join(BattleData.validate())
	_ok(text.contains("_test_bare.tres has no base stats"), "a hero with no stats")
	_ok(text.contains("_test_nameless.tres has no id"), "an entry with no id")
	_ok(text.contains("AI file that does not exist"), "an AI path that is not there")
	_ok(text.contains("_test_empty.tres has no enemies"), "a troop with no enemies")
	_ok(text.contains("_test_dud.tres has no action"), "an item that does nothing")
	_ok(text.contains("repeats id"), "two entries with one id")


func _test_default_abilities() -> void:
	_section("a new hero starts with Attack and Guard, a new enemy with Attack")
	var hero := PartyMember.new()
	var enemy := EnemyDef.new()
	_eq(hero.abilities.size(), 2, "a hero has two abilities")
	_eq(hero.abilities[0].id, &"attack", "the first is attack")
	_eq(hero.abilities[0].kind, Ability.Kind.ATTACK, "of kind ATTACK")
	_eq(hero.abilities[1].id, &"guard", "the second is guard")
	_eq(hero.abilities[1].kind, Ability.Kind.GUARD, "of kind GUARD")
	_eq(hero.abilities[1].target, Ability.Target.SELF, "which targets its user")
	_eq(enemy.abilities.size(), 1, "an enemy has one")
	_eq(enemy.abilities[0].id, &"attack", "and it is attack")
	_ok(hero.abilities[0] == enemy.abilities[0], "they are the same shared Attack resource")
	_ok(not hero.abilities[1].deals_damage(), "guard deals no damage")
	_eq(BattleData.singular(BattleData.HEROES), "hero", "a new hero's default id is new_hero, not new_heroe")


func _test_party_setup() -> void:
	_section("Party is populated from res://data/party.tres, as copies of its members")
	Party.load_setup()
	_eq(Party.active.size(), 2, "two members are in the party")
	_eq(Party.active[0].id, &"hero", "starting with the hero")
	_eq(Party.active[1].id, &"mage", "then the mage")
	_eq(Party.gold, 50, "with the gold the file says")
	_eq(Party.items.get(&"potion", 0), 3, "and the potions")
	_eq(Party.active[0].abilities.size(), 3, "the hero has attack, guard and fireball")

	Party.active[0].current_hp = 1
	var template := Party.member_catalogue().filter(
		func(m: PartyMember) -> bool: return m.id == &"hero")[0] as PartyMember
	_eq(template.current_hp, -1, "changing the running party leaves the resource untouched")
	_ok(Party.active[0] != template, "because the party holds a copy")

	var empty := PartySetup.new()
	var spare := PartyMember.new()
	spare.id = &"_test_spare"
	empty.reserve = [spare]
	empty.gold = 9
	Party.clear()
	Party.apply_setup(empty)
	_eq(Party.reserve.size(), 1, "a setup's reserve fills the reserve")
	_eq(Party.gold, 9, "and its gold replaces the old")
	Party.clear()
	_eq(Party.active.size(), 2, "clear() loads the file again")


func _test_dock_list() -> void:
	_section("the dock lists each kind's files and picks free ids")
	var panel: Control = PanelScript.new()
	add_child(panel)
	panel.refresh()
	var heroes: ItemList = panel._lists[BattleData.HEROES]
	var titles: Array[String] = []
	for i in heroes.item_count:
		titles.append(heroes.get_item_text(i))
	_ok(titles.any(func(t: String) -> bool: return t.contains("_test_hero")), "a hero file is listed by id")
	_eq(panel._free_id(BattleData.HEROES, "_test_hero"), "_test_hero_2", "a taken name gets _2")
	_eq(panel._free_id(BattleData.HEROES, "_test_brand_new"), "_test_brand_new", "a free one is kept")
	panel.queue_free()


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what if got == want else "%s (got %s, want %s)" % [what, str(got), str(want)])
