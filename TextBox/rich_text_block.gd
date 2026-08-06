@tool

class_name RichTextBlock
extends RichTextLabel

## Emitted each time a non-punctuation character is revealed.
signal on_character_displayed(character: String)
## Emitted when the first character of a word is revealed (punctuation stripped).
signal on_word_start(word: String)
## Emitted each time a full word finishes revealing (punctuation stripped).
signal on_word_displayed(word: String)
## Emitted once the whole block has finished revealing.
signal on_finished()
## Emitted when a line of text is full
signal on_line_displayed(line: int, next_block: bool)
## Emitted when the last line of a block (page) of text is full.
signal on_page_displayed(page: int, ratio: float)
## Emitted the first time the reveal enters a [dc ..] data block. Carries the
## start character index and the tag's parsed attributes (e.g. {"wait": "0.5"}).
signal on_data_block_entered(index: int, data: Dictionary)
signal on_data_block_exit(index: int, data: Dictionary)

## Glyphs that are still shown, but do NOT count as characters or word parts.
## They never trigger [signal on_character_displayed] and are stripped from
## the word passed to [signal on_word_displayed].
const PUNCTUATION := [
	".", ",", "!", "?", ";", ":", "-", "—", "…",
	"\"", "'", "(", ")", "[", "]", "{", "}", "/",
	"=", "+"
]

## Characters revealed per second. Higher is faster.
@export var characters_per_second: float = 30.0
## Rate that text will exit at
@export_range(1.0, 2000.0) var scroll_speed:= 256.0
## Rate to accelerate the wait time for 
@export var text_rate: float = 1
@export var speedup_rate:= 2.0
## Max number of lines of text
@export var _max_lines:= 4:
	set(value):
		_max_lines = value
		update_configuration_warnings()
@export var post_scroll_delay:= 0.2
@export_group("Animation Behavior")
## Do not wait for input at end of the block.
@export var auto_scroll_block:= false
## When false, the whole text is shown immediately with no animation.
@export var animate: bool = true

var request_speed_up:= false

enum States { PAUASED, REVEALING, TRANSITION, WAITING }

var _plain: String
var _state:= States.PAUASED
var _char_accumulator: float = 0.0
var _current_word: String = ""
var _top_line:= 0
var _displayed_line:= 0
var _scroll_accumulator:= 0.0

var _wait_remaining: float = 0.0
var _data_effect: BBC_Data     # the attached [dc ..] effect
var _snapshot:= []


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	# Custom BBCode requires bbcode parsing and the effect to be registered
	# before the text is parsed.
	bbcode_enabled = true
	_attach_data_effect()

	var line_height = self.get_line_height(0)
	if line_height * _max_lines != self.size.y:
		print("Text window requested %s lines at %s pixels. %s provided." % [_max_lines, line_height * _max_lines, self.size.y])

	# If text was authored in the editor, reveal it automatically.
	if text != "":
		display(text)
	else:
		# Otherwise reveal is driven manually; hide everything until display().
		self.visible_characters = 0

const SPEED_TAG = "speed"
func _push_snapshot() -> void:
	_snapshot.push_back(
		{
			SPEED_TAG: characters_per_second,
		}
	)

func _pop_snapshot() -> void:
	if _snapshot.size() <= 1:
		return
	var snap = _snapshot.pop_back()
	snap = _snapshot.back()
	if snap.has(SPEED_TAG):
		characters_per_second = snap[SPEED_TAG]

# Ensure a BBC_Data effect is present in custom_effects and points back at us,
# so it can call register_wait() when it parses a [dc wait=..] tag.
func _attach_data_effect() -> void:
	for effect in custom_effects:
		if effect is BBC_Data:
			effect.block = self
			_data_effect = effect
			return
	var data_effect := BBC_Data.new()
	data_effect.block = self
	_data_effect = data_effect
	custom_effects = custom_effects + [data_effect]

func _process(delta: float) -> void:
	match _state:
		States.REVEALING:
			_advance_text(delta)
		States.TRANSITION:
			_animate_transition(delta)


## State in which we process and advance text one character at a time
func _advance_text(delta: float) -> void:
	if _state != States.REVEALING:
		return

	delta *= text_rate
	if request_speed_up:
		delta *= speedup_rate
	# Hold the reveal while a [dc wait=..] pause is counting down.
	if _wait_remaining > 0.0:
		_wait_remaining -= delta
		return

	_char_accumulator += characters_per_second * delta
	# Reveal as many characters as the accumulated time allows this frame.
	while _char_accumulator >= 1.0 and self.visible_characters < self.get_total_character_count():
		_char_accumulator -= 1.0
		_reveal_next_character()
	if self.visible_characters >= self.get_total_character_count():
		_finish()

func _animate_transition(delta: float) -> void:
	var goal = self.get_line_offset(_displayed_line)
	var scroll = self.get_v_scroll_bar()
	_scroll_accumulator += delta * scroll_speed
	if scroll_speed >= 2000:
		scroll.value = goal
		_scroll_accumulator = 0
	while _scroll_accumulator >= 1.0:
		scroll.value += 1
		_scroll_accumulator -= 1.0
	if scroll.value >= goal:
		scroll.value = goal
		_state = States.REVEALING

## Build the newlines that fill the current text out to whole pages, plus one
## blank page for the last page to scroll up into on the way out.
##
## Must be called while the label already holds the text being measured, since
## the fill depends on the wrapped line count.
func _block_padding() -> String:
	var partial_lines := self.get_line_count() % _max_lines
	var fill_lines := (_max_lines - partial_lines) % _max_lines

	var padding := ""
	for x in range(fill_lines + _max_lines):
		# The space keeps the padded line from being collapsed away.
		padding += "\n "
	return padding

func pause() -> void:
	_state = States.PAUASED

