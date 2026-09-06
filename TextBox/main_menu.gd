extends Control

@export var dialogue: Dialogue = null
@export var pause_menu: SimpleMenu = null

func _ready() -> void:
	pause_menu.hide()
	pause_menu.on_return.connect(_resume)
	#TODO: temp
	InputManager.attach(self)
	dialogue.set_window_location(1)

func _resume() -> void:
		get_tree().paused = false
		pause_menu.hide()
		InputManager.attach(self)

func action(pressed: bool) -> void:
	dialogue.action(pressed)

func cancel(_pressed: bool) -> void:
	dialogue.cancel(false)

func pause(pressed: bool) -> void:
	if not pressed:
		return

	InputManager.attach(null)
	get_tree().paused = true
	print("pause")
	pause_menu.visible = true

func debug2(pressed: bool) -> void:
	if not pressed:
		return
	dialogue._finished()

func debug(pressed: bool) -> void:
	if not pressed:
		return

	print("pressed")
	dialogue.display(
"""Line 1
Line 2
Line 3
Line 4
2 Line 5
2 Line 6
2 Line 7
2 Line 8""")