extends Node

## Headless assertions that [DebugFlags.is_fast_forward] actually collapses a real
## [Dialogue] window - not just the [code]say[/code]/[code]append_say[/code]
## executors' own latch-wait (event_runner_test.gd's own mocked version of this) but
## the genuine [RichTextBlock] reveal, the window's own intro/outro tween, and the
## page-to-page scroll a multi-page message parks on waiting for a real press.
##
##     godot --headless --path . res://tests/dialogue_fast_forward_test.tscn

const DIALOGUE_SCENE := "res://code/ui/text_box/dialogue.tscn"

var _passed := 0
var _failed := 0

## Written by [method _on_dialogue_finished] - not a lambda closing over a local, which
## in GDScript captures by value and would never let the signal callback write back to
## a variable the awaiting loop below can see.
var _finished_key := ""


func _ready() -> void:
	print("")
	print("dialogue -- a real Dialogue window collapses under DebugFlags.is_fast_forward")
	print("")

	await _test_multi_page_message_finishes_in_a_handful_of_frames()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


## At this scene's own authored [code]characters_per_second = 20.0[/code], a message
## this long (8 lines, twice [member Dialogue.max_lines]) takes several real seconds to
## reveal even before the window's own intro/outro tweens and the forced pause between
## pages - so finishing inside a handful of process frames only happens if fast-forward
## is actually collapsing the reveal, the inter-page wait, and both tweens, not merely
## the say/append_say executors' own latch wait (already covered, with everything here
## mocked out, by event_runner_test.gd's own _test_say_blocks_until_finished).
func _test_multi_page_message_finishes_in_a_handful_of_frames() -> void:
	_section("Dialogue -- a long, multi-page message finishes fast under fast-forward")

	var was_forced := DebugFlags.force_fast_forward
	DebugFlags.force_fast_forward = true

	var dialogue := (load(DIALOGUE_SCENE) as PackedScene).instantiate()
	add_child(dialogue)
	await get_tree().process_frame

	_finished_key = ""
	EventBus.dialogue_finished.connect(_on_dialogue_finished)

	var text := "Line 1\nLine 2\nLine 3\nLine 4\nLine 5\nLine 6\nLine 7\nLine 8"
	var key := EventBus.say(text)

	const FRAME_BUDGET := 30
	var frames := 0
	while _finished_key != key and frames < FRAME_BUDGET:
		await get_tree().process_frame
		frames += 1

	_ok(_finished_key == key,
		"dialogue_finished fired for this message within %d frames (got %d)" % [FRAME_BUDGET, frames])

	EventBus.dialogue_finished.disconnect(_on_dialogue_finished)
	DebugFlags.force_fast_forward = was_forced
	dialogue.queue_free()
	for i in 3:
		await get_tree().process_frame


func _on_dialogue_finished(key: String) -> void:
	_finished_key = key


# -- Assertion helpers ---------------------------------------------------------------

func _section(title: String) -> void:
	print("  %s" % title)

func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1
