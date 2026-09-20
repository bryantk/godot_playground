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

	## Where this frame's [member nodes] came from, for [method EventRunner.to_save] /
	## [method EventRunner.restore] to reload fresh from disk rather than trusting a
	## frozen copy - "" for a frame [method EventRunner.begin] was handed a literal
	## array with no file behind it (every headless test today), in which case
	## [member nodes] itself is what gets embedded in the save instead.
	var doc_path: String = ""
	var page_index: int = -1


var ctx: EventContext
var latch: KeyLatch
var finished := false
var error := ""

## Segment 6's opt-out from "background suspends while exclusive is held" - the
## waterfall case (a background effect that must keep going regardless, architecture.md
## §7.5). False for every runner unless the thing that starts it says otherwise.
var keeps_running := false

var _stack: Array[_Frame] = []
var _budget := 0

## The brain this runner suspended on [method begin]/[method restore], if any - see
## [method _take_actor_over]. Tracked here, not by [GameEvent], because a lease only
## ever says who *may* drive an actor; the runner is the thing that actually took over,
## so it is the thing responsible for giving control back, on every path that ends it
## ([method stop], [method _drive]'s own natural finish), not only the happy one a
## caller remembers to unwind.
var _suspended_brain: Brain = null


func _init(a_ctx: EventContext) -> void:
	ctx = a_ctx
	latch = KeyLatch.new()


## Starts running [param nodes] from its one [code]start[/code] node. [param doc_path]/
## [param page_index] are this frame's own save/restore address (empty/[code]-1[/code]
## for a literal graph with no file behind it, e.g. every headless test's own inline
## array) - see [member _Frame.doc_path].
func begin(nodes: Array[Dictionary], doc_path: String = "", page_index: int = -1) -> void:
	if finished:
		return
	_take_actor_over()
	var frame := _Frame.new()
	frame.nodes = nodes
	frame.doc_path = doc_path
	frame.page_index = page_index
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
	_give_actor_back()


## Suspends [member EventContext.self_actor]'s own [Brain] (a patrolling [RouteBrain],
## most obviously) and drops whatever it was already doing - a lease alone never
## stopped either, which is why an actor used to keep walking straight through its own
## event. The motion cancel is deferred: [method begin] can be reached synchronously
## from inside [signal EventBus.actor_stepped], which [GridMotion._commit_step] emits
## *while still running* - a reentrant [method MotionController.cancel] there would
## clear fields that same commit is about to set right back, leaving the sprite stuck
## rather than merely interrupted.
func _take_actor_over() -> void:
	var actor := ctx.self_actor if ctx != null else null
	if actor == null:
		return
	var brain := actor.brain()
	if brain != null:
		brain.suspend(true)
		_suspended_brain = brain
	var motion := actor.motion()
	if motion != null:
		motion.call_deferred(&"cancel")


## The other half of [method _take_actor_over] - always safe to call, including when
## nothing was ever suspended.
func _give_actor_back() -> void:
	if _suspended_brain != null:
		_suspended_brain.suspend(false)
	_suspended_brain = null


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


# -- Save/restore (question 39, segment 5a - restart granularity only) -------------
#
# What a resumable command's own mid-flight progress would add (a move_to's remaining
# cells, a wait's elapsed time) is segment 5b, not built here: this captures which
# frame and which node each frame is on, nothing about what that node's own executor
# was doing. Restoring always restarts whatever node the cursor names - there is no
# live [EventCommandExec] on a freshly built runner for [method _drive] to find, so it
# calls [method EventCommandExec.start] fresh the same way it would for a node reached
# for the first time. [member _Frame.key_aliases] does not survive either, for the same
# reason: it only ever named a *now-gone* executor's own minted key.

