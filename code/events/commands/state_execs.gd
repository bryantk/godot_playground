## State executors: [code]set_flag[/code], [code]set_self_flag[/code],
## [code]set_var[/code], [code]add_var[/code], [code]eval_var[/code],
## [code]halt_control[/code], [code]return_control[/code], [code]print_debug[/code],
## [code]set_fast_forward[/code]. All non-blocking and complete synchronously -
## [GameState], [ModeStack] and [DebugFlags] are all global autoloads, so there is
## nothing to wait on, and [code]print_debug[/code] only ever talks to the console.


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
		# The A-D dropdown, when picked, is the flag's name; unset, the "flag" field is.
		var flag_name := str(args.get("slot", ""))
		if flag_name == "":
			flag_name = str(args.get("flag", ""))
		if flag_name == "":
			push_warning("set_self_flag: pick a slot (A-D) or give a flag name.")
			return
		GameState.set_self_flag(ctx.map_id, ctx.event_id, StringName(flag_name),
			bool(args.get("value", true)))


## Sets a declared variable to a value.
class SetVar extends EventCommandExec:
	func start() -> void:
		GameState.var_set(StringName(str(args.get("var", ""))), args.get("value", 0.0))


## Adds to a declared variable.
class AddVar extends EventCommandExec:
	func start() -> void:
		GameState.var_add(StringName(str(args.get("var", ""))), float(args.get("delta", 0.0)))


## Sets a declared variable to the result of an expression - the same "{v}" template
## [code]variable[/code] (flow_execs.gd) branches on, "var"'s own name substituted into
## it before parsing, except this commits the result as the variable's new value
## instead of taking a flow port over it. [EventCondition.evaluate] only ever returns a
## bool, so that is the shape a variable set this way ends up holding - "{v}" can read
## its own current value in the expression (a self-referential toggle, "not {v}") the
## same way it reads any other declared variable or flag.
class EvalVar extends EventCommandExec:
	func start() -> void:
		var var_name := str(args.get("var", ""))
		var expression := str(args.get("expression", "")).replace("{v}", var_name)
		var parsed := EventCondition.parse_expression(expression)
		var result := EventCondition.evaluate(parsed.get("tree", {}), ctx.condition_ctx())
		GameState.var_set(StringName(var_name), result)


## Disables player input by pushing [constant ModeStack.Mode.CUTSCENE] - the same mode
## the exclusive slot itself pushes, so [method PlayerController._think]'s
## [code]not ModeStack.is_field()[/code] check needs no second case. A bare push: see
## [method EventCommand] segment "Input" for the pairing this is meant to hold up its
## end of.
class HaltControl extends EventCommandExec:
	func start() -> void:
		ModeStack.push(ModeStack.Mode.CUTSCENE)


## Re-enables player input by popping one mode - the [method HaltControl] this is
## meant to pair with, or a [code]lock_player[/code] page's own push if this is what
## an author reaches for instead of just letting the page's run end.
class ReturnControl extends EventCommandExec:
	func start() -> void:
		ModeStack.pop()


## Prints [code]text[/code] to the console and nowhere else - no dialogue window, no
## [GameState], nothing a save round-trips. For watching a graph run in a build with no
## debugger attached, or an event with no visual at all to eyeball instead.
class PrintDebug extends EventCommandExec:
	func start() -> void:
		print(str(args.get("text", "")))


## Forces [member DebugFlags.force_fast_forward] on/off from a graph - the same escape
## hatch backtick/key 0 hold for a human, driven by an authored graph instead (a QA
## smoke-test skipping a stretch already known safe, a long intro nobody needs to sit
## through twice while testing). "enabled" defaults true, matching [code]set_flag[/code]'s
## own "a bare command means turn it on" convention. Left set until something else
## changes it - [member DebugFlags._process] only ever clears what its own key 0 hold
## set, never this.
class SetFastForward extends EventCommandExec:
	func start() -> void:
		DebugFlags.force_fast_forward = bool(args.get("enabled", true))


static func table() -> Dictionary:
	return {
		"set_flag": SetFlag,
		"set_self_flag": SetSelfFlag,
		"set_var": SetVar,
		"add_var": AddVar,
		"eval_var": EvalVar,
		"halt_control": HaltControl,
		"return_control": ReturnControl,
		"print_debug": PrintDebug,
		"set_fast_forward": SetFastForward,
	}
