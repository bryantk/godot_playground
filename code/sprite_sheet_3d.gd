@tool
extends Sprite3D
class_name SpriteSheet3D

## [SpriteSheet] against a [Sprite3D], for the billboarded sprites in a 3D map.
##
## Deliberately a twin rather than a shared base: [Sprite2D] and [Sprite3D] have no
## common ancestor that carries [code]frame[/code], [code]hframes[/code] and
## [code]flip_h[/code], which is the same reason [Actor] is a plain [Node] and the space
## adapter exists. The exports and the public API are identical on purpose, so the two
## can be read side by side - if the cycle behaviour changes in one, change it in both.

@export var anim_cycle: Array[int] = [1, 0, 1, 2]

## Row per [enum FacingUtils.Facings], in DOWN, RIGHT, UP, LEFT order. A negative entry
## means "row |n|, mirrored", which is how one side-on row serves both left and right.
@export var facing_offsets: Array[int] = [0, -2, 1, 2]

## Seconds per frame of [member anim_cycle].
@export var rate := 0.25

@export var facing: FacingUtils.Facings = FacingUtils.Facings.DOWN:
	set(value):
		facing = value
		set_facing(facing)

@export var step_in_place := false
@export var paused := false

var running := false
var _stop_next_frame := false
var _cycle := 0

@onready var timer = rate


func animating(active: bool) -> void:
	if active:
		begin_animating()
	else:
		request_stop_animating()


func request_stop_animating() -> void:
	_stop_next_frame = true


func begin_animating() -> void:
	_stop_next_frame = false
	running = true


func _ready() -> void:
	set_facing(facing)


func set_facing(f: FacingUtils.Facings) -> void:
	var index: int = facing_offsets[int(f)]
	flip_h = index < 0
	frame = hframes * absi(index) + anim_cycle[_cycle]


func _is_active() -> bool:
	return step_in_place or running


func _physics_process(delta: float) -> void:
	if paused or not _is_active() or Engine.is_editor_hint():
		return

	timer -= delta
	if timer > 0:
		return

	timer = rate
	_cycle = wrapi(_cycle + 1, 0, anim_cycle.size())
	set_facing(facing)

	if _stop_next_frame and not step_in_place:
		_stop_next_frame = false
		_cycle = 0
		set_facing(facing)
		running = false
		timer = 0.1
