extends Node

## Headless assertions over [BattleSimulator] and the [BattleTransfer] hand-off fields
## the battle sandbox tool and [code]start_battle[/code]'s own [code]allow_defeat[/code]
## argument both drive - no scene needed, same reasoning tests/battle_test.gd's own doc
## gives.
##
##     godot --headless --path . res://tests/battle_simulator_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("battle -- BattleSimulator, and the allow_defeat hand-off")
	print("")

	_test_stomp_is_a_near_certain_win()
	_test_hopeless_fight_is_a_near_certain_loss()
	_test_simulation_never_touches_real_party_data()
	_test_allow_defeat_defaults_false()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_stomp_is_a_near_certain_win() -> void:
	_section("BattleSimulator.simulate -- an overwhelming party stomps a weak troop")

	var hero := PartyMember.new()
	hero.id = &"sim_hero"
	hero.base_stats = _stats(50, 0, 20, 5, 0, 20)
	var attack := Ability.new()
	attack.kind = Ability.Kind.ATTACK
	attack.target = Ability.Target.SINGLE_ENEMY
	attack.power = 1.0
	hero.abilities = [attack]

	var weak := EnemyDef.new()
	weak.id = &"sim_weakling"
	weak.stats = _stats(5, 0, 1, 0, 0, 1)
	weak.abilities = [attack]

	var troop := Troop.new()
	troop.enemies = [{"enemy": weak, "count": 1}]

	var result := BattleSimulator.simulate([hero], troop, 100)
	_eq(result["trials"], 100, "ran the requested number of trials")
	_ok(result["win_rate"] > 0.95, "win rate is near-certain (%.2f)" % result["win_rate"])
	_ok(result["avg_rounds"] < 5.0, "and it is over fast (%.1f rounds)" % result["avg_rounds"])


func _test_hopeless_fight_is_a_near_certain_loss() -> void:
	_section("BattleSimulator.simulate -- a hopeless party is a near-certain loss")

	var weak_hero := PartyMember.new()
	weak_hero.id = &"sim_weak_hero"
	weak_hero.base_stats = _stats(5, 0, 1, 0, 0, 1)
	var weak_attack := Ability.new()
	weak_attack.kind = Ability.Kind.ATTACK
	weak_attack.target = Ability.Target.SINGLE_ENEMY
	weak_attack.power = 1.0
	weak_hero.abilities = [weak_attack]

	var brute := EnemyDef.new()
	brute.id = &"sim_brute"
	brute.stats = _stats(60, 0, 20, 5, 0, 20)
	brute.abilities = [weak_attack]

	var troop := Troop.new()
	troop.enemies = [{"enemy": brute, "count": 1}]

	var result := BattleSimulator.simulate([weak_hero], troop, 100)
	_ok(result["win_rate"] < 0.05, "win rate is near-zero (%.2f)" % result["win_rate"])


func _test_simulation_never_touches_real_party_data() -> void:
	_section("BattleSimulator.simulate -- never mutates the PartyMember it borrows stats from")

	var hero := PartyMember.new()
	hero.id = &"sim_untouched"
	hero.base_stats = _stats(10, 0, 3, 0, 0, 5)
	var attack := Ability.new()
	attack.kind = Ability.Kind.ATTACK
	attack.target = Ability.Target.SINGLE_ENEMY
	attack.power = 1.0
	hero.abilities = [attack]

	var enemy := EnemyDef.new()
	enemy.stats = _stats(30, 0, 5, 0, 0, 10)
	enemy.abilities = [attack]
	var troop := Troop.new()
	troop.enemies = [{"enemy": enemy, "count": 1}]

	BattleSimulator.simulate([hero], troop, 30)
	_eq(hero.current_hp, -1, "current_hp is untouched (-1, never fought) after simulating")


func _test_allow_defeat_defaults_false() -> void:
	_section("BattleTransfer.allow_defeat -- defaults false, so a defeat means game over")
	_ok(not BattleTransfer.allow_defeat, "false unless a start_battle node explicitly opts in")


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
