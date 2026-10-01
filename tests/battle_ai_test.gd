extends Node

## Headless assertions over enemy AI graphs ([BattleAI] and events/commands/ai_execs.gd):
## a graph decides an enemy's turn from the round number, stats, statuses and counts, picks
## targets by rule, and an enemy without (or with a silent) graph falls back to random.
##
##     godot --headless --path . res://tests/battle_ai_test.tscn

const AI_PATH := "user://battle_ai_test.event.json"

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("battle -- enemy AI graphs")
	print("")

	_test_round_and_target_rules()
	_test_stat_branch_and_fallbacks()
	_test_dry_run()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _stats(hp: int, atk: int, spd: int) -> Stats:
	var s := Stats.new()
	s.max_hp = hp
	s.max_mp = 10
	s.atk = atk
	s.def = 0
	s.mag = 0
	s.spd = spd
	return s


func _action(id: StringName, target: Ability.Target = Ability.Target.SINGLE_ENEMY) -> Ability:
	var a := Ability.new()
	a.id = id
	a.display_name = str(id).capitalize()
	a.target = target
	a.power = 1.0
	return a


func _node(id: String, command: String, args: Dictionary, outputs: Array) -> Dictionary:
	return {"id": id, "command": command, "args": args, "outputs": outputs}


## Writes [param nodes] as a one-page document and returns its path.
func _write_graph(nodes: Array) -> String:
	var doc := {"format": 1, "id": "ai", "pages": [{"graph": nodes}]}
	var f := FileAccess.open(AI_PATH, FileAccess.WRITE)
	f.store_string(JSON.stringify(doc))
	f.close()
	BattleAI.clear_cache()
	return AI_PATH


func _fight(graph_nodes: Array, hero_hps: Array, hero_max: Array = []) -> Dictionary:
	var bite := _action(&"bite")
	var roar := _action(&"roar", Ability.Target.SELF)
	var foe := EnemyDef.new()
	foe.id = &"wolf"
	foe.display_name = "Wolf"
	foe.stats = _stats(40, 5, 5)
	foe.abilities = [bite, roar]
	foe.ai_path = _write_graph(graph_nodes) if not graph_nodes.is_empty() else ""
	var troop := Troop.new()
	troop.enemies = [{"enemy": foe, "count": 1}]

	var members: Array[PartyMember] = []
	for i in hero_hps.size():
		var hero := PartyMember.new()
		hero.id = StringName("hero%d" % i)
		hero.display_name = "Hero%d" % i
		hero.base_stats = _stats(int(hero_max[i]) if not hero_max.is_empty() else int(hero_hps[i]), 1, 1)
		hero.current_hp = int(hero_hps[i])
		members.append(hero)

	var state := BattleState.new()
	state.begin(members, troop)
	return {"state": state, "wolf": state.enemy_side[0], "bite": bite, "roar": roar}


func _test_round_and_target_rules() -> void:
	_section("AI graph -- lowest_hp target, and a round branch picks the ability")
	# round >= 2 ? roar (buff-like self move) : attack the weakest hero with bite.
	var nodes := [
		_node("s", "start", {}, [{"flow": "next", "target": "r"}]),
		_node("r", "if_round", {"op": ">=", "value": 2},
			[{"flow": "true", "target": "roar"}, {"flow": "false", "target": "pick"}]),
		_node("pick", "choose_target", {"rule": "lowest_hp"},
			[{"flow": "next", "target": "bite"}]),
		_node("bite", "use_ability", {"ability": "bite"}, []),
		_node("roar", "use_ability", {"ability": "roar"}, []),
	]
	var fight := _fight(nodes, [30, 8, 20])
	var state: BattleState = fight["state"]
	var wolf: Battler = fight["wolf"]

	state.round_number = 1
	var first := BattleAI.decide(state, wolf)
	_eq((first["action"] as Ability).id, &"bite", "round 1 bites")
	_eq((first["target"] as Battler).display_name, "Hero1", "the lowest-hp hero is the target")

	state.round_number = 2
	var second := BattleAI.decide(state, wolf)
	_eq((second["action"] as Ability).id, &"roar", "round 2 roars instead")
	_eq(second["target"], wolf, "a self-targeting ability aims at its user")

	# most_hp, and first, on the same set.
	var by_rule := func(rule: String, max_hps: Array = []) -> String:
		var g := [
			_node("s", "start", {}, [{"flow": "next", "target": "p"}]),
			_node("p", "choose_target", {"rule": rule}, [{"flow": "next", "target": "u"}]),
			_node("u", "use_ability", {"ability": "bite"}, []),
		]
		var f := _fight(g, [30, 8, 20], max_hps)
		return (BattleAI.decide(f["state"], f["wolf"])["target"] as Battler).display_name
	_eq(by_rule.call("most_hp"), "Hero0", "most_hp picks the healthiest")
	_eq(by_rule.call("first"), "Hero0", "first picks the first")
	_eq(by_rule.call("lowest_hp_percent", [100, 10, 40]), "Hero0", "lowest_hp_percent picks the most hurt (30 of 100), not the lowest hp")
	_eq(by_rule.call("lowest_hp", [100, 10, 40]), "Hero1", "while lowest_hp picks the smallest number (8)")


