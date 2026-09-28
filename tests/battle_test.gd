extends Node

## Headless assertions over the party/battle data layer: [Stats], [PartyMember],
## [Equipment], [BattleFormula], [Battler] and [BattleState] - no scene needed, since
## none of this reaches into the tree (battle/battle_scene.gd is the one piece that
## does, and is exercised by hand rather than headlessly, the same as every other
## Control-based screen in this project).
##
##     godot --headless --path . res://tests/battle_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("battle -- BattleFormula, Battler, BattleState, and the Party autoload")
	print("")

	_test_formula()
	_test_battle_state_round()
	_test_hp_persists_across_fights()
	_test_equip_unequip()
	_test_party_save_round_trip()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- BattleFormula ---------------------------------------------------------------------

func _test_formula() -> void:
	_section("BattleFormula.damage -- element multipliers")

	var attacker := _stats(0, 0, 10, 0, 0, 0)
	var defender := _stats(0, 0, 0, 4, 0, 0)
	var action := BattleAction.new()
	action.power = 1.0

	_eq(BattleFormula.damage(attacker, defender, action), 6, "atk - def, no element involved")

	defender.elements = {&"fire": 2.0}
	action.element = &"fire"
	_eq(BattleFormula.damage(attacker, defender, action), 12, "weak to fire doubles it")

	defender.elements = {&"fire": 0.5}
	_eq(BattleFormula.damage(attacker, defender, action), 3, "resist halves it")

	defender.elements = {&"fire": 0.0}
	_eq(BattleFormula.damage(attacker, defender, action), 0, "immune is zero, not clamped to 1")

	defender.elements = {&"fire": -1.0}
	_ok(BattleFormula.damage(attacker, defender, action) < 0, "absorbing reads as negative (heals)")

	var weak_hit := BattleAction.new()
	weak_hit.power = 0.1
	defender.elements = {}
	_eq(BattleFormula.damage(attacker, defender, weak_hit), 1, "a hit that rounds to <=0 still lands for 1")


# -- BattleState -------------------------------------------------------------------------

func _test_battle_state_round() -> void:
	_section("BattleState.resolve_turn -- one player command plus enemy AI, in speed order")

	var hero := PartyMember.new()
	hero.id = &"test_hero"
	hero.display_name = "Hero"
	hero.base_stats = _stats(20, 0, 10, 2, 0, 20)
	var attack := BattleAction.new()
	attack.display_name = "Attack"
	attack.target = BattleAction.Target.SINGLE_ENEMY
	attack.power = 1.0
	hero.actions = [attack]

	var slime := EnemyDef.new()
	slime.id = &"test_slime"
	slime.display_name = "Slime"
	slime.stats = _stats(8, 0, 1, 0, 0, 1)
	var struggle := BattleAction.new()
	struggle.display_name = "Struggle"
	struggle.target = BattleAction.Target.SINGLE_ENEMY
	struggle.power = 0.5
	slime.actions = [struggle]

	var troop := Troop.new()
	troop.id = &"test_troop"
	troop.enemies = [{"enemy": slime, "count": 1}]

	var state := BattleState.new()
	state.begin([hero], troop)
	_eq(state.player_side.size(), 1, "one player battler")
	_eq(state.enemy_side.size(), 1, "one enemy battler")

	var enemy := state.enemy_side[0]
	var command := {"battler": state.player_side[0], "action": attack, "target": enemy}
	var log := state.resolve_turn([command])

	_ok(not log.is_empty(), "resolving a round produces log lines")
	_ok(enemy.hp < enemy.stats.max_hp, "the enemy took damage (hero is faster, acts first)")
	_ok(not state.is_defeat(), "the hero survived a 1-power struggle")

	# Faster than the enemy (spd 20 vs 1) and hits for far more than the enemy's own
	# 8 max hp - two rounds is enough to finish it off before the enemy lands a third hit.
	var rounds := 0
	while not state.is_over() and rounds < 5:
		state.resolve_turn([{"battler": state.player_side[0], "action": attack, "target": state.alive_enemies()[0]}])
		rounds += 1
	_ok(state.is_victory(), "the slime is defeated within a few rounds")
	_eq(state.gold_reward(), slime.gold_reward, "gold_reward sums the defeated enemy's own reward")


