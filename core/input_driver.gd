class_name InputDriver extends Node

## Produces an [InputIntent] each frame and drives an actor with it.
##
## This is the piece that was missing after stage A: [InputProfile] knew how to resolve
## a stick through a camera basis and [InputIntent] knew what the round gate holds, but
## nothing read the keyboard and connected the two.
##
## It handles both motion models, because the difference is entirely in the profile:
## [member InputProfile.discrete_steps] means the intent becomes a committed step, and
## otherwise it becomes continuous steering. Nothing here knows which game it is in.

## Whose intent this is. Resolved against the map's registry on ready.
@export var actor_id: StringName = &"player"

@export var profile: InputProfile = null

## The rig whose yaw resolves "up on the stick". Left null, input is world-relative -
## correct for a fixed camera, wrong the moment the view rotates.
@export var camera_rig: CameraRig = null

var intent := InputIntent.new()

var _actor: Actor = null
var _ctx: MapContext = null
var _held: float = 0.0
var _last_dir: Vector3i = Vector3i.ZERO


func _ready() -> void:
	_ctx = MapContext.of(self)
	if _ctx != null:
		_actor = _ctx.actor(actor_id)
	if profile == null:
		profile = InputProfile.new()


func actor() -> Actor:
	if _actor == null and _ctx != null:
		_actor = _ctx.actor(actor_id)
	return _actor


func _process(delta: float) -> void:
	var who := actor()
	if who == null:
		return

	# Everything except the step stays live even while the gate holds, which is why
	# the gate is one boolean on one field rather than a push onto the target stack.
	var raw := Input.get_vector("move_left", "move_right", "move_up", "move_down")
	var yaw := camera_rig.yaw() if camera_rig != null else 0.0

	intent.move = profile.resolve(raw, yaw)
	intent.run = Input.is_action_pressed("run")
	intent.jump = Input.is_action_just_pressed("jump")
	intent.interact = Input.is_action_just_pressed("action")
	intent.wait = Input.is_action_just_pressed("wait_step")

	if profile.discrete_steps:
		_drive_grid(who, delta)
	else:
		_drive_free(who)


## Grid: a held direction steps again the moment the actor settles, so the cadence is
## set by the step completing rather than by a repeat timer. A tap under
## [member InputProfile.turn_grace] only turns, which changes no cell and so opens no
## round.
##
## "The moment it settles" is why the held direction is handed to [GridMotion] as a step
## intent rather than re-tested here next frame: this runs in [method Node._process] and
## the tween finishes inside the scene tree's own step, so testing here would insert one
## dropped frame per cell. At a 250 ms step that reads as a stutter at every boundary.
func _drive_grid(who: Actor, delta: float) -> void:
	var grid := who.motion() as GridMotion
	var dir := Space.quantise(intent.move, profile.direction_count)

	if dir == Vector3i.ZERO:
		# Released before the grace elapsed: turn in place and take no step.
		if profile.tap_turns_in_place and _last_dir != Vector3i.ZERO and _held < profile.turn_grace:
			who.set_facing(_last_dir)
		_held = 0.0
		_last_dir = Vector3i.ZERO
		intent.step = Vector3i.ZERO
		# Withdrawn the frame the key comes up, so a release cannot buy one more cell.
		if grid != null:
			grid.set_step_intent(Vector3i.ZERO)
		return

	if dir != _last_dir:
		_held = 0.0
		_last_dir = dir
	_held += delta

	intent.step = dir

	# Held long enough to mean "walk" rather than "turn and look". Tapping a new
	# direction mid-step therefore turns at the boundary instead of stepping, which is
	# the same rule the standing case below applies.
	var committed := not profile.tap_turns_in_place or _held >= profile.turn_grace

	if who.is_moving():
		if grid != null:
			# effective_step, not dir: a locked gate has to hold the chained step too,
			# or the round gate would leak exactly one step per round.
			grid.set_step_intent(intent.effective_step() if committed else Vector3i.ZERO)
		return

	if not committed:
		# Face it now; commit only if the key is still down once the grace passes.
		who.set_facing(dir)
		return

	var step := intent.effective_step()
	if step != Vector3i.ZERO:
		who.motion().step(step)


## Free: continuous steering, straight into the controller.
func _drive_free(who: Actor) -> void:
	var motion := who.motion() as FreeMotion
	if motion == null:
		return

	var speed_scale := 1.0 if not intent.run else 1.75
	motion.set_intent(intent.move * speed_scale)

	if intent.jump:
		motion.jump(-1.0)
