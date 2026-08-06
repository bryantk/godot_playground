class_name ZoomWindowAnimation
extends TextWindowAnimation

## Grows the window out of a zero-size point at its own bottom-right corner, up to
## full size at its resting spot. The outro shrinks back down into that same corner.
##
## The growth runs in a fixed number of [member steps] rather than continuously:
## above ~50 the jumps are smaller than a pixel and it reads as a clean tween, below
## that it pops from size to size like a low-framerate effect.

## How many discrete sizes the window passes through between closed and open.
@export_range(1, 240, 1, "or_greater") var steps := 12
## Park the window closed on ready instead of leaving it at full size.
@export var start_closed := false

# 0..1 progress, written one step at a time by _build. Always equal to the scale on
# screen, so _progress() reports where the window really is.
var zoom := 1.0:
	set(value):
		zoom = clampf(value, 0.0, 1.0)
		scale = Vector2(zoom, zoom)

func _ready() -> void:
	super()
	if start_closed:
		zoom = 0.0

func _progress() -> float:
	return zoom

func _layout() -> void:
	# Scaling about the bottom-right corner keeps that corner pinned while the rest
	# of the window collapses toward it, so no position writes are needed - which
	# leaves Dialogue.set_window_location free to move us whenever it likes.
	pivot_offset = size

func _build(tween: Tween, target: float, time: float) -> void:
	var count := maxi(steps, 1)
	var from := zoom
	var to := 1.0 if target >= 1.0 else 0.0

	# One hard jump per step, each held for an equal slice of the run, so the whole
	# animation lands on exactly [param time] no matter how many steps there are.
	var hold := time / float(count)
	for i in count:
		var value: float = lerpf(from, to, float(i + 1) / float(count))
		tween.tween_callback(func() -> void: zoom = value).set_delay(hold)
