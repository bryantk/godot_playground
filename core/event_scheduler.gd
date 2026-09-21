extends Node

## The one clock. Autoloaded as [code]EventScheduler[/code], the fifth autoload beside
## [code]InputManager[/code], [code]EventBus[/code], [code]GameState[/code] and
## [code]ModeStack[/code].
##
## [b]Policy, segment 6:[/b] one exclusive slot; any number of background runners,
## suspended while the exclusive slot is held unless a runner opts out via [member
## EventRunner.keeps_running] (the waterfall case, architecture.md §7.5); actor leases,
## so a patrol and a cutscene cannot both be driving the same guard at once. [method tick]
## is exposed directly (not only through [method _process]) so a headless test can pump
## it by hand and assert exact state with no frame sampling - the same reason the round
## gate never existed as anything but a join over keys.
##
## [b]The exclusive runner is owned here[/b] the moment it acquires the slot, not by
## whichever [GameEvent]/[Actor] spawned it. A [GameEvent] is a child of the map scene
## it is placed on; if it stayed the only thing keeping a [RefCounted] runner alive,
## the runner would be destroyed the instant its map unloads, however far its graph
## still had left to go. Holding this autoload's own reference is what lets an
## exclusive runner survive a [code]change_map[/code] (question 51).
##
## [b]Queueing a refused exclusive request is not built.[/b] A second [method
## run_exclusive] while the slot is held is refused outright - the caller decides
## whether to retry later. Good enough for a single cutscene at a time; a real queue is
## deferred until something actually needs to wait in line.

var _exclusive: EventRunner = null
var _background: Array[EventRunner] = []

## actor_id -> whichever runner currently holds it. A lease is not ownership of the
## actor's node, only a claim other callers are expected to honour by asking first.
var _leases: Dictionary = {}


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if ModeStack.pauses_physics():
		return

	if _exclusive != null:
		_exclusive.tick(delta)
		if _exclusive.finished:
			var gone := _exclusive
			_exclusive = null
			_release_all(gone)
			if ModeStack.current() == ModeStack.Mode.CUTSCENE:
				ModeStack.pop()

	for runner in _background.duplicate():
		if _exclusive != null and not runner.keeps_running:
			continue
		runner.tick(delta)
		if runner.finished:
			_background.erase(runner)
			_release_all(runner)


## Requests the exclusive slot for [param runner], starting it at [param nodes].
## Refuses (returns false) without starting anything if the slot is already held -
## the caller's own lease, if it took one first, is untouched either way, so it can
## retry the same runner later without re-acquiring anything. [param doc_path]/
## [param page_index] are forwarded straight to [method EventRunner.begin] - see its
## own doc for what they are for.
func run_exclusive(runner: EventRunner, nodes: Array[Dictionary],
		doc_path: String = "", page_index: int = -1) -> bool:
	if _exclusive != null:
		return false
	_exclusive = runner
	ModeStack.push(ModeStack.Mode.CUTSCENE)
	runner.begin(nodes, doc_path, page_index)
	if runner.finished:
		_exclusive = null
		_release_all(runner)
		ModeStack.pop()
	return true


## Starts [param runner] as a background runner - a patrol, an ambient graph.
func run_background(runner: EventRunner, nodes: Array[Dictionary],
		doc_path: String = "", page_index: int = -1) -> void:
	_background.append(runner)
	runner.begin(nodes, doc_path, page_index)
	if runner.finished:
		_background.erase(runner)
		_release_all(runner)


## Registers [param runner] as a background runner without starting it fresh - for a
## caller that already called [method EventRunner.restore] itself, rather than
## [method EventRunner.begin], and just needs this scheduler's clock to pick it up.
## Mirrors what [method from_save] already does for a runner restored as part of a
## whole-scheduler load. [GameEvent]'s own route resume (question 52, stage-c-plan.md
## segment 7) is the other caller: a route's [Actor.suspended_route] bookmark is
## restored onto a fresh runner outside any [method EventRunner.to_save]/[method
## EventScheduler.from_save] envelope, since it can happen many times in a session with
## no save involved at all - a patrol simply being let go after a cutscene ends.
func adopt_background(runner: EventRunner) -> void:
	if runner.finished:
		_release_all(runner)
		return
	_background.append(runner)


