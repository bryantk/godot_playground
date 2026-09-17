class_name EventRunner extends RefCounted

## Walks one page's compiled graph, node by node. [EventScheduler] owns the one clock
## and calls [method tick] in a fixed order; this has no [code]_process[/code] of its
## own, and never [code]await[/code]s (segment 4's rule) - a blocking node's executor
## is polled through [method tick] instead, against the runner's own [KeyLatch].
##
## [b]Iterative, not recursive.[/b] Advancing from one node to the next - including a
## [code]goto[/code]/[code]label[/code] chain, or a [code]call[/code] frame's own
## [code]start[/code] - happens inside [method _drive]'s loop, never by one of these
## methods calling another that calls it back. A [code]goto[/code] cycle can otherwise
## run [constant NODE_BUDGET] node entries deep as real, nested GDScript call frames
## before the budget even trips - which is a stack overflow waiting to be the thing
## that actually stops it, not the budget.
##
## [b]A non-blocking node[/b] ([method EventCommand.is_blocking] false, either by the
## command's own default or a node's override) starts its executor and moves straight
## on to [code]next[/code] without waiting - the underlying work (a mover's own
## [code]_process[/code], say) keeps going on its own clock regardless of where the
## graph has since walked to. A later [code]wait_for[/code] can still join it by the
## node's own authored [code]key[/code], aliased to whatever real key the executor
## minted - see [member _Frame.key_aliases].
##
## [b][code]call[/code] and [code]exit_call[/code][/b] (question 49) are handled here
## directly rather than through [EventCommandExec]: [code]call[/code] clones its target
## page's graph and pushes it as a new frame on [member _stack]; reaching that frame's
## [code]end[/code] (any node with zero flow ports) pops back to the call site's own
## [code]next[/code]; [code]exit_call[/code] pops the most-nested frame early. Neither
## touches [EventContext] - identity stays whoever originally triggered this runner.

## A goto/label cycle guard: at most this many node entries per outer [method _drive]
## call. A legitimate chain of non-blocking nodes between two blocking commands never
## comes close; a real cycle hits it fast, and [member error] names the node it was on.
const NODE_BUDGET := 1000

## A call cycle is a separate, smaller guard from the node budget above, so the error
## reports it as a call cycle rather than a generic budget overrun many frames later.
const CALL_DEPTH_BUDGET := 32


class _Frame:
	var nodes: Array[Dictionary] = []
	var by_id: Dictionary = {}
	var cursor: String = ""
	var exec: EventCommandExec = null
	## Authored node "key" -> the real key its executor minted, for a non-blocking
	## node a later wait_for in the same graph wants to join.
	var key_aliases: Dictionary = {}


var ctx: EventContext
var latch: KeyLatch
var finished := false
var error := ""

var _stack: Array[_Frame] = []
var _budget := 0


func _init(a_ctx: EventContext) -> void:
	ctx = a_ctx
	latch = KeyLatch.new()


## Starts running [param nodes] from its one [code]start[/code] node.
func begin(nodes: Array[Dictionary]) -> void:
	if finished:
		return
	var frame := _Frame.new()
	frame.nodes = nodes
	for n in nodes:
		frame.by_id[str(n.get("id", ""))] = n
	_stack.append(frame)
	_budget = NODE_BUDGET
	_drive()


## Interrupted from outside - a lease, a scheduler shutting down. Cancels whatever the
## current frame's node is mid-executing so it cannot leave a key outstanding forever
## (the same invariant the four motion-key fixes exist to uphold), then drops every
## frame on the stack.
func stop() -> void:
	if not _stack.is_empty():
		var frame := _stack.back() as _Frame
		if frame.exec != null:
			frame.exec.cancel()
	_stack.clear()
	finished = true
	latch.detach()


## Called by [EventScheduler] once per its own clock tick.
func tick(delta: float) -> void:
	if finished or _stack.is_empty():
		finished = true
		return

	var frame := _stack.back() as _Frame
	if frame.exec == null:
		return

	if frame.exec.tick(delta) != EventCommandExec.Status.DONE:
		return

	var ex := frame.exec
	frame.exec = null
	_advance_cursor(frame, ex.flow_port())

	_budget = NODE_BUDGET
	_drive()


## The real key [param authored_name] aliases to in the current frame, or itself
## unchanged if nothing registered one - see [member _Frame.key_aliases].
func resolve_key(authored_name: String) -> String:
	if _stack.is_empty():
		return authored_name
	var frame := _stack.back() as _Frame
	return str(frame.key_aliases.get(authored_name, authored_name))


# -- The trampoline ----------------------------------------------------------------
#
# One loop, not a chain of methods calling each other back - see the class doc.