func _test_stat_branch_and_fallbacks() -> void:
	_section("AI graph -- stat and count branches, and the random fallback")
	# Below 50% hp of self: roar; else bite the first hero.
	var nodes := [
		_node("s", "start", {}, [{"flow": "next", "target": "hp"}]),
		_node("hp", "if_stat", {"who": "self", "stat": "hp", "op": "<", "value": 50, "percent": true},
			[{"flow": "true", "target": "roar"}, {"flow": "false", "target": "pick"}]),
		_node("pick", "choose_target", {"rule": "first"}, [{"flow": "next", "target": "bite"}]),
		_node("bite", "use_ability", {"ability": "bite"}, []),
		_node("roar", "use_ability", {"ability": "roar"}, []),
	]
	var fight := _fight(nodes, [30, 30])
	var state: BattleState = fight["state"]
	var wolf: Battler = fight["wolf"]

	_eq((BattleAI.decide(state, wolf)["action"] as Ability).id, &"bite", "healthy: bite")
	wolf.hp = 10
	_eq((BattleAI.decide(state, wolf)["action"] as Ability).id, &"roar", "hurt below 50 percent: roar")

	# if_count on the enemy side (the heroes): two standing -> true branch.
	var count_nodes := [
		_node("s", "start", {}, [{"flow": "next", "target": "c"}]),
		_node("c", "if_count", {"side": "enemies", "op": ">=", "value": 2},
			[{"flow": "true", "target": "roar"}, {"flow": "false", "target": "bite"}]),
		_node("bite", "use_ability", {"ability": "bite"}, []),
		_node("roar", "use_ability", {"ability": "roar"}, []),
	]
	var counted := _fight(count_nodes, [30, 30])
	_eq((BattleAI.decide(counted["state"], counted["wolf"])["action"] as Ability).id, &"roar",
		"two heroes standing takes the true branch")

	# A graph that never reaches use_ability decides nothing, and a turn still happens.
	var silent := [_node("s", "start", {}, [])]
	var quiet := _fight(silent, [30])
	_ok(BattleAI.decide(quiet["state"], quiet["wolf"]).is_empty(), "a silent graph decides nothing")
	var state2: BattleState = quiet["state"]
	var log := state2.resolve_turn([])
	_ok(not log.is_empty(), "so the fallback still takes a turn")

	# No AI at all.
	var plain := _fight([], [30])
	_ok(BattleAI.decide(plain["state"], plain["wolf"]).is_empty(), "no ai_path decides nothing")

	DirAccess.remove_absolute(AI_PATH)


func _test_dry_run() -> void:
	_section("AI dry run -- BattleAI.simulate lists decisions without resolving anything")
	var nodes := [
		_node("s", "start", {}, [{"flow": "next", "target": "r"}]),
		_node("r", "if_round", {"op": "==", "value": 1},
			[{"flow": "true", "target": "roar"}, {"flow": "false", "target": "bite"}]),
		_node("bite", "use_ability", {"ability": "bite"}, []),
		_node("roar", "use_ability", {"ability": "roar"}, []),
	]
	var fight := _fight(nodes, [30])
	var enemy: EnemyDef = (fight["wolf"] as Battler).enemy
	var members: Array[PartyMember] = []
	for b in (fight["state"] as BattleState).player_side:
		members.append(b.member)
	var lines := BattleAI.simulate(enemy, 3, members)
	_eq(lines.size(), 6, "three rounds, healthy and wounded")
	_ok(lines[0].begins_with("healthy, round 1: Roar"), "round 1 roars: %s" % lines[0])
	_ok(lines[1].begins_with("healthy, round 2: Bite on Hero0"), "round 2 bites the hero: %s" % lines[1])
	_ok(lines[3].begins_with("wounded, round 1"), "and the wounded run follows")
	enemy.ai_path = ""
	_ok(BattleAI.simulate(enemy)[0].contains("no AI graph"), "an enemy with no AI says so")
	DirAccess.remove_absolute(AI_PATH)


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
