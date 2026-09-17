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
## retry the same runner later without re-acquiring anything.
func run_exclusive(runner: EventRunner, nodes: Array[Dictionary]) -> bool:
	if _exclusive != null:
		return false
	_exclusive = runner
	ModeStack.push(ModeStack.Mode.CUTSCENE)
	runner.begin(nodes)
	if runner.finished:
		_exclusive = null
		_release_all(runner)
		ModeStack.pop()
	return true


## Starts [param runner] as a background runner - a patrol, an ambient graph.
func run_background(runner: EventRunner, nodes: Array[Dictionary]) -> void:
	_background.append(runner)
	runner.begin(nodes)
	if runner.finished:
		_background.erase(runner)
		_release_all(runner)


## Test-only reset - stops every runner and drops every lease without waiting for them
## to finish on their own, and pops [ModeStack] back to FIELD if the exclusive slot had
## pushed CUTSCENE. Mirrors [method GameState.clear].
func reset_for_test() -> void:
	if _exclusive != null:
		_exclusive.stop()
		if ModeStack.current() == ModeStack.Mode.CUTSCENE:
			ModeStack.pop()
	for runner in _background:
		runner.stop()
	_exclusive = null
	_background.clear()
	_leases.clear()


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
