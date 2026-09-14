class_name MotionController extends Node

## How an actor moves. [GridMotion] steps cell to cell; [FreeMotion] moves
## continuously and jumps. Both speak [Vector3i] cells and [Vector3] world positions,
## so nothing above here knows which is in play.
##
## Every long-running call returns a completion key, matching the pattern
## [method EventBus.say] uses - the caller awaits it or ignores it. That is also what
## makes a round a join over keys rather than a special mechanism.

## Cells per second for a grid stepper, world units per second for a free one.
@export var speed: float = 6.0

## How much of the camera's depth compression to cancel out of this actor's speed.
## 0 leaves motion in honest world units; 1 makes every direction cover the same screen
## pixels per second.
##
## [b]Why this exists.[/b] Under a tilted camera a horizontal move toward the eye
## projects to [code]sin(pitch)[/code] of the screen distance the same move covers
## sideways - at pitch 30 that is half - so walking up or down the screen reads as
## sluggish even though the actor is moving at the same world speed. Compensating here
## rather than changing the projection keeps the floor tile geometry the rig's pixel
## alignment depends on.
##
## [b]What it costs.[/b] World space stops being isotropic: the actor genuinely covers
## more world units per second along depth, so a distance in world units is no longer a
## time. Set it to 0 on anything whose world speed must stay literal.
##
## Inert until a rig pushes a basis, so 2D games ignore this without a branch.
@export_range(0.0, 1.0, 0.01) var depth_compensation: float = 1.0

## Ceiling on the depth speed-up, as a multiple of [member speed].
##
## [b]Why a ceiling is needed at all.[/b] The honest compensation is
## [code]1 / sin(pitch)[/code], which is well behaved at the angles this game actually
## uses - 2x at 30 degrees, 1.15x at 60 - and runs away as the camera approaches flat:
## 11x at 5 degrees, unbounded at 0. Now that [member OrthoPixelRig.pitch_degrees] opens
## all the way to a flat-on elevation, an uncapped boost turns a shallow angle into an
## actor that crosses the map in a frame.
##
## 3.0 corresponds to a pitch of about 19.5 degrees. Below that the compensation simply
## stops growing rather than doing something clever, because at a near-flat camera the
## depth axis is nearly invisible and no speed makes movement along it read properly.
@export var max_depth_boost: float = 3.0

var _actor: Actor = null
var _keys := 0
var _view_basis: Basis = Basis.IDENTITY

## Objects answering [code]scale_for(actor, dir) -> float[/code]. See
## [method add_speed_provider].
var _speed_providers: Array[Object] = []


func _ready() -> void:
	_actor = get_parent() as Actor


func actor() -> Actor:
	return _actor


func context() -> MapContext:
	return _actor.context() if _actor != null else null


func adapter() -> SpaceAdapter:
	return _actor.adapter() if _actor != null else null


## The camera basis to read depth compression off, pushed by the rig each frame the
## same way it pushes the pixel grid to views.
##
## Pushed rather than pulled because the mover would otherwise have to reach for a rig
## and know its pitch, and because the axis rotates: at yaw stops 0 and 2 depth is world
## Z, at 1 and 3 it is world X. Taking the whole basis is what makes this correct at
## every stop instead of only the one it was authored at.
func set_view_basis(b: Basis) -> void:
	_view_basis = b


## [param v] with the camera's depth compression cancelled out of it, per
## [member depth_compensation]. Horizontal input; returns it unchanged when no rig has
## pushed a basis.
func compensate(v: Vector3) -> Vector3:
	return Space.compensate_depth(v, _view_basis, depth_compensation, max_depth_boost)


# -- Speed modifiers ----------------------------------------------------------

## Register something that scales this actor's speed while it lasts - a [SpeedModifier]
## on a patch of mud, and later a status effect or an equipped item.
##
## [b]A provider, not a value, and that is the whole design.[/b] Nothing writes
## [member speed], so nothing has to remember what it was and put it back: the modifier
## is a thing that is asked, and removing it restores the actor by arithmetic rather than
## by bookkeeping. Two consequences worth having: a route that sets its own speed mid-mud
## is not clobbered when the mud ends, and a rule that depends on which way the actor is
## facing can be answered honestly, because the question carries the direction.
##
## Providers are asked every frame, so a scale may change mid-cell.
func add_speed_provider(p: Object) -> void:
	if p != null and not _speed_providers.has(p):
		_speed_providers.append(p)


func remove_speed_provider(p: Object) -> void:
	_speed_providers.erase(p)


## Every provider's scale for a step in [param dir], multiplied together.
##
## Multiplicative rather than smallest-wins: two overlapping slow zones are slower than
## either, which is what stacking mud on ice should do and what keeps the result
## independent of the order the zones were entered in.
func speed_scale(dir: Vector3) -> float:
	var scale := 1.0
	var stale := false
	for p in _speed_providers:
		if not is_instance_valid(p):
			stale = true
			continue
		scale *= float(p.call("scale_for", _actor, dir))
	if stale:
		_speed_providers = _speed_providers.filter(is_instance_valid)
	return maxf(0.0, scale)


func _next_key(kind: String) -> String:
	_keys += 1
	return "%s:%s:%d" % [kind, _actor.actor_id if _actor != null else "?", _keys]


# -- To implement -------------------------------------------------------------

## One cell in [param dir]. False if blocked - a rejected step is ordinary, not an
## error, and is what makes walking into a wall feel like walking into a wall.
func step(_dir: Vector3i) -> bool:
	return false


## [param opts] carries [code]speed[/code], [code]path[/code] ("line" / "astar" /
## "raw"), [code]through_walls[/code] and [code]blocking[/code].
func move_to(_cell: Vector3i, _opts: Dictionary = {}) -> String:
	return ""


func move_by(delta: Vector3i, opts: Dictionary = {}) -> String:
	if _actor == null:
		return ""
	return move_to(_actor.cell() + delta, opts)


func face(dir: Vector3i) -> void:
	if _actor != null:
		_actor.set_facing(dir)


## Free motion only. [GridMotion] warns rather than silently doing nothing, which is
## also what the [code]height[/code] capability tag catches at authoring time.
func jump(_strength: float) -> String:
	push_warning("MotionController: jump is not available to this actor's motion.")
	return ""


func cancel() -> void:
	pass


func is_busy() -> bool:
	return false


## Is the actor physically translating right now?
##
## Deliberately not the same question as [method is_busy], which means "still working
## through a command" - that is what a round joins on and what stops a second step being
## accepted mid-step. An input-steered free actor is travelling and not busy; a grid
## actor mid-tween is both. Presentation wants this one: it is what decides whether a
## walk cycle plays.
func is_travelling() -> bool:
	return is_busy()
