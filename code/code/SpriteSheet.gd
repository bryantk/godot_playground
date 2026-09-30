@tool
extends Sprite2D
class_name SpriteSheet

@export var anim_cycle = [1, 0, 1, 2]
@export var facing_offsets = [0, -2, 1, 2]
@export var rate = 0.25
@export var facing: FacingUtils.Facings = FacingUtils.Facings.DOWN:
	set(value):
		facing = value
		set_facing(facing)
			
@export var step_in_place = false

## Freezes the whole walk cycle outright, independent of which frame [member
## anim_cycle] happens to be on - a page's own [code]lock_animation[/code]
## ([ActorView.lock_animation]), not [method hold_frame]: picking a frame is a pose,
## this is a lock, and the two used to be (wrongly) the same flag. See [method
## hold_frame]'s own doc for why they no longer are.
@export var paused = false

## Multiplies into every [member rate] wait - how fast the whole cycle advances,
## independent of the sheet's own authored pace. 1.0 ("Normal") leaves [member rate]
## exactly as authored; driven by a page's own [code]animation_speed[/code]
## ([ActorView.animation_speed_scale]) or [code]set_animation_speed[/code] mid-graph.
@export var animation_speed_scale := 1.0

var running = false
var _stop_next_frame = false

@onready var timer = rate
## internal tracking of animation loop
var _cycle = 0

func animating(active: bool):
	if active:
		begin_animating()
	else:
		request_stop_animating()

func request_stop_animating():
	_stop_next_frame = true
	
func begin_animating():
	_stop_next_frame = false
	running = true

## Freezes on one exact frame, bypassing [member anim_cycle]/[member facing_offsets]
## entirely - a held pose (pointing, sitting, surprised) rather than a step of the walk
## cycle. [param mirror] flips the frame the same way a negative [member
## facing_offsets] entry does.
##
## [b]Does not touch [member paused][/b] - a picked frame is only ever a starting pose,
## not a lock: [member running] going false here is what holds it (the same way
## standing still already does, with nothing new to clear), and the ordinary
## [method animating]/walk-cycle hookup ([code]who.is_travelling()[/code], polled every
## frame by [SpriteView2D]/[SpriteView3D]) sets [member running] straight back to true
## and resumes the cycle the moment the actor next moves - a page that wants the pose
## to survive that has to say so itself, with its own [code]lock_animation[/code].
func hold_frame(row: int, col: int, mirror: bool = false) -> void:
	running = false
	_stop_next_frame = false
	flip_h = mirror
	frame = hframes * row + col

func _ready() -> void:
	#offset.x = -(texture.get_width() / float(hframes)) / 2.0
	set_facing(facing)	

func set_facing(f: FacingUtils.Facings):
	var index = facing_offsets[int(f)]
	self.flip_h = index < 0
	self.frame = hframes * abs(index) + anim_cycle[_cycle]

func _pausing(p: bool):
	paused = p

func _is_active() -> bool:
	return step_in_place || running

func _physics_process(delta: float) -> void:
	if paused || !_is_active() || Engine.is_editor_hint():
		return
		
	timer -= delta
	if timer > 0:
		return

	timer = rate / maxf(animation_speed_scale, 0.001)
	_cycle = wrap(_cycle + 1, 0, anim_cycle.size())
	set_facing(facing)
	
	if _stop_next_frame && !step_in_place:
		_stop_next_frame = false
		_cycle = 0
		set_facing(facing)
		running = false
		timer = 0.1
