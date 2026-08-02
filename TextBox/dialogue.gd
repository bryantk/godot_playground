extends Control

@export var max_lines:= 4
@export var text_block: RichTextBlock = null
@export var cursor: Control

func _ready() -> void:
	text_block.on_finished.connect(_finished)
	text_block.on_page_displayed.connect(_on_page_displayed)

	InputManager.attach(self)

func display(text: String) -> void:
	cursor.visible = false
	text_block.display(text)

func _finished() -> void:
	#TODO: close box
	print("end")

func _on_page_displayed(_page: int, _ratio: float) -> void:
	cursor.visible = true

func action(pressed: bool) -> void:
	_speed_up()
	if not pressed:
		return

	if text_block.advance():
		cursor.visible = false

func cancel(_pressed: bool) -> void:
	_speed_up()

func _speed_up() -> void:
	var input = InputManager.is_down(&"action") or InputManager.is_down(&"cancel")
	text_block.request_speed_up = input

func debug(pressed: bool) -> void:
	if not pressed:
		return

	display(
"""Line 1
Line 2
Line 3
Line 4
2 Line 5
2 Line 6
2 Line 7
2 Line 8""")
