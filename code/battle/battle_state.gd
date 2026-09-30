class_name BattleState extends RefCounted

## One fight, start to outcome. Classic turn-based (not ATB): every living player
## [Battler] is given a command, then [method resolve_turn] runs the whole round -
## player commands plus a simple enemy AI, everyone in speed order - and hands back the
## log lines a battle scene can print. No animation timeline; "resolve" is synchronous
## and immediate, which is what makes this the loose, playable-with-numbers layer
## battle/battle_scene.gd sits on top of rather than folded into it.

var player_side: Array[Battler] = []
var enemy_side: Array[Battler] = []


func begin(members: Array[PartyMember], troop: Troop) -> void:
	player_side.clear()
	enemy_side.clear()

	for m in members:
		player_side.append(Battler.for_member(m))

	for entry: Variant in troop.enemies:
		var enemy: EnemyDef = (entry as Dictionary).get("enemy")
		var count := int((entry as Dictionary).get("count", 1))
		for i in count:
			enemy_side.append(Battler.for_enemy(enemy, i))


func alive_allies() -> Array[Battler]:
	return player_side.filter(func(b: Battler) -> bool: return b.is_alive())


func alive_enemies() -> Array[Battler]:
	return enemy_side.filter(func(b: Battler) -> bool: return b.is_alive())


func is_victory() -> bool:
	return alive_enemies().is_empty()


func is_defeat() -> bool:
	return alive_allies().is_empty()


func is_over() -> bool:
	return is_victory() or is_defeat()


## Every enemy still alive's own [member EnemyDef.gold_reward], summed - what a
## victorious battle hands to [method Party.add_gold].
func gold_reward() -> int:
	var total := 0
	for b in enemy_side:
		if b.enemy != null:
			total += b.enemy.gold_reward
	return total


## Runs one whole round: [param player_commands] (one entry per still-living player
## [Battler], [code]{"battler": Battler, "action": BattleAction, "target": Battler}[/code]
## - a target of null means "resolve at execution time", for an
## [constant BattleAction.Target.ALL_*]/[constant BattleAction.Target.SELF] action that
## does not need one picked by hand) plus an AI-chosen command per living enemy, all
## sorted by [member Stats.spd] descending and executed in that order - skipping
## anything on either side that died earlier in the same round. Returns the log lines,
## in execution order, for a battle scene to print.
func resolve_turn(player_commands: Array[Dictionary]) -> Array[String]:
	var log: Array[String] = []
	var commands := player_commands.duplicate()
	for b in alive_enemies():
		commands.append(_choose_enemy_command(b))

	commands.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return (a["battler"] as Battler).stats.spd > (b["battler"] as Battler).stats.spd)

	for command in commands:
		var actor: Battler = command["battler"]
		if not actor.is_alive():
			continue
		log.append_array(_resolve_action(actor, command["action"], command.get("target")))

		if is_over():
			break

	return log


func _choose_enemy_command(actor: Battler) -> Dictionary:
	var action: BattleAction = actor.actions[randi() % actor.actions.size()] \
		if not actor.actions.is_empty() else _struggle()
	var targets := _targets_for(actor, action)
	var target: Battler = targets[randi() % targets.size()] if not targets.is_empty() else null
	return {"battler": actor, "action": action, "target": target}


## The one action every [Battler] can always fall back to - an enemy authored with no
## [member EnemyDef.actions] of its own still does *something* rather than passing
## silently every round.
func _struggle() -> BattleAction:
	var struggle := BattleAction.new()
	struggle.id = &"struggle"
	struggle.display_name = "Struggle"
	struggle.power = 0.5
	return struggle


func _targets_for(actor: Battler, action: BattleAction) -> Array[Battler]:
	var same_side := alive_allies() if actor.side == Battler.Side.PLAYER else alive_enemies()
	var other_side := alive_enemies() if actor.side == Battler.Side.PLAYER else alive_allies()
	match action.target:
		BattleAction.Target.SELF:
			return [actor]
		BattleAction.Target.SINGLE_ALLY, BattleAction.Target.ALL_ALLIES:
			return same_side
		_:
			return other_side


func _resolve_action(actor: Battler, action: BattleAction, target: Battler) -> Array[String]:
	actor.guarding = false

	match action.kind:
		BattleAction.Kind.GUARD:
			actor.guarding = true
			return ["%s guards." % actor.display_name]
		BattleAction.Kind.ITEM:
			return _resolve_item(actor, action, target)

	if action.mp_cost > 0 and not actor.spend_mp(action.mp_cost):
		return ["%s has no MP left for %s!" % [actor.display_name, action.display_name]]

	var targets := [target] if target != null else _targets_for(actor, action)
	var log: Array[String] = []
	for t in targets:
		if not t.is_alive():
			continue
		log.append(_apply_action(actor, action, t))
	return log


func _apply_action(actor: Battler, action: BattleAction, target: Battler) -> String:
	var raw := BattleFormula.damage(actor.stats, target.stats, action)
	var applied := target.apply_damage(raw)

	if applied < 0:
		return "%s's %s heals %s for %d HP." % [
			actor.display_name, action.display_name, target.display_name, -applied]
	if applied == 0:
		return "%s's %s has no effect on %s." % [actor.display_name, action.display_name, target.display_name]

	var fallen := "" if target.is_alive() else " %s falls!" % target.display_name
	return "%s's %s hits %s for %d damage.%s" % [
		actor.display_name, action.display_name, target.display_name, applied, fallen]


func _resolve_item(actor: Battler, action: BattleAction, target: Battler) -> Array[String]:
	if not Party.consume_item(action.item_id):
		return ["%s has no %s left!" % [actor.display_name, action.display_name]]

	var t := target if target != null else actor
	# A potion-shaped item heals by [member BattleAction.power] flat HP - negative
	# damage is [method Battler.apply_damage]'s own healing convention.
	var healed := -t.apply_damage(-roundi(action.power))
	return ["%s uses %s on %s, restoring %d HP." % [
		actor.display_name, action.display_name, t.display_name, healed]]
