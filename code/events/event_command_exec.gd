class_name EventCommandExec extends RefCounted

## The per-node executor contract every command in [constant EventCommand.COMMANDS]
## implements, with three deliberate exceptions:
##
## - [code]call[/code] and [code]exit_call[/code] are handled directly by [EventRunner],
##   since they manipulate its call stack (question 49) rather than executing in the
##   ordinary sense.
## - [code]goto[/code], [code]label[/code] and [code]end[/code] need no executor at
##   all: [method flow_port]'s default of [code]"next"[/code] plus a node's own wiring
##   already does their whole job, and a command with zero flow ports terminates its
##   frame generically in [EventRunner] regardless of which command produced it.
## - A command with no backing subsystem yet (a camera/animation/battle command, or
##   [code]follow[/code]/[code]close_window[/code]) has no entry in the factory table
##   below. [EventRunner] treats that the same as an unknown command - report and carry
##   on - matching [code]event_command.gd[/code]'s own repair-and-report rule.
##
## [b]Commands never [code]await[/code][/b] (segment 4's rule). A blocking command
## mints a key through [EventBus] if it needs one and reports completion through
## [method tick] by asking the runner's [KeyLatch] - never by waiting on the signal
## directly, since the key may already have resolved synchronously before [method tick]
## is ever called (a viewless actor, which every headless test actor is).

enum Status { RUNNING, DONE }

var node: Dictionary = {}
var args: Dictionary = {}
var ctx: EventContext = null
var runner: EventRunner = null


func setup(a_node: Dictionary, a_args: Dictionary, a_ctx: EventContext,
		a_runner: EventRunner) -> void:
	node = a_node
	args = a_args
	ctx = a_ctx
	runner = a_runner


## One-shot begin. May finish everything synchronously - a viewless actor's move, a
## state write - in which case [method tick]'s first call already sees it done.
func start() -> void:
	pass


## Called once right after [method start] (with [code]delta == 0.0[/code], to catch
## anything that already finished synchronously) and then once per scheduler tick
## while [constant Status.RUNNING].
func tick(_delta: float) -> int:
	return Status.DONE


## Which of the node's flow ports to take once DONE. "next" for almost everything,
## "true"/"false" for `if`, a choice's own label for `ask`.
func flow_port() -> String:
	return "next"


## A blocked attempt trying again, inside an active [code]define_route[/code] scope
## whose "blocked" is left unwired ([method EventRunner._retry_after_pause]) - the same
## instance retrying, never a fresh one built through [method create]. The base
## implementation just calls [method start] again, correct for anything whose target is
## already absolute ([code]move_to[/code]'s own cell, say) or that never reports [method
## was_blocked] true in the first place.
##
## [b]A relative move overrides this[/b] ([code]move_by[/code], events/
## commands/actor_execs.gd) because [method start] re-reads its own authored delta
## against wherever the actor happens to be [i]right now[/i] - which, after a move that
## got partway there before being refused, is no longer where it started. Retrying via
## [method start] there would aim the same delta again from the partially-advanced
## position, walking further past the original target with every failed-then-partial
## attempt instead of finishing at it. Retrying toward the already-captured target this
## command committed to at its own first [method start] - not re-deriving a new one - is
## what [method retry] exists to let each command choose for itself.
func retry() -> void:
	start()


## Interrupted from outside - a lease, a cutscene seizing the actor. Must leave nothing
## waiting on a key this command owns (the invariant segment 4's four motion-key fixes
## exist to uphold).
func cancel() -> void:
	pass


## Question 39's hybrid save. [code]RESUME_RESTART[/code] is the default (this returns
## false); a command in the [code]RESUME_STATE[/code] bucket overrides this and
## [method capture]/[method restore]. The base [method restore] calls [method start] -
## restart is always a legal downgrade, so a command that stops being resumable in a
## later version simply ignores an old save's state.
func resumable() -> bool:
	return false


func capture() -> Dictionary:
	return {}


func restore(_state: Dictionary) -> void:
	start()


## True for a command whose own effect is expected to tear down the very placement that
## started this runner - [code]change_map[/code]/[code]change_map_marker[/code]/
## [code]start_battle[/code] (see [method EventRunner.current_exec_survives_teardown]),
## whose whole job is leaving the map (or leaving for a battle scene) they were
## triggered from. False for everything else, including [code]erase_event[/code] -
## that one *wants* [method GameEvent._exit_tree] to stop its own runner, the opposite
## case this exists to except.
func survives_teardown() -> bool:
	return false


