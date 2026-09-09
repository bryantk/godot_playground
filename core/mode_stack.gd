extends Node

## Who has control. Autoloaded as [code]ModeStack[/code].
##
## This exists in stage A rather than stage F for two reasons. Game 1's battle is a
## separate scene that keeps the field map resident, so a Battle mode is a
## prerequisite for game 1 being playable at all. And there were three independent
## answers to "is input locked" on paper - the round gate and its watchdog, the input
## target stack, and the event scheduler's exclusive slot - which is one too many to
## leave unarbitrated.
##
## The failure that made this urgent: the player steps onto a cell, the round opens, a
## cell trigger takes the exclusive slot and puts up dialogue, and two seconds later
## the round watchdog force-closes the round, unlocks input and logs an error naming a
## command that is legitimately waiting on the player. Everything below is one
## mechanism so that cannot happen.

enum Mode { FIELD, CUTSCENE, BATTLE, MENU }

signal mode_pushed(mode: Mode)
signal mode_popped(mode: Mode)
signal mode_changed(mode: Mode)

## What each mode does. Read by the step pulse, the round watchdog, [FreeMotion] and
## whoever owns input - rather than each of them keeping its own idea.
const RULES: Dictionary = {
	Mode.FIELD:    {"pulse": true,  "physics": true,  "keeps_map": true,  "round": true},
	Mode.CUTSCENE: {"pulse": false, "physics": true,  "keeps_map": true,  "round": false},
	Mode.BATTLE:   {"pulse": false, "physics": true,  "keeps_map": true,  "round": false},
	Mode.MENU:     {"pulse": false, "physics": false, "keeps_map": true,  "round": false},
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

## Suppressed outside FIELD, so a cutscene that walks the player past monsters does
## not drive them. A move command may still opt in with [code]pulse: true[/code].
func suppresses_pulse() -> bool:
	return not bool(RULES[current()]["pulse"])


func pauses_physics() -> bool:
	return not bool(RULES[current()]["physics"])


func keeps_map_loaded() -> bool:
	return bool(RULES[current()]["keeps_map"])


## The answer to question 27. The round gate only holds - and its watchdog only
## runs - in a mode that has rounds. Everywhere else the exclusive runner owns input
## and the watchdog must stay quiet, or it force-unlocks a legitimate wait.
func rounds_active() -> bool:
	return bool(RULES[current()]["round"])
