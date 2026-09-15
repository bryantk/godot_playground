extends Node

## Headless assertions over [EventCommand] - the registry, terse expansion, argument
## coercion and node validation.
##
##     godot --headless --path . res://tests/event_command_test.tscn
##
## The five documents in docs/events/ are parsed as part of this, deliberately: they are
## the worked examples the three design documents point at, so a change to the vocabulary
## that leaves them stale is a change that made the documentation wrong.

const EXAMPLES := "res://docs/events/"

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("events -- the command registry")
	print("")

	_test_registry()
	_test_terse()
	_test_directions()
	_test_coercion()
	_test_terms()
	_test_validation()
	_test_examples()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- The table itself ----------------------------------------------------------

## Every definition is well formed. This is the assertion that makes adding a command
## cheap: get the entry wrong in any of six ways and the suite says which.
func _test_registry() -> void:
	_section("definitions -- every entry is well formed")

	var types := [
		EventCommand.T_CELL, EventCommand.T_DIR, EventCommand.T_TURN,
		EventCommand.T_ACTOR, EventCommand.T_FLOAT, EventCommand.T_INT,
		EventCommand.T_BOOL, EventCommand.T_STRING, EventCommand.T_SECONDS,
		EventCommand.T_CONDITION, EventCommand.T_FLAG, EventCommand.T_VAR,
		EventCommand.T_KEY, EventCommand.T_CHOICES,
	]
	var resumes := [EventCommand.RESUME_RESTART, EventCommand.RESUME_STATE]
	var spaces := [EventCommand.SPACE_ANY, EventCommand.SPACE_GRID, EventCommand.SPACE_FREE]

	var defs := EventCommand.definitions()
	_ok(defs.size() >= 30, "the registry has %d commands" % defs.size())

	var bad_keys: Array[String] = []
	var bad_args: Array[String] = []
	for name: Variant in defs:
		var def: Dictionary = defs[name]
		for required in ["args", "flows", "blocking", "space", "resume"]:
			if not def.has(required):
				bad_keys.append("%s is missing \"%s\"" % [name, required])
		if not resumes.has(def.get("resume", "")):
			bad_keys.append("%s has an unknown resume bucket" % name)
		if not spaces.has(def.get("space", "")):
			bad_keys.append("%s has an unknown space" % name)

		for arg: Variant in def.get("args", {}):
			var declared := str(def["args"][arg]).trim_suffix("?")
			if not types.has(declared):
				bad_args.append("%s.%s is type \"%s\"" % [name, arg, declared])

	_ok(bad_keys.is_empty(), "every definition has all five keys%s"
		% ("" if bad_keys.is_empty() else " -- " + ", ".join(bad_keys)))
	_ok(bad_args.is_empty(), "every argument has a known type%s"
		% ("" if bad_args.is_empty() else " -- " + ", ".join(bad_args)))

	# Two commands deliberately end a path rather than continuing one, and the rest must
	# have somewhere to go: a linear command with no port is a graph that stops dead.
	var enders := ["end", "change_map", "ask"]
	var portless: Array[String] = []
	for name: Variant in defs:
		if (defs[name]["flows"] as Array).is_empty() and not enders.has(name):
			portless.append(str(name))
	_ok(portless.is_empty(), "only %s end a path%s"
		% [", ".join(enders), "" if portless.is_empty() else " -- also " + ", ".join(portless)])

	_ok(EventCommand.has_command("say"), "has_command finds a real one")
	_ok(not EventCommand.has_command("sing"), "and not an invented one")
	_ok(EventCommand.definition("sing").is_empty(),
		"definition of an unknown command is empty, not null")


# -- Terse forms ---------------------------------------------------------------

