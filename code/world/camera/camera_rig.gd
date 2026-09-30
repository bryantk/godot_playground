class_name CameraRig extends Node

## One vocabulary for two genuinely different cameras. The point is that
## [code]camera_to[/code] in an event graph means the same thing in both and the rig
## decides what it can honour.
##
## Ownership, per the camera question: the camera follows the player by default and
## events [i]borrow[/i] it, returning it when they finish. That is what [method lock]
## is - not a permanent handover to whoever holds the exclusive slot.

signal yaw_changed(yaw_radians: float)

@export var follow_speed: float = 8.0

## Who the camera follows, by actor id. Exported so a map scene can name its subject in
## the inspector instead of a script calling [method follow] on ready.
@export var follow_target: StringName = &"":
	set(value):
		follow_target = value
		_target_id = value

var _target_id: StringName = &""
var _locked: bool = false
var _keys := 0
var _ctx: MapContext = null

## A pending [method follow] waiting to hear "caught up" - see [method
## _resolve_follow_if_caught_up]. "" when nothing is waiting, either because [method
## follow] was never asked to block or because it has already resolved.
var _follow_key := ""

## The running [method shake]'s tween and the key it will finish - see that method.
var _shake_tween: Tween = null
var _shake_key := ""


func _ready() -> void:
	_ctx = MapContext.of(self)
	if _ctx != null:
		_ctx.register_camera(self)
	EventBus.map_arrived.connect(_on_map_arrived)


func context() -> MapContext:
	return _ctx


## Snaps back onto the player the instant this rig's own map has just been arrived at
## via a transition ([signal EventBus.map_arrived]) - a page-authored [code]
## camera_follow[/code] onto an NPC for a cutscene is not meant to survive the cutscene's
## own [code]change_map[/code] onto somewhere that NPC has no equivalent, or any
## equivalent, on. Instant rather than eased: this runs before [method
## ChangeMapBase._begin_fade_in] while the screen may still be faded to black, so there
## is nothing to see easing toward in the first place, only a resting position to
## already be at once the fade reveals it.
##
## [param map] is whichever map just arrived, not necessarily this rig's own - two maps'
## worth of nodes can be briefly resident at once (a battle keeps the field one loaded),
## so this only acts when it matches [member _ctx].
func _on_map_arrived(map: MapContext) -> void:
	if map != _ctx or map == null:
		return
	for who: Actor in map.actors():
		if who.is_player():
			follow(who.actor_id, 0.0, true)
			return


func _next_key(kind: String) -> String:
	_keys += 1
	return "cam:%s:%d" % [kind, _keys]


## Player control on or off. An event borrowing the camera locks it, does its work,
## and unlocks - so no system has to know what the previous owner was.
func lock(locked: bool) -> void:
	_locked = locked


func is_locked() -> bool:
	return _locked


## Sets [member follow_target] and, from here on, keeps the camera on it - "speed"
## overrides [member follow_speed] going forward when given, and "instant" places the
## camera directly on the target this call rather than easing in (see [method
## _snap_to_target]). The base implementation has no easing to skip in the first place
## - nothing to catch up to means already caught up - so it always snaps and returns ""
## (already done); [RoomCamera2D] overrides this to mint a real key instead, resolved
## once its own per-frame follow actually closes the distance.
func follow(actor_id: StringName, speed: float = 0.0, _instant: bool = false) -> String:
	follow_target = actor_id
	if speed > 0.0:
		follow_speed = speed
	_snap_to_target()
	return ""


func _mint_follow_key() -> String:
	_follow_key = _next_key("follow")
	return _follow_key


## Subclasses call this once per [method Node._process], right after moving the camera
## toward [member follow_target] - true the moment they judge it close enough to call
## the catch-up done. A no-op unless [method follow] actually minted a key to wait on.
func _resolve_follow_if_caught_up(caught_up: bool) -> void:
	if _follow_key == "" or not caught_up:
		return
	var key := _follow_key
	_follow_key = ""
	EventBus.command_finished.emit(key)


func target() -> StringName:
	return _target_id


