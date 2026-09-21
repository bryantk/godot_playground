class_name EventCommand

## The command vocabulary, as data. Every command an event graph may contain is one
## entry in [method definitions] - its argument names and types, how many flow ports it
## has, whether it blocks, and what a save does with it mid-flight.
##
## [b]One table, three readers.[/b] The event dock's Validate pass, the graph editor's
## node inspector and the runtime all read this, which is the whole reason the schema is
## data rather than one class per command: adding a command is one dictionary entry plus
## one executor, and the three surfaces cannot drift apart because there is nothing for
## them to drift from.
##
## [b]Everything here is static and UI-free[/b], the same rule [code]graph_document.gd[/code]
## follows, so this is callable from an [code]@tool[/code] script in the editor and from a
## running game without either knowing about the other.
##
## [b]The parse contract: repair and report, never reject.[/b] An unknown command, a
## missing argument or a misspelled direction is reported and the node becomes a no-op -
## the document still opens and the rest of it still runs. That matches
## [code]graph_document.parse[/code] and it is what makes a half-typed event file editable
## rather than a wall of errors.

# -- Argument types ------------------------------------------------------------
#
# The type a value is coerced to, and what a problem says when it cannot be. A "?"
# suffix on a type in a definition's `args` marks that argument optional; the name is
# the key in the node's `args` dictionary.
#
# `flag` and `var` are deliberately distinct from `string`: they name declared state,
# so segment 2's validator can check them against GameState's manifest and catch
# `chpater` at author time rather than as a silent false at 2am. Nothing else can tell
# an identifier from a piece of text.

const T_CELL := "cell"          ## A [Vector3i] cell. Accepts Vector3i, Vector3 or [x, y, z].
const T_DIR := "dir"            ## A compass direction: a token like "n", or a vector.
const T_TURN := "turn"          ## A direction, "random", or a relative turn. See [method resolve_turn].
const T_ACTOR := "actor"        ## An [code]@[/code] term. See [method is_term].
const T_FLOAT := "float"
const T_INT := "int"
const T_BOOL := "bool"
const T_STRING := "string"
const T_SECONDS := "seconds"    ## A duration in seconds. Never steps - question 18.
const T_CONDITION := "condition" ## An expression string, parsed by EventCondition (segment 2).
const T_FLAG := "flag"          ## The name of a flag in GameState.
const T_VAR := "var"            ## The name of a variable in GameState's manifest.
const T_KEY := "key"            ## An author-chosen completion key, joined by `wait_for`.
const T_CHOICES := "choices"    ## A list of menu labels. Each becomes a flow port.

# -- Resume buckets ------------------------------------------------------------
#
# Question 39: saving is hybrid. A command says which half it is in, and segment 4's
# runner reads it. RESTART is the default and is always a legal downgrade - if a
# command stops being resumable later, an old save's state is ignored and it re-runs.

## Re-run this command from its start on load. Dialogue, and anything that completes
## in the tick it began.
const RESUME_RESTART := "restart"

## Capture this command's own progress and resume exactly there. Movement, animation
## playback and `wait`.
const RESUME_STATE := "state"

# -- Space -------------------------------------------------------------------
#
# Where a command is meaningful. The validator warns rather than the command silently
# doing nothing at runtime, which is architecture.md 7.3's rule for `jump`.

const SPACE_ANY := "any"
const SPACE_GRID := "grid"
const SPACE_FREE := "free"


# -- The registry --------------------------------------------------------------

