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
##
## [b][code]define_route[/code][/b] is handled here too, for the same reason: it sets a
## frame's own state ([member _Frame.route_scope]), which nothing outside this file has
## a reference to. It is not scoped by any explicit close - the policy it sets ([member
## _Frame.route_scope]'s own "blocked" target, read off the node's own wiring rather
## than an ordinary flow) stays in effect for every node the graph walks afterward until
## the next [code]define_route[/code] it reaches replaces it (looping back to the same
## node, most often). [method _resolve_finished_node] is where it actually does
## anything: a blocking command that reports [method EventCommandExec.was_blocked] true
## while a policy is set either retries (one scheduler tick of nothing via [class
## _RouteRetryPause], then the very same node fresh) when "blocked" is left unwired, or
## jumps straight to whatever "blocked" does name, skipping whatever "next" it would
## otherwise have taken - instead of silently walking "next" as if the move had
## succeeded, which is what a hand-wired patrol loop of ordinary [code]move_by[/code]
## nodes did before this existed (a permanently blocked back-and-forth trips [constant
## NODE_BUDGET] in a single tick, since a refused move finishes with no time elapsed at
## all).

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

	## Segment 5b: a resumable executor's own [method EventCommandExec.capture] result,
	## set by [method EventRunner.restore] and consumed the next time [method
	## EventRunner._drive] reaches [member cursor] - [method EventCommandExec.restore]
	## is called instead of [method EventCommandExec.start] exactly once, for exactly
	## that node, then this clears. Never set on a frame that restarted from a hash
	## mismatch - there is no guarantee the node at that cursor is even the same command
	## any more.
	var pending_restore: bool = false
	var pending_exec_state: Dictionary = {}

	## The [code]define_route[/code] policy currently active in this frame - empty
	## before the first one the graph reaches, replaced (not stacked) by every
	## [code]define_route[/code] after that, including one that loops back to itself.
	## [code]{"blocked_target": String}[/code] - "" when "blocked" was left unwired
	## (retry), a node id otherwise. See the class doc and [method
	## EventRunner._resolve_finished_node].
	var route_scope: Dictionary = {}

	## The executor a retry pause is waiting to retry - kept alive across the pause
	## rather than discarded, so [method EventCommandExec.retry] retries toward the
	## same target it already committed to (a partly-completed [code]move_by[/code]'s
	## own [member EventCommandExec.was_blocked] target, not a fresh one re-derived from
	## wherever the actor ended up short of it - see that method's own doc on why a
	## relative move cannot simply be re-started from scratch). Null whenever [member
	## exec] is not [class _RouteRetryPause].
	var retry_exec: EventCommandExec = null


## One scheduler tick of nothing - what a blocked move retries after, when the active
## [code]define_route[/code] policy leaves "blocked" unwired. Never reached through
## [method EventCommandExec.create] (it names no command of its own), and never
## advances a frame's cursor the way an ordinary finished executor does - [method
## tick]'s own check for it hands off to [method _retry_after_pause] instead of reading
## it as an ordinary completed command and walking its (nonexistent) "next" port. The
## blocked executor itself waits out the pause in [member _Frame.retry_exec], not
## discarded - see [method EventCommandExec.retry]'s own doc for why retrying has to
## mean asking that same instance to try again, not re-dispatching the node fresh.
class _RouteRetryPause extends EventCommandExec:
	func tick(_delta: float) -> int:
		return Status.DONE


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

## The [PlayerController] this runner suspended on [method begin]/[method restore], if
## any - see [method _take_actor_over]. Tracked here, not by [GameEvent], because a
## lease only ever says who *may* drive an actor; the runner is the thing that actually
## took over, so it is the thing responsible for giving control back, on every path
## that ends it ([method stop], [method _drive]'s own natural finish), not only the
## happy one a caller remembers to unwind.
var _suspended_controller: PlayerController = null


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
	_suspend_actor_controller()
	_cancel_actor_prior_motion()
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


