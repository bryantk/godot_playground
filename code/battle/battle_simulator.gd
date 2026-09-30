class_name BattleSimulator

## Monte-Carlo battle estimator - runs many independent fake fights with a simple auto
## strategy on both sides and tallies the outcome, so "what are my odds against this
## troop" is a number rather than a guess from hand-testing one fight at a time. What
## battle/battle_sandbox.tscn drives to give an estimated chance of victory.
##
## [b]Never touches real data.[/b] [method Battler.for_member] only reads a member's
## current hp/mp; nothing here ever calls [method Battler.sync_to_member], so a
## simulated fight cannot leak damage back onto the roster it borrowed stats from -
## the same reasoning that method's own doc gives for when it *should* be called.

## A fight that has not resolved either way by this many rounds counts as a draw
## rather than looping forever - two sides that can never actually kill each other
## (0 damage both ways) is a real, if degenerate, composition to be able to test.
const MAX_ROUNDS := 50


## Runs [param trials] independent fights of [param members] against a fresh copy of
## [param troop] each time, both sides using [method _auto_player_commands]/
## [method BattleState._choose_enemy_command]'s own simple AI - no player input.
## Returns [code]{trials, wins, losses, draws, win_rate, avg_rounds}[/code].
static func simulate(members: Array[PartyMember], troop: Troop, trials: int = 200) -> Dictionary:
	var wins := 0
	var draws := 0
	var round_total := 0

	for i in trials:
		var state := BattleState.new()
		state.begin(members, troop)

		var rounds := 0
		while not state.is_over() and rounds < MAX_ROUNDS:
			state.resolve_turn(_auto_player_commands(state))
			rounds += 1
		round_total += rounds

		if state.is_victory():
			wins += 1
		elif not state.is_defeat():
			draws += 1

	return {
		"trials": trials,
		"wins": wins,
		"losses": trials - wins - draws,
		"draws": draws,
		"win_rate": float(wins) / float(trials) if trials > 0 else 0.0,
		"avg_rounds": float(round_total) / float(trials) if trials > 0 else 0.0,
	}


## The "auto battle strategy": every living ally attacks (falling back to its first
## action, if any) whichever living enemy currently has the least hp - focus-fire,
## the simplest thing that is not literally random and still gives a stable, comparable
## estimate from one trial to the next.
static func _auto_player_commands(state: BattleState) -> Array[Dictionary]:
	var commands: Array[Dictionary] = []
	var enemies := state.alive_enemies()
	if enemies.is_empty():
		return commands

	for ally in state.alive_allies():
		commands.append({
			"battler": ally,
			"action": _best_attack(ally),
			"target": _weakest(enemies),
		})
	return commands


static func _best_attack(ally: Battler) -> Ability:
	for action in ally.abilities:
		if action.kind == Ability.Kind.ATTACK:
			return action
	return ally.abilities[0] if not ally.abilities.is_empty() else Ability.new()


static func _weakest(pool: Array[Battler]) -> Battler:
	var best := pool[0]
	for b in pool:
		if b.hp < best.hp:
			best = b
	return best
