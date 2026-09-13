class_name RouteBrain extends Brain

## A brain that plays a fixed list of commands, in order, optionally forever. The
## second thing an actor can be driven by, after the keyboard: a guard who paces, a
## shopkeeper who turns to face the counter, a crate that shuffles on a timer.
##
## [b]The command vocabulary is the event format's, deliberately.[/b] Each entry is
## [code]{"command": String, "args": Dictionary}[/code], with the names and argument
## keys [code]docs/event-pages.md[/code] already specifies - [code]move_to[/code],
## [code]step[/code], [code]face[/code], [code]wait[/code]. When stage C's runner
## arrives it executes the same nodes this does, so a route authored now is a route
## graph later rather than a format to migrate.
##
## [b]What it covers, and what it does not.[/b] There is no branching, no condition and
## no way to react to anything - a route is a loop, not an AI. An actor that should
## notice the player wants an event graph, which is the thing this is deliberately not
## growing into.
##
## Commands, all of which take an optional [code]actor[/code] key that is ignored here
## because a brain drives exactly one actor:
##
## - [code]step {direction: [x, y, z]}[/code] - one cell, as an intent, so a run of
##   them chains with no pause between cells.
## - [code]move_to {cell: [x, y, z], speed: float}[/code] - walk there, straight line,
##   stopping if a step is refused.
## - [code]face {direction: [x, y, z]}[/code] - turn without moving.
## - [code]wait {seconds: float}[/code] - stand still.

## The route. Edited in the inspector on the brain, or handed in from a resource once
## there is one worth sharing between actors.
@export var commands: Array[Dictionary] = []

## Start again at the top when the list runs out. False stops the brain dead, which is
## what a one-shot entrance wants.
@export var loop: bool = true

## Seconds before the first command. Staggering two guards by a fraction of a step is
## the difference between a patrol and a chorus line.
@export var start_delay: float = 0.0

var _index: int = 0
var _delay: float = 0.0


func _ready() -> void:
	super()
	_delay = start_delay


func _think(delta: float) -> void:
	# Cleared first, every frame: a command asks for one thing on the frame it is read
	# and nothing on the frames after it. A step left standing would repeat forever.
	intent.clear()

	if _actor == null or commands.is_empty():
		return

	if _delay > 0.0:
		_delay -= delta
		return

	# is_moving is "busy with a command", which covers both a single step mid-tween and
	# a move_to still working through its queue. Either way this route waits.
	if _actor.is_moving():
		return

	var entry := _next()
	if entry.is_empty():
		return
	_run(entry)


## The next command, advancing the cursor. Empty when the list has run out and
## [member loop] is off, which also stops this brain from being polled again.
func _next() -> Dictionary:
	if _index >= commands.size():
		if not loop:
			set_process(false)
			return {}
		_index = 0
	var entry: Dictionary = commands[_index]
	_index += 1
	return entry


func _run(entry: Dictionary) -> void:
	var command := str(entry.get("command", ""))
	var args: Dictionary = entry.get("args", {})

	match command:
		"step":
			# An intent rather than a direct call, so the base brain applies it the
			# same way it applies the player's - and so consecutive steps chain
			# through GridMotion's standing intent instead of dropping a frame each.
			intent.step = _dir(args.get("direction", Vector3i.ZERO))
		"move_to":
			var m := motion()
			if m != null:
				var opts := {}
				if args.has("speed"):
					opts["speed"] = float(args["speed"])
				if args.has("path"):
					opts["path"] = str(args["path"])
				m.move_to(_dir(args.get("cell", Vector3i.ZERO)), opts)
		"face":
			_actor.set_facing(_dir(args.get("direction", Vector3i.ZERO)))
		"wait":
			_delay = float(args.get("seconds", 0.0))
		_:
			push_warning("RouteBrain('%s'): unknown command '%s'." % [
				_actor.actor_id, command])


## A cell or direction from the two ways a route can spell one: a [Vector3i] typed in
## the inspector, or the three-element array the JSON event format uses.
func _dir(value: Variant) -> Vector3i:
	if value is Vector3i:
		return value as Vector3i
	if value is Vector3:
		return Vector3i(value as Vector3)
	if value is Array and (value as Array).size() >= 3:
		var a := value as Array
		return Vector3i(int(a[0]), int(a[1]), int(a[2]))
	push_warning("RouteBrain: cannot read '%s' as a cell." % value)
	return Vector3i.ZERO
