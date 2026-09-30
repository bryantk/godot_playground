class_name ActorQueries

## The four questions the [code]@actor.[/code] shorthand asks, in one place so every
## surface that spells them - [EventCondition] (page conditions, [code]if[/code],
## [code]eval_var[/code]) and the debug terminal - means exactly the same thing:
##
## [codeblock]
## @guard.at(3, 0, 4)              is the actor on that cell?
## @guard.near(3, 0, 4, 2)         within 2 cells (Manhattan) of that cell?
## @guard.near_event(@player, 2)   within 2 cells (Manhattan) of another actor?
## @guard.flag("alerted")          the actor's own self flag - read
## @guard.flag("alerted", true)    ... and write (terminal only; a condition cannot write)
## [/codeblock]
##
## Distance is Manhattan over cells, [code]|dx| + |dy| + |dz|[/code]. A flag is the same
## per-event, per-map self flag [code]self.talked[/code] and [code]set_self_flag[/code]
## use, read off the [GameEvent] that sits with the actor - so its key is that event's
## [method GameEvent.event_id] and the actor's map.


static func at(actor: Actor, cell: Vector3i) -> bool:
	return actor != null and actor.cell() == cell


static func near(actor: Actor, cell: Vector3i, distance: int) -> bool:
	return actor != null and manhattan(actor.cell(), cell) <= distance


static func near_event(actor: Actor, other: Actor, distance: int) -> bool:
	return actor != null and other != null and manhattan(actor.cell(), other.cell()) <= distance


static func manhattan(a: Vector3i, b: Vector3i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y) + absi(a.z - b.z)


## The [GameEvent] placed with [param actor] - a sibling under the same placement root, the
## shape [method GameEvent._find_actor]'s own fallback expects. Null for an actor with none.
static func event_of(actor: Actor) -> GameEvent:
	var parent := actor.get_parent() if actor != null else null
	if parent == null:
		return null
	for child in parent.get_children():
		if child is GameEvent:
			return child as GameEvent
	return null


## [param actor]'s own self flag [param flag_name]. False when it has no event to hold one.
static func flag(actor: Actor, flag_name: StringName) -> bool:
	var event := event_of(actor)
	var map := actor.context() if actor != null else null
	if event == null or map == null:
		return false
	return GameState.self_flag(map.map_id, event.event_id(), flag_name)


static func set_flag(actor: Actor, flag_name: StringName, value: bool) -> void:
	var event := event_of(actor)
	var map := actor.context() if actor != null else null
	if event == null or map == null:
		push_warning("ActorQueries: %s has no event to hold flag '%s'." % [
			actor.actor_id if actor != null else "<none>", flag_name])
		return
	GameState.set_self_flag(map.map_id, event.event_id(), flag_name, value)


# -- For the debug terminal ---------------------------------------------------------
#
# Godot's Expression cannot parse "@guard.at(...)", so the terminal rewrites it to
# actors["guard"].at(...) and hands the Expression an [ActorsProxy] as the input named
# "actors". Each method is the static above, taking plain numbers.

## [code]actors["guard"][/code] - one actor's shorthand methods.
class Handle extends RefCounted:
	var actor: Actor

	func _init(a: Actor) -> void:
		actor = a

	func at(x: int, y: int, z: int) -> bool:
		return ActorQueries.at(actor, Vector3i(x, y, z))

	func near(x: int, y: int, z: int, distance: int) -> bool:
		return ActorQueries.near(actor, Vector3i(x, y, z), distance)

	func near_event(other: Handle, distance: int) -> bool:
		return ActorQueries.near_event(actor, other.actor if other != null else null, distance)

	## One argument reads, two write - the same spelling as in a condition, plus the write.
	func flag(flag_name: String, value: Variant = null) -> Variant:
		if value == null:
			return ActorQueries.flag(actor, StringName(flag_name))
		ActorQueries.set_flag(actor, StringName(flag_name), bool(value))
		return bool(value)


## [code]actors[/code] itself - indexing it by actor id (or "player") gives that actor's
## [Handle]. Looks actors up on whichever map is loaded.
class ActorsProxy extends RefCounted:
	var map: MapContext

	func _init(m: MapContext) -> void:
		map = m

	func _get(property: StringName) -> Variant:
		if map == null:
			return null
		var found: Actor = null
		if property == &"player":
			for a in map.actors():
				if a.is_player():
					found = a
					break
		else:
			found = map.actor(property)
		return Handle.new(found) if found != null else null
