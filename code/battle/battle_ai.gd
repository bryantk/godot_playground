class_name BattleAI

## Runs an enemy's AI graph to decide its turn. The graph is an ordinary event graph file
## (built in the graph editor, page 1's [code]graph[/code]) made of the battle commands in
## events/commands/ai_execs.gd - [code]if_round[/code], [code]if_stat[/code],
## [code]if_status[/code], [code]if_count[/code], [code]if_random[/code],
## [code]choose_target[/code] and [code]use_ability[/code] - walked by the same
## [EventRunner] everything else uses. Every one of those is instant, so the whole graph
## runs inside [method decide] and nothing waits on a frame.
##
## [b]The first [code]use_ability[/code] the walk reaches is the turn.[/b] A graph that never
## reaches one (every branch falls through, or the file is missing) decides nothing, and
## [method BattleState._choose_enemy_command] falls back to its old random pick - an
## enemy is never left doing nothing.


## What a running AI graph reads and writes: the fight, whose turn it is, the target
## [code]choose_target[/code] last picked, and - once [code]use_ability[/code] runs - the
## decision, in the shape [method BattleState.resolve_turn] takes a command.
class Context extends RefCounted:
	var state: BattleState
	var actor: Battler
	var target: Battler = null
	var decision: Dictionary = {}

	func _init(a_state: BattleState, a_actor: Battler) -> void:
		state = a_state
		actor = a_actor


## path -> parsed graph nodes. A graph is read from disk once per run of the game.
static var _graphs: Dictionary = {}


## [param actor]'s decision this round, [code]{battler, action, target}[/code], or an empty
## dictionary when it has no AI or its graph did not choose.
static func decide(state: BattleState, actor: Battler) -> Dictionary:
	if actor.enemy == null or actor.enemy.ai_path == "":
		return {}

	var nodes := graph_for(actor.enemy.ai_path)
	if nodes.is_empty():
		return {}

	var context := Context.new(state, actor)
	var event_context := EventContext.for_event(null, &"battle", &"ai", null)
	event_context.battle_ai = context

	var runner := EventRunner.new(event_context)
	runner.begin(nodes)
	if not runner.finished:
		runner.stop()
	return context.decision


## The graph nodes of [param path]'s first page, cached. Empty if the file is missing or
## has no graph.
static func graph_for(path: String) -> Array[Dictionary]:
	if _graphs.has(path):
		return _graphs[path]

	var nodes: Array[Dictionary] = []
	if FileAccess.file_exists(path):
		var document := EventDocument.parse(FileAccess.get_file_as_string(path))
		var pages: Array = document.get("pages", [])
		if not pages.is_empty():
			nodes.assign((pages[0] as Dictionary).get("graph", []))
	_graphs[path] = nodes
	return nodes


## Forget every cached graph - after editing an AI file while a game is running, or between
## tests that write the same path twice.
static func clear_cache() -> void:
	_graphs.clear()
