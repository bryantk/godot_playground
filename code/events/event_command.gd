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
const T_MOVE_DIR := "move_dir"  ## A cell delta, or one of [constant MOVE_DIR_TOKENS]. See [method resolve_move_delta].
const T_ACTOR := "actor"        ## An [code]@[/code] term. See [method is_term].
const T_FLOAT := "float"
const T_INT := "int"
const T_BOOL := "bool"
const T_COLOR := "color"        ## An HTML colour string, "#rrggbb" or "#rrggbbaa" - kept as that string.
const T_STRING := "string"
const T_SECONDS := "seconds"    ## A duration in seconds. Never steps - question 18.
const T_CONDITION := "condition" ## An expression string, parsed by EventCondition (segment 2).
const T_FLAG := "flag"          ## The name of a flag in GameState.
const T_VAR := "var"            ## The name of a variable in GameState's manifest.
const T_KEY := "key"            ## An author-chosen completion key, joined by `wait_for`.
const T_CHOICES := "choices"    ## A list of menu labels. Each becomes a flow port.

# -- Flow ports -----------------------------------------------------------------
#
# Shared names for the "reached/immediate" pattern every command with real travel time
# uses (move_to, move_by, jump, camera_to, camera_move_by): wiring FLOW_IMMEDIATE takes
# the runner out of the way the instant the command starts; wiring only FLOW_REACHED (or
# neither) waits for it to actually finish; wiring both makes FLOW_IMMEDIATE always win
# (it is checked first - see [method EventCommandExec.reached_immediate_flow_port]), so
# FLOW_REACHED never fires. Constants rather than repeated literals, so a rename is one
# line instead of a grep-and-replace across every command's schema.

