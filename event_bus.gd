extends Node

## Project-wide signal hub. Nothing here holds game state or reaches into nodes - it
## just lets a sender fire an event without knowing who, if anyone, is listening.
##
## Autoloaded as [code]EventBus[/code].

## Asks for [param text] to be shown in the dialogue window. [param options] is a
## free-form bag the dialogue reader understands; unknown keys are ignored.
## Recognised keys:
## [codeblock]
## location: int  # index into Dialogue's locations, see Dialogue.Location
## append: bool   # follow the message before it, no outro/intro between
## [/codeblock]
## [param key] identifies this message so the sender can recognise its own
## completion; empty means the sender does not care.
signal dialogue_enqueue(text: String, options: Dictionary, key: String)

## Fired once a queued message has been read through and the window has closed.
## [param key] is the one the message was queued with, so a sender can await its
## own message finishing:
## [codeblock]
## var key := EventBus.say("Hello.")
## while await EventBus.dialogue_finished != key:
##     pass
## [/codeblock]
signal dialogue_finished(key: String)

## Convenience wrapper so callers can say [code]EventBus.say("...")[/code] instead of
## emitting by hand. Returns the key the message was queued under - the one passed
## in, or a fresh one from [method new_key] when [param key] is left empty.
func say(text: String, options: Dictionary = {}, key: String = "") -> String:
	if key == "":
		key = _new_key()
	dialogue_enqueue.emit(text, options, key)
	return key

func append_say(text: String, options: Dictionary = {}, key: String = "") -> String:
	options = options.duplicate()
	options["append"] = true
	return say(text, options, key)

func wait_for(key: String) -> void:
	if key == "":
		return

	while true:
		var finished_key: String = await dialogue_finished
		if finished_key == key:
			return

## A random identifier, unique enough to tell one in-flight message from another.
func _new_key() -> String:
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in bytes.size():
		bytes[i] = randi() % 256
	return bytes.hex_encode()
