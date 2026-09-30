## The battle AI commands - [code]if_round[/code], [code]if_stat[/code], [code]if_status[/code],
## [code]if_count[/code], [code]if_random[/code], [code]choose_target[/code],
## [code]use_ability[/code] (event_command.gd). They only make sense inside an enemy's AI
## graph, run by [BattleAI], which hands them a [BattleAI.Context] through
## [member EventContext.battle_ai]; outside one they read as false / do nothing.
##
## All of them are instant and non-blocking, so a whole AI graph resolves in one call.


## Branches on the round number: [code]value[/code] under [code]op[/code] (default >=), or -
## with [code]every[/code] - every Nth round (every 3: rounds 3, 6, 9).
class IfRound extends EventCommandExec:
	var _result := false

	func start() -> void:
		var ai := ctx.battle_ai as BattleAI.Context
		if ai == null:
			return
		var round_now := ai.state.round_number
		if args.has("every"):
			var every := maxi(1, int(args["every"]))
			_result = round_now % every == 0
		else:
			_result = EventCondition.compare(
				round_now, str(args.get("op", ">=")), int(args.get("value", 1)))

	func flow_port() -> String:
		return "true" if _result else "false"


## Branches on a stat of the actor ("self") or the chosen target ("target"):
## [code]stat[/code] under [code]op[/code] against [code]value[/code]. For hp and mp,
## [code]percent[/code] compares the percentage of the maximum instead - "hp <= 30 percent".
class IfStat extends EventCommandExec:
	var _result := false

	func start() -> void:
		var ai := ctx.battle_ai as BattleAI.Context
		if ai == null:
			return
		var who := str(args.get("who", "self"))
		var battler := ai.target if who == "target" else ai.actor
		if battler == null:
			return
		var amount := _stat(battler, str(args.get("stat", "hp")), bool(args.get("percent", false)))
		_result = EventCondition.compare(amount, str(args.get("op", "<=")), float(args.get("value", 0)))

	static func _stat(battler: Battler, stat: String, as_percent: bool) -> float:
		match stat:
			"hp":
				return float(battler.hp) * 100.0 / maxf(1.0, float(battler.stats.max_hp)) \
					if as_percent else float(battler.hp)
			"mp":
				return float(battler.mp) * 100.0 / maxf(1.0, float(battler.stats.max_mp)) \
					if as_percent else float(battler.mp)
			"max_hp", "max_mp", "atk", "def", "mag", "spd":
				return float(int(battler.stats.get(stat)))
		return 0.0

	func flow_port() -> String:
		return "true" if _result else "false"


## Branches on whether the actor ("self") or the chosen target ("target") has the named
## status effect running.
class IfStatus extends EventCommandExec:
	var _result := false

	func start() -> void:
		var ai := ctx.battle_ai as BattleAI.Context
		if ai == null:
			return
		var battler := ai.target if str(args.get("who", "self")) == "target" else ai.actor
		_result = battler != null and battler.has_effect(StringName(str(args.get("status", ""))))

	func flow_port() -> String:
		return "true" if _result else "false"


## Branches on how many are still standing on a side: "allies" (the actor's own side,
## itself included) or "enemies" (the other one) - [code]value[/code] under [code]op[/code].
class IfCount extends EventCommandExec:
	var _result := false

	func start() -> void:
		var ai := ctx.battle_ai as BattleAI.Context
		if ai == null:
			return
		var own_side: Array[Battler] = ai.state.alive_enemies() \
			if ai.actor.side == Battler.Side.ENEMY else ai.state.alive_allies()
		var other_side: Array[Battler] = ai.state.alive_allies() \
			if ai.actor.side == Battler.Side.ENEMY else ai.state.alive_enemies()
		var count := own_side.size() if str(args.get("side", "enemies")) == "allies" else other_side.size()
		_result = EventCondition.compare(count, str(args.get("op", ">=")), int(args.get("value", 1)))

	func flow_port() -> String:
		return "true" if _result else "false"


## Branches by chance: "true" [code]chance[/code] percent of the time.
class IfRandom extends EventCommandExec:
	var _result := false

	func start() -> void:
		_result = randf() * 100.0 < float(args.get("chance", 50.0))

	func flow_port() -> String:
		return "true" if _result else "false"


