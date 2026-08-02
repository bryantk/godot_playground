@tool
class_name RichTextSound
extends AudioStreamPlayer

## Plays a sound as a [RichTextBlock] reveals its text.
##
## Attach this to a child node of a [RichTextBlock]. Depending on [member trigger],
## it plays [member sound] either as each character is revealed or as each word
## begins.

## When the sound plays: on each character, or at the start of each word.
enum Trigger { PER_CHARACTER, PER_WORD }

## The block to listen to. Defaults to the parent node if left empty.
var block: RichTextBlock
## What causes the sound to play.
@export var trigger: Trigger = Trigger.PER_CHARACTER
## The sound played on each trigger.
@export var sound: AudioStream
## Code evaluated on each trigger to compute the stream's pitch. Must return a
## float. Use [code]{character}[/code] to reference the revealed character/word,
## e.g. [code]1.0 + {c}.length() * 0.1[/code]. or
## [code]{c}.to_lower().unicode_at(0) / 100.0 + 0.5[/code]
## Leave empty for pitch 1.0.
@export var pitch_expression: String = "":
	set(value):
		pitch_expression = value
		_compile_pitch_expression()

## Play the sound once every this many triggers. 1 plays for every character,
## 2 for every other, 3 for every third, and so on. Skipped triggers are silent.
@export_range(1, 20) var play_every: int = 1

# Compiled form of [member pitch_expression]; null when no expression is set.
var _pitch_expression: Expression
# Running count of triggers received, used to decide which ones play.
var _trigger_count: int = 0


func _ready() -> void:
	if Engine.is_editor_hint():
		return

	if block == null:
		block = get_parent() as RichTextBlock

	if block == null:
		push_warning("RichTextSound has no RichTextBlock to listen to.")
		return

	if sound == null:
		push_warning("RichTextSound has no audio file to play.")
		return

	self.stream = sound
	_compile_pitch_expression()
	block.on_character_displayed.connect(_on_char_start)
	block.on_word_start.connect(_on_word_start)

func _on_word_start(text: String) -> void:
	_trigger_count = 0
	if trigger == Trigger.PER_WORD:
		_triggered(text)

func _on_char_start(text: String) -> void:
	# Only every play_every-th trigger makes a sound; the rest are skipped.
	var should_play := _trigger_count % play_every == 0
	_trigger_count += 1
	if not should_play:
		return
	if trigger == Trigger.PER_CHARACTER:
		_triggered(text)

func _triggered(text: String) -> void:
	self.pitch_scale = _evaluate_pitch(text)
	self.play()


# Parse [member pitch_expression] once, binding {character} to an input variable.
func _compile_pitch_expression() -> void:
	if pitch_expression.strip_edges() == "":
		return
	var expression := Expression.new()
	# {character} is exposed to the user; internally it is the input "character".
	var code := pitch_expression.replace("{c}", "character")
	if expression.parse(code, ["character"]) != OK:
		push_warning("RichTextSound pitch expression failed to parse: %s"
			% expression.get_error_text())
		return
	_pitch_expression = expression


# Run the compiled expression with the current character/word, returning the
# pitch. Falls back to 1.0 when there is no expression or evaluation fails.
func _evaluate_pitch(character: String) -> float:
	if _pitch_expression == null:
		return 1.0
	var result = _pitch_expression.execute([character])
	if _pitch_expression.has_execute_failed():
		push_warning("RichTextSound pitch expression failed to run: %s"
			% _pitch_expression.get_error_text())
		return 1.0
	return float(result)

func _exit_tree() -> void:
	if block == null:
		return
	if block.on_character_displayed.is_connected(_on_char_start):
		block.on_character_displayed.disconnect(_on_char_start)
	if block.on_word_start.is_connected(_on_word_start):
		block.on_word_start.disconnect(_on_word_start)


# Debug
func _enter_tree() -> void:
	update_configuration_warnings()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		update_configuration_warnings()

func _get_configuration_warnings() -> PackedStringArray:
	var parent := get_parent()
	if parent == null:
		return ["RichTextSound must be a child of a RichTextBlock node."]
	if not parent is RichTextBlock:
		return ["RichTextSound's parent must be of type RichTextBlock (got %s)." % parent.get_class()]
	return []