## Where the camera should actually look: the body, plus whatever the view has
## displaced the visual by.
##
## The body is authoritative and, under [GridMotion], teleports a whole cell at commit
## - so a rig that follows [method Actor.world_position] directly lurches one cell per
## step. The eye tracks the sprite, not the body, so the camera must too. Free motion
## leaves the offset at zero, which makes this the same expression for both.
func focus_of(who: Actor) -> Vector3:
	if who == null:
		return Vector3.ZERO
	var p := who.world_position()
	var v := who.view()
	return (p + v.offset()) if v != null else p


# -- To implement -------------------------------------------------------------

func move_to(_cell: Vector3i, _seconds: float = 0.0) -> String:
	return ""


## Game 2 only. [RoomCamera2D] warns rather than silently doing nothing.
func rotate_to(_yaw: float, _seconds: float = 0.0) -> String:
	push_warning("CameraRig: this rig does not rotate.")
	return ""


func zoom_to(_z: float, _seconds: float = 0.0) -> String:
	return ""


## Shakes the camera: a random offset of up to [param amount] (px in 2D, texels in 3D)
## re-rolled every frame and fading linearly to nothing over [param seconds], then the
## camera is back exactly where it was. Written through [method _apply_shake_offset] -
## the rig's own camera offset, not its position, which [method follow] and friends
## rewrite every frame. A new shake replaces one already running. Returns the key that
## finishes with it - immediately for a zero [param amount]/[param seconds].
func shake(amount: float, seconds: float = 0.0) -> String:
	_stop_shake()
	var key := _next_key("shake")
	if amount <= 0.0 or seconds <= 0.0 or not is_inside_tree():
		EventBus.command_finished.emit(key)
		return key

	_shake_key = key
	_shake_tween = create_tween()
	_shake_tween.tween_method(func(t: float) -> void:
		var direction := Vector2.from_angle(randf() * TAU)
		_apply_shake_offset(direction * randf() * amount * (1.0 - t)), 0.0, 1.0, seconds)
	_shake_tween.finished.connect(_finish_shake)
	return key


## Ends any running shake: camera offset back to zero, and its key finished so nothing
## joined on it waits forever.
func _stop_shake() -> void:
	if _shake_tween != null:
		_shake_tween.kill()
		_shake_tween = null
	if _shake_key != "":
		_apply_shake_offset(Vector2.ZERO)
		var stale := _shake_key
		_shake_key = ""
		EventBus.command_finished.emit(stale)


func _finish_shake() -> void:
	_shake_tween = null
	_apply_shake_offset(Vector2.ZERO)
	var key := _shake_key
	_shake_key = ""
	if key != "":
		EventBus.command_finished.emit(key)


## Where a subclass writes the shake's current offset (screen px) into its camera. The
## base has no camera.
func _apply_shake_offset(_offset: Vector2) -> void:
	pass


## Places the camera directly on [member follow_target], bypassing whatever easing
## normally closes the distance - the "instant" half of [method follow]. The base no-op
## matches every rig here except [RoomCamera2D]: nothing to skip easing on if the rig
## never eases toward its target to begin with.
func _snap_to_target() -> void:
	pass


## Constrains [method follow] to stay inside [param rect] - [constant Rect2()] (the
## default) means unclamped. Game 1 only for now ([RoomCamera2D]); every other rig
## ignores it, the same "decides what it can honour" rule the rest of this section
## already follows.
func set_bounds(_rect: Rect2) -> void:
	pass


## Whether [param world_pos] falls inside whatever [method set_bounds] last set - always
## true with nothing set, or on a rig ([method set_bounds]'s own no-op) that never
## honoured bounds to begin with. [code]camera_move_by[/code] (events/commands/
## camera_execs.gd) is what this is for: a leg whose target lands outside reads as
## blocked, the camera's own version of a grid actor finding a wall.
func in_bounds(_world_pos: Vector3) -> bool:
	return true


## Where the camera is actually looking from, in world space - [code]camera_move_by[/code]
## (events/commands/camera_execs.gd) reads this as the "relative to wherever it already
## is" starting point for its own delta. [constant Vector3.ZERO] for a rig that has not
## positioned a camera yet, or has no [method move_to] of its own to be relative to.
func world_position() -> Vector3:
	return Vector3.ZERO


## Current yaw. Zero for a fixed rig, which is what makes
## [method Space.view_frame] safe to call unconditionally.
func yaw() -> float:
	return 0.0
