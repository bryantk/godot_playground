class_name TextWindowAnimation
extends Control

## Base window open/close animation. Subclasses override the three virtuals
## below to change the look without touching the intro/outro bookkeeping.
## The default is a vertical scale (unroll) from the window's center.

@export var duration := 2.0

var _tween: Tween = null
var _target := 1.0

func _ready() -> void:
	_layout()

func is_open() -> bool:
	return _tween == null and is_equal_approx(_progress(), 1.0)

func intro() -> Tween:
	if is_open():
		return null

	# Already animating in - let it finish rather than restarting.
	if _tween != null and is_equal_approx(_target, 1.0):
		return _tween

	return _start(1.0)

func outro() -> Tween:
	return _start(0.0)

func _start(target: float) -> Tween:
	if _tween != null:
		_tween.kill()

	_target = target
	visible = true
	_layout()
	_prepare(target)

	# Scale the time to the distance left so a partial animation isn't slowed down.
	var time := duration * absf(target - _progress())

	_tween = create_tween()
	_build(_tween, target, time)
	_tween.finished.connect(func() -> void: _tween = null)
	return _tween

# --- Virtuals -----------------------------------------------------------------

## How far the window currently is through its intro: 0.0 fully hidden, 1.0 fully open.
func _progress() -> float:
	return scale.y

## Cache anything that depends on the window's resting layout. Called on ready and
## again before every animation, since the window may have been moved in between.
func _layout() -> void:
	pivot_offset = size / 2.0

## Called at the start of an animation, before [method _progress] is sampled for
## timing. Put the node in a valid starting state for the coming
## [param target_progress] (0.0 = closing, 1.0 = opening).
func _prepare(_target_progress: float) -> void:
	pass

## Fill [param tween] with the tweens that move the window to [param target] over [param time].
func _build(tween: Tween, target: float, time: float) -> void:
	tween.tween_property(self, "scale:y", target, time)
