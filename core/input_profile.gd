class_name InputProfile extends Resource

## How raw input becomes an [InputIntent] for one game.
##
## The thing this must handle that nothing before it did: the moment game 2's camera
## rotates, "up" on the stick is no longer -Z. Input direction has to be resolved
## through the camera basis and then re-quantised. Get it wrong and rotation feels
## broken in a way that is hard to diagnose later.
##
## What is [i]not[/i] here: whether steps are discrete. That follows from the actor's
## [MotionController] - [Brain] hands a [GridMotion] a committed step and a [FreeMotion]
## continuous steering - so a profile that also declared it would be a second source of
## truth for the one thing [MapContext.default_motion] is allowed to override.

## Directions a movement intent snaps to. 4 for game 1's grid, 8 for game 2. 0 means
## a fully analog stick, which no shipping profile uses.
@export_range(0, 8, 4) var direction_count: int = 4

## Resolve the stick through the camera's yaw. False only for a fixed-camera game
## where screen up should always mean world north.
@export var view_relative: bool = true

## Turning in place is a held modifier - the [code]turn_in_place[/code] action, Q -
## rather than a tap under a grace timer, so there is nothing to tune here.
##
## [b]Why the tap went.[/b] A tap-versus-hold rule makes the first frames of every step
## ambiguous: the game cannot know whether a press is a step or a turn until the grace
## has elapsed, so either the step is delayed by that long or a turn retroactively
## cancels one. A modifier key is unambiguous on the frame it arrives, and it can be
## held across several turns without the timer resetting under your fingers.


## [param raw] as a world-space direction, resolved through [param camera_yaw] and
## snapped to [member direction_count].
##
## The yaw rotation happens before the snap, never after: snapping in screen space and
## then rotating would give eight directions that drift off the world axes as the
## camera turns, which is the bug that is hard to see and impossible to unsee.
func resolve(raw: Vector2, camera_yaw: float) -> Vector3:
	if raw.length_squared() < 0.0001:
		return Vector3.ZERO

	var dir := Vector3(raw.x, 0.0, raw.y)
	if view_relative and not is_zero_approx(camera_yaw):
		dir = dir.rotated(Vector3.UP, camera_yaw)

	if direction_count <= 0:
		return dir.limit_length(1.0)

	var snapped := Space.quantise(dir, direction_count)
	return Vector3(snapped).normalized() * minf(1.0, raw.length())
