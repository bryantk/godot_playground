extends Node

## Who has control. Autoloaded as [code]ModeStack[/code].
##
## This exists in stage A rather than stage F because game 1's battle is a separate
## scene that keeps the field map resident, so a Battle mode is a prerequisite for game
## 1 being playable at all.
##
## [b]It was also the arbiter between three answers to "is input locked".[/b] Two of
## those three are gone: the round gate and the step pulse were struck from the design
## on 2026-09-14 (question 42), so what remains is the input target stack and the event
## scheduler's exclusive slot, and the mode stack is what keeps those two agreeing.
## [member InputIntent.lock_step] survives the round that invented it - an exclusive
## cutscene still has to stop the player walking off - and the exclusive slot will be
## its only caller.

enum Mode { FIELD, CUTSCENE, BATTLE, MENU }

signal mode_pushed(mode: Mode)
signal mode_popped(mode: Mode)
signal mode_changed(mode: Mode)

## What each mode does. Read by [FreeMotion], [GridMotion] and whoever owns input -
## rather than each of them keeping its own idea.
##
## [b]Two keys were removed on 2026-09-14[/b] (question 42): [code]pulse[/code] and
## [code]round[/code], along with the step pulse and the round gate they described.
## Neither had a caller. What is left is what is actually read.
const RULES: Dictionary = {
	Mode.FIELD:    {"physics": true,  "keeps_map": true},
	Mode.CUTSCENE: {"physics": true,  "keeps_map": true},
	Mode.BATTLE:   {"physics": true,  "keeps_map": true},
	Mode.MENU:     {"physics": false, "keeps_map": true},
}

var _stack: Array[Mode] = [Mode.FIELD]


func current() -> Mode:
	return _stack[-1]


func is_field() -> bool:
	return current() == Mode.FIELD


func depth() -> int:
	return _stack.size()


func push(mode: Mode) -> void:
	_stack.append(mode)
	mode_pushed.emit(mode)
	mode_changed.emit(mode)


## Pops back to the mode below. The bottom of the stack is always FIELD and is never
## popped, so there is no state in which nothing owns control.
func pop() -> void:
	if _stack.size() <= 1:
		return
	var gone: Mode = _stack.pop_back()
	mode_popped.emit(gone)
	mode_changed.emit(current())


## Drop everything above FIELD - for a map change or a hard reset, where unwinding
## mode by mode would run teardown that no longer has a map to run against.
func reset() -> void:
	if _stack.size() <= 1:
		return
	_stack = [Mode.FIELD] as Array[Mode]
	mode_changed.emit(Mode.FIELD)


# -- What the current mode allows ---------------------------------------------


func pauses_physics() -> bool:
	return not bool(RULES[current()]["physics"])


func keeps_map_loaded() -> bool:
	return bool(RULES[current()]["keeps_map"])
