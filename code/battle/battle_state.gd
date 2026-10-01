class_name BattleState extends RefCounted

## One fight, start to outcome. Classic turn-based (not ATB): every living player
## [Battler] is given a command, then [method resolve_turn] runs the whole round -
## player commands plus a simple enemy AI, everyone in speed order - and hands back the
## log lines a battle scene can print. No animation timeline; "resolve" is synchronous
## and immediate, which is what makes this the loose, playable-with-numbers layer
## battle/battle_scene.gd sits on top of rather than folded into it.

var player_side: Array[Battler] = []
var enemy_side: Array[Battler] = []

## Rounds started so far - 1 during the first [method resolve_turn]. What an enemy AI's
## [code]if_round[/code] reads.
var round_number: int = 0


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


## What winning pays out, applied to [Party] and returned as log lines: the enemies' gold,
## their experience shared between the party members still standing (each may level up and
## learn abilities - see [method PartyMember.grant_xp]), and whatever each defeated enemy's
## [member EnemyDef.drops] rolled.
func grant_rewards() -> Array[String]:
	var log: Array[String] = []

	var gold := gold_reward()
	Party.add_gold(gold)
	log.append("Victory! %d gold earned." % gold)

	var xp := 0
	for b in enemy_side:
		if b.enemy != null:
			xp += b.enemy.xp_reward
	var survivors: Array[Battler] = alive_allies().filter(
		func(b: Battler) -> bool: return b.member != null)
	if xp > 0 and not survivors.is_empty():
		var share := ceili(float(xp) / survivors.size())
		log.append("Each survivor gains %d XP." % share)
		for b in survivors:
			log.append_array(b.member.grant_xp(share))

	for b in enemy_side:
		if b.enemy == null:
			continue
		for drop in b.enemy.drops:
			if drop != null and drop.item != null and randf() <= drop.chance:
				Party.add_item(drop.item.id, drop.count)
				log.append("Found %s%s." % [drop.item.display_name,
					"" if drop.count == 1 else " x%d" % drop.count])
	return log


## Runs one whole round: [param player_commands] (one entry per still-living player
## [Battler], [code]{"battler": Battler, "action": Ability, "target": Battler}[/code]
## - a target of null means "resolve at execution time", for an
## [constant Ability.Target.ALL_*]/[constant Ability.Target.SELF] action that
## does not need one picked by hand) plus an AI-chosen command per living enemy, all
## sorted by [member Stats.spd] descending and executed in that order - skipping
## anything on either side that died earlier in the same round. Returns the log lines,
## in execution order, for a battle scene to print.
func resolve_turn(player_commands: Array[Dictionary]) -> Array[String]:
	var log: Array[String] = []
	round_number += 1
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

	log.append_array(_end_round())
	return log


## End of a round: every living battler's ROUNDS effects count down, and what wears off is
## reported.
func _end_round() -> Array[String]:
	var log: Array[String] = []
	for b in player_side + enemy_side:
		if not b.is_alive():
			continue
		# Regeneration and poison first, so an effect that kills does not also "wear off".
		for active in b.effects:
			var change := active.effect.hp_per_round * active.stacks
			if change == 0:
				continue
			b.hp = clampi(b.hp + change, 0, b.stats.max_hp)
			log.append("%s %s %d HP from %s.%s" % [
				b.display_name, "recovers" if change > 0 else "loses", absi(change),
				active.effect.display_name,
				"" if b.is_alive() else " %s falls!" % b.display_name])
			if not b.is_alive():
				break
		if not b.is_alive():
			continue
		for expired in b.tick_round():
			log.append("%s's %s wears off." % [b.display_name, expired.display_name])
	return log


func _choose_enemy_command(actor: Battler) -> Dictionary:
	# An enemy with an AI graph lets it decide; one without (or whose graph reaches no
	# use_ability) falls through to the random pick below.
	var decided := BattleAI.decide(self, actor)
	if not decided.is_empty():
		return decided

	var action: Ability = actor.abilities[randi() % actor.abilities.size()] \
		if not actor.abilities.is_empty() else _struggle()
	var targets := _targets_for(actor, action)
	var target: Battler = targets[randi() % targets.size()] if not targets.is_empty() else null
	return {"battler": actor, "action": action, "target": target}