func _test_terse() -> void:
	_section("terse forms -- sugar that expands at the boundary (question 15)")

	# The exact string event_editor_dock.gd seeds a new command with.
	var seeded := _parse_one({"command": "mov n 2"})
	_eq(seeded["command"], "move_by", "\"mov n 2\" is a move_by")
	_eq(seeded["args"]["cells"], Vector3i(0, 0, -2), "  two cells north, north being -Z")

	var south := _parse_one({"command": "mov s 3"})
	_eq(south["args"]["cells"], Vector3i(0, 0, 3), "\"mov s 3\" goes the other way")

	var once := _parse_one({"command": "mov e"})
	_eq(once["args"]["cells"], Vector3i(1, 0, 0), "a missing count means one cell")

	# The point of the rule: both spellings land on the same structure, so nothing
	# downstream can tell which was typed.
	var long_form := _parse_one({"command": "move_by", "args": {"cells": [0, 0, -2]}})
	_eq(seeded["args"]["cells"], long_form["args"]["cells"],
		"terse and long forms produce the same structure")

	_eq(_parse_one({"command": "wait 1.5"})["args"]["seconds"], 1.5, "\"wait 1.5\" is seconds")
	_eq(_parse_one({"command": "face n"})["command"], "face_direction", "\"face n\" is face_direction")
	_eq(_parse_one({"command": "flag got_key"})["args"]["flag"], "got_key", "\"flag x\" sets a flag")

	# A trailing text argument keeps its spaces, which is the only reason `*` exists.
	var said := _parse_one({"command": "say Halt. The gate is closed."})
	_eq(said["args"]["text"], "Halt. The gate is closed.", "a terse say keeps its spaces")

	# A bare string is a command too - the dock is not the only thing that writes these.
	var bare := _parse_one("mov w 1")
	_eq(bare["args"]["cells"], Vector3i(-1, 0, 0), "a bare terse string parses as a command")

	var explicit := _parse_one({"command": "mov n 2", "args": {"speed": 3.0}})
	_eq(explicit["args"]["speed"], 3.0, "an explicit arg survives terse expansion")
	_eq(explicit["args"]["cells"], Vector3i(0, 0, -2), "  alongside the expanded one")

	_ok(_problems_of({"command": "mov q 2"}).size() > 0, "an unknown direction is reported")
	_ok(_problems_of({"command": "jog n 2"}).size() > 0, "an unknown terse alias is reported")


# -- Directions and turns ------------------------------------------------------

func _test_directions() -> void:
	_section("directions -- tokens agree with Space (question 41)")

	_eq(EventCommand.direction_of("n"), Vector3i(0, 0, -1), "north is -Z")
	_eq(EventCommand.direction_of("N"), Vector3i(0, 0, -1), "  and is case-insensitive")
	_eq(EventCommand.direction_of("north"), Vector3i(0, 0, -1), "  spelled out too")
	_eq(EventCommand.direction_of("ne"), Vector3i(1, 0, -1), "north-east is both")
	_eq(EventCommand.direction_of([1, 0, 0]), Vector3i(1, 0, 0), "a raw array is a direction")
	_eq(EventCommand.direction_of("up"), Vector3i.ZERO, "and \"up\" is not a compass direction")

	# The tokens must land on exactly the vectors Space uses, or a command and a sprite's
	# facing disagree about where north-east is.
	for i in Space.DIRS_4.size():
		var token: String = ["n", "e", "s", "w"][i]
		_eq(EventCommand.direction_of(token), Space.DIRS_4[i],
			"\"%s\" is Space.DIRS_4[%d]" % [token, i])

	_section("turns -- named by handedness, not degrees")

	var north := Vector3i(0, 0, -1)
	_eq(EventCommand.resolve_turn("turn_cw", north, 4), Vector3i(1, 0, 0),
		"turn_cw from north is east in a 4-direction game")
	_eq(EventCommand.resolve_turn("turn_ccw", north, 4), Vector3i(-1, 0, 0),
		"turn_ccw from north is west")
	_eq(EventCommand.resolve_turn("turn_180", north, 4), Vector3i(0, 0, 1),
		"turn_180 from north is south")

	# The whole reason the name carries no number: the same token is a different angle
	# in the two games, and a `turn_90` would have been a lie in one of them.
	_eq(EventCommand.resolve_turn("turn_cw", north, 8), Vector3i(1, 0, -1),
		"turn_cw from north is north-EAST in an 8-direction game")
	_eq(EventCommand.resolve_turn("turn_180", north, 8), Vector3i(0, 0, 1),
		"  while turn_180 is south in both")

	_eq(EventCommand.resolve_turn("e", north, 4), Vector3i(1, 0, 0),
		"an absolute token ignores the facing")
	_ok(Space.DIRS_4.has(EventCommand.resolve_turn("random", north, 4)),
		"random lands on a real facing")


# -- Argument coercion ---------------------------------------------------------