const FLOW_REACHED := "reached"
const FLOW_IMMEDIATE := "immediate"
## Actor move commands (move_to, move_by, jump) also have this: fires when the target
## cell is inaccessible. Wired, the refused move counts as completed and the graph flows
## on from here; unwired, the runner waits a frame and retries the command, so a looped
## path awaiting "reached" resumes the same loop once whatever blocked it moves away.
const FLOW_BLOCKED := "blocked"
## move_route only: the search could not reach the target (walled off, or over its node
## cap). Fires straight away: the actor does not move.
const FLOW_NO_PATH_FOUND := "no_path_found"

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
		# The one node a graph is entered through. Which output it takes depends on
		# what kind of graph this is - see [method flows_of]: a page's own graph (its
		# start node carries [code]args.page_entry == true[/code]) branches on
		# [constant TRIGGERS] plus a trailing "next" for [code]call[/code]'s own manual
		# entry; anything else (a route, a called sub-graph) keeps the single "next"
		# port this always had. It carries no state of its own, so it is a RESTART
		# command like "label" and "goto".
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
	"wait_between": {
		# "min"/"max" rolled once, at start() - not re-rolled each tick, so a resumed
		# save picks up the same duration this run already committed to, the same
		# resume contract [Wait] itself keeps. See flow_execs.gd's own WaitBetween.
		"args": {"min": T_SECONDS, "max": T_SECONDS},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Pause for a random duration between \"min\" and \"max\" seconds.",
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
	"variable": {
		# "expression" is a template, not a condition on its own - "{v}" is a literal
		# placeholder events/commands/flow_execs.gd's own VariableCmd substitutes "var"'s
		# name into before parsing, so the same expression ("{v} >= 5", say) reads against
		# whichever variable this node names rather than being retyped for each one - a
		# reusable branch, not a one-off "if".
		"args": {"var": T_VAR, "expression": T_CONDITION},
		"flows": ["true", "false"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Branch on an expression, with \"{v}\" standing in for a named variable.",
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
	"define_route": {
		# Handled directly by EventRunner, the same as "call"/"exit_call" - it sets a
		# policy other nodes' own blocked moves are read against, which only the
		# runner's frame has anywhere to keep. In effect from here until the next
		# "define_route" the graph reaches (looping back to this same node, most often),
		# not scoped by any pairing this file or the graph editor need police.
		#
		# No args: "blocked" is not an ordinary flow EventRunner ever takes while
		# walking this node itself, only reads off the node's own wiring as the policy
		# - left unwired, a blocked move retries (pauses a tick, tries the same move
		# again, forever); wired, a blocked move jumps there instead of retrying. See
		# EventCommandExec.was_blocked and event_runner.gd's own class doc.
		"args": {},
		"flows": ["next", "blocked"], "blocking": false, "space": SPACE_GRID,
		"resume": RESUME_RESTART,
		"blurb": "Sets this route's on-blocked policy: leave \"blocked\" unwired to "
			+ "retry, or wire it to jump there instead of retrying.",
	},

	# -- Actor -----------------------------------------------------------------
	"move_to": {
		# No "path" arg - "line" (step toward the target, stop if refused) is the only
		# behavior this command drives; a teleport is its own command ([code]teleport[/code]
		# below), and pathing around obstacles ("astar") is deferred to a future command
		# of its own rather than a third value silently accepted here and doing nothing.
		# "animation_speed" is unset by default - use whatever pace is already playing,
		# same "unset means leave it alone" contract the page-level field has (see
		# event_document.gd's own note on it) rather than a fourth flag that always
		# resolves to some value whether or not it was authored.
		"args": {"actor": T_ACTOR + "?", "cell": T_CELL, "speed": T_FLOAT + "?",
			"animation_speed": T_FLOAT + "?"},
		"flows": [FLOW_REACHED, FLOW_BLOCKED, FLOW_IMMEDIATE], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Walk an actor to a specific cell.",
	},
	"move_by": {
		# "cells" is a literal delta, or a symbolic token with an optional distance
		# ("wander:3" - see [method split_move_token]); there is no separate "count".
		# A token's distance is walked as that many one-cell legs, so a leg that comes
		# up blocked stops the whole chain there rather than the actor being dragged
		# through whatever refused it. "towards_player"/"away_from_player" re-resolve
		# every leg (chasing a moving target); "forward", "random" and "wander" resolve
		# once and repeat that choice, rather than re-rolling each step
		# (towards_player/away_from_player included - see [method resolve_move_plan]).
		# No "path" arg - see move_to's own note above. "animation_speed" is unset by
		# default too, the same reasoning.
		# See events/commands/actor_execs.gd's own MoveBy.
		"args": {"actor": T_ACTOR + "?", "cells": T_MOVE_DIR,
			"speed": T_FLOAT + "?", "animation_speed": T_FLOAT + "?"},
		"flows": [FLOW_REACHED, FLOW_BLOCKED, FLOW_IMMEDIATE], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Walk an actor a relative number of cells, or a direction (forward, random, wander...) for a distance.",
	},
	"move_route": {
		# A* to "cell" at runtime (over GridMotion.plan_step, capped at "max_nodes"
		# expanded cells, default 2000), the path stored on the actor as JSON move_to
		# commands until the next move_route on it, then walked. See actor_execs.gd's
		# MoveRoute for what each flow means.
		"args": {"actor": T_ACTOR + "?", "cell": T_CELL, "speed": T_FLOAT + "?",
			"animation_speed": T_FLOAT + "?", "max_nodes": T_INT + "?"},
		"flows": [FLOW_REACHED, FLOW_BLOCKED, FLOW_IMMEDIATE, FLOW_NO_PATH_FOUND],
		"blocking": true, "space": SPACE_GRID,
		"resume": RESUME_STATE,
		"blurb": "Walk an actor to a cell by the shortest route around obstacles (A*), remembering the route.",
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
		"args": {"actor": T_ACTOR + "?", "cell": T_CELL, "height": T_FLOAT + "?"},
		"flows": [FLOW_REACHED, FLOW_BLOCKED, FLOW_IMMEDIATE], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"requires": [GameProfile.Capability.HEIGHT],
		"blurb": "Have an actor jump to a cell, arcing a height above it.",
	},
	# -- The party caterpillar (FollowerChain) ------------------------------------------
	"follow_add": {
		# Give "member" (a party member's id - back into the automatic chain) or "actor"
		# (an ordinary actor on the map, who then trails the party). See follower_execs.gd.
		"args": {"member": T_STRING + "?", "actor": T_ACTOR + "?"},
		"flows": ["next"], "blocking": false, "space": SPACE_GRID,
		"resume": RESUME_RESTART,
		"blurb": "Make a party member, or another actor, follow the player in the party line.",
	},
	"follow_remove": {
		"args": {"member": T_STRING + "?", "actor": T_ACTOR + "?"},
		"flows": ["next"], "blocking": false, "space": SPACE_GRID,
		"resume": RESUME_RESTART,
		"blurb": "Stop a party member, or another actor, following the player.",
	},
	"follow_show": {
		# "actor" left out means every follower.
		"args": {"visible": T_BOOL, "actor": T_ACTOR + "?"},
		"flows": ["next"], "blocking": false, "space": SPACE_GRID,
		"resume": RESUME_RESTART,
		"blurb": "Show or hide the followers (all of them, or just \"actor\").",
	},
	"follow_group": {
		"args": {},
		"flows": [FLOW_REACHED, FLOW_IMMEDIATE], "blocking": true, "space": SPACE_GRID,
		"resume": RESUME_RESTART,
		"blurb": "Walk every follower to its place right behind the player.",
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
	"set_lock_facing": {
		"args": {"actor": T_ACTOR + "?", "lock_facing": T_BOOL},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Toggle an actor's lock_facing without waiting for a page switch.",
	},
	"set_through": {
		"args": {"actor": T_ACTOR + "?", "through": T_BOOL},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Toggle an actor's through (phases through other actors) without waiting for a page switch.",
	},
	"set_through_terrain": {
		"args": {"actor": T_ACTOR + "?", "through_terrain": T_BOOL},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Toggle an actor's through_terrain without waiting for a page switch.",
	},
	"set_show_shadow_override": {
		"args": {"actor": T_ACTOR + "?", "show_shadow_override": T_BOOL},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Toggle an actor's show_shadow_override - force its shadow to show even with no sprite assigned.",
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
	"erase_event": {
		# No "next": once an actor's whole placement is gone there is nothing left to
		# resume into, the same reasoning "end" and "exit_call" already carry - see
		# events/commands/actor_execs.gd's EraseEvent for what actually happens.
		"args": {"actor": T_ACTOR + "?"},
		"flows": [], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Remove an actor's placement - itself, its event, everything - from the map.",
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
	"eval_var": {
		# Same "{v}" substitution as "variable" (flow_execs.gd) - the same expression
		# template reads against whichever variable this node names - but this sets
		# "var" to the (boolean - EventCondition.evaluate's only return shape) result
		# rather than branching on it. See events/commands/state_execs.gd's own EvalVar.
		"args": {"var": T_VAR, "expression": T_CONDITION},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Set a variable to the result of an expression, with \"{v}\" standing in for its own name.",
	},

	# -- Debug -------------------------------------------------------------------
	"print_debug": {
		"args": {"text": T_STRING},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Print text to the console - for watching a graph run without a window.",
	},
	"set_fast_forward": {
		"args": {"enabled": T_BOOL + "?"},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Force DebugFlags.is_fast_forward() on/off from a graph, the same as holding backtick/0.",
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
		# than whatever GameEvent/Actor spawned it. fade_out/fade_in/texture are the
		# "or instant" option (event-pages.md) - omitted or zero skips that leg
		# entirely rather than fading for zero seconds.
		"args": {"map": T_STRING, "cell": T_CELL + "?", "facing": T_DIR + "?",
			"fade_out": T_SECONDS + "?", "fade_in": T_SECONDS + "?", "texture": T_STRING + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Leave for another map, placing the player at a cell.",
	},
	"change_map_marker": {
		# The "linked scene and a named teleport location" half of map transfer - see
		# core/map_marker_2d.gd/map_marker_3d.gd. "facing" here overrides the marker's
		# own; with neither set the player's facing is left exactly as it was.
		"args": {"map": T_STRING, "marker": T_STRING, "facing": T_DIR + "?",
			"fade_out": T_SECONDS + "?", "fade_in": T_SECONDS + "?", "texture": T_STRING + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Leave for another map, placing the player at a named marker.",
	},
	"fade": {
		"args": {"to": T_FLOAT + "?", "seconds": T_SECONDS + "?", "texture": T_STRING + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Fade the screen to or from a colour.",
	},
	"fade_in": {
		"args": {"seconds": T_SECONDS + "?", "texture": T_STRING + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Fade the screen in from a colour.",
	},
	"fade_out": {
		"args": {"seconds": T_SECONDS + "?", "texture": T_STRING + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_STATE,
		"blurb": "Fade the screen out to a colour.",
	},
	"shake": {
		# "strength" is the peak offset in screen px, fading to nothing over "seconds".
		# See events/commands/camera_execs.gd's Shake.
		"args": {"seconds": T_SECONDS + "?", "strength": T_FLOAT + "?"},
		"flows": [FLOW_REACHED, FLOW_IMMEDIATE], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Shake the camera - a random offset (strength, px) fading out over seconds.",
	},
	"camera_to": {
		# See this file's own FLOW_REACHED/FLOW_IMMEDIATE doc, and
		# events/commands/camera_execs.gd's CameraTo.
		"args": {"cell": T_CELL, "speed": T_FLOAT + "?", "instant": T_BOOL + "?"},
		"flows": [FLOW_REACHED, FLOW_IMMEDIATE], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Pan the camera to a cell, at a speed (cells/sec) or instantly.",
	},
	"camera_follow": {
		"args": {"actor": T_ACTOR, "speed": T_FLOAT + "?", "instant": T_BOOL + "?",
			"block": T_BOOL + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Have the camera follow an actor, optionally waiting until it catches up (\"block\", default true).",
	},
	"camera_move_by": {
		# "cells" reads exactly as move_by's does: a literal delta, or a token with an
		# optional distance ("random:3"), rolled once and repeated (see
		# [method resolve_move_plan]). The camera has no facing, so "forward" is north.
		# A leg outside camera_bounds stops the chain.
		"args": {"cells": T_MOVE_DIR, "speed": T_FLOAT + "?"},
		"flows": [FLOW_REACHED, FLOW_IMMEDIATE], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Move the camera a relative number of cells, or a direction (random, towards_player...) for a distance.",
	},
	"camera_bounds": {
		"args": {"bounds": T_STRING},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Constrain the camera to a named CameraBounds shape - \"\" clears it.",
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
	"set_y_level": {
		"args": {"actor": T_ACTOR + "?", "y_level": T_INT},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Change an actor's draw order relative to other actors and sprites.",
	},
	"set_step_in_place": {
		"args": {"actor": T_ACTOR + "?", "step_in_place": T_BOOL},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Toggle whether an actor's walk cycle keeps running while it stands still.",
	},
	"set_lock_animation": {
		"args": {"actor": T_ACTOR + "?", "lock_animation": T_BOOL},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Freeze (or resume) an actor's walk-cycle animation outright, without waiting for a page switch.",
	},
	"set_animation_speed": {
		"args": {"actor": T_ACTOR + "?", "animation_speed": T_FLOAT},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Change how fast an actor's walk-cycle animation plays, without waiting for a page switch.",
	},
	"set_color": {
		# "actor" is the target event's actor (@self, or an @id like "@debug-3"); the
		# colour tints its art - ActorView.color - and is written into a save.
		"args": {"actor": T_ACTOR + "?", "color": T_COLOR},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Tint an actor's art a colour (white restores it), without waiting for a page switch.",
	},
	"hold_frame": {
		"args": {"actor": T_ACTOR + "?", "row": T_INT, "col": T_INT, "flip": T_BOOL + "?"},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Freeze an actor's sprite sheet on one exact frame.",
	},
	"set_sheet": {
		"args": {"actor": T_ACTOR + "?", "sheet": T_STRING, "facing": T_TURN + "?"},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Swap an actor's sprite sheet texture, optionally setting its facing.",
	},

	# -- Menu ------------------------------------------------------------------
	"open_menu": {
		"args": {"menu": T_STRING},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"blurb": "Open a full-screen menu (\"party\" or \"shop\") and wait for it to close.",
	},

	# -- Battle ----------------------------------------------------------------
	"start_battle": {
		"args": {"troop": T_STRING, "fade_out": T_SECONDS + "?", "fade_in": T_SECONDS + "?",
			"texture": T_STRING + "?", "allow_defeat": T_BOOL + "?"},
		"flows": ["next"], "blocking": true, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"requires": [GameProfile.Capability.BATTLE_SCENE],
		"blurb": "Start a battle against a troop.",
	},

	# -- Battle AI (enemy graphs, run by BattleAI - see events/commands/ai_execs.gd) ------
	"if_round": {
		# "op" is one of == != < <= > >= (default >=); "every" replaces op/value with
		# "every Nth round".
		"args": {"op": T_STRING + "?", "value": T_INT + "?", "every": T_INT + "?"},
		"flows": ["true", "false"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"requires": [GameProfile.Capability.BATTLE_SCENE],
		"blurb": "AI: branch on the battle round number (or every Nth round).",
	},
	"if_stat": {
		# "who" is self or target; "stat" is hp, mp, max_hp, max_mp, atk, def, mag or spd;
		# "percent" makes hp/mp a percentage of their maximum.
		"args": {"who": T_STRING + "?", "stat": T_STRING, "op": T_STRING, "value": T_FLOAT,
			"percent": T_BOOL + "?"},
		"flows": ["true", "false"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"requires": [GameProfile.Capability.BATTLE_SCENE],
		"blurb": "AI: branch on a stat of self or the chosen target (at/below/above a value).",
	},
	"if_status": {
		"args": {"who": T_STRING + "?", "status": T_STRING},
		"flows": ["true", "false"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"requires": [GameProfile.Capability.BATTLE_SCENE],
		"blurb": "AI: branch on whether self or the chosen target has a status effect.",
	},
	"if_count": {
		# "side" is allies (own side, self included) or enemies (the other side).
		"args": {"side": T_STRING, "op": T_STRING, "value": T_INT},
		"flows": ["true", "false"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"requires": [GameProfile.Capability.BATTLE_SCENE],
		"blurb": "AI: branch on how many are still standing on a side.",
	},
	"if_random": {
		"args": {"chance": T_FLOAT},
		"flows": ["true", "false"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"requires": [GameProfile.Capability.BATTLE_SCENE],
		"blurb": "AI: branch by chance - \"true\" that percent of the time.",
	},
	"choose_target": {
		# "rule": first, random, self, lowest_hp, most_hp, lowest_hp_percent, highest_atk,
		# highest_def, highest_mag, highest_spd, lowest_spd, lowest_def. "side": enemies
		# (default) or allies.
		"args": {"rule": T_STRING, "side": T_STRING + "?"},
		"flows": ["next"], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"requires": [GameProfile.Capability.BATTLE_SCENE],
		"blurb": "AI: choose who the next ability will hit (most hp, lowest hp, first, random...).",
	},
	"use_ability": {
		"args": {"ability": T_STRING},
		"flows": [], "blocking": false, "space": SPACE_ANY,
		"resume": RESUME_RESTART,
		"requires": [GameProfile.Capability.BATTLE_SCENE],
		"blurb": "AI: use an ability on the chosen target - ends the decision.",
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
	# "step" is `move_by` with the count left blank - the special-case below already
	# defaults a missing "count" to 1, so one direction word is a single grid cell.
	"step": {"command": "move_by", "fills": ["direction"]},
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

## What a [constant T_MOVE_DIR] "cells" value may be instead of a literal delta - each
## resolved fresh against the actor's own position (and, for the two "player" tokens,
## wherever [code]@player[/code] currently stands) at the moment [method
## resolve_move_delta] is actually called, never baked in at parse time the way a
## literal [x, y, z] already is. See that method's own doc for what each one means.
const MOVE_DIR_TOKENS: PackedStringArray = [
	"forward", "towards_player", "away_from_player", "random", "wander",
]

## The prefix that marks a resolvable term - question 40. [code]@player[/code],
## [code]@self[/code] and [code]@npc_scout[/code] are references resolved at runtime; a
## bare string is a literal string and never an actor id.
const TERM_PREFIX := "@"

## The command that marks a graph's entry point - see [method validate_reachability].
## Every page's graph is expected to have exactly one node with this command; which of
## its outputs names where execution actually begins depends on [method flows_of].
const START_COMMAND := "start"

## The seven moments a page's own start node may branch on - decision 44's set,
## formerly a page-level [code]settings.trigger[/code] string [method GameEvent._maybe_fire]
## compared by hand, now wired as flow ports on the start node itself: an author connects
## whichever of these a page should react to, and [method GameEvent._maybe_fire] runs the
## graph from there only if that port is actually connected - see [method
## EventCommand.start_wired]. A page's start node carries these (plus a trailing "next",
## for [code]call[/code]'s own manual entry) only when its own [code]args.page_entry[/code]
## is true; a route's or a called sub-graph's start node is untouched by this and keeps
## the single "next" port it always had - see [method flows_of].
const TRIGGERS: PackedStringArray = [
	"player_touch", "event_touch", "action", "auto", "on_load", "leave_cell", "on_flag",
]


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

	if name == START_COMMAND:
		var args: Dictionary = node.get("args", {})
		if bool(args.get("page_entry", false)):
			var out := PackedStringArray(TRIGGERS)
			out.append("next")
			return out
		return PackedStringArray(def["flows"])

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


## Resolves a [constant T_MOVE_DIR] "cells" value against wherever the actor actually
## stands and faces right now.
##
## [param facing]/[param from_cell] are the actor's own; [param player_cell] is
## wherever [code]@player[/code] currently stands, or null if nothing resolved one (a
## graph run with no player on the map, or a bodiless actor with nothing to compare
## against) - "towards_player"/"away_from_player" both read that as nothing to chase
## and answer [constant Vector3i.ZERO], the same as an authored [code][0, 0, 0][/code]
## delta already means.
##
## [b]"towards_player"/"away_from_player"[/b] take one cardinal step along whichever
## axis is furthest from [param player_cell] right now - ties favour X, matching
## [method GridMotion._line_to]'s own dominant-axis rule, so a page's own chase reads
## the same as the pathing [code]move_to[/code] already draws. [b]"random"[/b] is one
## of the four cardinal steps, uniformly. [b]"wander"[/b] is the same four, plus a
## fifth, equally likely outcome - stand still this leg ([constant Vector3i.ZERO]) -
## the only [constant MOVE_DIR_TOKENS] entry that can resolve to no movement at all;
## a bare [code]move_to[/code]/[method MotionController.move_by] already treats a zero
## delta as "already there," so nothing downstream needs to know this was a deliberate
## pause rather than an authored [code][0, 0, 0][/code]. [b]"forward"[/b] is [param
## facing] itself, unit length. A literal delta (already coerced to a
## [Vector3i]/[Vector3]/array by [method _coerce]) answers directly, untouched.
static func resolve_move_delta(value: Variant, facing: Vector3i, from_cell: Vector3i,
		player_cell: Variant) -> Vector3i:
	if value is String:
		match String(split_move_token(value)["token"]):
			"forward":
				return facing
			"towards_player":
				return _one_step_towards(from_cell, player_cell)
			"away_from_player":
				return -_one_step_towards(from_cell, player_cell)
			"random":
				return _random_cardinal()
			"wander":
				return _random_cardinal_or_stay()
		return Vector3i.ZERO
	return _as_cell(value, Vector3i.ZERO)


## A [constant T_MOVE_DIR] string split into its token and distance - [code]"wander:3"[/code]
## is [code]{token: "wander", count: 3}[/code], a bare token is distance 1. The distance
## is how many one-cell legs [code]MoveBy[/code] walks (it is not applied by [method
## resolve_move_delta], which always answers one step). [code]count[/code] is 0 when the
## suffix is not a whole number of at least 1.
static func split_move_token(text: String) -> Dictionary:
	var lowered := text.strip_edges().to_lower()
	var colon := lowered.rfind(":")
	if colon < 0:
		return {"token": lowered, "count": 1}
	var suffix := lowered.substr(colon + 1).strip_edges()
	var count := int(suffix) if suffix.is_valid_int() else 0
	return {"token": lowered.substr(0, colon).strip_edges(), "count": maxi(count, 0)}


## What a [constant T_MOVE_DIR] "cells" value means as a move, resolved once:
## [code]{delta, legs}[/code]. A literal delta is one leg of that delta. A token is rolled
## exactly once here - [code]towards_player[/code]/[code]away_from_player[/code] included,
## so a chase heads the direction it had at the start rather than re-aiming every step -
## and that one-cell step is repeated for its distance ([code]legs[/code]). A step that
## resolves to no movement ("wander" standing still) is a single leg.
static func resolve_move_plan(value: Variant, facing: Vector3i, from_cell: Vector3i,
		player_cell: Variant) -> Dictionary:
	if not (value is String):
		return {"delta": resolve_move_delta(value, facing, from_cell, player_cell), "legs": 1}
	var step := resolve_move_delta(value, facing, from_cell, player_cell)
	var legs := maxi(1, int(split_move_token(value)["count"]))
	return {"delta": step, "legs": 1 if step == Vector3i.ZERO else legs}


## Folds a pre-removal [code]count[/code] argument on a [code]move_by[/code] node into its
## [code]cells[/code], so a document authored before count went away still moves the
## same distance: a token becomes [code]"token:N"[/code], a literal delta is multiplied.
static func _fold_legacy_move_count(args: Dictionary) -> void:
	var n := maxi(1, int(args["count"]))
	args.erase("count")
	if n == 1 or not args.has("cells"):
		return
	var cells: Variant = args["cells"]
	if cells is String:
		var split := split_move_token(cells)
		if int(split["count"]) > 0:
			args["cells"] = "%s:%d" % [split["token"], int(split["count"]) * n]
	elif _looks_like_cell(cells):
		args["cells"] = _as_cell(cells, Vector3i.ZERO) * n


## One cardinal step from [param from] toward [param target] - the larger axis first
## (ties favour X), the same rule [method GridMotion._line_to] already walks a whole
## path by, one step of it at a time here. [constant Vector3i.ZERO] if [param target]
## is not a resolved [Vector3i] (nothing to chase) or already reached.
static func _one_step_towards(from: Vector3i, target: Variant) -> Vector3i:
	if not (target is Vector3i):
		return Vector3i.ZERO
	var delta: Vector3i = (target as Vector3i) - from
	if delta == Vector3i.ZERO:
		return Vector3i.ZERO
	if absi(delta.x) >= absi(delta.z) and delta.x != 0:
		return Vector3i(signi(delta.x), 0, 0)
	return Vector3i(0, 0, signi(delta.z))


## One of the four cardinal directions, uniformly - [constant MOVE_DIR_TOKENS]'
## "random", kept separate from [method resolve_turn]'s own "random" since that one
## picks among however many facings the actor has art for ([method Space.dirs]),
## not always four.
static func _random_cardinal() -> Vector3i:
	const CARDINALS: Array[Vector3i] = [
		Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0),
	]
	return CARDINALS[randi() % CARDINALS.size()]


## [constant MOVE_DIR_TOKENS]' "wander" - [method _random_cardinal]'s own four, plus a
## fifth: stand still this leg. All five equally likely, so standing still is neither
## rarer nor more common than any one direction.
static func _random_cardinal_or_stay() -> Vector3i:
	const CARDINALS_OR_STAY: Array[Vector3i] = [
		Vector3i(0, 0, -1), Vector3i(1, 0, 0), Vector3i(0, 0, 1), Vector3i(-1, 0, 0),
		Vector3i.ZERO,
	]
	return CARDINALS_OR_STAY[randi() % CARDINALS_OR_STAY.size()]


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

	if (name == "move_by" or name == "camera_move_by") and args.has("count"):
		_fold_legacy_move_count(args)

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

		T_MOVE_DIR:
			# Left as a string, same reasoning as T_TURN above: "towards_player" needs
			# wherever @player and this actor actually stand, neither of which the parser
			# has - that is [method resolve_move_delta]'s own job, called once per leg by
			# events/commands/actor_execs.gd's own MoveBy.
			if value is String:
				var split := split_move_token(value)
				if MOVE_DIR_TOKENS.has(split["token"]) and int(split["count"]) >= 1:
					return split["token"] if int(split["count"]) == 1 \
						else "%s:%d" % [split["token"], int(split["count"])]
				problems.append("%s must be a cell [x, y, z], or one of %s (optionally \"token:distance\")."
					% [where, ", ".join(MOVE_DIR_TOKENS)])
				return null
			var cell := _as_cell(value, Vector3i.ZERO)
			if cell == Vector3i.ZERO and not _looks_like_cell(value):
				problems.append("%s must be a cell [x, y, z], or one of %s."
					% [where, ", ".join(MOVE_DIR_TOKENS)])
				return null
			return cell

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

		T_COLOR:
			if value is Color:
				return (value as Color).to_html()
			if value is String and Color.html_is_valid(value):
				return value
			problems.append("%s must be a colour like \"#ff8800\" or \"#ff880080\", found %s."
				% [where, type_string(typeof(value))])
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
		# Move commands gained a "blocked" port (between reached and immediate) after
		# files were already written with only those two; a file missing just that one
		# is fine. Outputs are matched to ports by flow name, so its position is moot.
		if actual == expected - 1 and flows_of(entry).has(FLOW_BLOCKED):
			var has_blocked := false
			for output: Variant in outputs as Array:
				if output is Dictionary and str((output as Dictionary).get("flow", "")) == FLOW_BLOCKED:
					has_blocked = true
			if not has_blocked:
				actual = expected
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


## Whether [param nodes]' own start node has a live output wired to [param flow] - what
## [method GameEvent._maybe_fire] checks before running a page's graph at all, now that a
## trigger firing is answered by the graph's own wiring rather than a page-level
## [code]settings.trigger[/code] string match. False for a missing start node, a start
## node with no such port (a route's or a called sub-graph's, which only ever has
## "next"), or one that has the port but left it unwired.
static func start_wired(nodes: Array, flow: String) -> bool:
	for node in nodes:
		if node is Dictionary and str((node as Dictionary).get("command", "")) == START_COMMAND:
			for output in (node as Dictionary).get("outputs", []) as Array:
				if output is Dictionary and str((output as Dictionary).get("flow", "")) == flow:
					return str((output as Dictionary).get("target", "")) != ""
			return false
	return false


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
