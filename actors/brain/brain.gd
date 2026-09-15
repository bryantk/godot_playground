class_name Brain extends Node

## What drives one actor. The only node in the tree that decides what an actor does
## next.
##
## An [Actor] is a data container: an id, a facing, and three axis children that know
## how to move a body, occupy a cell and draw a sprite. None of them choose anything.
## The brain chooses, and it does so in one currency - an [InputIntent], the same
## struct the keyboard used to produce - so the player, a patrolling NPC and, later, an
## event graph all reach the motion controller down one path.
##
## [b]A brain is added per instance, not baked into the actor scene.[/b] One actor
## prefab serves the player and every NPC on a map; what makes one of them the player
## is a [PlayerBrain] child rather than a [RouteBrain] child - or no brain at all, for
## something that only stands there. That is the whole reason player and NPC stopped
## being separate scenes.
##
## Subclasses override [method _think] and fill [member intent]. Turning that intent
## into motion is this class's job, because it varies by [MotionController] rather than
## by who is asking: [GridMotion] takes a committed step, [FreeMotion] takes continuous
## steering. Nothing in a subclass needs to know which game it is in.

## How much faster [member InputIntent.run] is than a walk.
##
## [b]Both motion types, and it means the same thing in each[/b]: a multiplier on the
## actor's speed. What that buys differs because the controllers differ - [FreeMotion]
## steers faster, while a [GridMotion] step still crosses exactly one cell and so crosses
## it in less time (see [method GridMotion.set_run_scale]). One number, one feel to tune.
@export var run_speed_scale: float = 1.75

## What this brain is asking for this frame. Rewritten by [method _think], read by
## [method _apply]. One instance, reused - nothing holds onto it between frames.
var intent := InputIntent.new()

var _actor: Actor = null


func _ready() -> void:
	# The parent, not a lookup by id: a brain drives the actor it is attached to, which
	# is what lets the same prefab be placed twice with two different brains.
	_actor = get_parent() as Actor
	if _actor == null:
		push_error("Brain: expected an Actor parent, found '%s'." % get_parent())
		set_process(false)


func actor() -> Actor:
	return _actor


func context() -> MapContext:
	return _actor.context() if _actor != null else null


func motion() -> MotionController:
	return _actor.motion() if _actor != null else null


func _process(delta: float) -> void:
	if _actor == null:
		return
	_think(delta)
	_apply(delta)


# -- To implement -------------------------------------------------------------

## Fill [member intent] with what this actor wants this frame. The base brain wants
## nothing, which is a perfectly good NPC.
func _think(_delta: float) -> void:
	pass


# -- Applying the intent ------------------------------------------------------

## Hand [member intent] to whichever controller the actor has. Dispatching on the
## controller rather than on a flag in the input profile means a map that overrides
## [member MapContext.default_motion] is obeyed without anyone being told.
func _apply(_delta: float) -> void:
	var m := motion()
	if m is GridMotion:
		_drive_grid(m as GridMotion)
	elif m is FreeMotion:
		_drive_free(m as FreeMotion)


## Discrete stepping.
##
## The order here is load-bearing. While the actor is mid-step the direction is handed
## over as a [i]standing intent[/i], which [GridMotion] takes the instant the step
## settles - inside the tree's own step, rather than a frame later when this
## [method Node._process] next runs. At a 167 ms step a single dropped frame per cell
## is a visible hitch at every boundary.
##
## While the actor is [i]idle[/i] the intent is cleared before stepping instead. A view
## with no tween duration - a headless test, a settled teleport - settles inside
## [method GridMotion.step], and a standing intent left set would be consumed by that
## settle and step again, recursing until the actor hit a wall.
func _drive_grid(grid: GridMotion) -> void:
	# Before the early return, so a run asked for mid-step is honoured by the step in
	# flight rather than only by the next one. The controller re-reads it every frame.
	grid.set_run_scale(run_speed_scale if intent.run else 1.0)

	var step := intent.effective_step()

	if _actor.is_moving():
		grid.set_step_intent(step)
		return

	grid.set_step_intent(Vector3i.ZERO)

	# Turning changes no cell, so it opens no round - and it happens only when the
	# actor is idle, which is what makes a turn asked for mid-step land at the cell
	# boundary rather than swinging the sprite around mid-stride.
	if intent.turn != Vector3i.ZERO:
		_actor.set_facing(intent.turn)

	if step != Vector3i.ZERO:
		grid.step(step)


## Continuous steering, straight into the controller.
##
## The run goes in as [method FreeMotion.set_intent]'s second argument, not as a longer
## direction vector: the controller quantises whatever direction it is handed, which
## normalises the magnitude away. See that method.
func _drive_free(free: FreeMotion) -> void:
	free.set_intent(intent.move, run_speed_scale if intent.run else 1.0)
	if intent.jump:
		free.jump(-1.0)
