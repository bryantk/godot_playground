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


func _ready() -> void:
	_ctx = MapContext.of(self)
	if _ctx != null:
		_ctx.register_camera(self)


func context() -> MapContext:
	return _ctx


func _next_key(kind: String) -> String:
	_keys += 1
	return "cam:%s:%d" % [kind, _keys]


## Player control on or off. An event borrowing the camera locks it, does its work,
## and unlocks - so no system has to know what the previous owner was.
func lock(locked: bool) -> void:
	_locked = locked


func is_locked() -> bool:
	return _locked


func follow(actor_id: StringName, _seconds: float = 0.0) -> String:
	follow_target = actor_id
	return ""


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


func shake(_amount: float, _seconds: float = 0.0) -> String:
	return ""


## Current yaw. Zero for a fixed rig, which is what makes
## [method Space.view_frame] safe to call unconditionally.
func yaw() -> float:
	return 0.0
