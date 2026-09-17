class_name KeyLatch extends RefCounted

## One per [EventRunner]. Connects [signal EventBus.command_finished] and
## [signal EventBus.dialogue_finished] exactly once and keeps a small ring of
## recently-resolved keys, so a key that resolves *synchronously inside* [code]start()[/code]
## - which is what a viewless actor does, and every headless test actor in this segment
## is viewless - is already latched by the time anything asks about it.
##
## No mirror signal is added to [EventBus]: the project's rule is one moment, one
## signal, and the consumer decides what it means. This is the consumer deciding.

## Small on purpose - one runner is never juggling anywhere near this many outstanding
## keys at once, so wrapping only protects against an unbounded leak over a long game.
const RING_SIZE := 64

var _resolved: Array[String] = []


func _init() -> void:
	EventBus.command_finished.connect(_on_resolved)
	EventBus.dialogue_finished.connect(_on_resolved)


## Detached before the runner that owns this latch goes away, so a stray connection
## does not keep firing into a dead object.
func detach() -> void:
	if EventBus.command_finished.is_connected(_on_resolved):
		EventBus.command_finished.disconnect(_on_resolved)
	if EventBus.dialogue_finished.is_connected(_on_resolved):
		EventBus.dialogue_finished.disconnect(_on_resolved)


func _on_resolved(key: String) -> void:
	if key == "":
		return
	_resolved.append(key)
	if _resolved.size() > RING_SIZE:
		_resolved.pop_front()


## True if [param key] has resolved, without consuming it.
func has_resolved(key: String) -> bool:
	return key != "" and _resolved.has(key)


## Consumes the resolution so a second wait on the same key later does not read a
## stale true forever. Returns whether it had resolved.
func consume(key: String) -> bool:
	var idx := _resolved.find(key)
	if idx == -1:
		return false
	_resolved.remove_at(idx)
	return true
