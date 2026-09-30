class_name InputIntent extends RefCounted

## What the player is asking for this frame, produced by [InputProfile] and consumed
## by a [MotionController]. Already basis-corrected, so a controller never touches a
## camera.
##
## [member step] is separate from the rest for one reason: the round gate holds it and
## nothing else. Locking all input during a round would feel dreadful, so menu, cancel
## and interact stay live and the gate is one boolean on one field rather than a push
## onto the input target stack.

## World space, already resolved through the camera basis.
var move: Vector3 = Vector3.ZERO

var jump: bool = false
var run: bool = false
var interact: bool = false

## A discrete committed step, or ZERO. Game 1.
var step: Vector3i = Vector3i.ZERO

## Turning without stepping - the player holding the turn modifier, or a route saying
## [code]face[/code]. Changes no cell, so it opens no round.
var turn: Vector3i = Vector3i.ZERO

## Passing time deliberately. Explicit rather than letting the player bump a wall to
## do it, so time passing is a choice.
var wait: bool = false

var _step_locked: bool = false


## Held by the round gate. Everything except [member step] stays live.
func lock_step(locked: bool) -> void:
	_step_locked = locked
	if locked:
		step = Vector3i.ZERO


func step_locked() -> bool:
	return _step_locked


## The step, or ZERO while the gate holds it. Callers read this rather than
## [member step] directly, so there is one place the lock is honoured.
func effective_step() -> Vector3i:
	return Vector3i.ZERO if _step_locked else step


func clear() -> void:
	move = Vector3.ZERO
	jump = false
	run = false
	interact = false
	step = Vector3i.ZERO
	turn = Vector3i.ZERO
	wait = false