## This runner's frame stack, keyed for [method restore] to rebuild - identity
## ([member EventContext.map_id]/[member EventContext.event_id]) and
## [member EventContext.self_actor]'s id travel too, since [EventContext] itself is
## never serialised (question 51: the live [MapContext] reference has to be re-supplied
## by whoever is restoring, not saved).
func to_save() -> Dictionary:
	var frames: Array = []
	for frame: _Frame in _stack:
		frames.append({
			"doc_path": frame.doc_path,
			"page_index": frame.page_index,
			"doc_hash": EventCommand.doc_hash(frame.nodes),
			# Embedded only when there is no file to reload from - see _Frame's own doc.
			"nodes": frame.nodes.duplicate(true) if frame.doc_path == "" else [],
			"cursor": frame.cursor,
		})
	return {
		"map_id": str(ctx.map_id) if ctx != null else "",
		"event_id": str(ctx.event_id) if ctx != null else "",
		"self_actor_id": str(ctx.self_actor.actor_id) if ctx != null and ctx.self_actor != null else "",
		"keeps_running": keeps_running,
		"frames": frames,
	}


## Rebuilds a runner from [method to_save]'s envelope. [param map] is the live map to
## resolve [code]self_actor_id[/code] and, for a doc-backed frame, to evaluate against
## nothing at all - reloading a page's graph needs only the file and the saved page
## index, not the map - but a caller with no live actor to hand back (the actor is
## gone) still gets a runner, just one with a null [member EventContext.self_actor],
## the same as a bodiless region trigger's ever was.
static func from_save(state: Dictionary, map: MapContext) -> EventRunner:
	var actor_id := StringName(str(state.get("self_actor_id", "")))
	var self_actor: Actor = map.actor(actor_id) if map != null and actor_id != &"" else null
	var new_ctx := EventContext.for_event(map, StringName(str(state.get("map_id", ""))),
		StringName(str(state.get("event_id", ""))), self_actor)

	var runner := EventRunner.new(new_ctx)
	runner.keeps_running = bool(state.get("keeps_running", false))
	runner.restore(state.get("frames", []))
	return runner


## Rebuilds [member _stack] from [method to_save]'s [code]frames[/code] array and picks
## the run back up. A doc-backed frame is reloaded from disk, never trusted from the
## save itself, so an edit made to the file since the save was taken is what the
## restored run actually sees; [constant EventCommand.doc_hash] is what decides whether
## that reload still matches what was captured (resume at the saved cursor) or has
## drifted (restart this one frame from its own entry - "restart is always a legal
## downgrade", question 39). A frame whose document or page has gone missing entirely
## restarts the same way a hash mismatch does, rather than being dropped.
func restore(frames: Array) -> void:
	for entry: Variant in frames:
		var saved: Dictionary = entry
		var doc_path := str(saved.get("doc_path", ""))
		var page_index := int(saved.get("page_index", -1))
		var cursor := str(saved.get("cursor", ""))
		var nodes: Array[Dictionary] = []

		if doc_path == "":
			for n: Variant in saved.get("nodes", []) as Array:
				if n is Dictionary:
					nodes.append(n as Dictionary)
		else:
			var doc := EventDocument.parse(FileAccess.get_file_as_string(doc_path))
			var pages: Array = doc.get("pages", [])
			if page_index >= 0 and page_index < pages.size():
				nodes = (pages[page_index] as Dictionary).get("graph", [])
			if EventCommand.doc_hash(nodes) != str(saved.get("doc_hash", "")):
				cursor = ""  # _drive() re-finds the start node when cursor is empty

		var frame := _Frame.new()
		frame.nodes = nodes
		frame.doc_path = doc_path
		frame.page_index = page_index
		frame.cursor = cursor
		for n in nodes:
			frame.by_id[str(n.get("id", ""))] = n
		_stack.append(frame)

	_take_actor_over()
	_budget = NODE_BUDGET
	_drive()


# -- The trampoline ----------------------------------------------------------------
#
# One loop, not a chain of methods calling each other back - see the class doc.

func _drive() -> void:
	while true:
		if _stack.is_empty():
			finished = true
			latch.detach()
			_give_actor_back()
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
	new_frame.doc_path = path
	new_frame.page_index = index
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
