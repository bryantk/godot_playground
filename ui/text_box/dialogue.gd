class_name Dialogue
extends Control

signal finished

@export var max_lines:= 4
@export_group("References")
@export var text_block: RichTextBlock = null
@export var cursor: Control
@export var window: Control
@export var locations: Control

enum Location { TOP, MIDDLE, BOTTOM }

## Messages waiting their turn, oldest first. Each entry is
## [code]{"text": String, "options": Dictionary, "key": String}[/code].
var _queue: Array[Dictionary] = []
## The message on screen right now, or an empty dictionary between messages.
var _current: Dictionary = {}
## Set by [method _finished] when it hands a still-open window straight to an
## appended follow-up, and cleared by the [method display] that takes it. Only a
## message that finished on screen can pass this on, so the first message of a run
## always gets its intro no matter how it was queued.
var _handed_open_window: bool = false

func _ready() -> void:
	text_block.on_finished.connect(_finished)
	text_block.on_page_displayed.connect(_on_page_displayed)
	EventBus.dialogue_enqueue.connect(_on_dialogue_enqueue)

func set_window_location(index: int) -> void:
	if index < 0 or index >= locations.get_child_count():
		push_error("set_window_location: no location at index %d" % index)
		return

	var location: Control = locations.get_child(index)
	# Control.global_position folds in the window's own pivot-scale offset, so writing
	# it while the window sits collapsed (a zoom animation parked closed) shoves
	# position pivot_offset * (1 - scale) the other way to compensate - hundreds of
	# pixels offscreen once the intro scales back up. Zeroing the pivot makes this a
	# plain parent-space move; the animation rebuilds its own pivot in _layout().
	var pivot: Vector2 = window.pivot_offset
	window.pivot_offset = Vector2.ZERO
	window.global_position = location.global_position
	window.pivot_offset = pivot

## Queues [param text] behind whatever is already on screen. See [method display]
## for the keys [param options] understands.
func _on_dialogue_enqueue(text: String, options: Dictionary, key: String = "") -> void:
	_queue.push_back({"text": text, "options": options, "key": key})
	_next()

## Starts the oldest queued message, if the window is free to take one.
func _next() -> void:
	if not _current.is_empty() or _queue.is_empty():
		return

	var message: Dictionary = _queue.pop_front()
	display(message.text, message.options, message.key)

## Puts [param text] on screen now, replacing whatever the window was showing.
##
## [param options] is a free-form bag; unrecognised keys are ignored. Recognised:
## [codeblock]
## location: int  # where the window sits, index into locations - see Location
## append: bool   # follow the message before this one, no outro/intro between
## [/codeblock]
## Any [code]append[/code] value other than [code]false[/code] counts, so the key
## simply being present is enough. An appended message is an ordinary message that
## takes over a window already open: the block still clears and the text still
## reveals from the start, but the window neither closes behind the message ahead
## of it nor animates back in, and it stays where it is ([code]location[/code] is
## ignored). With no message on screen to follow it opens the window and plays the
## intro like any other, so appending only chains off a message that finished while
## this one was already queued behind it.
##
## [param key] is echoed back on [signal EventBus.dialogue_finished] when the
## message is done, so a sender can await its own message. Empty means nobody is
## waiting on this one. Each appended message keeps its own key and reports
## finished separately.
func display(text: String, options: Dictionary = {}, key: String = "") -> void:
	self.show()
	_current = {"text": text, "options": options, "key": key}

	var continues: bool = _handed_open_window
	_handed_open_window = false

	cursor.visible = false
	text_block.reset()

	if not continues:
		var location: int = options.get("location", -1)
		if location >= 0:
			set_window_location(location)

		await _animate_window(&"intro", true)

	text_block.display(text)

## True when [param options] asks for the message to continue the one before it.
## The key being present is enough; only an explicit [code]false[/code] opts out.
func _appends(options: Dictionary) -> bool:
	return options.has("append") and options["append"] != false

func _finished() -> void:
	cursor.visible = false

	# The message waiting behind this one decides whether the window closes: an
	# appended follow-up takes the window over as it stands, so the outro is skipped
	# and the block is left alone for display() to clear as it starts.
	var continued: bool = not _queue.is_empty() and _appends(_queue[0].options)
	if not continued:
		await _animate_window(&"outro", false)
		text_block.reset()

	var message: Dictionary = _current
	_current = {}

	self.hide()
	finished.emit()
	if not message.is_empty():
		EventBus.dialogue_finished.emit(message.key)

	# Set last: a listener above may have queued and started a message of its own,
	# and that one is opening the window from scratch rather than taking ours.
	_handed_open_window = continued
	_next()

## Runs the window's [param method] animation if it has one, otherwise falls back to
## toggling visibility to [param shown]. Always awaitable.
func _animate_window(method: StringName, shown: bool) -> void:
	if not window.has_method(method):
		window.visible = shown
		return

	var tween: Tween = window.call(method)
	if tween != null:
		text_block.pause()
		await tween.finished

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

func debug2(pressed: bool) -> void:
	if not pressed:
		return
	_finished()

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