## Suspends [member EventContext.self_actor]'s own [PlayerController], if it has one -
## a lease alone never stopped it, which is why an actor used to keep walking straight
## through its own event. Called from both [method begin] and [method restore]:
## either way this runner is taking the actor over.
func _suspend_actor_controller() -> void:
	var actor := ctx.self_actor if ctx != null else null
	if actor == null:
		return
	var controller := actor.player_controller()
	if controller != null:
		controller.suspend(true)
		_suspended_controller = controller


## Drops whatever motion the actor was already mid-flight on *before* this runner took
## over - [method begin] only, never [method restore]: a restore's own
## [method MotionController.from_save] (segment 5b) is what re-establishes this
## runner's *own* prior motion, and cancelling would erase the very state about to be
## written back into it.
##
## Deferred: [method begin] can be reached synchronously from inside [signal
## EventBus.actor_stepped], which [GridMotion._commit_step] emits *while still
## running* - a reentrant [method MotionController.cancel] there would clear fields
## that same commit is about to set right back, leaving the sprite stuck rather than
## merely interrupted.
func _cancel_actor_prior_motion() -> void:
	var actor := ctx.self_actor if ctx != null else null
	if actor == null:
		return
	var motion := actor.motion()
	if motion != null:
		motion.call_deferred(&"cancel")


## The other half of [method _suspend_actor_controller] - always safe to call, including when
## nothing was ever suspended.
func _give_actor_back() -> void:
	if _suspended_controller != null:
		_suspended_controller.suspend(false)
	_suspended_controller = null


## Called by [EventScheduler] once per its own clock tick.
func tick(delta: float) -> void:
	if finished or _stack.is_empty():
		finished = true
		return

	var frame := _stack.back() as _Frame
	if frame.exec == null:
		return

	if frame.exec is _RouteRetryPause:
		_retry_after_pause(frame)
		return

	if frame.exec.tick(delta) != EventCommandExec.Status.DONE:
		return

	var ex := frame.exec
	frame.exec = null
	if not _resolve_finished_node(frame, ex):
		return  # _resolve_finished_node queued another retry pause - nothing more this tick

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
	for i in _stack.size():
		var frame: _Frame = _stack[i]
		var entry := {
			"doc_path": frame.doc_path,
			"page_index": frame.page_index,
			"doc_hash": EventCommand.doc_hash(frame.nodes),
			# Embedded only when there is no file to reload from - see _Frame's own doc.
			"nodes": frame.nodes.duplicate(true) if frame.doc_path == "" else [],
			"cursor": frame.cursor,
			"route_scope": frame.route_scope.duplicate(true),
		}
		# Only the top frame can ever have a live executor - every frame beneath it is
		# a suspended caller sitting on its own already-resolved "call" node, waiting
		# for the frame above to pop back to it (see _pop_frame).
		if i == _stack.size() - 1 and frame.exec != null and frame.exec.resumable():
			entry["exec_state"] = frame.exec.capture()
		frames.append(entry)
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

		# Segment 5b: a resumable executor's own capture, only ever present when the
		# cursor above wasn't just reset by a hash mismatch - see _Frame.pending_restore.
		if cursor != "" and saved.has("exec_state"):
			frame.pending_restore = true
			frame.pending_exec_state = saved["exec_state"]

		# Same reasoning, one level up: a policy named by a graph that has since changed
		# shape (the hash mismatch above) is not trustworthy either - its own
		# blocked_target id might not even exist in the reloaded graph any more.
		if cursor != "" and saved.get("route_scope", {}) is Dictionary:
			frame.route_scope = (saved["route_scope"] as Dictionary).duplicate(true)

		_stack.append(frame)

	_suspend_actor_controller()
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
			var start_id: Variant = _find_start(frame)
			if start_id == null:
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
		# doc_path == "" is a route (GameEvent._start_route() always calls
		# run_background with no document behind it, since a route is compiled
		# separately from a page's own triggered graph) - autonomous patrolling that
		# starts and keeps going for as long as the page is active, not an event worth
		# a console line of its own. A doc-backed frame is a triggered run instead
		# (player_touch, action, ...), which still gets logged.
		if name == EventCommand.START_COMMAND and frame.doc_path != "":
			_log_node_process(frame)

		if name == "call":
			if not _begin_call(frame, n):
				return  # _fail() already stopped the runner
			continue

		if name == "exit_call":
			_pop_frame()
			continue

		if name == "define_route":
			_set_route_policy(frame, n)
			continue

		var ex := EventCommandExec.create(name)
		if ex == null:
			# No executor for this command yet, or the command is unknown outright -
			# both repair-and-carry-on, matching event_command.gd's own parse contract.
			_advance_cursor(frame, "next")
			continue

		var coerced := _coerce_args(name, n)
		ex.setup(n, coerced, ctx, self)
		if frame.pending_restore:
			# Segment 5b: this is the one node a restore is picking back up mid-flight -
			# restore() instead of start(), and only ever once per frame.
			frame.pending_restore = false
			ex.restore(frame.pending_exec_state)
			frame.pending_exec_state = {}
		else:
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
			if not _resolve_finished_node(frame, ex):
				return  # queued a retry pause - _drive() picks back up next real tick
			continue

		frame.exec = ex
		return


