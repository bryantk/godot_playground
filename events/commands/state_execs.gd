## State executors: [code]set_flag[/code], [code]set_self_flag[/code],
## [code]set_var[/code], [code]add_var[/code]. All non-blocking and complete
## synchronously - [GameState] is a global autoload, so there is nothing to wait on.


## Sets a global flag. [code]value[/code] defaults to true, matching a bare "set_flag"
## meaning "turn it on" the way an author expects.
class SetFlag extends EventCommandExec:
	func start() -> void:
		GameState.set_flag(StringName(str(args.get("flag", ""))), bool(args.get("value", true)))


## Sets a flag scoped to this event - question 51's identity, never the map the runner
## happens to be standing on right now, so a call (question 49) or a change_map both
## leave this pointed at whoever originally triggered the runner.
class SetSelfFlag extends EventCommandExec:
	func start() -> void:
		GameState.set_self_flag(ctx.map_id, ctx.event_id,
			StringName(str(args.get("flag", ""))), bool(args.get("value", true)))


## Sets a declared variable to a value.
class SetVar extends EventCommandExec:
	func start() -> void:
		GameState.var_set(StringName(str(args.get("var", ""))), args.get("value", 0.0))


## Adds to a declared variable.
class AddVar extends EventCommandExec:
	func start() -> void:
		GameState.var_add(StringName(str(args.get("var", ""))), float(args.get("delta", 0.0)))


static func table() -> Dictionary:
	return {
		"set_flag": SetFlag,
		"set_self_flag": SetSelfFlag,
		"set_var": SetVar,
		"add_var": AddVar,
	}
