extends Node

## Headless assertions over status effects and the shared [Combatant] base: [StatusEffect]
## maths, [EffectList] stacking and expiry, a [Battler] seeing its own buffs, [BattleState]
## applying and expiring them, and field use of an [Item] on a [PartyMember].
##
##     godot --headless --path . res://tests/battle_effects_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("battle -- Combatant, StatusEffect, EffectList")
	print("")

	GameState.clear()
	_test_combatant_base()
	_test_effect_maths_and_stacking()
	_test_expiry()
	_test_battler_and_battle_state()
	_test_field_use_and_save()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _stats(hp: int, atk: int, def: int, spd: int) -> Stats:
	var s := Stats.new()
	s.max_hp = hp
	s.max_mp = 10
	s.atk = atk
	s.def = def
	s.mag = 0
	s.spd = spd
	return s


func _effect(id: StringName, flat: Dictionary, percent: Dictionary, duration: int,
		unit: StatusEffect.Unit = StatusEffect.Unit.ROUNDS) -> StatusEffect:
	var e := StatusEffect.new()
	e.id = id
	e.display_name = str(id).capitalize()
	e.flat = flat
	e.percent = percent
	e.duration = duration
	e.unit = unit
	return e


func _test_combatant_base() -> void:
	_section("Combatant -- heroes and enemies share one base")
	var hero := PartyMember.new()
	var enemy := EnemyDef.new()
	_ok(hero is Combatant and enemy is Combatant, "both extend Combatant")
	enemy.stats = _stats(9, 1, 1, 1)
	_eq(enemy.base_stats.max_hp, 9, "EnemyDef.stats is the same field as base_stats")
	hero.base_stats = _stats(30, 5, 2, 3)
	_eq(hero.effective_stats().max_hp, 30, "a hero with no gear or effects is its base")


func _test_effect_maths_and_stacking() -> void:
	_section("StatusEffect -- flat then percent, per stack")
	var buff := _effect(&"rage", {"atk": 3}, {"atk": 50}, 3)
	var out := buff.modify(_stats(20, 10, 4, 5), 1)
	_eq(out.atk, 20, "(10 + 3) * 1.5 rounds to 20")
	_eq(out.def, 4, "other stats are untouched")
	_eq(buff.modify(_stats(20, 10, 4, 5), 2).atk, 32, "two stacks: (10 + 6) * (1 + 1.0) = 32")

	var list: Array[ActiveEffect] = []
	var stack := _effect(&"stack", {"def": 2}, {}, 3)
	stack.stacking = StatusEffect.Stack.STACK
	stack.max_stacks = 2
	EffectList.add(list, stack)
	EffectList.add(list, stack)
	EffectList.add(list, stack)
	_eq(list.size(), 1, "the same effect is one entry")
	_eq(list[0].stacks, 2, "STACK caps at max_stacks")

	var ignore := _effect(&"once", {}, {}, 3)
	ignore.stacking = StatusEffect.Stack.IGNORE
	_ok(EffectList.add(list, ignore) != null, "IGNORE applies the first time")
	_ok(EffectList.add(list, ignore) == null, "and ignores the second")


func _test_expiry() -> void:
	_section("EffectList -- rounds and steps tick in their own unit; a flag ends one early")
	var list: Array[ActiveEffect] = []
	EffectList.add(list, _effect(&"short", {}, {}, 2))
	EffectList.add(list, _effect(&"walk", {}, {}, 2, StatusEffect.Unit.STEPS))
	EffectList.add(list, _effect(&"forever", {}, {}, 0))

	_eq(EffectList.tick(list, StatusEffect.Unit.ROUNDS).size(), 0, "one round: nothing yet")
	var gone := EffectList.tick(list, StatusEffect.Unit.ROUNDS)
	_eq(gone.size(), 1, "two rounds: the round effect wears off")
	_eq(gone[0].id if gone.size() == 1 else &"", &"short", "and it is the right one")
	_ok(EffectList.has(list, &"walk"), "a steps effect did not tick in rounds")
	EffectList.tick(list, StatusEffect.Unit.STEPS)
	EffectList.tick(list, StatusEffect.Unit.STEPS)
	_ok(not EffectList.has(list, &"walk"), "but it does in steps")
	_ok(EffectList.has(list, &"forever"), "duration 0 never runs out by itself")

	var flagged := _effect(&"until", {}, {}, 99)
	flagged.until_flag = &"curse_lifted"
	EffectList.add(list, flagged)
	EffectList.tick(list, StatusEffect.Unit.ROUNDS)
	_ok(EffectList.has(list, &"until"), "still on while the flag is false")
	GameState.set_flag(&"curse_lifted")
	EffectList.tick(list, StatusEffect.Unit.ROUNDS)
	_ok(not EffectList.has(list, &"until"), "gone once the flag is set")
	GameState.clear()


