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

var _actor: Actor = null
var _keys := 0


func _ready() -> void:
	_actor = get_parent() as Actor


func actor() -> Actor:
	return _actor


func context() -> MapContext:
	return _actor.context() if _actor != null else null


func adapter() -> SpaceAdapter:
	return _actor.adapter() if _actor != null else null


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