## The one action every [Battler] can always fall back to - an enemy authored with no
## [member Combatant.abilities] of its own still does *something* rather than passing
## silently every round.
func _struggle() -> Ability:
	var struggle := Ability.new()
	struggle.id = &"struggle"
	struggle.display_name = "Struggle"
	struggle.power = 0.5
	return struggle


func _targets_for(actor: Battler, action: Ability) -> Array[Battler]:
	var same_side := alive_allies() if actor.side == Battler.Side.PLAYER else alive_enemies()
	var other_side := alive_enemies() if actor.side == Battler.Side.PLAYER else alive_allies()
	match action.target:
		Ability.Target.SELF:
			return [actor]
		Ability.Target.SINGLE_ALLY, Ability.Target.ALL_ALLIES:
			return same_side
		_:
			return other_side


func _resolve_action(actor: Battler, action: Ability, target: Battler) -> Array[String]:
	actor.guarding = false

	match action.kind:
		Ability.Kind.GUARD:
			actor.guarding = true
			return ["%s guards." % actor.display_name]
		Ability.Kind.ITEM:
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


func _apply_action(actor: Battler, action: Ability, target: Battler) -> String:
	var extras := _apply_dispel(action, target) + _apply_effects(action, target)

	var healed_text := ""
	if action.restores_hp():
		var amount := action.heal_amount + roundi(action.heal_mag_scale * actor.stats.mag)
		var restored := -target.apply_damage(-amount)
		healed_text = " %s recovers %d HP." % [target.display_name, restored]

	if not action.deals_damage():
		if action.restores_hp():
			return "%s's %s heals %s.%s%s" % [
				actor.display_name, action.display_name, target.display_name, healed_text, extras]
		return "%s uses %s on %s.%s" % [
			actor.display_name, action.display_name, target.display_name, extras]

	var raw := BattleFormula.damage(actor.stats, target.stats, action)
	var applied := target.apply_damage(raw)

	if applied < 0:
		return "%s's %s heals %s for %d HP.%s%s" % [
			actor.display_name, action.display_name, target.display_name, -applied,
			healed_text, extras]
	if applied == 0:
		return "%s's %s has no effect on %s.%s%s" % [
			actor.display_name, action.display_name, target.display_name, healed_text, extras]

	var fallen := "" if target.is_alive() else " %s falls!" % target.display_name
	return "%s's %s hits %s for %d damage.%s%s%s" % [
		actor.display_name, action.display_name, target.display_name, applied, fallen,
		healed_text, extras]


## Strips the effects [param action] dispels from [param target], returning the text to add
## to the log (empty if it dispels nothing or nothing was on the target).
func _apply_dispel(action: Ability, target: Battler) -> String:
	var text := ""
	for effect in target.remove_effects(action.dispel):
		text += " %s's %s is removed." % [target.display_name, effect.display_name]
	return text


func _resolve_item(actor: Battler, action: Ability, target: Battler) -> Array[String]:
	if not Party.consume_item(action.item_id):
		return ["%s has no %s left!" % [actor.display_name, action.display_name]]

	var t := target if target != null else actor
	# A potion-shaped item heals by [member Ability.power] flat HP - negative
	# damage is [method Battler.apply_damage]'s own healing convention.
	var healed := -t.apply_damage(-roundi(action.power))
	var restored := "" if healed == 0 else " Restoring %d HP." % healed
	return ["%s uses %s on %s.%s%s%s" % [
		actor.display_name, action.display_name, t.display_name, restored,
		_apply_dispel(action, t), _apply_effects(action, t)]]


## Puts each of [param action]'s status effects on [param target], each subject to its
## [member Ability.effect_chance]. Returns the text to append to the action's log
## line - empty when nothing was applied.
func _apply_effects(action: Ability, target: Battler) -> String:
	var text := ""
	for effect in action.effects:
		if effect == null or randf() > action.effect_chance:
			continue
		if target.add_effect(effect):
			text += " %s gains %s." % [target.display_name, effect.display_name]
	return text
