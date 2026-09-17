## Dialogue executors: [code]say[/code], [code]append_say[/code].
##
## [code]close_window[/code] has no executor yet - there is no force-close hook on
## [EventBus] or the dialogue window today, only the read-through-it flow [code]say[/code]
## already drives. Left to the generic fallback (report and carry on) until one exists.


## Shows a line of dialogue via [method EventBus.say] and waits for [signal
## EventBus.dialogue_finished] through the runner's [KeyLatch] - never by awaiting the
## signal directly (segment 4's rule).
class Say extends EventCommandExec:
	var _key := ""

	func start() -> void:
		var options := {}
		if args.has("location"):
			options["location"] = args["location"]
		_key = EventBus.say(str(args.get("text", "")), options)

	func tick(_delta: float) -> int:
		return Status.DONE if runner.latch.consume(_key) else Status.RUNNING

	func cancel() -> void:
		if _key != "":
			runner.latch.consume(_key)


## Adds another line to the open window - the same wait, with [code]append: true[/code]
## so the window does not run its intro/outro between the two.
class AppendSay extends EventCommandExec:
	var _key := ""

	func start() -> void:
		var options := {}
		if args.has("location"):
			options["location"] = args["location"]
		_key = EventBus.append_say(str(args.get("text", "")), options)

	func tick(_delta: float) -> int:
		return Status.DONE if runner.latch.consume(_key) else Status.RUNNING

	func cancel() -> void:
		if _key != "":
			runner.latch.consume(_key)


static func table() -> Dictionary:
	return {
		"say": Say,
		"append_say": AppendSay,
	}
