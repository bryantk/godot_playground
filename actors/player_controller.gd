class_name PlayerController extends Node

## The node that reads the keyboard and drives the player's actor.
##
## This was [code]InputDriver[/code], a node that sat on the map root and named the
## actor it drove by id, then [code]Brain[/code]/[code]PlayerBrain[/code], a base
## class built for several kinds of "what decides where this actor goes" (the player,
## a patrolling NPC) with one subclass per kind. The NPC side of that,
## [code]RouteBrain[/code], was retired once [GameEvent]'s own [code]route[/code]
## field started compiling straight to [EventRunner] commands - no per-frame decider
## needed at all for an NPC. That left exactly one concrete subclass, so the base
## class bought nothing merging back into it didn't already have for free; this is
## that merge, with the shared name dropped since there is only one of it left.
##
## It produces an intent and applies it in the same class now - there being only one
## kind of "applying" left to have split out. The turn-versus-step decision still
## lives in [method _think]'s own body rather than being a property of a shared base:
## it depends on the [i]input[/i] (whether the turn modifier is down), and the answer
## goes into [member InputIntent.turn] or [member InputIntent.step] either way.
##
## [b]Added per instance, not baked into the actor scene.[/b] One actor prefab serves
## the player and every NPC on a map; what makes one of them the player is this node
## being a child of it - or nothing at all, for something that only stands there (an
## NPC, or one driven by a [GameEvent] instead). That is the whole reason player and
## NPC stopped being separate scenes.

## How much faster [member InputIntent.run] is than a walk.
##
## [b]Both motion types, and it means the same thing in each[/b]: a multiplier on the
## actor's speed. What that buys differs because the controllers differ - [FreeMotion]
## steers faster, while a [GridMotion] step still crosses exactly one cell and so
## crosses it in less time (see [method GridMotion.set_run_scale]). One number, one
## feel to tune.
@export var run_speed_scale: float = 1.75

@export var profile: InputProfile = null

## The rig whose yaw resolves "up on the stick". Left empty, the map's own rig is used
## - see [method MapContext.camera_rig] - and failing that input is world-relative,
## which is correct for a fixed camera and wrong the moment the view rotates.
@export var camera_rig: CameraRig = null

## What this controller is asking for this frame. Rewritten by [method _think], read
## by [method _apply]. One instance, reused - nothing holds onto it between frames.
var intent := InputIntent.new()

var _actor: Actor = null

## True while [method suspend] holds this controller off producing an intent at all -
## a [GameEvent] taking its actor over for a triggered run without a competing decider
## still walking or turning it underneath the graph.
var _suspended := false


func _ready() -> void:
	# The parent, not a lookup by id: this drives the actor it is attached to, which
	# is what lets the same prefab be placed twice with two different controllers (or
	# none).
	_actor = get_parent() as Actor
	if _actor == null:
		push_error("PlayerController: expected an Actor parent, found '%s'." % get_parent())
		set_process(false)
		return

	if profile == null:
		profile = InputProfile.new()


func actor() -> Actor:
	return _actor


func context() -> MapContext:
	return _actor.context() if _actor != null else null


func motion() -> MotionController:
	return _actor.motion() if _actor != null else null


## The rig, resolved lazily so this works whether the map wires one in or not. Looked
## up rather than exported by default because a path out of a prefab into the map that
## instanced it is exactly the wiring one shared actor scene is meant to avoid.
func rig() -> CameraRig:
	if camera_rig == null:
		var ctx := context()
		if ctx != null:
			camera_rig = ctx.camera_rig()
	return camera_rig


## Holds this controller off producing an intent (or takes it back off hold). Whatever
## the actor was already doing when suspended stays as it left it - a step in flight
## still settles, a facing does not un-turn - only the next frame's [method _think]/
## [method _apply] pair stops happening. Idempotent either way.
func suspend(on: bool) -> void:
	_suspended = on


func is_suspended() -> bool:
	return _suspended


func _process(delta: float) -> void:
	if _actor == null or _suspended:
		return
	_think(delta)
	_apply(delta)


