class_name InputProfile extends Resource

## How raw input becomes an [InputIntent] for one game.
##
## The thing this must handle that nothing before it did: the moment game 2's camera
## rotates, "up" on the stick is no longer -Z. Input direction has to be resolved
## through the camera basis and then re-quantised. Get it wrong and rotation feels
## broken in a way that is hard to diagnose later.

## Directions a movement intent snaps to. 4 for game 1's grid, 8 for game 2. 0 means
## a fully analog stick, which no shipping profile uses.
@export_range(0, 8, 4) var direction_count: int = 4

## Resolve the stick through the camera's yaw. False only for a fixed-camera game
## where screen up should always mean world north.
@export var view_relative: bool = true

## Does a tap that only changes facing count as a turn rather than a step? Game 1's
## "turn in place" - and the reason turning opens no round, since it changes no cell.
@export var tap_turns_in_place: bool = true

## Seconds a direction must be held before it becomes a step rather than a turn.
@export var turn_grace: float = 0.12

## Discrete stepping. The cadence is set by round completion rather than a repeat
## timer, so holding a direction means "step again the moment the round closes, if
## still held".
@export var discrete_steps: bool = true


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
