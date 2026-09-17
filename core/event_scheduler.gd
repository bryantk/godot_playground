extends Node

## The one clock. Autoloaded as [code]EventScheduler[/code], the fifth autoload beside
## [code]InputManager[/code], [code]EventBus[/code], [code]GameState[/code] and
## [code]ModeStack[/code].
##
## [b]This segment builds the clock and the exclusive slot's ownership (question 51)
## only[/b] - leases, [code]keeps_running[/code], the seven triggers and [GameEvent]
## itself are segment 6. [method tick] is exposed directly (not only through
## [method _process]) so a headless test can pump it by hand and assert exact state
## with no frame sampling - the same reason the round gate never existed as anything
## but a join over keys.
##
## [b]The exclusive runner is owned here[/b] the moment it acquires the slot, not by
## whichever [GameEvent]/[Actor] spawned it. A [GameEvent] is a child of the map scene
## it is placed on; if it stayed the only thing keeping a [RefCounted] runner alive,
## the runner would be destroyed the instant its map unloads, however far its graph
## still had left to go. Holding this autoload's own reference is what lets an
## exclusive runner survive a [code]change_map[/code] (question 51).

var _exclusive: EventRunner = null
var _background: Array[EventRunner] = []


func _process(delta: float) -> void:
	tick(delta)


func tick(delta: float) -> void:
	if ModeStack.pauses_physics():
		return

	if _exclusive != null:
		_exclusive.tick(delta)
		if _exclusive.finished:
			_exclusive = null
			if ModeStack.current() == ModeStack.Mode.CUTSCENE:
				ModeStack.pop()

	# Background suspends while exclusive is held - segment 6's policy. No
	# keeps_running opt-out yet; every background runner is paused for now.
	if _exclusive != null:
		return

	for runner in _background.duplicate():
		runner.tick(delta)
		if runner.finished:
			_background.erase(runner)


## Requests the exclusive slot for [param runner], starting it at [param nodes].
## Refuses (returns false) without starting anything if the slot is already held -
## segment 6's queue-or-refuse policy is not built yet, so this is the refuse half only.
func run_exclusive(runner: EventRunner, nodes: Array[Dictionary]) -> bool:
	if _exclusive != null:
		return false
	_exclusive = runner
	ModeStack.push(ModeStack.Mode.CUTSCENE)
	runner.begin(nodes)
	if runner.finished:
		_exclusive = null
		ModeStack.pop()
	return true


## Starts [param runner] as a background runner - a patrol, an ambient graph.
func run_background(runner: EventRunner, nodes: Array[Dictionary]) -> void:
	_background.append(runner)
	runner.begin(nodes)
	if runner.finished:
		_background.erase(runner)


func is_exclusive_held() -> bool:
	return _exclusive != null


func exclusive_runner() -> EventRunner:
	return _exclusive


func background_runners() -> Array[EventRunner]:
	return _background.duplicate()
