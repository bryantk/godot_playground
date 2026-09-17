## Flow-control executors: [code]start[/code], [code]wait[/code], [code]if[/code],
## [code]ask[/code], [code]wait_for[/code].
##
## [code]goto[/code], [code]label[/code] and [code]end[/code] need no executor -
## [method EventCommandExec.flow_port]'s default of [code]"next"[/code] plus a node's
## own wiring already does their whole job, and a zero-port command terminates its
## frame generically in [EventRunner]. [code]call[/code]/[code]exit_call[/code] are
## handled directly by [EventRunner] since they touch its call stack.


## The node every graph begins at. No work of its own - existing at all is the point
## ([method EventCommand.validate_reachability]'s anchor).
class Start extends EventCommandExec:
	pass


## Pauses for [code]seconds[/code]. RESUME_STATE: captures the remainder and resumes
## there, per question 39. Collapses instantly under debug fast-forward (question 48) -
## a wait has no end state to preserve, so there is nothing to snap to but done.
class Wait extends EventCommandExec:
	var _left := 0.0

	func start() -> void:
		_left = float(args.get("seconds", 0.0))

	func tick(delta: float) -> int:
		if DebugFlags.is_fast_forward():
			return Status.DONE
		_left -= delta
		return Status.DONE if _left <= 0.0 else Status.RUNNING

	func resumable() -> bool:
		return true

	func capture() -> Dictionary:
		return {"left": _left}

	func restore(state: Dictionary) -> void:
		_left = float(state.get("left", 0.0))


## Branches on [code]condition[/code], a [EventCondition] expression string - question
## 16's grammar, shared with a page's own [code]conditions[/code] (question 50).
class If extends EventCommandExec:
	var _result := false

	func start() -> void:
		var parsed := EventCondition.parse_expression(str(args.get("condition", "")))
		_result = EventCondition.evaluate(parsed.get("tree", {}), ctx.condition_ctx())

	func flow_port() -> String:
		return "true" if _result else "false"


## Presents [code]choices[/code] as flow ports.
##
## [b]Known gap, named rather than papered over:[/b] there is no choice-selection
## channel yet, only [signal EventBus.dialogue_finished]'s bare key - so this always
## takes the first choice once the window closes. Enough to make an authored
## [code]ask[/code] node completable and testable mechanically until real choice UI
## exists to report which one was picked.
class Ask extends EventCommandExec:
	var _key := ""

	func start() -> void:
		var text := str(args.get("text", ""))
		var choices: Array = args.get("choices", [])
		_key = EventBus.say(text, {"choices": choices})

	func tick(_delta: float) -> int:
		return Status.DONE if runner.latch.consume(_key) else Status.RUNNING

	func flow_port() -> String:
		var choices: Array = args.get("choices", [])
		return str(choices[0]) if not choices.is_empty() else "next"

	func cancel() -> void:
		if _key != "":
			runner.latch.consume(_key)


## Pauses until [code]key[/code] - authored by some other node's own [code]key[/code]
## field - resolves. [method EventCommand.validate_graph] already catches a key nothing
## in the graph produces at author time.
class WaitFor extends EventCommandExec:
	var _key := ""

	func start() -> void:
		_key = runner.resolve_key(str(args.get("key", "")))

	func tick(_delta: float) -> int:
		return Status.DONE if runner.latch.consume(_key) else Status.RUNNING


static func table() -> Dictionary:
	return {
		"start": Start,
		"wait": Wait,
		"if": If,
		"ask": Ask,
		"wait_for": WaitFor,
	}
