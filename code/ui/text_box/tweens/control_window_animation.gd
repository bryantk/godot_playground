class_name ControlWindowAnimation
extends Control

## Base window open/close animation. Subclasses override the three virtuals
## below to change the look without touching the intro/outro bookkeeping.
## The default is a vertical scale (unroll) from the window's center.
##
## The animation node is not the window - it drives [member window], so several
## animations can sit side by side under a [ControlWindowAnimationGroup] and each
## move a different property of the same control.

@export var duration := 1.0
## Park the window closed on ready instead of leaving it at its authored state.
@export var start_closed := true
## The control this animation moves. Left unset, a group above us fills it in with
## the window it stands for; failing that we fall back to animating ourselves.
@export var window: Control = null:
	set(value):
		window = value
		_window = value

var _tween: Tween = null
var _target := 1.0
# Resolved form of [member window]; never read directly, go through _win().
var _window: Control = null

func _ready() -> void:
	_layout()
	if start_closed:
		_close()

func is_open() -> bool:
	return _tween == null and is_equal_approx(_progress(), 1.0)

## Opens the window. Pass [param tween] to have the animation built into someone
## else's tween - see [method _start] - instead of one of our own, and
## [param time_scale] to stretch or squash [member duration] for this run.
func intro(tween: Tween = null, time_scale := 1.0) -> Tween:
	if is_open():
		return null

	# Already animating in - let it finish rather than restarting.
	if _tween != null and is_equal_approx(_target, 1.0):
		return _tween

	return _start(1.0, tween, time_scale)

## Closes the window. See [method intro] for [param tween] and [param time_scale].
func outro(tween: Tween = null, time_scale := 1.0) -> Tween:
	return _start(0.0, tween, time_scale)

## Animates to [param target]. When [param tween] is given the steps go into it,
## running alongside whatever else it holds, and the caller owns its lifetime;
## otherwise we make and own a tween of our own. Returns the tween that was used, so
## a caller passing one in can tell whether we actually contributed anything to it.
func _start(target: float, tween: Tween = null, time_scale := 1.0) -> Tween:
	if _tween != null:
		_tween.kill()

	_target = target
	_win().visible = true
	_layout()
	_prepare(target)

	# Scale the time to the distance left so a partial animation isn't slowed down.
	var time := duration * time_scale * absf(target - _progress())

	if tween != null:
		# Shared tween: our steps have to sit beside the other windows' rather than
		# queue up after them.
		tween.set_parallel(true)
	else:
		tween = create_tween()

	_tween = tween
	_build(tween, target, time)
	tween.finished.connect(func() -> void: _tween = null)
	return tween

## The control we animate. Resolved late, since a group only hands [member window]
## down once it enters the tree, which can be after an exported setter has run.
func _win() -> Control:
	if _window == null:
		_window = window if window != null else self
	return _window

# --- Virtuals -----------------------------------------------------------------

## How far the window currently is through its intro: 0.0 fully hidden, 1.0 fully open.
func _progress() -> float:
	return _win().scale.y

## Cache anything that depends on the window's resting layout. Called on ready and
## again before every animation, since the window may have been moved in between.
func _layout() -> void:
	_win().pivot_offset = _win().size / 2.0

## Snap straight to the fully-closed state, no animation. Called on ready when
## [member start_closed] is set, after [method _layout] has run.
func _close() -> void:
	_win().scale.y = 0.0

## Called at the start of an animation, before [method _progress] is sampled for
## timing. Put the node in a valid starting state for the coming
## [param target_progress] (0.0 = closing, 1.0 = opening).
func _prepare(_target_progress: float) -> void:
	pass

## Fill [param tween] with the tweens that move the window to [param target] over [param time].
## The tween may be shared with sibling windows and set to parallel, so add steps that
## stand on their own rather than relying on them chaining one after another.
func _build(tween: Tween, target: float, time: float) -> void:
	tween.tween_property(_win(), "scale:y", target, time)