## Set the block's text and begin revealing it one character at a time.
func display(new_text: String) -> void:
	# Measure the wrapped line count, then re-assign with the padding baked in.
	# add_text() would not write back to `text`, so a repeat call with the same
	# string would no-op the setter and stack another block of padding.
	self.text = new_text
	self.text = new_text + _block_padding()
	self.get_v_scroll_bar().value = 0
	_top_line = 0
	_displayed_line = 0
	_char_accumulator = 0.0
	_current_word = ""
	_wait_remaining = 0.0
	_plain = get_parsed_text()
	if _data_effect != null:
		_data_effect.reset()

	if not animate or characters_per_second <= 0.0:
		_finish()
		return

	_push_snapshot()
	self.visible_characters = 0
	_state = States.REVEALING

## Stop revealing and drop the block back to empty, ready for the next [method display].
## Nothing is emitted - this abandons the text rather than finishing it.
func reset() -> void:
	_state = States.PAUASED
	self.text = ""
	self.visible_characters = 0
	self.get_v_scroll_bar().value = 0
	_plain = ""
	_top_line = 0
	_displayed_line = 0
	_char_accumulator = 0.0
	_scroll_accumulator = 0.0
	_current_word = ""
	_wait_remaining = 0.0
	# A [dc speed=..] block may have been left open, so restore the authored rate
	# from the base snapshot instead of keeping whatever it was overridden to.
	if not _snapshot.is_empty():
		characters_per_second = _snapshot[0][SPEED_TAG]
		_snapshot.clear()
	if _data_effect != null:
		_data_effect.reset()

## Instantly reveal all remaining text, emitting any pending signals.
func skip() -> void:
	if _state != States.REVEALING:
		return

	_finish()

func _reveal_next_character() -> void:
	# The character about to become visible sits at the current index.
	var index := self.visible_characters
	self.visible_characters += 1

	if index >= _plain.length():
		return

	_handle_data_command_at(index)
	_handle_data_command_exit_at(index)
	var character := _plain[index]

	if self.get_character_line(index + 1) > _displayed_line:
		_new_text_line()

	if PUNCTUATION.has(character) or character.strip_edges() == "":
		# Punctuation ends a word but is not part of it.
		# Whitespace separates words but is not a character part.
		_flush_word()
		return

	if _current_word == "":
		# This character opens a new word; announce the whole word up front.
		on_word_start.emit(_word_at(index))

	on_character_displayed.emit(character)
	_current_word += character

func _handle_data_command_at(index: int) -> void:
	var data := _data_effect.data_at(index)
	if data.is_empty():
		return

	_push_snapshot()
	on_data_block_entered.emit(index, data)
	var wait_command_time := float(data.get(BBC_Data.WAIT_TAG, 0.0))
	if wait_command_time > 0.0:
		_wait_remaining = wait_command_time
	
	var speed := float(data.get("speed", 0.0))
	if speed > 0.0:
		characters_per_second = speed

func _new_text_line():
	_displayed_line += 1
	var next_block = _displayed_line - _top_line >= _max_lines
	if next_block:
		_top_line += _max_lines
		if auto_scroll_block:
			_state = States.TRANSITION
		else:
			_state = States.WAITING
	on_line_displayed.emit(_displayed_line - 1, next_block)
	if not next_block:
		return

	_wait_remaining = post_scroll_delay
	if _displayed_line + _max_lines == self.get_line_count():
		_wait_remaining = 0
	@warning_ignore("integer_division")
	on_page_displayed.emit(_displayed_line / _max_lines, float(_displayed_line) / self.get_line_count())

# Fire on_DC_exit for any [dc ..] block whose wrapped text ends just before
# [param index] (i.e. start + length == index — the first glyph past the block).
func _handle_data_command_exit_at(index: int) -> void:
	for start in _data_effect._registered:
		var data: Dictionary = _data_effect._registered[start]
		var length := int(data.get(BBC_Data.LENGTH_TAG, 0))
		if start + length == index:
			_pop_snapshot()
			on_data_block_exit.emit(index, data)

## Read forward from [param start] to build the word (punctuation stripped)
## that begins at that index.
func _word_at(start: int) -> String:
	var word := ""
	var index := start
	while index < _plain.length():
		var character := _plain[index]
		if character.strip_edges() == "" or PUNCTUATION.has(character):
			break
		word += character
		index += 1
	return word

func _flush_word() -> void:
	if _current_word != "":
		on_word_displayed.emit(_current_word)
		_current_word = ""

func _finish() -> void:
	_wait_remaining = 0.0
	_flush_word()
	_state = States.PAUASED
	self.visible_characters = -1  # -1 shows all characters.
	on_finished.emit()

func advance() -> bool:
	match _state:
		States.PAUASED:
			return true
		States.WAITING:
			_state = States.TRANSITION
			return true
		States.REVEALING:
			pass
		_:
			print("error state: %s" % _state)
	return false


# Debug
func _enter_tree() -> void:
	# NOTIFICATION_TRANSFORM_CHANGED is opt-in; without this, changing `scale`
	# never notifies us (only `size` fires NOTIFICATION_RESIZED).
	set_notify_transform(true)
	update_configuration_warnings()

func _notification(what: int) -> void:
	match what:
		# size changed / scale changed / font (line height) changed
		NOTIFICATION_RESIZED, NOTIFICATION_TRANSFORM_CHANGED, NOTIFICATION_THEME_CHANGED:
			update_configuration_warnings()

func _get_configuration_warnings() -> PackedStringArray:
	var line_height := get_line_height(0)
	var required_height := line_height * _max_lines
	if required_height != int(size.y):
		return ["Text window requested %s lines at %s pixels. %s provided." % [_max_lines, required_height, size.y]]

	return []
