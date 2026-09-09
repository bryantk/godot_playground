class_name Space

## Static projections between the canonical 3D vocabulary and the 2D one, plus the
## direction quantisation every presentation layer needs.
##
## Nothing else in the project is allowed to write [code]Vector2(v.x, v.z)[/code] by
## hand - it all comes through here, so the axis choice lives in one file. No state,
## all static, mirroring [Anchor_Constants] in style.
##
## Y is up. A 2D map is a 3D map flattened at [code]y = 0[/code].

# -- Projection ---------------------------------------------------------------

static func as_v2(v: Vector3) -> Vector2:
	return Vector2(v.x, v.z)


static func as_v2i(c: Vector3i) -> Vector2i:
	return Vector2i(c.x, c.z)


static func as_v3(v: Vector2, y: float = 0.0) -> Vector3:
	return Vector3(v.x, y, v.y)


static func as_v3i(c: Vector2i, y: int = 0) -> Vector3i:
	return Vector3i(c.x, y, c.y)


## [param v] with its height stripped but still 3D, for comparing positions on a
## single floor without dropping to [Vector2].
static func flatten(v: Vector3) -> Vector3:
	return Vector3(v.x, 0.0, v.z)


# -- Directions ---------------------------------------------------------------
#
# North is -Z, matching Godot's forward. Both lists run clockwise seen from above,
# so an index into either is a facing and the two agree wherever they overlap:
# DIRS_8[i * 2] == DIRS_4[i].

const DIRS_4: Array[Vector3i] = [
	Vector3i(0, 0, -1),   # N
	Vector3i(1, 0, 0),    # E
	Vector3i(0, 0, 1),    # S
	Vector3i(-1, 0, 0),   # W
]

const DIRS_8: Array[Vector3i] = [
	Vector3i(0, 0, -1),   # N
	Vector3i(1, 0, -1),   # NE
	Vector3i(1, 0, 0),    # E
	Vector3i(1, 0, 1),    # SE
	Vector3i(0, 0, 1),    # S
	Vector3i(-1, 0, 1),   # SW
	Vector3i(-1, 0, 0),   # W
	Vector3i(-1, 0, -1),  # NW
]


## The directions a facing count offers. Only 4 and 8 are meaningful; anything else
## falls back to 4 rather than returning an empty list a caller would index into.
static func dirs(count: int) -> Array[Vector3i]:
	return DIRS_8 if count == 8 else DIRS_4


## Which of [param count] facings [param dir] points at, as an index into
## [method dirs]. A zero direction has no answer, so it reads as north (0) - callers
## that care about "no direction at all" should test [param dir] themselves.
static func facing_index(dir: Vector3, count: int = 4) -> int:
	if is_zero_approx(dir.x) and is_zero_approx(dir.z):
		return 0

	# atan2(x, -z) is 0 at north and grows clockwise, matching the DIRS_* order.
	var angle := atan2(dir.x, -dir.z)
	var step := TAU / float(count)
	return posmod(roundi(angle / step), count)


## [param dir] snapped to the nearest of [param count] world directions. This is the
## one place input becomes a discrete direction, so a grid game and a sprite's facing
## cannot disagree about where "north-east" is.
static func quantise(dir: Vector3, count: int = 4) -> Vector3i:
	if is_zero_approx(dir.x) and is_zero_approx(dir.z):
		return Vector3i.ZERO
	return dirs(count)[facing_index(dir, count)]


## Which 90-degree stop a camera yaw is at, 0 through 3. Games 2 and 3 rotate the
## view, which is what makes a sprite's frame depend on more than its own facing.
static func yaw_index(yaw_radians: float) -> int:
	return posmod(roundi(yaw_radians / (PI * 0.5)), 4)


## The sprite frame to show for a world facing seen from a yawed camera.
##
## With 8 facings and 4 yaw stops this is exact: frames sit 45 degrees apart and each
## stop is 90, so a stop is worth exactly two frames. No rounding, and no yaw at which
## some frame has no art.
static func view_frame(dir: Vector3, yaw_radians: float, count: int = 4) -> int:
	var per_stop := count / 4
	return posmod(facing_index(dir, count) - yaw_index(yaw_radians) * per_stop, count)