# -- HP carries between fights -----------------------------------------------------------

func _test_hp_persists_across_fights() -> void:
	_section("Battler.sync_to_member -- damage carries into the next fight")

	var hero := PartyMember.new()
	hero.id = &"persist_hero"
	hero.base_stats = _stats(30, 0, 5, 0, 0, 5)

	var b1 := Battler.for_member(hero)
	_eq(b1.hp, 30, "a fresh member starts at full hp (current_hp == -1)")
	b1.apply_damage(10)
	b1.sync_to_member()
	_eq(hero.current_hp, 20, "sync_to_member writes the damage back onto the PartyMember")

	var b2 := Battler.for_member(hero)
	_eq(b2.hp, 20, "the next Battler built from the same member starts wounded")


# -- Equip/unequip through Party ----------------------------------------------------------

func _test_equip_unequip() -> void:
	_section("Party.equip_from_inventory / unequip_to_inventory")
	Party.clear()

	var hero: PartyMember = Party.active[0]
	var starting_atk := hero.effective_stats().atk

	Party.owned_equipment[&"rusty_sword"] = 1
	_ok(Party.equip_from_inventory(hero, &"rusty_sword"), "equips from inventory")
	_ok(hero.effective_stats().atk > starting_atk, "the bonus is reflected in effective_stats()")
	_eq(int(Party.owned_equipment.get(&"rusty_sword", 0)), 0, "inventory count dropped to zero")

	Party.unequip_to_inventory(hero, Equipment.Slot.WEAPON)
	_eq(hero.effective_stats().atk, starting_atk, "unequipping restores the base stat")
	_eq(int(Party.owned_equipment.get(&"rusty_sword", 0)), 1, "and the sword is back in inventory")


# -- Party save/load, through real JSON --------------------------------------------------

func _test_party_save_round_trip() -> void:
	_section("Party.to_save/from_save -- survives real JSON encoding, not just Godot's own types")
	Party.clear()
	Party.gold = 77
	Party.items = {}
	Party.add_item(&"potion", 2)
	Party.owned_equipment[&"cloth_robe"] = 1
	Party.active[0].equip(Party.equipment_catalogue().filter(
		func(e: Equipment) -> bool: return e.id == &"rusty_sword")[0])
	Party.active[0].current_hp = 5

	var encoded := JSON.stringify(Party.to_save())
	var decoded: Dictionary = JSON.parse_string(encoded)

	Party.clear()
	Party.from_save(decoded)

	_eq(Party.gold, 77, "gold survives")
	_eq(int(Party.items.get(&"potion", 0)), 2, "item counts survive, keyed by StringName again")
	_eq(int(Party.owned_equipment.get(&"cloth_robe", 0)), 1, "owned equipment survives")
	_ok(not Party.active.is_empty(), "the active roster survives")
	if not Party.active.is_empty():
		_eq(Party.active[0].current_hp, 5, "a member's current_hp survives")
		var weapon: Equipment = Party.active[0].equipped.get(Equipment.Slot.WEAPON)
		_ok(weapon != null and weapon.id == &"rusty_sword", "and its equipped weapon resolves back to a real Equipment")

	Party.clear()


# -- Helpers ------------------------------------------------------------------------------

func _stats(hp: int, mp: int, atk: int, def: int, mag: int, spd: int) -> Stats:
	var s := Stats.new()
	s.max_hp = hp
	s.max_mp = mp
	s.atk = atk
	s.def = def
	s.mag = mag
	s.spd = spd
	return s


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, "%s (got %s, want %s)" % [what, got, want] if got != want else what)