## The actor this node addresses - args.actor if given, else @self. Every actor
## command's own arg is optional and defaults to self (event_command.gd's own note).
func actor() -> Actor:
	if ctx == null:
		return null
	return ctx.resolve(str(args.get("actor", "@self")))


## The [CameraRig] driving whatever map this graph is running on - events/commands/
## camera_execs.gd's own shared lookup, the same "resolve through the live map, never a
## concrete rig type" reasoning [method actor] already follows for [Actor]. Null with no
## map bound (never in ordinary play) or no rig registered yet.
func camera_rig() -> CameraRig:
	if ctx == null or ctx.map == null:
		return null
	return ctx.map.camera_rig()


# -- "reached/immediate" -----------------------------------------------------------
#
# Shared by every command with real travel time (move_to, move_by, jump - actor_execs.gd;
# camera_to, camera_move_by - camera_execs.gd): two flow ports instead of the generic
# per-node "blocking" override, which the graph editor has no toggle for yet
# (event_graph_node.gd's own blocking indicator is read-only). Wiring [constant
# EventCommand.FLOW_IMMEDIATE] takes the command out of the runner's way the instant it
# starts; wiring only [constant EventCommand.FLOW_REACHED] (or neither) waits for it to
# actually finish. A command using this only has to call [method own_key] to mint its
## key, then use [method reached_immediate_tick]/[method reached_immediate_flow_port]
## verbatim for its own [method tick]/[method flow_port].

## Whether this node has wired [constant EventCommand.FLOW_IMMEDIATE] - checked fresh
## each call rather than cached, since [member node] never changes after [method setup]
## and the scan is a handful of entries at most.
func immediate_wired() -> bool:
	return EventCommandExec.flow_wired(node, EventCommand.FLOW_IMMEDIATE)


## Common [method tick] for every "reached/immediate" command: DONE the instant
## [method immediate_wired] is true (the graph chose not to wait), else DONE once
## [method own_key] resolves through this run's [KeyLatch] - the same wait [method
## MoveTo.tick] (events/commands/actor_execs.gd) always used, just factored out now that
## more than one command needs it.
func reached_immediate_tick(_delta: float = 0.0) -> int:
	if immediate_wired():
		return Status.DONE
	var key := own_key()
	return Status.DONE if key == "" or runner.latch.consume(key) else Status.RUNNING


## Common [method flow_port] for every "reached/immediate" command.
func reached_immediate_flow_port() -> String:
	return EventCommand.FLOW_IMMEDIATE if immediate_wired() else EventCommand.FLOW_REACHED


## True the moment this command's own movement finished somewhere other than where it
## meant to land - a refused step, not merely one still in flight. [method
## EventRunner._resolve_finished_node] reads this only while a [code]define_route[/code]
## scope is active (event_runner.gd's own class doc); a command that never overrides
## this - almost all of them - can never trigger that path. [code]move_to[/code]/[code]
## move_by[/code] (events/commands/actor_execs.gd) are the two that
## do, the same "compare the actor's real cell to where this meant to land" check
## [code]route_step[/code]/[code]route_move_to[/code]'s own [method flow_port] already
## makes for a compiled route (events/commands/route_execs.gd).
func was_blocked() -> bool:
	return false


## True for a move command with a "blocked" flow port ([constant
## EventCommand.FLOW_BLOCKED]) - [method EventRunner._resolve_finished_node] jumps to it
## when [method was_blocked] and it is wired, and otherwise waits a frame and [method
## retry]s the command, whether or not a [code]define_route[/code] is active.
func supports_blocked_flow() -> bool:
	return false


## The real key this command's own system minted, if any - "" for a command with none.
## What a node's authored [code]key[/code] field (event_command.gd) aliases to, so a
## later [code]wait_for[/code] can join a non-blocking command by the name the author
## gave it rather than the internal name [GridMotion]/[FreeMotion] happened to mint.
func own_key() -> String:
	return ""