func _test_coercion() -> void:
	_section("arguments -- coerced to one shape, or reported")

	var cell := _parse_one({"command": "move_to", "args": {"cell": [3, 0, 4]}})
	_eq(cell["args"]["cell"], Vector3i(3, 0, 4), "a JSON array becomes a Vector3i")

	var origin := _parse_one({"command": "move_to", "args": {"cell": [0, 0, 0]}})
	_eq(origin["args"]["cell"], Vector3i.ZERO, "and [0,0,0] is a cell, not a failure")
	_ok(_problems_of({"command": "move_to", "args": {"cell": [0, 0, 0]}}).is_empty(),
		"  reported as clean, which is the trap in coercing to a zero value")

	_eq(_parse_one({"command": "wait", "args": {"seconds": 2}})["args"]["seconds"], 2.0,
		"an int seconds becomes a float")
	_eq(_parse_one({"command": "set_flag", "args": {"flag": "x", "value": true}})["args"]["value"],
		true, "a bool stays a bool")

	_ok(_problems_of({"command": "wait", "args": {"seconds": -1}}).size() > 0,
		"a negative duration is reported")
	_ok(_problems_of({"command": "wait", "args": {"seconds": "soon"}}).size() > 0,
		"and so is a duration that is not a number")
	_ok(_problems_of({"command": "move_to", "args": {"cell": "over there"}}).size() > 0,
		"a cell that is not a cell is reported")

	_ok(_problems_of({"command": "wait", "args": {}}).size() > 0,
		"a missing required argument is reported")
	_ok(_problems_of({"command": "wait", "args": {"seconds": 1, "speed": 2}}).size() > 0,
		"an argument the command does not have is reported")
	_ok(_problems_of({"command": "say", "args": {"text": "hi"}}).is_empty(),
		"a missing OPTIONAL argument is not")

	_ok(_problems_of({"command": "sing", "args": {}}).size() > 0, "an unknown command is reported")

	# Question 41: one argument each, and a token that is neither a direction nor a turn
	# has to be caught here rather than silently facing north at runtime.
	_ok(_problems_of({"command": "face_direction", "args": {"direction": "turn_left"}}).size() > 0,
		"\"turn_left\" is not a turn -- it is turn_ccw")
	_ok(_problems_of({"command": "face_direction", "args": {"direction": "turn_ccw"}}).is_empty(),
		"turn_ccw is")


func _test_terms() -> void:
	_section("terms -- @ marks a reference, a bare string is a string (question 40)")

	_ok(EventCommand.is_term("@player"), "@player is a term")
	_ok(EventCommand.is_term("@self"), "@self is a term")
	_ok(not EventCommand.is_term("player"), "\"player\" is not -- it is a literal string")
	_eq(EventCommand.term_name("@npc_scout"), "npc_scout", "term_name strips the sigil")

	_ok(_problems_of({"command": "face_to", "args": {"target": "@player"}}).is_empty(),
		"an actor argument takes a term")

	var bare := _problems_of({"command": "face_to", "args": {"target": "player"}})
	_ok(bare.size() > 0, "a bare string in an actor argument is an error")
	_ok(bare.size() > 0 and bare[0].contains("@player"),
		"  and the message suggests the @ form")

	# @self is the default, so a patrol does not repeat it on every node.
	_ok(_problems_of({"command": "move_to", "args": {"cell": [1, 0, 1]}}).is_empty(),
		"actor is optional and defaults to @self")


# -- Node validation -----------------------------------------------------------

func _test_validation() -> void:
	_section("validate_node -- wiring, keys, and clickable messages")

	var linear := {
		"id": "n1", "command": "say", "args": {"text": "hi"},
		"outputs": [{"type": "flow", "target": "n2"}],
	}
	_ok(EventCommand.validate_node(linear).is_empty(), "a well-formed node is clean")

	var unwired := {"id": "n1", "command": "say", "args": {"text": "hi"}, "outputs": []}
	_ok(EventCommand.validate_node(unwired).size() > 0,
		"a linear command with no output port is reported")

	var branch := {
		"id": "n2", "command": "if", "args": {"condition": "chapter >= 2"},
		"outputs": [{"type": "flow", "target": "n3"}],
	}
	_ok(EventCommand.validate_node(branch).size() > 0,
		"an `if` with one port is short of the two it branches on")

	# `ask` is the one command whose port count is its own data.
	var menu := {
		"id": "n4", "command": "ask",
		"args": {"text": "Unlock it?", "choices": ["Unlock it", "Leave it"]},
		"outputs": [{"type": "flow", "target": "n5"}, {"type": "flow", "target": ""}],
	}
	_eq(EventCommand.flows_of(menu).size(), 2, "ask takes its ports from its choices")
	_ok(EventCommand.validate_node(menu).is_empty(), "  and two choices want two outputs")

	# Every message must quote the node id, or graph_editor_panel cannot make the result
	# clickable -- it finds the node by scanning for the first quoted id.
	var broken := {"id": "n9", "command": "wait", "args": {}, "outputs": [{"type": "flow"}]}
	var messages := EventCommand.validate_node(broken)
	_ok(messages.size() > 0, "a broken node reports something")
	var quoted := true
	for message in messages:
		if not message.contains("\"n9\""):
			quoted = false
	_ok(quoted, "  and every message quotes the node id, so the result is clickable")

	# A key on a blocking command can never be joined: the runner has already waited.
	var pointless := {
		"id": "n5", "command": "say", "args": {"text": "hi"}, "blocking": true,
		"key": "line", "outputs": [{"type": "flow", "target": ""}],
	}
	_ok(EventCommand.validate_node(pointless).size() > 0,
		"a key on a blocking command is reported as unjoinable")

	_section("validate_graph -- the joins across a whole graph")

	# With no watchdog (question 8), a wait_for that names a key nothing produces is a
	# runner that waits forever. Catching it at author time is the whole mitigation.
	var orphan: Array = [
		{"id": "n1", "command": "wait_for", "args": {"key": "cam"},
			"outputs": [{"type": "flow", "target": ""}]},
	]
	_ok(EventCommand.validate_graph(orphan).size() > 0,
		"wait_for on a key no command produces is reported")

	var joined: Array = [
		{"id": "n1", "command": "camera_to", "args": {"cell": [1, 0, 1]},
			"blocking": false, "key": "cam",
			"outputs": [{"type": "flow", "target": "n2"}]},
		{"id": "n2", "command": "wait_for", "args": {"key": "cam"},
			"outputs": [{"type": "flow", "target": ""}]},
	]
	_ok(EventCommand.validate_graph(joined).is_empty(),
		"and a key a non-blocking command does produce is clean")