## Stops every runner and drops every lease without waiting for them to finish on their
## own, and pops [ModeStack] back to FIELD if the exclusive slot had pushed CUTSCENE.
## Mirrors [method GameState.clear]. Not test-only any more - [SaveGame] calls this too,
## to drop whatever the map being left behind was doing before abandoning it for a
## loaded one; the name outlived the "only tests reset this" assumption it was given
## under.
func reset() -> void:
	if _exclusive != null:
		_exclusive.stop()
		if ModeStack.current() == ModeStack.Mode.CUTSCENE:
			ModeStack.pop()
	for runner in _background:
		runner.stop()
	_exclusive = null
	_background.clear()
	_leases.clear()


## Question 39's envelope, one level up from [method EventRunner.to_save] - every live
## runner plus who leases what. Refused outright during BATTLE (returns [code]{}[/code]
## and logs an error) rather than saving something the plan already named as explicitly
## unsupported.
func to_save() -> Dictionary:
	if ModeStack.current() == ModeStack.Mode.BATTLE:
		push_error("EventScheduler: to_save() is refused during BATTLE.")
		return {}

	var background: Array = []
	for r in _background:
		background.append(r.to_save())

	var leases := {}
	for actor_id: Variant in _leases:
		var holder: EventRunner = _leases[actor_id]
		if holder == _exclusive:
			leases[actor_id] = "exclusive"
		else:
			var idx := _background.find(holder)
			if idx >= 0:
				leases[actor_id] = idx

	return {
		"exclusive": _exclusive.to_save() if _exclusive != null else null,
		"background": background,
		"leases": leases,
	}


## The inverse of [method to_save]. Drops whatever this scheduler was already doing
## first ([method reset]'s own reasoning: nothing here should straddle two sessions),
## then rebuilds every runner against [param map] and re-takes its leases.
## [constant ModeStack.Mode.CUTSCENE] is pushed for a restored exclusive runner the same
## way [method run_exclusive] pushes it for a fresh one - unless that runner came back
## already finished (its document or actor gone), in which case there is nothing left
## to hold the mode open for.
func from_save(state: Dictionary, map: MapContext) -> void:
	reset()
	if state.is_empty():
		return

	var exclusive_state: Variant = state.get("exclusive")
	if exclusive_state is Dictionary:
		_exclusive = EventRunner.from_save(exclusive_state as Dictionary, map)
		if not _exclusive.finished:
			ModeStack.push(ModeStack.Mode.CUTSCENE)
		else:
			_exclusive = null

	for entry: Variant in state.get("background", []) as Array:
		var runner := EventRunner.from_save(entry as Dictionary, map)
		if not runner.finished:
			_background.append(runner)

	for actor_id: Variant in state.get("leases", {}) as Dictionary:
		var slot: Variant = (state["leases"] as Dictionary)[actor_id]
		var holder: EventRunner = null
		if slot == "exclusive":
			holder = _exclusive
		elif slot is int and slot >= 0 and slot < _background.size():
			holder = _background[slot]
		if holder != null:
			_leases[StringName(actor_id)] = holder


func is_exclusive_held() -> bool:
	return _exclusive != null


func exclusive_runner() -> EventRunner:
	return _exclusive


func background_runners() -> Array[EventRunner]:
	return _background.duplicate()


# -- Actor leases ----------------------------------------------------------------

## Claims [param actor_id] for [param runner]. True if it was free or already held by
## this same runner; false if another runner holds it - a patrol and a cutscene are
## not allowed to both be driving one guard.
func try_lease(actor_id: StringName, runner: EventRunner) -> bool:
	var holder: EventRunner = _leases.get(actor_id)
	if holder != null and holder != runner:
		return false
	_leases[actor_id] = runner
	return true


## Releases [param actor_id] if [param runner] is the one holding it - releasing a
## lease held by someone else is a no-op, not an error, so a runner that never
## actually got the lease can call this unconditionally when it gives up.
func release_lease(actor_id: StringName, runner: EventRunner) -> void:
	if _leases.get(actor_id) == runner:
		_leases.erase(actor_id)


func is_leased(actor_id: StringName) -> bool:
	return _leases.has(actor_id)


func lease_holder(actor_id: StringName) -> EventRunner:
	return _leases.get(actor_id)


## Every lease [param runner] still holds, dropped - called once it finishes, so a
## forgetful caller cannot leave an actor permanently claimed by a dead runner.
func _release_all(runner: EventRunner) -> void:
	var held: Array = []
	for actor_id: Variant in _leases:
		if _leases[actor_id] == runner:
			held.append(actor_id)
	for actor_id in held:
		_leases.erase(actor_id)
