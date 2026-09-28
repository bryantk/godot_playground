class_name BattleScene extends Control

## The one battle screen every troop fights on - generic, not authored per-troop.
## Reads what to fight off [member BattleTransfer.pending_troop] on ready, drives one
## [BattleState] through the classic "choose a command for every living ally, resolve
## the round" loop (see that class's own doc), and writes the outcome back to
## [BattleTransfer] for [code]start_battle[/code]'s own executor
## (events/commands/battle_execs.gd) to notice and swap back to the field.
##
## Deliberately plain [Button]/[Label] UI, no sprites or animation yet - the loose,
## playable-with-numbers layer this whole feature asked for. Swap the visuals once the
## formulas and pacing underneath have been played with enough to hone in on.

@onready var _log: RichTextLabel = %Log
@onready var _enemy_row: HBoxContainer = %EnemyRow
@onready var _party_row: HBoxContainer = %PartyRow
@onready var _action_menu: VBoxContainer = %ActionMenu
@onready var _target_menu: VBoxContainer = %TargetMenu

var _state: BattleState
var _commands: Array[Dictionary] = []
var _turn_index := 0


func _ready() -> void:
	_state = BattleState.new()
	var troop := BattleTransfer.pending_troop
	BattleTransfer.pending_troop = null
	_state.begin(Party.active_members(), troop)

	_refresh_rows()
	_log.text = "%s appears!\n" % (troop.id if troop != null else &"a troop")
	_begin_command_phase()


# -- The command phase: one action per living ally, in order -------------------------

func _begin_command_phase() -> void:
	_commands.clear()
	_turn_index = 0
	_prompt_next_command()


func _prompt_next_command() -> void:
	var alive := _state.alive_allies()
	if _turn_index >= alive.size():
		_resolve_round()
		return
	_show_action_menu(alive[_turn_index])


func _show_action_menu(actor: Battler) -> void:
	_target_menu.hide()
	_action_menu.show()
	_clear(_action_menu)

	_add_header(_action_menu, "%s's turn" % actor.display_name)
	for action in actor.actions:
		_add_button(_action_menu, action.display_name, _choose_action.bind(actor, action))
	_add_button(_action_menu, "Guard", _choose_action.bind(actor, _guard_action()))
	if not Party.items.is_empty():
		_add_button(_action_menu, "Item", _show_item_menu.bind(actor))


func _show_item_menu(actor: Battler) -> void:
	_clear(_action_menu)
	_add_header(_action_menu, "Use an item")
	for item_id: Variant in Party.items:
		var count: int = Party.items[item_id]
		_add_button(_action_menu, "%s x%d" % [str(item_id), count],
			_choose_action.bind(actor, _item_action(item_id)))
	_add_button(_action_menu, "Back", _show_action_menu.bind(actor))


func _guard_action() -> BattleAction:
	var action := BattleAction.new()
	action.display_name = "Guard"
	action.kind = BattleAction.Kind.GUARD
	return action


## A generic "restore 15 HP" item action - loose on purpose, same as everything else
## here: honing in on real per-item potency is picking numbers per [member
## BattleAction.item_id], once there is more than one kind of item to tell apart.
func _item_action(item_id: StringName) -> BattleAction:
	var action := BattleAction.new()
	action.display_name = str(item_id)
	action.kind = BattleAction.Kind.ITEM
	action.item_id = item_id
	action.target = BattleAction.Target.SINGLE_ALLY
	action.power = 15.0
	return action


func _choose_action(actor: Battler, action: BattleAction) -> void:
	if action.target == BattleAction.Target.SINGLE_ENEMY \
			or action.target == BattleAction.Target.SINGLE_ALLY:
		_show_target_menu(actor, action)
	else:
		_commit_command(actor, action, null)


func _show_target_menu(actor: Battler, action: BattleAction) -> void:
	_action_menu.hide()
	_target_menu.show()
	_clear(_target_menu)

	_add_header(_target_menu, "Choose a target")
	var pool := _state.alive_enemies() if action.target == BattleAction.Target.SINGLE_ENEMY \
		else _state.alive_allies()
	for target in pool:
		_add_button(_target_menu, target.display_name, _commit_command.bind(actor, action, target))
	_add_button(_target_menu, "Back", _show_action_menu.bind(actor))


func _commit_command(actor: Battler, action: BattleAction, target: Battler) -> void:
	_commands.append({"battler": actor, "action": action, "target": target})
	_turn_index += 1
	_prompt_next_command()


# -- Resolving a round -----------------------------------------------------------------

func _resolve_round() -> void:
	_action_menu.hide()
	_target_menu.hide()

	for line in _state.resolve_turn(_commands):
		_log.append_text(line + "\n")
	_refresh_rows()

	if _state.is_over():
		_finish()
	else:
		_begin_command_phase()


func _finish() -> void:
	for b in _state.player_side:
		b.sync_to_member()

	if _state.is_victory():
		var reward := _state.gold_reward()
		Party.add_gold(reward)
		_log.append_text("Victory! %d gold earned.\n" % reward)
		BattleTransfer.outcome = &"victory"
	else:
		_log.append_text("The party has fallen...\n")
		BattleTransfer.outcome = &"defeat"


# -- Display ----------------------------------------------------------------------------

func _refresh_rows() -> void:
	_clear(_enemy_row)
	for b in _state.enemy_side:
		_add_label(_enemy_row, "%s\nHP %d/%d" % [b.display_name, b.hp, b.stats.max_hp])

	_clear(_party_row)
	for b in _state.player_side:
		_add_label(_party_row, "%s\nHP %d/%d  MP %d/%d" % [
			b.display_name, b.hp, b.stats.max_hp, b.mp, b.stats.max_mp])


func _clear(container: Container) -> void:
	for child in container.get_children():
		container.remove_child(child)
		child.queue_free()


func _add_button(container: Container, text: String, callback: Callable) -> void:
	var button := Button.new()
	button.text = text
	button.pressed.connect(callback)
	container.add_child(button)


func _add_label(container: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	container.add_child(label)


func _add_header(container: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	container.add_child(label)
