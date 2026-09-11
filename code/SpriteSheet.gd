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
@export var paused = false

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

	timer = rate
	_cycle = wrap(_cycle + 1, 0, anim_cycle.size())
	set_facing(facing)
	
	if _stop_next_frame && !step_in_place:
		_stop_next_frame = false
		_cycle = 0
		set_facing(facing)
		running = false
		timer = 0.1