## Picks the target a later [code]use_ability[/code] will aim at, by [code]rule[/code], from
## the living battlers on [code]side[/code] ("enemies" - the other side - by default, or
## "allies"). Rules: first, random, self, lowest_hp, most_hp, lowest_hp_percent, highest_atk,
## highest_def, highest_mag, highest_spd, lowest_spd, lowest_def. A tie goes to the first.
class ChooseTarget extends EventCommandExec:
	func start() -> void:
		var ai := ctx.battle_ai as BattleAI.Context
		if ai == null:
			return

		var candidates: Array[Battler] = []
		if str(args.get("rule", "first")) == "self":
			candidates.append(ai.actor)
		elif str(args.get("side", "enemies")) == "allies":
			candidates = ai.state.alive_enemies() if ai.actor.side == Battler.Side.ENEMY \
				else ai.state.alive_allies()
		else:
			candidates = ai.state.alive_allies() if ai.actor.side == Battler.Side.ENEMY \
				else ai.state.alive_enemies()
		if candidates.is_empty():
			ai.target = null
			return

		match str(args.get("rule", "first")):
			"random":
				ai.target = candidates[randi() % candidates.size()]
			"lowest_hp":
				ai.target = _best(candidates, func(b: Battler) -> float: return -float(b.hp))
			"most_hp":
				ai.target = _best(candidates, func(b: Battler) -> float: return float(b.hp))
			"lowest_hp_percent":
				ai.target = _best(candidates, func(b: Battler) -> float:
					return -float(b.hp) / maxf(1.0, float(b.stats.max_hp)))
			"highest_atk":
				ai.target = _best(candidates, func(b: Battler) -> float: return float(b.stats.atk))
			"highest_def":
				ai.target = _best(candidates, func(b: Battler) -> float: return float(b.stats.def))
			"highest_mag":
				ai.target = _best(candidates, func(b: Battler) -> float: return float(b.stats.mag))
			"highest_spd":
				ai.target = _best(candidates, func(b: Battler) -> float: return float(b.stats.spd))
			"lowest_spd":
				ai.target = _best(candidates, func(b: Battler) -> float: return -float(b.stats.spd))
			"lowest_def":
				ai.target = _best(candidates, func(b: Battler) -> float: return -float(b.stats.def))
			_:
				ai.target = candidates[0]

	## The candidate with the highest [param score]; the first wins a tie.
	static func _best(candidates: Array[Battler], score: Callable) -> Battler:
		var best: Battler = candidates[0]
		var best_score: float = score.call(best)
		for b in candidates:
			var s: float = score.call(b)
			if s > best_score:
				best = b
				best_score = s
		return best


## Ends the graph by deciding the turn: the actor uses [code]ability[/code] (one of its own
## actions, or any registered ability) on the target [code]choose_target[/code] picked - or,
## with none picked, a random legal one. A self-targeting ability ignores the picked target;
## an "all" ability takes no single target.
class UseAbility extends EventCommandExec:
	func start() -> void:
		var ai := ctx.battle_ai as BattleAI.Context
		if ai == null:
			return

		var wanted := StringName(str(args.get("ability", "")))
		var action: Ability = null
		for candidate in ai.actor.abilities:
			if candidate != null and candidate.id == wanted:
				action = candidate
				break
		if action == null:
			action = BattleData.ability(wanted)
		if action == null:
			push_warning("use_ability: '%s' is not one of %s's abilities." % [wanted, ai.actor.display_name])
			return

		var target: Battler = null
		match action.target:
			Ability.Target.SELF:
				target = ai.actor
			Ability.Target.ALL_ENEMIES, Ability.Target.ALL_ALLIES:
				target = null
			_:
				var legal := ai.state._targets_for(ai.actor, action)
				if ai.target != null and legal.has(ai.target):
					target = ai.target
				elif not legal.is_empty():
					target = legal[randi() % legal.size()]
		ai.decision = {"battler": ai.actor, "action": action, "target": target}


static func table() -> Dictionary:
	return {
		"if_round": IfRound,
		"if_stat": IfStat,
		"if_status": IfStatus,
		"if_count": IfCount,
		"if_random": IfRandom,
		"choose_target": ChooseTarget,
		"use_ability": UseAbility,
	}
