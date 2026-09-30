@tool
extends Node

enum Voice { NORMAL, HIGH, LOW, MONO, INVERTED, NONE }

@export var voice: Voice = Voice.NORMAL

var _voice_functions := {
	Voice.NORMAL: _by_char("%s / 2.0 + 0.75"),
	Voice.HIGH: _by_char("%s / 2.0 + 1"),
	Voice.LOW: _by_char("%s / 2.0 + 0.5"),
	Voice.INVERTED: _by_char("(1-%s) + 0.5"),
	Voice.MONO: "1",
	Voice.NONE: "0",
}


func _ready() -> void:
	if Engine.is_editor_hint():
		return
	var rich_text_sound := get_parent()
	# TODO: Likely tie in sound and char% to each voice
	rich_text_sound.pitch_expression = _voice_functions[voice]

func _by_char(s: String):
	return s % "(({c}.to_lower().unicode_at(0) - 97) / 26.0)"

# Debug
func _enter_tree() -> void:
	update_configuration_warnings()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PARENTED or what == NOTIFICATION_UNPARENTED:
		update_configuration_warnings()

func _get_configuration_warnings() -> PackedStringArray:
	var parent := get_parent()
	if parent == null:
		return ["TextVoice must be a child of a RichTextSound node."]
	if not parent is RichTextSound:
		return ["TextVoice's parent must be of type RichTextSound (got %s)." % parent.get_class()]
	return []
