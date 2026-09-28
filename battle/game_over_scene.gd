class_name GameOverScene extends Control

## What a defeat swaps to when [member BattleTransfer.allow_defeat] is false (the
## default) - see [method BattleScene._finish]. Terminal on purpose: nothing here
## resumes whatever graph called [code]start_battle[/code] (its own runner is left to
## hang, per [member BattleTransfer.allow_defeat]'s own doc); the only way out is
## [method SaveGame.load] or a fresh start.

const NEW_GAME_SCENE := "res://games/jrpg/jrpg_demo.tscn"

@onready var _load_button: Button = %LoadButton
@onready var _new_game_button: Button = %NewGameButton


func _ready() -> void:
	_load_button.disabled = not SaveGame.can_load()
	_load_button.pressed.connect(_on_load_pressed)
	_new_game_button.pressed.connect(_on_new_game_pressed)


func _on_load_pressed() -> void:
	_load_button.disabled = true
	_new_game_button.disabled = true
	await SaveGame.load()


func _on_new_game_pressed() -> void:
	GameState.clear()
	Party.clear()
	EventScheduler.reset()
	ModeStack.reset()
	get_tree().change_scene_to_file(NEW_GAME_SCENE)
