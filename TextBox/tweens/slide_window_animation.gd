class_name SlideWindowAnimation
extends ControlWindowAnimation

## Slides the window off the screen and back on again. [member direction] picks the
## edge it leaves through - a corner sends it diagonally - and it always enters from
## the opposite one.

## The way out. [constant Anchor_Constants.AnchorPreset.CENTER_RIGHT] leaves to the right,
## [constant Anchor_Constants.AnchorPreset.TOP_CENTER] straight up,
## [constant Anchor_Constants.AnchorPreset.TOP_RIGHT] diagonally up and to the right.
@export var direction := Anchor_Constants.AnchorPreset.CENTER_RIGHT:
	set(value):
		direction = value
		_layout()

## Extra pixels past the screen edge, so a shadow or outline clears the view too.
@export var margin := 16.0

# Offset from the resting spot, in the window's parent space. Everything else works in
# these terms so the window can be repositioned (see Dialogue.set_window_location)
# between animations.
var slide_offset := Vector2.ZERO:
	set(value):
		slide_offset = value
		# Moving the window notifies us right back, so claim the write before making it.
		_applied = _rest + value
		_applying = true
		_win().position = _applied
		_applying = false

var _rest := Vector2.ZERO
# Offsets that park the window just off screen, on the way out and on the way in.
var _exit := Vector2.ZERO
var _enter := Vector2.ZERO
var _applied := Vector2.ZERO
var _applying := false

func _ready() -> void:
	# We need to hear about anyone else repositioning or resizing the window, so the
	# offset does not drift out of sync with where it actually sits.
	_win().item_rect_changed.connect(_on_window_rect_changed)
	super()

func _on_window_rect_changed() -> void:
	if is_inside_tree():
		_layout()

func _layout() -> void:
	if not is_inside_tree():
		return

	_sync_rest()
	_measure()

func _close() -> void:
	slide_offset = _exit

func _prepare(target_progress: float) -> void:
	# Intros always come from the entry side, so jump there unless we are already on it.
	if is_equal_approx(target_progress, 1.0) and slide_offset.dot(_enter) <= 0.0:
		slide_offset = _enter

func _progress() -> float:
	if slide_offset.is_zero_approx():
		return 1.0

	# However far we are along whichever side we currently sit on.
	var travel := _exit if slide_offset.dot(_exit) > 0.0 else _enter
	if travel.is_zero_approx():
		return 1.0

	return clampf(1.0 - slide_offset.length() / travel.length(), 0.0, 1.0)

func _build(tween: Tween, target: float, time: float) -> void:
	tween.tween_property(self, "slide_offset", Vector2.ZERO if target >= 1.0 else _exit, time)

# Anyone writing position themselves (Dialogue.set_window_location) is choosing a new
# resting spot, so re-anchor to it and re-apply however far we were slid.
func _sync_rest() -> void:
	var window_position := _win().position
	if _applying or window_position.is_equal_approx(_applied):
		return

	var was_closed := slide_offset.dot(_exit) > 0.0 and is_zero_approx(_progress())
	_rest = window_position
	_measure()
	# Writing this back re-enters through the setter, which refreshes _applied.
	slide_offset = _exit if was_closed else Vector2.ZERO

func _measure() -> void:
	_exit = _offscreen(direction)
	_enter = _offscreen(Anchor_Constants.reverse(direction))

## How far the window has to move along [param preset] to clear the screen entirely.
## Each axis is worked out on its own, so a corner preset clears both at once.
func _offscreen(preset: Anchor_Constants.AnchorPreset) -> Vector2:
	var win := _win()
	var towards := Anchor_Constants.direction(preset)
	var rest_global := win.global_position - (win.position - _rest)
	# Deliberately the unscaled size: a sibling animation may have the window scaled
	# down to nothing right now, and we want the distance that clears it once open.
	var window_size := win.size
	var view := get_viewport_rect().size
	var offset := Vector2.ZERO

	if towards.x > 0.0:
		offset.x = view.x - rest_global.x + margin
	elif towards.x < 0.0:
		offset.x = -(rest_global.x + window_size.x + margin)

	if towards.y > 0.0:
		offset.y = view.y - rest_global.y + margin
	elif towards.y < 0.0:
		offset.y = -(rest_global.y + window_size.y + margin)

	return offset
