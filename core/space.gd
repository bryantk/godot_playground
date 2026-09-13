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


## [param v] snapped to the texel grid [i]as the camera sees it[/i]: rounded along the
## basis' screen-right and screen-up axes, left alone along the view axis.
##
## Snapping on world axes instead is the subtle version of this that does not work. At
## any pitch the camera's up axis is not world Y, so a world-axis round and a
## basis-axis round land on different grids, their remainders never cancel, and
## anything snapped one way while the camera snaps the other beats against it by up to
## a texel. Everything that participates in pixel alignment has to round the same
## quantity through here.
static func snap_to_basis(v: Vector3, b: Basis, texels_per_unit: float) -> Vector3:
	if texels_per_unit <= 0.0:
		return v
	var r: float = round(v.dot(b.x) * texels_per_unit) / texels_per_unit
	var u: float = round(v.dot(b.y) * texels_per_unit) / texels_per_unit
	return b.x * r + b.y * u + b.z * v.dot(b.z)


## The horizontal direction that the camera compresses, and by how much.
##
## A tilted camera flattens the ground: a horizontal move toward or away from the eye
## covers [code]sin(pitch)[/code] of the screen distance the same move covers sideways,
## which is why walking "up" the screen at pitch 30 feels half speed. Returns that
## direction as a unit vector with [code]sin(pitch)[/code] as its length, or ZERO when
## there is nothing to compensate - a top-down camera, or the identity basis a 2D game
## never replaces.
##
## Derivation, so nobody has to re-derive it: for a horizontal [param v] the screen-up
## coordinate is [code]v.dot(b.y)[/code], and the horizontal part of [code]b.y[/code] is
## the ground-forward axis scaled by [code]-sin(pitch)[/code]. So this vector *is* the
## compression, read straight off the basis rather than from a pitch the caller would
## have to be told separately.
static func depth_axis(b: Basis) -> Vector3:
	return flatten(b.y)


## [param v] with its screen-depth component stretched so it covers the same screen
## distance per second as a sideways move, blended by [param strength] (0 none, 1 full).
##
## Deliberately scales the component rather than the whole vector: uniform screen speed
## is exactly what an anisotropic world gives you, so a diagonal gets stretched only in
## the part of it that the projection squashed. World space stops being isotropic, which
## is the trade - distances and speeds along depth are no longer world units.
##
## [param b] is the camera basis, pushed by the rig. An unset basis is the identity,
## whose depth axis is zero, so an un-pushed mover and a 2D game both pass through
## untouched with no branch anywhere else.
static func compensate_depth(v: Vector3, b: Basis, strength: float,
		max_factor: float = INF) -> Vector3:
	var axis := depth_axis(b)
	var compression := axis.length()
	# A zero-length depth axis means there is no depth direction to stretch: the identity
	# basis a 2D game never replaces, or a camera looking straight down where nothing is
	# compressed in the first place. Either way there is nothing to do, and 1 /
	# compression would be a division by zero.
	if compression < 0.01:
		return v
	var along := v.dot(axis) / compression
	# Capped before the strength blend, so max_factor means what it says at full strength.
	# Without it a near-flat camera asks for an unbounded boost - 1 / sin(5 degrees) is
	# 11x - and the actor leaves the map. See MotionController.max_depth_boost.
	var factor := lerpf(1.0, minf(1.0 / compression, max_factor), clampf(strength, 0.0, 1.0))
	return v + (axis / compression) * along * (factor - 1.0)


## Which 90-degree stop a camera yaw is at, 0 through 3. Games 2 and 3 rotate the
## view, which is what makes a sprite's frame depend on more than its own facing.
static func yaw_index(yaw_radians: float) -> int:
	return posmod(roundi(yaw_radians / (PI * 0.5)), 4)


## The sprite frame to show for a world facing seen from a yawed camera.
##
## With 8 facings and 4 yaw stops this is exact: frames sit 45 degrees apart and each
## stop is 90, so a stop is worth exactly two frames. No rounding, and no yaw at which
## some frame has no art.
##
## [b]The yaw is added, not subtracted, and the reason is a handedness trap.[/b] The two
## angles run in opposite directions: [method facing_index] measures clockwise seen from
## above, matching [constant DIRS_8], while Godot's [member Node3D.rotation] y is
## counter-clockwise seen from above. So the camera's angle expressed in the facing
## convention is [i]minus[/i] the yaw index, and removing it from the world facing is a
## subtraction of a negative.
##
## Subtracting looks right and is wrong at exactly half the stops, which is what makes it
## worth a paragraph: the error is [code]count / 2[/code], and at stops 0 and 2 that is
## zero modulo [param count]. Front and back views stay correct and the two side views
## come out reversed - the actor moons the camera - so the bug hides until someone
## rotates the view a quarter turn.
static func view_frame(dir: Vector3, yaw_radians: float, count: int = 4) -> int:
	var per_stop := count / 4
	return posmod(facing_index(dir, count) + yaw_index(yaw_radians) * per_stop, count)
