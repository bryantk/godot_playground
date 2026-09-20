class_name SimpleMenu
extends VBoxContainer

## The pause menu - shown by [method MainUI.pause]. Return/Exit are the original two;
## Save/Load/Reset (SaveGame's own action, stage E) just emit signals the same way
## Return does, so [MainUI] is the one place that decides what "leaving the menu"
## involves (unpausing, re-attaching input) regardless of which button asked for it.

signal on_return()
signal on_save()
signal on_load()
signal on_reset()

@onready var _return_button: Button = $Button
@onready var _exit_button: Button = $Button2
@onready var _save_button: Button = $SaveButton
@onready var _load_button: Button = $LoadButton
@onready var _reset_button: Button = $ResetButton

func _ready() -> void:
	# Buttons must stay responsive while the tree is paused.
	self.process_mode = Node.PROCESS_MODE_ALWAYS
	_return_button.pressed.connect(_on_return_pressed)
	_exit_button.pressed.connect(_on_exit_pressed)
	_save_button.pressed.connect(func(): on_save.emit())
	_load_button.pressed.connect(func(): on_load.emit())
	_reset_button.pressed.connect(func(): on_reset.emit())

func _on_return_pressed() -> void:
	on_return.emit()

func _on_exit_pressed() -> void:
	get_tree().quit()

## Refreshed whenever the menu is about to be shown - see [method MainUI.pause] - so a
## fresh game (no slot written yet) doesn't offer a Load that can only fail.
func refresh() -> void:
	_load_button.disabled = not SaveGame.can_load()
