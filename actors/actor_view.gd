class_name ActorView extends Node

## What an actor looks like, independent of what space it lives in. A sibling of
## [MotionController] under [Actor].
##
## This exists because presentation is its own axis: game 2 is sprites in a 3D world,
## which neither the space axis nor the motion axis has anywhere to put. It is also
## where the grid-step tween lands - [method apply_step_offset] rather than a
## [SpaceAdapter] method - because the offset is a lie told to the eye, and keeping it
## off the adapter is what keeps the adapter thin.

## The node actually displaced by the step tween and the texel rounding. Left null it
## takes the first child, which is the normal arrangement.
@export var visual_path: NodePath = NodePath()

var _visual: Node = null
var _offset: Vector3 = Vector3.ZERO
var _tween: Tween = null
var _keys := 0


func _ready() -> void:
	_visual = get_node_or_null(visual_path) if not visual_path.is_empty() else _first_child()


func _first_child() -> Node:
	return get_child(0) if get_child_count() > 0 else null


# -- To implement -------------------------------------------------------------

func set_facing(_dir: Vector3i) -> void:
	pass


## Re-applied on page activation, so a chest that changes art between pages does not
## need its own mechanism. See event-pages.md.
func apply_art(_art: Dictionary) -> void:
	pass


func set_visible(v: bool) -> void:
	if _visual is CanvasItem:
		(_visual as CanvasItem).visible = v
	elif _visual is Node3D:
		(_visual as Node3D).visible = v


## Plays [param anim] and returns a completion key, matching the pattern
## [method EventBus.say] uses - the caller awaits it or ignores it. A key is what lets
## a round join over a view's animation exactly as it joins over a step.
func play(_anim: StringName) -> String:
	return ""


# -- The step tween -----------------------------------------------------------

## Push the visual back by [param back] and tween it to zero over [param duration].
## The body has already snapped to the destination cell; this is the sprite catching
## up.
##
## [param duration] is passed in rather than configured here because the controller
## owns it: a fast monster taking two steps per pulse has to fit both inside roughly
## one player step, so each action's time is derived from the step speed and the
## actions taken this pulse. A view holding its own duration could disagree with that.
##
## Returns a completion key that resolves when the tween ends, which is what
## [code]wait_settle[/code] joins on - or [code]""[/code] when nothing long-running
## happened, since a key that has already fired is a key the caller can never catch.
func apply_step_offset(back: Vector3, duration: float) -> String:
	_offset = back
	_write_offset()

	if _tween != null and _tween.is_valid():
		_tween.kill()

	if duration <= 0.0 or not is_inside_tree():
		_offset = Vector3.ZERO
		_write_offset()
		return ""

	_keys += 1
	var owner_name := str(get_parent().name) if get_parent() != null else "?"
	var key := "view:%s:%d" % [owner_name, _keys]

	_tween = create_tween()
	_tween.tween_method(_set_offset, back, Vector3.ZERO, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_tween.finished.connect(func () -> void: EventBus.command_finished.emit(key))
	return key


## Drop the offset immediately - a cutscene that teleports an actor mid-step wants the
## sprite where the body is, not still sliding toward where it used to be going.
func cancel_step_offset() -> void:
	if _tween != null and _tween.is_valid():
		_tween.kill()
	_offset = Vector3.ZERO
	_write_offset()


func offset() -> Vector3:
	return _offset


func _set_offset(v: Vector3) -> void:
	_offset = v
	_write_offset()


## Subclasses write the offset into whatever their visual understands, and are the
## place any texel rounding happens.
func _write_offset() -> void:
	pass