## Fills [member intent] with what the player wants this frame.
func _think(_delta: float) -> void:
	# The exclusive slot locks movement the same way the struck round gate used to -
	# one boolean, not a push onto the input stack, so everything except movement
	# (menu, cancel, interact) stays live through a cutscene.
	#
	# [member InputIntent.lock_step] only ever zeroed [member InputIntent.step], which
	# is all a grid game needed - but a free actor has no step, and until this,
	# nothing stopped [method _drive_free] steering one straight through a cutscene it
	# should have been locked out of (GameEvent's lock_player page setting is what
	# surfaced it: FreeMotion just never had a caller that cared before). Locked here
	# stops [member move] and [member jump] the same frame it stops the step.
	var locked := not ModeStack.is_field()
	intent.lock_step(locked)

	# Everything except movement stays live even while the lock holds, which is why
	# it is a couple of booleans on a couple of fields rather than a push onto the
	# input stack.
	var raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var r := rig()

	intent.move = Vector3.ZERO if locked else profile.resolve(raw, r.yaw() if r != null else 0.0)
	intent.run = Input.is_action_pressed("run")
	intent.jump = false if locked else Input.is_action_just_pressed("jump")
	intent.interact = Input.is_action_just_pressed("action")
	intent.wait = Input.is_action_just_pressed("wait_step")

	intent.step = Vector3i.ZERO
	intent.turn = Vector3i.ZERO
	if motion() is GridMotion:
		_decide_step()


## Step, or turn to face without moving? The [code]turn_in_place[/code] modifier
## decides, and it decides on the frame the direction arrives - there is no grace
## period, no tap to time, and nothing ambiguous about the first frames of a press.
##
## Turning changes no cell, so it opens no round. That is why it is [member
## InputIntent.turn] rather than a step the round gate would have to learn to ignore.
func _decide_step() -> void:
	var dir := Space.quantise(intent.move, profile.direction_count)
	if dir == Vector3i.ZERO:
		return

	if Input.is_action_pressed("turn_in_place"):
		intent.turn = dir
	else:
		intent.step = dir


# -- Applying the intent ------------------------------------------------------

## Hand [member intent] to whichever controller the actor has. Dispatching on the
## controller rather than on a flag in the input profile means a map that overrides
## [member MapContext.default_motion] is obeyed without anyone being told.
func _apply(_delta: float) -> void:
	if intent.interact:
		EventBus.actor_interacted.emit(_actor.actor_id)
		if _actor.is_player():
			_report_action_attempt()

	var m := motion()
	if m is GridMotion:
		_drive_grid(m as GridMotion)
	elif m is FreeMotion:
		_drive_free(m as FreeMotion)


## Emits [signal EventBus.player_interacted] and reports what came of it, for
## [DebugInteractView]'s own marker - a green X on every facing cell that actually
## fired (the tiles faced, or failing that the player's own footprint, the same cells
## [method GameEvent._on_player_interacted] itself checks - [method Actor.facing_cells]/
## [method Actor.footprint_cells] already widen to more than one for a bigger-than-1x1
## [member Actor.footprint]), a red X on every tile faced if none did.
##
## [b]Listening around one emit rather than asking [GameEvent] directly[/b]: nothing
## here needs to know which events exist or how any of them decide to fire - only
## whether [signal EventBus.event_fired] happened to land on one of the cells that
## matter while the button's own signal was still being dispatched.
func _report_action_attempt() -> void:
	var facing_cells := _actor.facing_cells()
	var own_cells := _actor.footprint_cells()
	var fired: Array[Vector3i] = []
	var on_fired := func(cell: Vector3i) -> void: fired.append(cell)

	EventBus.event_fired.connect(on_fired)
	EventBus.player_interacted.emit()
	EventBus.event_fired.disconnect(on_fired)

	var facing_hit := false
	for c in facing_cells:
		if fired.has(c):
			facing_hit = true
			EventBus.interact_attempted.emit(c, true)
	if facing_hit:
		return

	var own_hit := false
	for c in own_cells:
		if fired.has(c):
			own_hit = true
			EventBus.interact_attempted.emit(c, true)
	if own_hit:
		return

	for c in facing_cells:
		EventBus.interact_attempted.emit(c, false)


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