## One line per run, at its start node only: time, the parent node (this runner's own
## event) name, which page is running, and the trigger that started it.
func _log_node_process(frame: _Frame) -> void:
	var page := "%s#%d" % [frame.doc_path, frame.page_index] if frame.doc_path != "" else "<inline>"
	print("[%d] event=%s page=%s action=%s"
		% [Time.get_ticks_msec(), str(ctx.self_actor.get_parent().name) if ctx != null else "", page,
			_trigger_of(frame)])


## The page's own [code]settings.trigger[/code] (decision 44's seven: [code]action[/code],
## [code]player_touch[/code], [code]auto[/code], ...) - re-read from disk rather than
## threaded through [method begin] as a parameter of its own, since this line prints once
## per run and is not worth widening this class's public surface for. [code]""[/code]
## for an inline frame with no document behind it (every headless test's own literal
## node array) - nothing to look a trigger up in.
func _trigger_of(frame: _Frame) -> String:
	if frame.doc_path == "" or frame.page_index < 0:
		return ""

	var doc := EventDocument.parse(FileAccess.get_file_as_string(frame.doc_path))
	var pages: Array = doc.get("pages", [])
	if frame.page_index >= pages.size():
		return ""

	var settings: Dictionary = (pages[frame.page_index] as Dictionary).get("settings", {})
	return str(settings.get("trigger", ""))


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


## [code]define_route[/code]'s own execution: sets [member _Frame.route_scope] to
## whatever [param node]'s own "blocked" flow names - "" if left unwired - replacing
## whichever policy was active before, then moves on via "next" like any other linear
## node. The "blocked" target is read straight off [param node]'s own wiring rather than
## taken as an ordinary flow port: it is not where this node's execution goes next, only
## the address [method _resolve_finished_node] jumps to later, should a move under this
## policy need it.
func _set_route_policy(frame: _Frame, node: Dictionary) -> void:
	frame.route_scope = {"blocked_target": _target_for(node, "blocked")}
	_advance_cursor(frame, "next")


