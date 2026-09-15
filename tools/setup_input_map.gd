extends Node

## Adds the input actions the three demos need, and persists them to project.godot so
## they are rebindable in the editor rather than invented at runtime:
##
##     godot --headless --path . res://tools/setup_input_map.tscn
##
## Only adds what is missing, so re-running it never clobbers a binding.

const ACTIONS := {
	"move_up":    [KEY_W, KEY_UP],
	"move_down":  [KEY_S, KEY_DOWN],
	"move_left":  [KEY_A, KEY_LEFT],
	"move_right": [KEY_D, KEY_RIGHT],
	"jump":       [KEY_SPACE],
	# Shift runs in both games now. It used to be shared with turn_in_place, on the
	# reasoning that a grid game never runs - which stopped being true on 2026-09-14,
	# when GridMotion learned to shorten a step. Turning in place moved to Q rather than
	# the two contending.
	"run":        [KEY_SHIFT],
	# Note this collides with yaw_ccw, also Q, in isoish_grid_demo - the only scene that
	# is both a grid map and a rotatable camera. Game 1 proper has no yaw.
	"turn_in_place": [KEY_Q],
	"wait_step":  [KEY_PERIOD],
	"yaw_ccw":    [KEY_Q],
	"yaw_cw":     [KEY_E],
	"toggle_a":   [KEY_1],
	"toggle_b":   [KEY_2],
	"toggle_c":   [KEY_3],
	"back":       [KEY_ESCAPE],
}


func _ready() -> void:
	var added := 0
	for action: String in ACTIONS:
		var path := "input/%s" % action

		var events: Array[InputEvent] = []
		for keycode: Key in ACTIONS[action]:
			var ev := InputEventKey.new()
			ev.physical_keycode = keycode
			# -1 is "any device", matching the actions already in project.godot. A
			# fresh InputEventKey does not default to it, and a device id that does
			# not match the real keyboard makes the action silently never fire.
			ev.device = -1
			events.append(ev)

		ProjectSettings.set_setting(path, {"deadzone": 0.2, "events": events})
		print("wrote   %s" % action)
		added += 1

	if added > 0:
		var err := ProjectSettings.save()
		if err != OK:
			printerr("failed to save project.godot (%d)" % err)
			get_tree().quit(1)
			return
	print("%d actions added" % added)
	get_tree().quit(0)