## Every command, keyed by name.
##
## [code]args[/code] maps an argument name to one of the [code]T_*[/code] types, with a
## trailing [code]?[/code] for optional. [code]flows[/code] names the flow ports in port
## order - one for a linear command, several for a branch, none for a command that ends
## the path. [code]blocking[/code] is the default a node may override. [code]blurb[/code]
## is one line for an author choosing a command, not a spec - the graph editor's add-node
## picker is its only reader today (see [method description]).
##
## [b]`actor` is optional on every actor command and defaults to [code]@self[/code][/b],
## because the overwhelmingly common case is an event moving itself, and writing
## [code]"actor": "@self"[/code] on every node of a patrol is noise that hides the one
## node that names somebody else.
const COMMANDS: Dictionary = {
	# -- Flow ------------------------------------------------------------------
	"start": {
		# The one node a graph is entered through. Its single output names the node
		# execution actually begins at - see [constant START_COMMAND] and
		# [method validate_reachability]. It carries no state of its own, so it is a
		# RESTART command like "label" and "goto".
		"args": {},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "The node every graph begins at.",
	},
	"wait": {
		"args": {"seconds": T_SECONDS},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Pause for a duration.",
	},
	"goto": {
		# No args: the flow port IS the jump. patrol_guard.event.json used to write the
		# target twice, in args and in the port, which is two sources that can disagree.
		"args": {},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Jump to another node in the graph.",
	},
	"label": {
		"args": {"name": T_STRING},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "A named point another node can jump to.",
	},
	"if": {
		"args": {"condition": T_CONDITION},
		"flows": ["true", "false"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Branch on a condition.",
	},
	"ask": {
		# The flow ports are the choices, so `flows` here is only the fallback for a node
		# with none listed yet. See [method flows_of].
		"args": {"text": T_STRING, "choices": T_CHOICES, "location": T_INT + "?"},
		"flows": [], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Present a choice menu, one flow port per choice.",
	},
	"call": {
		"args": {"document": T_STRING, "entry": T_STRING + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Run another event's graph inline.",
	},
	"exit_call": {
		# Question 49: pops the most-nested call frame early, resuming the caller at
		# its own "next". Outside any call frame it behaves like "end", since a
		# top-level graph has nowhere to exit to but still has a runner to stop.
		"args": {},
		"flows": [], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Leave the current call early, resuming the caller.",
	},
	"wait_for": {
		"args": {"key": T_KEY},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Pause until a matching key command finishes.",
	},
	"end": {
		"args": {},
		"flows": [], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Stop the graph here.",
	},
	"re_validate": {
		# Question 23's escape hatch: force page selection to run now, rather than at
		# graph completion. Re-runs the ordinary conditional check; it does not name a
		# page, so it is not question 13's rejected `set_page`.
		"args": {},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Re-check which page should be active, right now.",
	},

	# -- Actor -----------------------------------------------------------------
	"move_to": {
		"args": {"actor": T_ACTOR + "?", "cell": T_CELL, "speed": T_FLOAT + "?",
			"path": T_STRING + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Walk an actor to a specific cell.",
	},
	"move_by": {
		"args": {"actor": T_ACTOR + "?", "cells": T_CELL, "speed": T_FLOAT + "?",
			"path": T_STRING + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Walk an actor a relative number of cells.",
	},
	"step": {
		"args": {"actor": T_ACTOR + "?", "direction": T_DIR},
		"flows": ["next"], "blocking": true, "space": SPACE_GRID,
		"resume": RESUME_STATE,
		"blurb": "Move an actor one grid cell in a direction.",
	},
	"face_direction": {
		"args": {"actor": T_ACTOR + "?", "direction": T_TURN},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Turn an actor to face a direction.",
	},
	"face_to": {
		"args": {"actor": T_ACTOR + "?", "target": T_ACTOR},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Turn an actor to face another actor.",
	},
	"jump": {
		"args": {"actor": T_ACTOR + "?", "strength": T_FLOAT + "?", "toward": T_CELL + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"requires": [GameProfile.Capability.HEIGHT],
		"blurb": "Have an actor jump, optionally toward a cell.",
	},
	"follow": {
		"args": {"actor": T_ACTOR + "?", "target": T_ACTOR, "distance": T_INT + "?"},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Have an actor continuously follow another.",
	},
	"set_speed": {
		"args": {"actor": T_ACTOR + "?", "speed": T_FLOAT},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Change an actor's movement speed.",
	},
	"teleport": {
		"args": {"actor": T_ACTOR + "?", "cell": T_CELL},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Move an actor to a cell instantly, no animation.",
	},
	"wait_settle": {
		"args": {"actor": T_ACTOR + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_GRID,
		"resume": RESUME_RESTART,
		"blurb": "Pause until an actor is centred on its cell.",
	},

	# -- Route (segment 7) -------------------------------------------------------
	#
	# Never authored by hand - EventRoute.compile() is the only writer of these three.
	# Each has a second flow port, "blocked", that a page's own move_to/step never
	# need: a route's on_blocked policy (event-pages.md §3) is which target the
	# compiler wires that port to, not something these executors decide.

	"route_step": {
		"args": {"actor": T_ACTOR + "?", "direction": T_DIR},
		"flows": ["next", "blocked"], "blocking": true, "space": SPACE_GRID,
		"resume": RESUME_STATE,
		"blurb": "One compiled-route grid step, branching on whether it was refused.",
	},
	"route_move_to": {
		"args": {"actor": T_ACTOR + "?", "cell": T_CELL, "speed": T_FLOAT + "?"},
		"flows": ["next", "blocked"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "One compiled-route walk-to-cell, branching on whether it stopped short.",
	},
	"route_seek": {
		"args": {"actor": T_ACTOR + "?", "target": T_ACTOR + "?", "mode": T_STRING,
			"speed": T_FLOAT + "?"},
		"flows": ["next", "blocked"], "blocking": true, "space": SPACE_GRID,
		"resume": RESUME_RESTART,
		"blurb": "One compiled-route step toward/away/random, target read live.",
	},

	# -- Dialogue --------------------------------------------------------------
	"say": {
		"args": {"text": T_STRING, "location": T_INT + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Show a line of dialogue.",
	},
	"append_say": {
		"args": {"text": T_STRING, "location": T_INT + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Add another line to the open dialogue window.",
	},
	"close_window": {
		"args": {},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Close the dialogue window.",
	},

	# -- State -----------------------------------------------------------------
	"set_flag": {
		"args": {"flag": T_FLAG, "value": T_BOOL + "?"},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Set a global flag.",
	},
	"set_self_flag": {
		"args": {"flag": T_FLAG, "value": T_BOOL + "?"},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Set a flag scoped to this event.",
	},
	"set_var": {
		"args": {"var": T_VAR, "value": T_FLOAT},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Set a declared variable to a value.",
	},
	"add_var": {
		"args": {"var": T_VAR, "delta": T_FLOAT},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Add to a declared variable.",
	},

	# -- Input -------------------------------------------------------------------
	"halt_control": {
		# The manual half of "lock player" (event-pages.md): a page's own lock_player
		# setting locks input for exactly the run that page's trigger started and
		# releases it the moment that run ends (GameEvent's own facing-capture pattern,
		# applied to ModeStack instead of facing). This is the escape hatch for locking
		# past that boundary - a graph that ends but wants the lock to survive until
		# something else, later, calls return_control. Plain ModeStack.push(CUTSCENE),
		# so it nests correctly with lock_player's own push/pop and with the exclusive
		# slot's own push around the whole run.
		"args": {},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Disable player input until return_control (or a lock_player page ends).",
	},
	"return_control": {
		# The opposite of halt_control - one ModeStack.pop(). Popping something this
		# command did not itself push (a lock_player run that has already ended, an
		# exclusive slot still held) is the authoring hazard a bare stack always has;
		# nothing here tracks who owns which push.
		"args": {},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Re-enable player input locked by halt_control.",
	},

	# -- Map -------------------------------------------------------------------
	"change_map": {
		# Question 51: gained a "next" port so an exclusive runner can chain across
		# the load and keep running on the far side, owned by EventScheduler rather
		# than whatever GameEvent/Actor spawned it.
		"args": {"map": T_STRING, "cell": T_CELL + "?", "facing": T_DIR + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Leave for another map.",
	},
	"fade": {
		"args": {"to": T_FLOAT + "?", "seconds": T_SECONDS + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Fade the screen to or from a colour.",
	},
	"shake": {
		"args": {"seconds": T_SECONDS + "?", "strength": T_FLOAT + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Shake the camera.",
	},
	"camera_to": {
		"args": {"cell": T_CELL, "seconds": T_SECONDS + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Pan the camera to a cell.",
	},
	"camera_follow": {
		"args": {"actor": T_ACTOR, "seconds": T_SECONDS + "?"},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Have the camera follow an actor.",
	},

	# -- Presentation ----------------------------------------------------------
	"play_anim": {
		"args": {"actor": T_ACTOR + "?", "anim": T_STRING},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Play an animation on an actor.",
	},
	"play_sound": {
		"args": {"sound": T_STRING},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Play a sound effect.",
	},
	"play_music": {
		"args": {"track": T_STRING, "fade": T_SECONDS + "?"},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Change the background music.",
	},
	"set_visible": {
		"args": {"actor": T_ACTOR + "?", "visible": T_BOOL},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Show or hide an actor.",
	},

	# -- Battle ----------------------------------------------------------------
	"start_battle": {
		"args": {"troop": T_STRING},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"requires": [GameProfile.Capability.BATTLE_SCENE],
		"blurb": "Start a battle against a troop.",
	},
}


# -- Terse forms ---------------------------------------------------------------
#
# Question 15: the terse string is parse-time sugar and nothing downstream ever sees it.
# The dock seeds `{"command": "mov n 2"}` and a route is faster to type this way, but the
# instant it is read it becomes the long form, so there is exactly one command shape in
# memory and a file saved after a round trip comes back long.
#
# Deliberately a short table. Every entry here is a second spelling to keep in step with
# the first, so it earns its place only for commands typed often enough to matter.

## Terse alias -> the command it expands to, and the argument names its positional
## words fill in order. A [code]*[/code] prefix on a name marks the whole remainder of
## the line, so a trailing text argument may contain spaces.
const TERSE: Dictionary = {
	"mov": {"command": "move_by", "fills": ["direction", "count"]},
	"step": {"command": "step", "fills": ["direction"]},
	"face": {"command": "face_direction", "fills": ["direction"]},
	"wait": {"command": "wait", "fills": ["seconds"]},
	"flag": {"command": "set_flag", "fills": ["flag", "value"]},
	"say": {"command": "say", "fills": ["*text"]},
}

# -- Directions ----------------------------------------------------------------
#
# The tokens an author types, mapped onto Space's own lists so a command and a sprite's
# facing cannot disagree about where north-east is. North is -Z; both lists run
# clockwise seen from above (core/space.gd).

const DIRECTION_TOKENS: Dictionary = {
	"n": Vector3i(0, 0, -1), "north": Vector3i(0, 0, -1),
	"e": Vector3i(1, 0, 0), "east": Vector3i(1, 0, 0),
	"s": Vector3i(0, 0, 1), "south": Vector3i(0, 0, 1),
	"w": Vector3i(-1, 0, 0), "west": Vector3i(-1, 0, 0),
	"ne": Vector3i(1, 0, -1), "se": Vector3i(1, 0, 1),
	"sw": Vector3i(-1, 0, 1), "nw": Vector3i(-1, 0, -1),
}

## Relative turns, question 41. Named by handedness rather than degrees because a
## [code]turn_cw[/code] is 90 degrees in a 4-direction game and 45 in an 8-direction
## one - any number in the name would be wrong in one of the two games.
const TURN_TOKENS: PackedStringArray = ["turn_cw", "turn_ccw", "turn_180", "random"]

## The prefix that marks a resolvable term - question 40. [code]@player[/code],
## [code]@self[/code] and [code]@npc_scout[/code] are references resolved at runtime; a
## bare string is a literal string and never an actor id.
const TERM_PREFIX := "@"

## The command that marks a graph's entry point - see [method validate_reachability].
## Every page's graph is expected to have exactly one node with this command; its single
## output names the node execution actually begins at.
const START_COMMAND := "start"


# -- Reading the registry ------------------------------------------------------

## The whole table. A function rather than the bare constant because
## [code]event_editor_dock.gd[/code] resolves this class by name at validate time and
## calls into it, and a method is what it can find.
static func definitions() -> Dictionary:
	return COMMANDS


static func has_command(name: String) -> bool:
	return COMMANDS.has(name)


## One command's definition, or an empty dictionary. Never null, so a caller may read
## through it without a guard.
static func definition(name: String) -> Dictionary:
	return COMMANDS.get(name, {})


## [param name]'s one-line [code]blurb[/code], or "" for an unknown command - the graph
## editor's add-node picker reads this so an author sees what a command does before
## dropping it in the graph.
static func description(name: String) -> String:
	return str(definition(name).get("blurb", ""))


## The flow ports [param node] actually has, in port order.
##
## Usually the command's declared [code]flows[/code]. [code]ask[/code] is the exception:
## its ports are its choices, so the node's own [code]choices[/code] decide, and a node
## that has not been given any yet falls back to a single unnamed port rather than none -
## a branch with no way out is harder to edit than one with a spare wire.
static func flows_of(node: Dictionary) -> PackedStringArray:
	var name := str(node.get("command", ""))
	var def := definition(name)
	if def.is_empty():
		return PackedStringArray(["next"])

	if name == "ask":
		var choices: Variant = (node.get("args", {}) as Dictionary).get("choices", [])
		if choices is Array and not (choices as Array).is_empty():
			var out := PackedStringArray()
			for choice in choices as Array:
				out.append(str(choice))
			return out
		return PackedStringArray(["next"])

	return PackedStringArray(def["flows"])


## Whether [param node] blocks - its own [code]blocking[/code] when it authored one,
## otherwise its command's default. An unknown or absent command reads as non-blocking:
## nothing has said otherwise yet, so it should not read as loudly as a real command's
## default might.
static func is_blocking(node: Dictionary) -> bool:
	if node.has("blocking"):
		return bool(node["blocking"])
	return bool(definition(str(node.get("command", ""))).get("blocking", false))


## True when [param value] is a resolvable term rather than a literal - question 40.
static func is_term(value: Variant) -> bool:
	return value is String and (value as String).begins_with(TERM_PREFIX)


## The name inside a term: [code]@npc_scout[/code] becomes [code]npc_scout[/code].
static func term_name(value: String) -> String:
	return value.substr(TERM_PREFIX.length()) if value.begins_with(TERM_PREFIX) else value


## [param token] as a direction, or ZERO if it is not one. Accepts the compass tokens,
## a [Vector3i], a [Vector3], or a three-element array.
static func direction_of(token: Variant) -> Vector3i:
	if token is String:
		return DIRECTION_TOKENS.get((token as String).to_lower(), Vector3i.ZERO)
	return _as_cell(token, Vector3i.ZERO)


## Resolves a [constant T_TURN] value against a facing.
##
## A compass token or vector answers directly; [code]random[/code] and the three
## relative turns are answered against [param facing] and [param count], reusing
## [method Space.facing_index] and [method Space.dirs] so a turn lands on exactly the
## facings the actor has art for. Returns ZERO for a token that means nothing.
static func resolve_turn(token: Variant, facing: Vector3i, count: int = 4) -> Vector3i:
	var dirs := Space.dirs(count)

	if token is String:
		var text := (token as String).to_lower()
		match text:
			"random":
				return dirs[randi() % dirs.size()]
			"turn_cw":
				return dirs[posmod(Space.facing_index(Vector3(facing), count) + 1, count)]
			"turn_ccw":
				return dirs[posmod(Space.facing_index(Vector3(facing), count) - 1, count)]
			"turn_180":
				return dirs[posmod(Space.facing_index(Vector3(facing), count)
					+ int(count / 2.0), count)]

	return direction_of(token)


# -- Save/restore ----------------------------------------------------------------

## A stable hash over the parts of a graph that change what it *does* - a node's
## command, args, key and any explicit blocking override, plus its wiring (flow ->
## target) - never its id, title or position, which are editor bookkeeping (question
## 39: dragging a node two pixels in the graph editor must not invalidate every save
## that happens to be mid-graph). [EventRunner.to_save]/[method EventRunner.restore]
## compare this against a document reloaded fresh from disk: a match resumes exactly
## where a frame left off, a mismatch restarts that frame from its own entry instead of
## dropping it - "restart is always a legal downgrade" (question 39).
##
## Nodes are sorted by id before hashing, so two structurally identical graphs authored
## with their nodes in a different order still agree - and [JSON.stringify] (not string
## concatenation) is what turns each node into a canonical, order-independent-within-
## itself piece of text, so two dictionaries with the same keys in a different order
## also agree.
static func doc_hash(nodes: Array[Dictionary]) -> String:
	var by_id: Dictionary = {}
	for n in nodes:
		by_id[str(n.get("id", ""))] = n
	var ids := by_id.keys()
	ids.sort()

	var canon: Array = []
	for id: Variant in ids:
		var n: Dictionary = by_id[id]
		var outputs: Array = []
		for output: Variant in n.get("outputs", []) as Array:
			if output is Dictionary:
				outputs.append({
					"flow": str((output as Dictionary).get("flow", "")),
					"target": str((output as Dictionary).get("target", "")),
				})
		outputs.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
			return str(a["flow"]) < str(b["flow"]))
		canon.append({
			"id": str(id),
			"command": str(n.get("command", "")),
			"args": n.get("args", {}),
			"key": str(n.get("key", "")),
			"blocking": n.get("blocking") if n.has("blocking") else null,
			"outputs": outputs,
		})

	var digest := HashingContext.new()
	digest.start(HashingContext.HASH_SHA256)
	digest.update(JSON.stringify(canon).to_utf8_buffer())
	return digest.finish().hex_encode()


# -- Parsing -------------------------------------------------------------------

## Reads a list of authored commands into their normalised form.
##
## Returns [code]{"commands": Array[Dictionary], "problems": Array[String],
## "errors": Array[Dictionary]}[/code]. [code]commands[/code] is what a runtime or an
## editor should use; [code]problems[/code] is the flat list for a caller that only wants
## to print them.
##
## [b]Why [code]errors[/code] is a third key carrying the same information.[/b]
## [code]event_editor_dock.gd[/code] was written before this class existed and reads a
## dictionary's [code]errors[/code] or [code]error[/code] key, treating anything else -
## including a [code]problems[/code] key - as a clean route. Emitting both means the dock
## lights up with per-line results without being touched, which is worth one duplicated
## list.
##
## Nothing is ever rejected. A malformed entry becomes a no-op command carrying its
## problems, so a half-typed file still opens and the rest of it still runs.
static func parse_route(data: Variant) -> Dictionary:
	var commands: Array[Dictionary] = []
	var problems: Array[String] = []
	var errors: Array[Dictionary] = []

	if typeof(data) != TYPE_ARRAY:
		var message := "Top level must be an array of commands, found %s." % type_string(typeof(data))
		problems.append(message)
		errors.append({"error": message, "index": -1})
		return {"commands": commands, "problems": problems, "errors": errors}

	for i in (data as Array).size():
		var found: Array[String] = []
		commands.append(parse_command(data[i], found))
		for message in found:
			problems.append(message)
			errors.append({"error": message, "index": i})

	return {"commands": commands, "problems": problems, "errors": errors}


## One authored entry, normalised. Appends anything wrong to [param problems].
##
## Accepts the three shapes an author can write: a bare terse string, a dictionary whose
## [code]command[/code] is terse, and the long form. All three come back long.
static func parse_command(raw: Variant, problems: Array[String]) -> Dictionary:
	var node: Dictionary = {}

	if raw is String:
		node = _expand_terse(raw as String, problems)
	elif raw is Dictionary:
		node = (raw as Dictionary).duplicate(true)
		var name := str(node.get("command", ""))
		if name.strip_edges().contains(" "):
			# A space is what tells the two spellings apart: no command name has one.
			var expanded := _expand_terse(name, problems)
			var authored: Dictionary = node.get("args", {})
			node["command"] = expanded["command"]
			# Explicit args win over the terse ones, so `{"command": "mov n 2",
			# "args": {"speed": 3}}` is a legal thing to write while editing.
			var merged: Dictionary = expanded.get("args", {})
			for key: Variant in authored:
				merged[key] = authored[key]
			node["args"] = merged
	else:
		problems.append("A command must be an object or a terse string, found %s."
			% type_string(typeof(raw)))
		return {"command": "", "args": {}}

	if not node.has("args") or typeof(node["args"]) != TYPE_DICTIONARY:
		node["args"] = {}

	_normalise_args(node, problems)
	return node


## [code]"mov n 2"[/code] into the long form, per [constant TERSE].
static func _expand_terse(text: String, problems: Array[String]) -> Dictionary:
	var words := text.strip_edges().split(" ", false)
	if words.is_empty():
		problems.append("Empty command string.")
		return {"command": "", "args": {}}

	var alias := words[0]
	if not TERSE.has(alias):
		# Not sugar at all - a long-form name that happens to have been typed with
		# trailing words. Report against the name so the message names what was read.
		problems.append("\"%s\" is not a terse command. Known: %s."
			% [alias, ", ".join(TERSE.keys())])
		return {"command": alias, "args": {}}

	var recipe: Dictionary = TERSE[alias]
	var args: Dictionary = {}
	var fills: Array = recipe["fills"]

	for i in fills.size():
		var name := str(fills[i])
		if name.begins_with("*"):
			# The rest of the line, spaces and all, for a trailing text argument.
			if i + 1 <= words.size() - 1 or words.size() > i + 1:
				args[name.substr(1)] = " ".join(Array(words).slice(i + 1))
			break
		if i + 1 < words.size():
			args[name] = words[i + 1]

	var command := str(recipe["command"])
	if command == "move_by":
		# `mov n 2` is a direction and a count; move_by takes a cell delta.
		var dir := direction_of(args.get("direction", ""))
		if dir == Vector3i.ZERO:
			problems.append("\"%s\": \"%s\" is not a direction." % [text, args.get("direction", "")])
		var count := int(args.get("count", 1))
		args = {"cells": [dir.x * count, dir.y * count, dir.z * count]}

	return {"command": command, "args": args}


## Coerces every argument to its declared type in place, reporting what it cannot.
##
## An argument that fails coercion is [i]left as authored[/i] rather than dropped: the
## problem is reported, and keeping the value means the editor can still show the author
## what they typed instead of silently emptying the field they got wrong.
static func _normalise_args(node: Dictionary, problems: Array[String]) -> void:
	var name := str(node.get("command", ""))
	if name == "":
		problems.append("A command has no name.")
		return

	var def := definition(name)
	if def.is_empty():
		problems.append("Unknown command \"%s\"." % name)
		return

	var args: Dictionary = node["args"]
	var spec: Dictionary = def["args"]

	for key: Variant in spec:
		var declared := str(spec[key])
		var optional := declared.ends_with("?")
		var type := declared.trim_suffix("?")

		if not args.has(key):
			if not optional:
				problems.append("\"%s\" needs \"%s\" (%s)." % [name, key, type])
			continue

		var coerced: Variant = _coerce(args[key], type, "\"%s\".%s" % [name, key], problems)
		if coerced != null:
			args[key] = coerced

	for key: Variant in args:
		if not spec.has(key):
			problems.append("\"%s\" has no argument \"%s\"." % [name, key])

	# `goto` wrote its target twice - in args and in the flow port - which is two
	# sources that can disagree. The port wins; this says so rather than silently
	# ignoring the arg an author may be relying on.
	if name == "goto" and args.has("target"):
		problems.append("\"goto\" takes its target from its flow port, not args.target. Wire the port and delete the argument.")


## [param value] as [param type], or null when it cannot be. [param where] names the
## place for the problem message.
static func _coerce(value: Variant, type: String, where: String,
		problems: Array[String]) -> Variant:
	match type:
		T_CELL:
			var cell := _as_cell(value, Vector3i.ZERO)
			if cell == Vector3i.ZERO and not _looks_like_cell(value):
				problems.append("%s must be a cell [x, y, z], found %s."
					% [where, type_string(typeof(value))])
				return null
			return cell

		T_DIR:
			var dir := direction_of(value)
			if dir == Vector3i.ZERO:
				problems.append("%s must be a direction - one of %s, or a vector."
					% [where, ", ".join(_compass_tokens())])
				return null
			return dir

		T_TURN:
			# Left as a string: a relative turn cannot be resolved until the actor's
			# facing is known, which is the runner's business rather than the parser's.
			if value is String:
				var text := (value as String).to_lower()
				if TURN_TOKENS.has(text) or DIRECTION_TOKENS.has(text):
					return text
				problems.append("%s must be a direction, or one of %s."
					% [where, ", ".join(TURN_TOKENS)])
				return null
			var vector := direction_of(value)
			if vector == Vector3i.ZERO:
				problems.append("%s must be a direction, or one of %s."
					% [where, ", ".join(TURN_TOKENS)])
				return null
			return vector

		T_ACTOR:
			if is_term(value):
				return value
			if value is String:
				problems.append("%s must be a term - did you mean \"@%s\"? A bare string is a literal, not an actor."
					% [where, value])
				return null
			problems.append("%s must be a term like \"@self\" or \"@player\", found %s."
				% [where, type_string(typeof(value))])
			return null

		T_FLOAT, T_SECONDS:
			if value is float or value is int:
				var number := float(value)
				if type == T_SECONDS and number < 0.0:
					problems.append("%s is a duration in seconds and cannot be negative." % where)
					return null
				return number
			if value is String and (value as String).is_valid_float():
				return float(value)
			problems.append("%s must be a number, found %s." % [where, type_string(typeof(value))])
			return null

		T_INT:
			if value is int or value is float:
				return int(value)
			if value is String and (value as String).is_valid_int():
				return int(value)
			problems.append("%s must be a whole number, found %s." % [where, type_string(typeof(value))])
			return null

		T_BOOL:
			if value is bool:
				return value
			if value is String:
				var text := (value as String).to_lower()
				if text == "true" or text == "false":
					return text == "true"
			problems.append("%s must be true or false, found %s." % [where, type_string(typeof(value))])
			return null

		T_CHOICES:
			if value is Array:
				var out: Array = []
				for entry in value as Array:
					out.append(str(entry))
				if out.is_empty():
					problems.append("%s is empty - a menu with no choices has no way out." % where)
				return out
			problems.append("%s must be a list of labels, found %s." % [where, type_string(typeof(value))])
			return null

		T_STRING, T_CONDITION, T_FLAG, T_VAR, T_KEY:
			if value is String:
				return value
			problems.append("%s must be text, found %s." % [where, type_string(typeof(value))])
			return null

	return null


static func _compass_tokens() -> PackedStringArray:
	var out := PackedStringArray()
	for key: Variant in DIRECTION_TOKENS:
		if str(key).length() <= 2:
			out.append(str(key))
	return out


## True when [param value] is shaped like a cell, so a legitimate [code][0, 0, 0][/code]
## is not reported as a failure to parse.
static func _looks_like_cell(value: Variant) -> bool:
	if value is Vector3i or value is Vector3:
		return true
	return value is Array and (value as Array).size() >= 3


## The cell coercion [RouteBrain] already does, kept in one place now that two callers
## need it. Accepts a [Vector3i], a [Vector3] or a three-element array.
static func _as_cell(value: Variant, fallback: Vector3i) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Vector3:
		var v: Vector3 = value
		return Vector3i(roundi(v.x), roundi(v.y), roundi(v.z))
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Vector3i(int(a[0]), int(a[1]), int(a[2]))
	return fallback


# -- Validating a graph node ---------------------------------------------------

## Problems with one graph node, as messages.
##
## This is the editor-facing check, and it is a superset of what parsing reports: the
## node's wiring is checked too, which [method parse_command] has no view of.
##
## [b]Every message quotes the node's id.[/b] [code]graph_editor_panel.gd[/code] makes a
## result clickable by scanning a problem for its first quoted id, so a message that
## names the node without quoting it is a result that does nothing when you click it.
static func validate_node(node: Variant) -> Array[String]:
	var problems: Array[String] = []

	if typeof(node) != TYPE_DICTIONARY:
		problems.append("A node must be an object, found %s." % type_string(typeof(node)))
		return problems

	var entry: Dictionary = node
	var id := str(entry.get("id", ""))
	var where := "Node \"%s\"" % id if id != "" else "A node"

	var found: Array[String] = []
	parse_command(entry, found)
	for message in found:
		problems.append("%s: %s" % [where, message])

	var name := str(entry.get("command", ""))
	if not has_command(name):
		return problems

	# Wiring. A command with fewer ports than it declares cannot reach the paths the
	# author drew, and one with more has wires that go nowhere.
	var expected := flows_of(entry).size()
	var outputs: Variant = entry.get("outputs", [])
	if outputs is Array:
		var actual: int = (outputs as Array).size()
		if actual != expected:
			problems.append("%s: \"%s\" has %d flow port(s) but %d output(s)."
				% [where, name, expected, actual])
	elif entry.has("outputs"):
		problems.append("%s: outputs must be an array, found %s."
			% [where, type_string(typeof(outputs))])

	# A non-blocking command is fire-and-forget unless it is given a key, and a key on a
	# blocking one is never joinable because the runner has already waited for it.
	if is_blocking(entry) and entry.has("key"):
		problems.append("%s: \"%s\" is blocking, so its \"key\" can never be joined - a later wait_for would already have missed it."
			% [where, name])

	return problems


## Problems with a whole list of nodes, each already carrying its node id.
static func validate_graph(nodes: Variant) -> Array[String]:
	var problems: Array[String] = []
	if typeof(nodes) != TYPE_ARRAY:
		problems.append("A graph must be an array of nodes, found %s."
			% type_string(typeof(nodes)))
		return problems

	# Author-chosen keys, so a `wait_for` that names one nothing produces can be caught
	# here rather than hanging the runner with no watchdog to notice.
	var offered: Dictionary = {}
	for node in nodes as Array:
		if node is Dictionary and (node as Dictionary).has("key"):
			offered[str((node as Dictionary)["key"])] = true

	for node in nodes as Array:
		problems.append_array(validate_node(node))

		if node is Dictionary and str((node as Dictionary).get("command", "")) == "wait_for":
			var entry: Dictionary = node
			var key := str((entry.get("args", {}) as Dictionary).get("key", ""))
			if key != "" and not offered.has(key):
				problems.append("Node \"%s\": wait_for joins \"%s\", which no command in this graph produces - it would wait forever."
					% [str(entry.get("id", "")), key])

	return problems


## Problems reachability alone can find: no [constant START_COMMAND] node, more than
## one, or nodes [method start] cannot reach by following [code]outputs[/code] targets.
##
## [b]A separate function from [method validate_graph][/b], deliberately - folding this
## into it would have broken every hand-built test fixture and every graph written
## before "start" existed, none of which carry one. A caller that wants both calls both.
##
## An empty [param nodes] is clean: a page with no graph at all is legitimate
## (event-pages.md §2 - a route-only decoration has nothing to reach).
static func validate_reachability(nodes: Variant) -> Array[String]:
	var problems: Array[String] = []
	if typeof(nodes) != TYPE_ARRAY or (nodes as Array).is_empty():
		return problems

	var list: Array = nodes
	var by_id: Dictionary = {}
	var starts: Array[String] = []
	var forward: Dictionary = {}

	for node in list:
		if typeof(node) != TYPE_DICTIONARY:
			continue
		var entry: Dictionary = node
		var id := str(entry.get("id", ""))
		by_id[id] = entry
		if str(entry.get("command", "")) == START_COMMAND:
			starts.append(id)

		var targets: Array[String] = []
		var outputs: Variant = entry.get("outputs", [])
		if outputs is Array:
			for output in outputs as Array:
				if output is Dictionary:
					var target := str((output as Dictionary).get("target", ""))
					if target != "":
						targets.append(target)
		forward[id] = targets

	if starts.is_empty():
		problems.append("This graph has no \"%s\" node - nothing says where it begins."
			% START_COMMAND)
		return problems
	if starts.size() > 1:
		problems.append("This graph has %d \"%s\" nodes (%s) - exactly one is expected."
			% [starts.size(), START_COMMAND, _quoted(starts)])

	# Forward reachability from the first start node, even when there is more than one -
	# the duplicate is already reported above, and reachability from the first is still
	# useful information rather than none.
	var reached: Dictionary = {}
	var queue: Array[String] = [starts[0]]
	reached[starts[0]] = true
	while not queue.is_empty():
		var current: String = queue.pop_back()
		for target in (forward.get(current, []) as Array[String]):
			if by_id.has(target) and not reached.has(target):
				reached[target] = true
				queue.append(target)

	var unreached: Array[String] = []
	for id: Variant in by_id:
		if not reached.has(id):
			unreached.append(id)

	if unreached.is_empty():
		return problems

	# Group the unreached set into chains: nodes an author dragged out a sequence of
	# commands into, that nothing hooks back up to "start". Grouped by following outputs
	# as undirected edges, so "a chain" matches what it looks like on screen - one
	# dangling run of connected nodes - rather than counting every node in it separately.
	var undirected: Dictionary = {}
	for id in unreached:
		undirected[id] = []
	for id in unreached:
		for target in (forward.get(id, []) as Array[String]):
			if undirected.has(target):
				(undirected[id] as Array).append(target)
				(undirected[target] as Array).append(id)

	var visited: Dictionary = {}
	var chains := 0
	for id in unreached:
		if visited.has(id):
			continue
		chains += 1
		var stack: Array[String] = [id]
		visited[id] = true
		while not stack.is_empty():
			var current: String = stack.pop_back()
			for neighbor in (undirected.get(current, []) as Array[String]):
				if not visited.has(neighbor):
					visited[neighbor] = true
					stack.append(neighbor)

	# START_COMMAND is deliberately not quoted here: every other message in this file
	# quotes a node id, and this one would otherwise put "start" first in the string,
	# which graph_editor_panel's click-to-jump would then always resolve to the start
	# node itself rather than to one of the unreachable ones it is actually reporting.
	problems.append(
		"%d node(s) unreachable from %s: %s (%d orphaned chain%s)."
		% [unreached.size(), START_COMMAND, _quoted(unreached), chains,
			"" if chains == 1 else "s"])
	return problems

## [param ids], each individually quoted and comma-joined - so every id a reachability
## message names is clickable the same way [method validate_node]'s messages already are
## (graph_editor_panel.gd scans a message for its first quoted id).
static func _quoted(ids: Array[String]) -> String:
	var out := PackedStringArray()
	for id in ids:
		out.append("\"%s\"" % id)
	return ", ".join(out)
