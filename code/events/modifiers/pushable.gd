class_name Pushable extends GameEventModifier

## A [GameEventModifier] that turns a refused step against this event's own [Actor]
## into a shove: the blocked actor's own attempted direction becomes a one-cell
## [method GridMotion.step] for this event's actor instead. Succeeds or fails exactly
## like any other step - occupancy, terrain and every other [RestrictToArea]-style
## restrictor all get a say, so a crate cannot be pushed through a wall or out of its
## own fenced area.
##
## Listens to [signal EventBus.actor_blocked] directly rather than going through
## [method GameEvent._maybe_fire] - a push is a physical reaction, not a dialogue
## trigger, and has to work with no page authored at all.

## How many times this can still be pushed. -1 is unlimited; once it reaches 0 a
## refused step against this event just stays a wall bump - the same as any other
## solid, unmovable prop.
@export var max_pushes: int = -1

var _pushes_used: int = 0


func _ready() -> void:
	super._ready()
	EventBus.actor_blocked.connect(_on_actor_blocked)


func _exit_tree() -> void:
	if EventBus.actor_blocked.is_connected(_on_actor_blocked):
		EventBus.actor_blocked.disconnect(_on_actor_blocked)


## Fires for every refused step in the map, not only ones aimed at this event - see
## the class doc on why this bypasses [method GameEvent._maybe_fire] and its own
## [code]_active_page[/code] gating.
func _on_actor_blocked(blocked_id: StringName, from: Vector3i, to: Vector3i) -> void:
	var my_actor := actor()
	if my_actor == null or blocked_id == my_actor.actor_id:
		return

	var ctx := my_actor.context()
	var blocker: Actor = ctx.actor(blocked_id) if ctx != null else null
	if blocker == null:
		return

	if not _shifted_overlap(blocker.footprint_cells(), from, to, my_actor.footprint_cells()):
		return  # this refusal had nothing to do with this event

	if max_pushes >= 0 and _pushes_used >= max_pushes:
		return  # spent - an ordinary, silent wall bump from here on

	var direction := to - from
	if my_actor.motion().step(direction):
		_pushes_used += 1
		AudioMaster.play_sound_effect(&"push", 80.0)
	else:
		AudioMaster.play_sound_effect(&"push_blocked", 80.0)
		_bump_blocker(blocker)


## No animation system exists yet to hand this to - a placeholder for the day one
## does, so the call site that will want it is already here.
func _bump_blocker(_blocker: Actor) -> void:
	pass


## [param cells] (a footprint at rest) shifted by the refused step [param from] ->
## [param to], checked against [param other] for overlap - the same "was this refusal
## aimed at me" arithmetic [method GameEvent._on_actor_blocked] uses, kept local rather
## than reaching into that class's own private helpers.
func _shifted_overlap(cells: Array[Vector3i], from: Vector3i, to: Vector3i,
		other: Array[Vector3i]) -> bool:
	var delta := to - from
	for c in cells:
		if other.has(c + delta):
			return true
	return false