## Where a just-finished blocking command's outcome becomes the frame's next cursor -
## called from both [method _drive]'s own synchronous-finish branch (a viewless actor's
## move, refused or not, settles inside the very same call) and [method tick] (a real
## step still in flight when this was last called). Ordinarily just [method
## _advance_cursor] against [param ex]'s own [method EventCommandExec.flow_port];
## intercepted only when [method EventCommandExec.was_blocked] is true and a
## [code]define_route[/code] policy is currently active ([member _Frame.route_scope]
## not empty - see its own doc), per that policy's own "blocked" target:
##
## - Left unwired ("") pauses one scheduler tick ([class _RouteRetryPause]) rather than
##   advancing the cursor at all, so the very same node runs again fresh next tick - not
##   in the same call, which is what let a permanently blocked back-and-forth trip
##   [constant NODE_BUDGET] before this existed.
## - Wired jumps the cursor straight there, skipping whatever "next" this node would
##   otherwise have taken.
##
## Returns whether [method _drive]'s own loop (or [method tick]) may keep going
## synchronously - false only for the one-tick pause, which must wait for a real
## [method tick] call to clear it.
func _resolve_finished_node(frame: _Frame, ex: EventCommandExec) -> bool:
	if ex.was_blocked() and not frame.route_scope.is_empty():
		var target := str(frame.route_scope.get("blocked_target", ""))
		if target == "":
			# ex itself is kept, not discarded - see _retry_after_pause() and
			# EventCommandExec.retry()'s own doc for why re-dispatching this node fresh
			# (a plain node lookup would only ever call start() again) is not the same
			# thing as retrying it.
			frame.retry_exec = ex
			frame.exec = _RouteRetryPause.new()
			return false

		frame.cursor = target
		if not frame.by_id.has(frame.cursor):
			_pop_frame()
		return true

	_advance_cursor(frame, ex.flow_port())
	return true


## The other half of [class _RouteRetryPause]: the one scheduler tick of pause is over,
## so [member _Frame.retry_exec] gets another attempt - via [method
## EventCommandExec.retry], not [method EventCommandExec.start] - and is ticked once at
## [code]delta == 0.0[/code] the same way a freshly dispatched node is in [method
## _drive], to catch a viewless actor settling synchronously again. Finished the same
## way [method _drive]'s own dispatch resolves one; still blocked, it goes back to
## being this frame's live [member _Frame.exec] and waits for the next real [method
## tick] like any other in-flight command.
func _retry_after_pause(frame: _Frame) -> void:
	frame.exec = null
	var ex := frame.retry_exec
	frame.retry_exec = null

	ex.retry()
	if ex.tick(0.0) != EventCommandExec.Status.DONE:
		frame.exec = ex
		return

	if _resolve_finished_node(frame, ex):
		_budget = NODE_BUDGET
		_drive()


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


## Where this frame's start node sits, or [code]null[/code] if it has none (an empty
## or malformed graph - event-pages.md §2's route-only page has nothing to reach).
##
## [b]Never [code]""[/code] for "not found"[/b]: a node's own [code]id[/code] can
## legitimately be [code]""[/code] - the start node is the one node allowed a blank
## one (question 47 follow-up), and it is what every start node the graph editor
## itself adds is actually given (see [method GraphEditorPanel._ensure_start_node]) -
## so a graph whose start node has the blank id it is normally given used to read as
## having no start node at all, and [method _drive] would pop the frame without ever
## running it.
func _find_start(frame: _Frame) -> Variant:
	for id: Variant in frame.by_id:
		if str((frame.by_id[id] as Dictionary).get("command", "")) == EventCommand.START_COMMAND:
			return str(id)
	return null


func _target_for(node: Dictionary, port: String) -> String:
	for output: Variant in node.get("outputs", []) as Array:
		if output is Dictionary and str((output as Dictionary).get("flow", "")) == port:
			return str((output as Dictionary).get("target", ""))
	return ""


## [param message] is what [member error] is set to and what a caller reading it back
## sees - kept free of the document path, which is only ever known here, so a saved
## error string does not depend on where a doc happened to sit on disk when it failed.
## The console line does carry it - [method push_error] is a diagnostic, not saved
## state - taken from whichever frame is on top of [member _stack] right now, which
## every call site fails from before popping its own frame.
func _fail(message: String) -> void:
	error = message
	var doc_path := (_stack.back() as _Frame).doc_path if not _stack.is_empty() else ""
	var suffix := "  (%s)" % doc_path if doc_path != "" else ""
	push_error("EventRunner: %s%s" % [message, suffix])
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
