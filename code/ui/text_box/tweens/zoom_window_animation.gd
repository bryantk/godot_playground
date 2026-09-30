class_name ZoomWindowAnimation
extends ControlWindowAnimation

## Grows the window out of a zero-size point at [member anchor], up to full size at
## its resting spot. The outro shrinks back down into that same point.
##
## The growth runs in a fixed number of [member steps] rather than continuously:
## above ~50 the jumps are smaller than a pixel and it reads as a clean tween, below
## that it pops from size to size like a low-framerate effect.

## Which corner/edge the window collapses into. Pick
## [constant Anchor_Constants.AnchorPreset.CUSTOM] to type a point by hand in [member anchor].
@export var anchor_preset := Anchor_Constants.AnchorPreset.BOTTOM_RIGHT:
	set(value):
		anchor_preset = value
		if value != Anchor_Constants.AnchorPreset.CUSTOM:
			anchor = Anchor_Constants.anchor(value)
		notify_property_list_changed()

## The point the window zooms out of, in fractions of its own size: (0, 0) is the
## top-left corner, (1, 1) the bottom-right. Values outside 0..1 zoom toward a
## point off the window entirely, which is allowed.
@export var anchor := Vector2.ONE:
	set(value):
		anchor = value
		_layout()

## How many discrete sizes the window passes through between closed and open.
@export_range(1, 240, 1, "or_greater") var steps := 12

# 0..1 progress, written one step at a time by _build. Always equal to the scale on
# screen, so _progress() reports where the window really is.
var zoom := 1.0:
	set(value):
		zoom = clampf(value, 0.0, 1.0)
		_win().scale = Vector2(zoom, zoom)

func _close() -> void:
	zoom = 0.0

func _progress() -> float:
	return zoom

func _validate_property(property: Dictionary) -> void:
	# The raw point is only worth showing when a preset isn't already driving it.
	if property.name == "anchor" and anchor_preset != Anchor_Constants.AnchorPreset.CUSTOM:
		property.usage |= PROPERTY_USAGE_READ_ONLY

func _layout() -> void:
	# Scaling about the anchor keeps that point pinned while the rest of the window
	# collapses toward it, so no position writes are needed - which leaves
	# Dialogue.set_window_location free to move us whenever it likes.
	_win().pivot_offset = _win().size * anchor

func _build(tween: Tween, target: float, time: float) -> void:
	var count := maxi(steps, 1)
	var from := zoom
	var to := 1.0 if target >= 1.0 else 0.0

	# One hard jump per step, each held for an equal slice of the run, so the whole
	# animation lands on exactly [param time] no matter how many steps there are.
	# Quantizing inside the method keeps this to a single tween step, which means it
	# reads the same whether the tween runs on its own or in parallel with others -
	# a chain of delayed callbacks would collapse to a single instant jump there.
	tween.tween_method(
		func(t: float) -> void: zoom = lerpf(from, to, floorf(t * count) / count),
		0.0, 1.0, time)
