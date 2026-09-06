class_name SimpleMenu
extends VBoxContainer

signal on_return()

@onready var _return_button: Button = $Button
@onready var _exit_button: Button = $Button2

func _ready() -> void:
	# Buttons must stay responsive while the tree is paused.
	self.process_mode = Node.PROCESS_MODE_ALWAYS
	_return_button.pressed.connect(_on_return_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)

func _on_return_pressed() -> void:
	on_return.emit()

func _on_exit_pressed() -> void:
	get_tree().quit()
