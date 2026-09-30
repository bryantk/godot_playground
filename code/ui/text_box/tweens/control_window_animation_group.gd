class_name ControlWindowAnimationGroup
extends ControlWindowAnimation

## Combines several [ControlWindowAnimation] children into one look: [method intro]
## and [method outro] fire all of them into a single tween running in parallel, so a
## caller only has to await the one returned tween. Each child drives this node - the
## window - rather than itself, so a slide and a zoom can play over the same control.
## Being a window animation itself, a group can also be nested inside another group.
##
## [member duration] is a multiplier here rather than a time - each child still
## animates over its own duration, scaled by ours.

## Where to look for the animations to run. Leave unset to use our own children.
@export var target: Control = null

var _children: Array[ControlWindowAnimation] = []

# Gathered here rather than in _ready: _enter_tree runs top-down, so the children get
# told which window they drive before their own _ready parks them closed.
func _enter_tree() -> void:
	var parent: Control = target if target != null else self
	_children.clear()

	for child in parent.get_children():
		if child is ControlWindowAnimation:
			_children.append(child)
			# We stand in for the window; a group above us may have named a different
			# one, in which case pass that along instead.
			if child.window == null:
				child.window = _win()

func intro(tween: Tween = null, time_scale := 1.0) -> Tween:
	return _run(&"intro", tween, time_scale)

func outro(tween: Tween = null, time_scale := 1.0) -> Tween:
	return _run(&"outro", tween, time_scale)

## Runs [param method] on every child, all sharing one tween - [param tween] when a
## group above us handed one down, otherwise one of our own. Returns null when
## nothing had anything to animate; an empty tween never finishes, so awaiting it
## would hang.
func _run(method: StringName, tween: Tween, time_scale: float) -> Tween:
	if _tween != null:
		_tween.kill()

	var owned := tween == null
	if owned:
		tween = create_tween()
	else:
		tween.set_parallel(true)

	var started := false
	for child in _children:
		# A child with nothing to do (already open, say) returns null or its own
		# in-flight tween; only a child that built into ours counts.
		if child.call(method, tween, duration * time_scale) == tween:
			started = true

	if not started:
		# Only ours is safe to drop - a parent's tween may hold other windows' steps.
		if owned:
			tween.kill()
		return null

	_tween = tween
	tween.finished.connect(func() -> void: _tween = null)
	return tween

# --- Virtuals -----------------------------------------------------------------

## Nothing of our own to park - every child closes the window in its own terms, and
## whichever of them touch the same property agree on where closed is.
func _close() -> void:
	for child in _children:
		child._close()

## Measuring is the children's business; we hold no state that depends on the layout.
func _layout() -> void:
	for child in _children:
		child._layout()

## The least-open child, so the group only reads as open once all of them are.
func _progress() -> float:
	var progress := 1.0
	for child in _children:
		progress = minf(progress, child._progress())
	return progress