func _drive() -> void:
	while true:
		if _stack.is_empty():
			finished = true
			latch.detach()
			return

		var frame := _stack.back() as _Frame

		# Blocked on an in-flight blocking executor - wait for the next tick() to
		# resume this loop.
		if frame.exec != null:
			return

		if frame.cursor == "":
			var start_id := _find_start(frame)
			if start_id == "":
				# An empty or malformed graph (event-pages.md §2's route-only page
				# has nothing to reach). Nothing to run.
				_stack.pop_back()
				continue
			frame.cursor = start_id

		_budget -= 1
		if _budget <= 0:
			_fail("Node budget exceeded at \"%s\" - a goto/label cycle with nothing to stop it."
				% frame.cursor)
			return

		var n: Dictionary = frame.by_id.get(frame.cursor, {})
		var name := str(n.get("command", ""))

		if name == "call":
			if not _begin_call(frame, n):
				return  # _fail() already stopped the runner
			continue

		if name == "exit_call":
			_pop_frame()
			continue

		var ex := EventCommandExec.create(name)
		if ex == null:
			# No executor for this command yet, or the command is unknown outright -
			# both repair-and-carry-on, matching event_command.gd's own parse contract.
			_advance_cursor(frame, "next")
			continue

		var coerced := _coerce_args(name, n)
		ex.setup(n, coerced, ctx, self)
		ex.start()

		var authored_key := str(n.get("key", ""))
		if authored_key != "" and ex.own_key() != "":
			frame.key_aliases[authored_key] = ex.own_key()

		if not EventCommand.is_blocking(n):
			# Fire and forget: the work keeps going on its own clock (a mover's own
			# _process), and the graph does not wait for it.
			_advance_cursor(frame, ex.flow_port())
			continue

		if ex.tick(0.0) == EventCommandExec.Status.DONE:
			_advance_cursor(frame, ex.flow_port())
			continue

		frame.exec = ex
		return


## Moves [param frame]'s cursor to whichever node [param port] targets, or pops the
## frame when the current node has no matching port (including a zero-port command
## like [code]end[/code], which terminates its frame generically regardless of name).
func _advance_cursor(frame: _Frame, port: String) -> void:
	var node: Dictionary = frame.by_id.get(frame.cursor, {})
	if EventCommand.flows_of(node).is_empty():
		_pop_frame()
		return

	var target := _target_for(node, port)
	if target == "" or not frame.by_id.has(target):
		_pop_frame()
		return

	frame.cursor = target


## Drops the top frame and, if it was a called sub-frame, resumes whatever is beneath
## it at its own [code]call[/code] node's [code]"next"[/code] port - the frame that
## pushed it just finished, from the caller's point of view. Without this, a call
## frame popping just re-exposes the caller sitting on its own unresolved [code]call[/code]
## node, which the trampoline would re-enter and push right back - an infinite loop
## that looks like a cycle but is really a missing resume.
func _pop_frame() -> void:
	_stack.pop_back()
	if _stack.is_empty():
		return
	_advance_cursor(_stack.back() as _Frame, "next")


func _find_start(frame: _Frame) -> String:
	for id: Variant in frame.by_id:
		if str((frame.by_id[id] as Dictionary).get("command", "")) == EventCommand.START_COMMAND:
			return str(id)
	return ""


func _target_for(node: Dictionary, port: String) -> String:
	for output: Variant in node.get("outputs", []) as Array:
		if output is Dictionary and str((output as Dictionary).get("flow", "")) == port:
			return str((output as Dictionary).get("target", ""))
	return ""


func _fail(message: String) -> void:
	error = message
	push_error("EventRunner: %s" % message)
	stop()


# -- call --------------------------------------------------------------------------
#
# Pushes a new frame; the outer _drive loop picks it up on its next iteration (its
# cursor is "", so the loop finds its start node exactly like any other fresh frame).
# exit_call above needs no counterpart here - it just pops, handled inline in _drive.

func _begin_call(frame: _Frame, node: Dictionary) -> bool:
	if _stack.size() >= CALL_DEPTH_BUDGET:
		_fail("Call depth exceeded at \"%s\" - a call cycle with nothing to stop it."
			% str(node.get("id", "")))
		return false

	var call_args: Dictionary = node.get("args", {})
	var path := str(call_args.get("document", ""))
	var doc := EventDocument.parse(FileAccess.get_file_as_string(path))
	var pages: Array = doc.get("pages", [])
	var index := EventDocument.active_page(pages, ctx.condition_ctx())
	if index < 0:
		# No page passes - nothing to run. Same as an empty graph: carry straight on.
		_advance_cursor(frame, "next")
		return true

	var page: Dictionary = pages[index]
	var graph: Array = page.get("graph", [])

	# Deep-copied, not referenced (question 49): two actors calling into the same
	# shared subroutine each get their own private copy, so nothing about running one
	# is observable from or mutable by the other's.
	var cloned: Array[Dictionary] = []
	for n: Variant in graph:
		cloned.append((n as Dictionary).duplicate(true))

	var new_frame := _Frame.new()
	new_frame.nodes = cloned
	for n in cloned:
		new_frame.by_id[str(n.get("id", ""))] = n
	_stack.append(new_frame)
	return true


# -- Argument coercion -------------------------------------------------------------

## A node's [code]args[/code] as authored are raw JSON shapes - [code]graph_document.gd[/code]
## never coerces them, only [method EventCommand.parse_command] does (for the dock's
## Validate pass). Reusing that exact coercion here means an executor sees the same
## typed value (a [Vector3i], a resolved turn) the validator already checked it
## against, rather than a second, ad hoc reading of the same schema.
func _coerce_args(name: String, node: Dictionary) -> Dictionary:
	var found: Array[String] = []
	var normalised := EventCommand.parse_command(
		{"command": name, "args": (node.get("args", {}) as Dictionary).duplicate(true)},
		found)
	return normalised.get("args", {})
