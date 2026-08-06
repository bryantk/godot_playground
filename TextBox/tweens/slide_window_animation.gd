class_name SlideWindowAnimation
extends TextWindowAnimation

## Slides the window in from the left edge of the screen and out past the right edge.

## Extra pixels past the screen edge, so a shadow or outline clears the view too.
@export var margin := 16.0
## Park the window offscreen on ready instead of leaving it at its authored spot.
@export var start_closed := false

# Offset from the resting spot, in local x. Everything else works in these terms so
# the window can be repositioned (see Dialogue.set_window_location) between animations.
var slide_offset := 0.0:
	set(value):
		slide_offset = value
		# Moving the window notifies us right back, so claim the write before making it.
		_applied_x = _rest_x + value
		_applying = true
		position.x = _applied_x
		_applying = false

var _rest_x := 0.0
var _left := 0.0
var _right := 0.0
var _applied_x := 0.0
var _applying := false

func _enter_tree() -> void:
	# Control only reports transform changes on request, and we need to hear about
	# anyone repositioning the window so the offset does not drift out of sync.
	set_notify_transform(true)

func _notification(what: int) -> void:
	match what:
		NOTIFICATION_TRANSFORM_CHANGED, NOTIFICATION_RESIZED:
			if is_inside_tree():
				_layout()

func _ready() -> void:
	super()
	if start_closed:
		slide_offset = _right

func _layout() -> void:
	_sync_rest()
	_measure()

func _prepare(target_progress: float) -> void:
	# Intros always come from the left, so jump there unless we are already on that side.
	if is_equal_approx(target_progress, 1.0) and slide_offset >= 0.0:
		slide_offset = _left

func _progress() -> float:
	if is_zero_approx(slide_offset):
		return 1.0

	var travel := _right if slide_offset > 0.0 else -_left
	if is_zero_approx(travel):
		return 1.0

	return clampf(1.0 - absf(slide_offset) / travel, 0.0, 1.0)

func _build(tween: Tween, target: float, time: float) -> void:
	tween.tween_property(self, "slide_offset", 0.0 if target >= 1.0 else _right, time)

# Anyone writing position themselves (Dialogue.set_window_location) is choosing a new
# resting spot, so re-anchor to it and re-apply however far we were slid.
func _sync_rest() -> void:
	if _applying or is_equal_approx(position.x, _applied_x):
		return

	var was_closed := slide_offset > 0.0 and is_zero_approx(_progress())
	_rest_x = position.x
	_measure()
	# Writing this back re-enters through the setter, which refreshes _applied_x.
	slide_offset = _right if was_closed else 0.0

func _measure() -> void:
	var rest_global_x := global_position.x - (position.x - _rest_x)
	var width := size.x * scale.x
	_left = -(rest_global_x + width + margin)
	_right = get_viewport_rect().size.x - rest_global_x + margin
