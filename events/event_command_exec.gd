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


## The actor this node addresses - args.actor if given, else @self. Every actor
## command's own arg is optional and defaults to self (event_command.gd's own note).
func actor() -> Actor:
	if ctx == null:
		return null
	return ctx.resolve(str(args.get("actor", "@self")))


## The real key this command's own system minted, if any - "" for a command with none.
## What a node's authored [code]key[/code] field (event_command.gd) aliases to, so a
## later [code]wait_for[/code] can join a non-blocking command by the name the author
## gave it rather than the internal name [GridMotion]/[FreeMotion] happened to mint.
func own_key() -> String:
	return ""


# -- Factory --------------------------------------------------------------------

const _FlowExecs := preload("res://events/commands/flow_execs.gd")
const _ActorExecs := preload("res://events/commands/actor_execs.gd")
const _DialogueExecs := preload("res://events/commands/dialogue_execs.gd")
const _StateExecs := preload("res://events/commands/state_execs.gd")
const _MapExecs := preload("res://events/commands/map_execs.gd")
const _PresentationExecs := preload("res://events/commands/presentation_execs.gd")
const _RouteExecs := preload("res://events/commands/route_execs.gd")

static var _table: Dictionary = {}

static func _ensure_table() -> void:
	if not _table.is_empty():
		return
	for source: GDScript in [_FlowExecs, _ActorExecs, _DialogueExecs, _StateExecs,
			_MapExecs, _PresentationExecs, _RouteExecs]:
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
