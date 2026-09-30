extends Control

## The battle sandbox tool - pick which party members and which enemies (and how many
## of each) fight, run [BattleSimulator] over the composition, and read an estimated
## win rate. Not wired into the game at all: open battle/battle_sandbox.tscn in the
## editor and press "Run Current Scene" (F6) to use it, the same way this project's
## other demo/tool scenes are run directly rather than through a dock.
##
## Lists every candidate off [method Party.member_catalogue]/[method
## BattleTransfer.enemy_catalogue] rather than a fixed roster, so a new [PartyMember]/
## [EnemyDef] registered anywhere shows up here without this file changing.

@onready var _ally_list: VBoxContainer = %AllyList
@onready var _enemy_list: VBoxContainer = %EnemyList
@onready var _trials_spin: SpinBox = %TrialsSpin
@onready var _simulate_button: Button = %SimulateButton
@onready var _results_label: Label = %ResultsLabel

## member id -> CheckBox
var _ally_checks: Dictionary = {}
## enemy id -> SpinBox (count to include, 0 = excluded)
var _enemy_counts: Dictionary = {}


func _ready() -> void:
	_build_ally_list()
	_build_enemy_list()
	_simulate_button.pressed.connect(_on_simulate_pressed)


func _build_ally_list() -> void:
	for member in Party.member_catalogue():
		var check := CheckBox.new()
		check.text = "%s (HP %d, ATK %d, SPD %d)" % [
			member.display_name, member.base_stats.max_hp, member.base_stats.atk,
			member.base_stats.spd]
		# Whoever is active today is a reasonable starting guess for "who would fight".
		check.button_pressed = Party.active.has(member)
		_ally_list.add_child(check)
		_ally_checks[member.id] = check


func _build_enemy_list() -> void:
	for enemy in BattleTransfer.enemy_catalogue():
		var row := HBoxContainer.new()

		var label := Label.new()
		label.text = "%s (HP %d, ATK %d, SPD %d)" % [
			enemy.display_name, enemy.stats.max_hp, enemy.stats.atk, enemy.stats.spd]
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)

		var count := SpinBox.new()
		count.min_value = 0
		count.max_value = 8
		count.value = 0
		row.add_child(count)

		_enemy_list.add_child(row)
		_enemy_counts[enemy.id] = count


func _on_simulate_pressed() -> void:
	var members := _selected_members()
	var troop := _ad_hoc_troop()

	if members.is_empty() or troop.enemies.is_empty():
		_results_label.text = "Pick at least one ally and one enemy first."
		return

	var trials := int(_trials_spin.value)
	var result := BattleSimulator.simulate(members, troop, trials)
	_results_label.text = (
		"%d trials: %.1f%% win, %.1f%% loss, %.1f%% draw - avg %.1f rounds" % [
			result["trials"], result["win_rate"] * 100.0,
			(float(result["losses"]) / float(result["trials"])) * 100.0,
			(float(result["draws"]) / float(result["trials"])) * 100.0,
			result["avg_rounds"]])


func _selected_members() -> Array[PartyMember]:
	var out: Array[PartyMember] = []
	for member in Party.member_catalogue():
		var check: CheckBox = _ally_checks.get(member.id)
		if check != null and check.button_pressed:
			out.append(member)
	return out


func _ad_hoc_troop() -> Troop:
	var troop := Troop.new()
	troop.id = &"sandbox"
	var enemies: Array[Dictionary] = []
	for enemy in BattleTransfer.enemy_catalogue():
		var count: SpinBox = _enemy_counts.get(enemy.id)
		if count != null and int(count.value) > 0:
			enemies.append({"enemy": enemy, "count": int(count.value)})
	troop.enemies = enemies
	return troop
