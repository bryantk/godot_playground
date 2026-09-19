class_name MainUI
extends Control

## The one piece of UI every map scene shares: dialogue, the pause menu, and now the
## debug readout each demo used to keep its own per-scene HUD [Label] for. A map calls
## [method set_debug_text] instead of owning a label of its own, so the same overlay -
## and the same 640x320 frame it already sits in - is what shows it.

@export var dialogue: Dialogue = null
@export var pause_menu: SimpleMenu = null
@export var debug_label: Label = null


## The hook a map (or anything else with a [MainUI] reference) writes its debug readout
## through - cell, facing, control hints, whatever that scene wants on screen. Replaces
## the whole text each call, the same way the per-scene HUD labels this superseded did.
func set_debug_text(text: String) -> void:
	debug_label.text = text

func _ready() -> void:
	self.show()
	pause_menu.hide()
	pause_menu.on_return.connect(_resume)
	#TODO: temp
	InputManager.attach(self)
	dialogue.set_window_location(1)

func _resume() -> void:
		get_tree().paused = false
		pause_menu.hide()
		InputManager.attach(self)

func _message() -> void:
	EventBus.append_say("hello there mate.")

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

	print("go")
	_message()
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