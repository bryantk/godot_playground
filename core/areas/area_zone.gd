class_name AreaZone extends Node

## A bounded region of a map that actors enter and leave. A [Node] under an [Area2D] or
## an [Area3D] - the same arrangement [Actor] uses under a body, and for the same reason:
## one script that serves both spaces.
##
## [b]The collider is the authored shape; it is not always what detects the crossing.[/b]
## A free-moving actor is a physics body travelling continuously through the shape, so
## the area's own [code]body_entered[/code] reports it. A grid actor never travels through
## anything - it snaps from cell centre to cell centre - so [GridMotion] asks the physics
## server what covers the destination at the moment it commits. That answer is
## synchronous, which is the whole point: it arrives in time to change the speed of the
## step that is entering. An overlap signal would arrive a physics frame later, which is
## after the step it was meant to slow had already been given its speed.
##
## The path therefore follows the [i]motion[/i], not the space: a grid actor in a 3D map
## is queried at commit like any other grid actor, at a cell centre that carries its
## floor's Y.
##
## [b]Many zones may cover one cell, and every one of them fires.[/b] Nothing here assumes
## a cell has one occupant, one event or one zone. The same is true of components: a zone
## carries as many as it likes and every one of them is asked.
##
## [b]Author shapes on cell centres, not on cell boundaries.[/b] The grid query asks about
## the exact centre of a cell, and a 3D collision shape is inflated by its margin - about
## 4 cm - before it answers. A box sized to whole cells and centred on a cell boundary
## therefore has its edges sitting within a margin's width of the two cell centres either
## side, and catches both rows. Centre a 4x1 patch at [code](x.0, 0, z.5)[/code] and it
## covers the row it looks like it covers; centre it at [code](x.0, 0, z.0)[/code] and it
## quietly covers two.
##
## [b]Four moments[/b], because the body and the sprite disagree for the length of a step:
## [codeblock]
## actor_entered   commit of the step that lands inside    body in
## actor_arrived   that step's sprite settles inside       visually in
## actor_leaving   commit of the step that lands outside   body out
## actor_exited    that step's sprite settles outside      visually out
## [/codeblock]
## A component wires to whichever of those it means, which is why there are four rather
## than a flag: a speed change wants [signal actor_entered], so the step into the mud is
## itself slow; a footfall splash wants [signal actor_arrived]; "you have left the forest"
## wants [signal actor_exited], the only one that means the actor is wholly out.
##
## Under free motion there is no sprite lagging behind a body, so entered and arrived fire
## together, and so do leaving and exited.
##
## [b]This node does nothing.[/b] It reports crossings; [AreaComponent] children are what
## act on them, and they are ordinary components precisely so that a mud patch, a trigger
## and a music change are the same node with different children.

## The physics layer zone colliders are found on. Forced on in [method _ready] rather than
## left to the author, because a zone that is merely painted on the wrong layer is
## invisible to the commit query and fails silently.
const LAYER := 1 << 3

## Where an actor is with respect to this zone [i]during the current step[/i]. The
## distinction only exists between a commit and its settle, and it is what lets a
## component ask whether the step it is being consulted about is going in or coming out.
enum State {
	ENTERED,  ## Committed a step into the zone; the sprite has not arrived yet.
	INSIDE,   ## Wholly in.
	LEAVING,  ## Committed a step out; the sprite is still inside.
}

## Optional name, for a component that has to tell one zone from another.
@export var zone_id: StringName = &""

signal actor_entered(actor: Actor)
signal actor_arrived(actor: Actor)
signal actor_leaving(actor: Actor)
signal actor_exited(actor: Actor)

var _area: Node = null

## Actor -> State. The zone owns the state; the actor owns the list of zones it is in.
## Split that way so neither is a copy of the other.
var _occupants: Dictionary[Actor, State] = {}


