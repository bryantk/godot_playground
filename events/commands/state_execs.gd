## State executors: [code]set_flag[/code], [code]set_self_flag[/code],
## [code]set_var[/code], [code]add_var[/code], [code]halt_control[/code],
## [code]return_control[/code], [code]print_debug[/code]. All non-blocking and complete
## synchronously - [GameState] and [ModeStack] are both global autoloads, so there is
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


static func table() -> Dictionary:
	return {
		"set_flag": SetFlag,
		"set_self_flag": SetSelfFlag,
		"set_var": SetVar,
		"add_var": AddVar,
		"halt_control": HaltControl,
		"return_control": ReturnControl,
		"print_debug": PrintDebug,
	}
