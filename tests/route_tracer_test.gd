extends Node

## Headless assertions over [RouteTracer] (code/events/route_tracer.gd): the one-path walk
## the editor's route overlay draws.
##
##     godot --headless --path . res://tests/route_tracer_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("events -- RouteTracer")
	print("")

	_test_straight_moves_then_random_then_loop()
	_test_first_branch_and_markers()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _node(id: String, command: String, args: Dictionary, outputs: Array) -> Dictionary:
	return {"id": id, "command": command, "args": args, "outputs": outputs}


func _test_straight_moves_then_random_then_loop() -> void:
	_section("a graph of moves that loops back on itself stops where it would repeat")

	var nodes: Array = [
		_node("s", "start", {}, [{"flow": "next", "target": "a"}]),
		_node("a", "move_by", {"cells": [2, 0, 0]},
			[{"flow": "reached", "target": "b"}, {"flow": "immediate", "target": ""}]),
		_node("b", "move_by", {"cells": "wander"},
			[{"flow": "reached", "target": "c"}, {"flow": "immediate", "target": ""}]),
		_node("c", "move_to", {"cell": [5, 0, 3]},
			[{"flow": "reached", "target": "a"}, {"flow": "immediate", "target": ""}]),
	]
	var segments := RouteTracer.trace(nodes, Vector3i.ZERO)

	_eq(segments.size(), 4, "a line, a random marker, a line, then the loop mark")
	_eq(segments[0]["kind"], "line", "the literal move_by draws a line")
	_eq(segments[0]["to"], Vector3i(2, 0, 0), "two cells east of the start")
	_eq(segments[1]["kind"], "random", "wander is a random marker")
	_eq(segments[1]["at"], Vector3i(2, 0, 0), "at the cell it would happen in")
	_eq(segments[2]["to"], Vector3i(5, 0, 3), "move_to draws to its cell, from where the trace was")
	_eq(segments[3]["kind"], "loop", "re-entering node a ends the trace with a loop mark")
	_eq(segments[3]["at"], Vector3i(5, 0, 3), "where the loop closes")


func _test_first_branch_and_markers() -> void:
	_section("a branch follows its first wired output, and unknowable steps are marked")

	var nodes: Array = [
		_node("s", "start", {}, [{"flow": "next", "target": "q"}]),
		_node("q", "if", {"condition": "true"},
			[{"flow": "true", "target": "f"}, {"flow": "false", "target": "never"}]),
		_node("f", "move_by", {"cells": "forward:3"},
			[{"flow": "reached", "target": "t"}, {"flow": "immediate", "target": ""}]),
		_node("t", "move_by", {"cells": "towards_player"},
			[{"flow": "reached", "target": "j"}, {"flow": "immediate", "target": ""}]),
		_node("j", "jump", {"cell": [0, 0, 0]},
			[{"flow": "reached", "target": ""}, {"flow": "blocked", "target": ""},
				{"flow": "immediate", "target": ""}]),
		_node("never", "move_to", {"cell": [9, 9, 9]}, []),
	]
	var segments := RouteTracer.trace(nodes, Vector3i(1, 0, 1), Vector3i(1, 0, 0))

	_eq(segments[0]["kind"], "line", "forward:3 draws a line")
	_eq(segments[0]["to"], Vector3i(4, 0, 1), "three cells along the starting facing")
	_eq(segments[1]["kind"], "unknown", "towards_player is an unknown marker")
	_eq(segments[2]["kind"], "line", "jump draws a line")
	_eq(segments[2]["dashed"], true, "dashed, since the arc is not a walk")
	_eq(segments.size(), 3, "and the \"false\" branch was never followed")


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, what if got == want else "%s (got %s, want %s)" % [what, str(got), str(want)])
