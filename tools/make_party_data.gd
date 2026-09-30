extends Node

## Writes the starter party as resources under res://data/: the Hero and Mage, their
## Fireball, the two pieces of gear, a Potion, and the [PartySetup] that puts them together
## (res://data/party.tres). Run rather than hand-authored, so Godot writes the typed arrays
## and dictionaries exactly as it reads them back:
##
##     godot --headless --path . res://tools/make_party_data.tscn
##
## Only needed to regenerate the defaults - once the files exist, edit them in the
## inspector (or the Battle Data dock) instead. Re-running overwrites them.


func _ready() -> void:
	var fireball := Ability.new()
	fireball.id = &"fireball"
	fireball.display_name = "Fireball"
	fireball.kind = Ability.Kind.SKILL
	fireball.target = Ability.Target.SINGLE_ENEMY
	fireball.power = 1.4
	fireball.uses_magic = true
	fireball.element = &"fire"
	fireball.mp_cost = 4
	_save(fireball, BattleData.ABILITIES, "fireball")

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

	var potion_action := Ability.new()
	potion_action.id = &"potion"
	potion_action.display_name = "Potion"
	potion_action.kind = Ability.Kind.ITEM
	potion_action.target = Ability.Target.SINGLE_ALLY
	potion_action.power = 15.0
	potion_action.item_id = &"potion"
	var potion := Item.new()
	potion.id = &"potion"
	potion.display_name = "Potion"
	potion.description = "Restores 15 HP."
	potion.price = 10
	potion.action = potion_action
	_save(potion, BattleData.ITEMS, "potion")

	var hero := PartyMember.new()
	hero.id = &"hero"
	hero.display_name = "Hero"
	hero.base_stats = _stats(28, 8, 7, 5, 4, 6)
	hero.abilities = [Ability.attack(), Ability.guard(), fireball]
	_save(hero, BattleData.HEROES, "hero")

	var mage := PartyMember.new()
	mage.id = &"mage"
	mage.display_name = "Mage"
	mage.base_stats = _stats(18, 16, 3, 3, 8, 5)
	mage.abilities = [Ability.attack(), Ability.guard(), fireball]
	_save(mage, BattleData.HEROES, "mage")

	var setup := PartySetup.new()
	setup.active = [hero, mage]
	setup.gold = 50
	setup.items = {&"potion": 3}
	var err := ResourceSaver.save(setup, Party.SETUP_PATH)
	print("party setup -> %s (%s)" % [Party.SETUP_PATH, error_string(err)])
	get_tree().quit(0 if err == OK else 1)


func _save(resource: Resource, kind: StringName, file: String) -> void:
	DirAccess.make_dir_recursive_absolute(BattleData.folder(kind))
	var path := "%s/%s.tres" % [BattleData.folder(kind), file]
	var err := ResourceSaver.save(resource, path)
	print("%s (%s)" % [path, error_string(err)])
	# Reloaded from disk so what is referenced next is the saved file, not this copy.
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