## A saved cell - a 3-element array, the same shape [method GridMotion.to_save]'s own
## queue entries already use - back to a [Vector3i], or [param fallback] when [param
## value] is not one (an older save, captured before a command started saving its own
## target cell explicitly). Shared by [code]move_by[/code]/[code]step[/code]'s own
## [method restore] (events/commands/actor_execs.gd) - both need it for the same
## reason: a target relative to wherever the actor stood when the move started must
## survive a mid-flight capture, not be recomputed against wherever it has since ended
## up.
## A [code]texture[/code] argument's resource, loaded from its path - null for "" or a
## path nothing resolves to. Shared by every fade-driven command ([code]fade[/code]/
## [code]fade_in[/code]/[code]fade_out[/code], [code]change_map[/code]/
## [code]change_map_marker[/code]'s own optional fade legs) that lets an author override
## [FadeOverlay]'s default grayscale mask with their own.
static func load_texture_arg(value: Variant) -> Texture2D:
	var path := str(value)
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


static func saved_cell_or(value: Variant, fallback: Vector3i) -> Vector3i:
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Vector3i(int(a[0]), int(a[1]), int(a[2]))
	return fallback


## Whether [param node]'s own [code]outputs[/code] wires [param flow] to anywhere -
## checked by name rather than only by count ([method EventCommand.validate_node]'s own
## job). [code]camera_to[/code] (events/commands/camera_execs.gd) is what this is for:
## a command with more than one flow port that needs to know which one an author
## actually connected, not just how many are present.
static func flow_wired(from_node: Dictionary, flow: String) -> bool:
	for output: Variant in (from_node.get("outputs", []) as Array):
		if typeof(output) == TYPE_DICTIONARY and str((output as Dictionary).get("flow", "")) == flow:
			# Present but unconnected does not count - the same distinction [method
			# EventCommand.start_wired] already draws for a start node's own ports.
			return str((output as Dictionary).get("target", "")) != ""
	return false


## Distance-to-duration for a rate-based move - 0 or unset speed reads as instant.
## Shared by every camera pan (events/commands/camera_execs.gd) the same way an actor's
## own movement commands share [method saved_cell_or] above.
##
## Collapses to instant under [method DebugFlags.is_fast_forward] too, same as [Wait]'s
## own [code]tick()[/code] - a camera pan is exactly the kind of real-time animation
## fast-forward exists to skip, and every caller already treats 0 as "do not animate
## this," so nothing downstream needs its own separate fast-forward check.
static func seconds_for_speed(distance: float, speed: float) -> float:
	if DebugFlags.is_fast_forward():
		return 0.0
	return 0.0 if speed <= 0.0 else distance / speed


# -- Factory --------------------------------------------------------------------

const _FlowExecs := preload("res://code/events/commands/flow_execs.gd")
const _ActorExecs := preload("res://code/events/commands/actor_execs.gd")
const _DialogueExecs := preload("res://code/events/commands/dialogue_execs.gd")
const _StateExecs := preload("res://code/events/commands/state_execs.gd")
const _MapExecs := preload("res://code/events/commands/map_execs.gd")
const _PresentationExecs := preload("res://code/events/commands/presentation_execs.gd")
const _RouteExecs := preload("res://code/events/commands/route_execs.gd")
const _BattleExecs := preload("res://code/events/commands/battle_execs.gd")
const _MenuExecs := preload("res://code/events/commands/menu_execs.gd")
const _CameraExecs := preload("res://code/events/commands/camera_execs.gd")
const _FollowerExecs := preload("res://code/events/commands/follower_execs.gd")
const _AiExecs := preload("res://code/events/commands/ai_execs.gd")

static var _table: Dictionary = {}

static func _ensure_table() -> void:
	if not _table.is_empty():
		return
	for source: GDScript in [_FlowExecs, _ActorExecs, _DialogueExecs, _StateExecs,
			_MapExecs, _PresentationExecs, _RouteExecs, _BattleExecs, _MenuExecs,
			_CameraExecs, _FollowerExecs, _AiExecs]:
		var part: Dictionary = source.table()
		for key: Variant in part:
			_table[key] = part[key]


## A fresh executor for [param command_name], or null when this segment has no
## executor for it yet - see the class doc's third exception.
static func create(command_name: String) -> EventCommandExec:
	_ensure_table()
	var script: Variant = _table.get(command_name)
	if script == null:
		return null
	return (script as GDScript).new()