func _ready() -> void:
	_area = get_parent()
	if not (_area is Area2D or _area is Area3D):
		push_warning("AreaZone('%s'): parent is '%s', not an Area2D or Area3D."
			% [name, str(_area.name) if _area != null else "<none>"])
		_area = null
		return

	# set()/connect() by name rather than branching on the type: Area2D and Area3D share
	# no base that has either member, and this is the same "one script, both spaces"
	# trick SpaceAdapter exists for.
	_area.set("collision_layer", int(_area.get("collision_layer")) | LAYER)
	_area.set("monitorable", true)
	_area.connect("body_entered", _on_body_entered)
	_area.connect("body_exited", _on_body_exited)


## The [Area2D] or [Area3D] this zone reads its shape from.
func area() -> Node:
	return _area


func occupants() -> Array[Actor]:
	var out: Array[Actor] = []
	for a: Actor in _occupants:
		out.append(a)
	return out


func has_actor(actor: Actor) -> bool:
	return _occupants.has(actor)


## Where [param actor] stands with respect to this zone right now. [constant State.INSIDE]
## for an actor that is not in the zone at all is never returned - check
## [method has_actor] first.
func state_of(actor: Actor) -> State:
	return _occupants.get(actor, State.INSIDE)


## Is the step currently being taken one that ends inside this zone? False only while the
## actor is on its way out.
func step_enters(actor: Actor) -> bool:
	return _occupants.get(actor, State.LEAVING) != State.LEAVING


## Did the step currently being taken start inside this zone? False only on the step that
## brought the actor in.
func step_leaves(actor: Actor) -> bool:
	return _occupants.get(actor, State.ENTERED) != State.ENTERED


# -- Bookkeeping --------------------------------------------------------------
#
# Called by Actor, which owns membership. Nothing else should call these: routing every
# change through one place is what keeps the actor's list and this table from drifting.

func mark_entered(actor: Actor) -> void:
	_occupants[actor] = State.ENTERED
	actor_entered.emit(actor)


## Silently back to [constant State.INSIDE], for a step out that was cancelled or undone
## before it settled. No signal: nothing happened, and the actor never left.
func mark_inside(actor: Actor) -> void:
	if _occupants.has(actor):
		_occupants[actor] = State.INSIDE


func mark_arrived(actor: Actor) -> void:
	if not _occupants.has(actor):
		return
	_occupants[actor] = State.INSIDE
	actor_arrived.emit(actor)


func mark_leaving(actor: Actor) -> void:
	if not _occupants.has(actor):
		return
	_occupants[actor] = State.LEAVING
	actor_leaving.emit(actor)


func mark_exited(actor: Actor) -> void:
	if not _occupants.has(actor):
		return
	_occupants.erase(actor)
	actor_exited.emit(actor)


# -- The free-motion path -----------------------------------------------------

func _on_body_entered(body: Node) -> void:
	var actor := _actor_of(body)
	if actor != null:
		actor.enter_area(self)


func _on_body_exited(body: Node) -> void:
	var actor := _actor_of(body)
	if actor != null:
		actor.exit_area(self)


## The free-moving [Actor] under [param body], or null.
##
## Grid actors are deliberately ignored here even when they do have a body: their
## crossings are resolved at commit, and letting the overlap signal fire as well would
## report every crossing twice, a frame apart, in the wrong order.
func _actor_of(body: Node) -> Actor:
	for child in body.get_children():
		if child is Actor:
			var actor := child as Actor
			return actor if actor.effective_motion() == Actor.MotionMode.FREE else null
	return null


# -- Lookup -------------------------------------------------------------------

## Every zone covering [param cell], asked of the physics server through the actor's own
## [SpaceAdapter] so that one call serves both spaces.
static func zones_at(actor: Actor, cell: Vector3i) -> Array[AreaZone]:
	var out: Array[AreaZone] = []
	if actor == null:
		return out
	var ctx := actor.context()
	var adapt := actor.adapter()
	if ctx == null or adapt == null:
		return out

	for node in adapt.areas_at(ctx.cell_centre(cell)):
		var zone := of(node)
		if zone != null and not out.has(zone):
			out.append(zone)
	return out


## The [AreaZone] child of [param node], or null if it has none.
static func of(node: Node) -> AreaZone:
	if node == null:
		return null
	for child in node.get_children():
		if child is AreaZone:
			return child as AreaZone
	return null