func _test_battler_and_battle_state() -> void:
	_section("BattleState -- an ability applies an effect, stats follow it, and it wears off")
	var hero := PartyMember.new()
	hero.id = &"h"
	hero.display_name = "Hero"
	hero.base_stats = _stats(40, 6, 2, 10)

	var haste := _effect(&"haste", {}, {"spd": 100}, 1)
	var cast := Ability.new()
	cast.id = &"cast_haste"
	cast.display_name = "Haste"
	cast.kind = Ability.Kind.SKILL
	cast.target = Ability.Target.SELF
	cast.power = 0.0
	cast.effects = [haste]
	hero.abilities = [cast]

	var foe := EnemyDef.new()
	foe.id = &"e"
	foe.display_name = "Foe"
	foe.stats = _stats(30, 1, 0, 1)
	var troop := Troop.new()
	troop.enemies = [{"enemy": foe, "count": 1}]

	var state := BattleState.new()
	var members: Array[PartyMember] = [hero]
	state.begin(members, troop)
	var me: Battler = state.player_side[0]
	_eq(me.stats.spd, 10, "starts at base speed")

	var commands: Array[Dictionary] = [{"battler": me, "action": cast, "target": null}]
	var log := state.resolve_turn(commands)
	_ok(log.any(func(l: String) -> bool: return l.contains("gains Haste")), "the log says it was gained")
	_ok(log.any(func(l: String) -> bool: return l.contains("wears off")), "and that it wore off at round end")
	_eq(me.stats.spd, 10, "speed is back to base afterwards")
	_eq(state.round_number, 1, "one round has been played")

	var debuffed := Battler.for_member(hero)
	debuffed.add_effect(_effect(&"frail", {"max_hp": -100}, {}, 3))
	_eq(debuffed.stats.max_hp, 1, "max hp has a floor of 1")
	_eq(debuffed.hp, 1, "and hp is kept inside the new maximum")


func _test_field_use_and_save() -> void:
	_section("Party -- an item used in the field heals, buffs, ticks by steps, and saves")
	var tonic := _effect(&"tonic", {"def": 5}, {}, 2, StatusEffect.Unit.STEPS)
	BattleData.register(BattleData.EFFECTS, tonic)

	var action := Ability.new()
	action.kind = Ability.Kind.ITEM
	action.power = 10.0
	action.effects = [tonic]
	var item := Item.new()
	item.id = &"tonic_bottle"
	item.display_name = "Tonic"
	item.action = action
	Party.register_item(item)
	Party.add_item(&"tonic_bottle", 1)

	var member := PartyMember.new()
	member.id = &"m"
	member.display_name = "Mel"
	member.base_stats = _stats(40, 5, 3, 5)
	member.current_hp = 10
	var line := Party.use_item_in_field(&"tonic_bottle", member)
	_ok(line.contains("recovers 10"), "it reports the healing: %s" % line)
	_eq(member.current_hp, 20, "hp went up by the item's power")
	_eq(member.effective_stats().def, 8, "and the effect is in the member's stats")
	_eq(Party.use_item_in_field(&"tonic_bottle", member), "", "with none left it does nothing")

	var saved := member.to_save()
	var restored := PartyMember.new()
	restored.base_stats = member.base_stats
	restored.from_save(saved, func(_id: String) -> Equipment: return null)
	_eq(restored.effective_stats().def, 8, "the effect survives save and load")

	member.tick_steps()
	_eq(member.effective_stats().def, 8, "one step: still on")
	member.tick_steps()
	_eq(member.effective_stats().def, 3, "two steps: worn off")


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
