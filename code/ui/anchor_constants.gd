class_name Anchor_Constants

## Project-wide values and small helpers, all static - nothing here holds state.

## The nine named points of a control's rect, plus a slot for a hand-typed one.
enum AnchorPreset {
	TOP_LEFT, TOP_CENTER, TOP_RIGHT,
	CENTER_LEFT, CENTER, CENTER_RIGHT,
	BOTTOM_LEFT, BOTTOM_CENTER, BOTTOM_RIGHT,
	CUSTOM,
}

const ANCHORS: Array[Vector2] = [
	Vector2(0.0, 0.0), Vector2(0.5, 0.0), Vector2(1.0, 0.0),
	Vector2(0.0, 0.5), Vector2(0.5, 0.5), Vector2(1.0, 0.5),
	Vector2(0.0, 1.0), Vector2(0.5, 1.0), Vector2(1.0, 1.0),
]

## [param preset] as a fraction of a control's size: (0, 0) is the top-left corner,
## (1, 1) the bottom-right. [constant AnchorPreset.CUSTOM] has no point of its own,
## so it reads as the center.
static func anchor(preset: AnchorPreset) -> Vector2:
	if preset < 0 or preset >= ANCHORS.size():
		return ANCHORS[AnchorPreset.CENTER]
	return ANCHORS[preset]

## [param preset] as a direction pointing away from the center: (0, -1) is straight
## up, (1, -1) diagonally up and to the right, (0, 0) nowhere at all.
static func direction(preset: AnchorPreset) -> Vector2:
	return anchor(preset) * 2.0 - Vector2.ONE

## The preset facing the other way - [constant AnchorPreset.TOP_RIGHT] comes back as
## [constant AnchorPreset.BOTTOM_LEFT]. CENTER and CUSTOM have no opposite, so they
## come back unchanged.
static func reverse(preset: AnchorPreset) -> AnchorPreset:
	if preset == AnchorPreset.CUSTOM:
		return preset

	# The nine presets are laid out in reading order, so opposites are mirrored
	# around CENTER and always sum to BOTTOM_RIGHT.
	return (AnchorPreset.BOTTOM_RIGHT - preset) as AnchorPreset