# -- The worked examples -------------------------------------------------------

func _test_examples() -> void:
	_section("docs/events -- the five worked examples parse clean")

	for file in ["cliff_jump", "greet_guard", "locked_door", "patrol_guard"]:
		var nodes: Variant = _read_json("%s%s.event.json" % [EXAMPLES, file])
		if nodes == null:
			_ok(false, "%s could not be read" % file)
			continue

		var result := EventCommand.parse_route(nodes)
		_ok(result["problems"].is_empty(), "%s parses with no problems%s"
			% [file, "" if result["problems"].is_empty() else ": " + str(result["problems"])])

		var problems := EventCommand.validate_graph(nodes)
		_ok(problems.is_empty(), "  and validates%s"
			% ("" if problems.is_empty() else ": " + str(problems)))

	# slime_a is the page-wrapped one, so only its graphs are a command list. The wrapper
	# itself is segment 3's business.
	var doc: Variant = _read_json("%sslime_a.event.json" % EXAMPLES)
	_ok(doc is Dictionary, "slime_a is a page-wrapped document")
	if doc is Dictionary:
		var pages: Array = (doc as Dictionary).get("pages", [])
		_eq(pages.size(), 3, "  with three pages")
		for i in pages.size():
			var graph: Variant = (pages[i] as Dictionary).get("graph", [])
			var result := EventCommand.parse_route(graph)
			_ok(result["problems"].is_empty(), "  page %d's graph parses clean%s"
				% [i + 1, "" if result["problems"].is_empty() else ": " + str(result["problems"])])

	_section("the dock's contract")

	# event_editor_dock.gd reads "errors"/"error" and treats a problems-only dictionary
	# as clean, so both keys have to carry the same information or Validate says nothing.
	var bad := EventCommand.parse_route([{"command": "wait", "args": {}}])
	_ok(bad.has("errors") and bad.has("problems"), "parse_route returns both keys")
	_eq((bad["errors"] as Array).size(), (bad["problems"] as Array).size(),
		"  carrying the same number of messages")
	_eq((bad["errors"][0] as Dictionary)["index"], 0, "  with the index of the command at fault")
	_ok((bad["errors"][0] as Dictionary).has("error"),
		"  under the \"error\" key the dock actually looks for")

	var not_a_list := EventCommand.parse_route({"command": "wait"})
	_ok((not_a_list["problems"] as Array).size() > 0, "a non-array top level is reported")


# -- Helpers -------------------------------------------------------------------

func _parse_one(raw: Variant) -> Dictionary:
	var problems: Array[String] = []
	return EventCommand.parse_command(raw, problems)


func _problems_of(raw: Variant) -> Array[String]:
	var problems: Array[String] = []
	EventCommand.parse_command(raw, problems)
	return problems


func _read_json(path: String) -> Variant:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return null
	var json := JSON.new()
	if json.parse(file.get_as_text()) != OK:
		return null
	return json.data


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1


func _eq(got: Variant, want: Variant, what: String) -> void:
	var same: bool = got == want
	print(("    ok    " if same else "    FAIL  ") + what
		+ ("" if same else "  (got %s, want %s)" % [got, want]))
	if same:
		_passed += 1
	else:
		_failed += 1
