class_name PlayerBrain extends Brain

## The brain that reads the keyboard.
##
## This was [code]InputDriver[/code], a node that sat on the map root and named the
## actor it drove by id. It is now a child of that actor, which is what lets one actor
## prefab be the player here and an NPC there: the difference is which brain is
## attached, not which scene was instanced.
##
## It produces an intent and nothing else - [Brain] applies it. The turn-versus-step
## decision lives here rather than in the base because it is a property of the
## [i]input[/i]: whether the turn modifier is down. The answer goes into
## [member InputIntent.turn] or [member InputIntent.step], and the base brain does the
## same thing with those fields whoever filled them.

@export var profile: InputProfile = null

## The rig whose yaw resolves "up on the stick". Left empty, the map's own rig is used
## - see [method MapContext.camera_rig] - and failing that input is world-relative,
## which is correct for a fixed camera and wrong the moment the view rotates.
@export var camera_rig: CameraRig = null


func _ready() -> void:
	super()
	if profile == null:
		profile = InputProfile.new()


## The rig, resolved lazily so this works whether the map wires one in or not. Looked
## up rather than exported by default because a path out of a prefab into the map that
## instanced it is exactly the wiring one shared actor scene is meant to avoid.
func rig() -> CameraRig:
	if camera_rig == null:
		var ctx := context()
		if ctx != null:
			camera_rig = ctx.camera_rig()
	return camera_rig


func _think(_delta: float) -> void:
	# The exclusive slot locks movement the same way the struck round gate used to -
	# one boolean, not a push onto the input stack, so everything except movement
	# (menu, cancel, interact) stays live through a cutscene.
	#
	# [member InputIntent.lock_step] only ever zeroed [member InputIntent.step], which
	# is all a grid game needed - but a free actor has no step, and until this, nothing
	# stopped [method Brain._drive_free] steering one straight through a cutscene it
	# should have been locked out of (GameEvent's new lock_player page setting is what
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


## Step, or turn to face without moving? The [code]turn_in_place[/code] modifier decides,
## and it decides on the frame the direction arrives - there is no grace period, no tap
## to time, and nothing ambiguous about the first frames of a press.
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
