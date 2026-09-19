class_name Occupancy extends RefCounted

## Who is standing on which cell, for one map.
##
## [b]A cell holds zero to many actors.[/b] Presence and blocking are two different
## questions and this class answers both: [method actors_at] reports everyone standing
## there, [method blockers_at] reports only those who stop a step. That split is the
## point - an actor that phases through others used to be absent from this table
## entirely, so "what is at [code]player.cell() + facing()[/code]" could not find it and
## a through NPC was unaddressable by interact.
##
## The only way to change it by agreement is [method commit], which takes a whole set of
## cell changes and applies all of them or none. A single step is only one claim and
## could have been one dictionary write - but pushing a block is a chain that must not
## half-apply, and if the ordinary step does not already go through [method commit] then
## push arrives as a rewrite instead of a caller. So there is one path.
##
## [method place] is the other path, and it is deliberately not the same one: a teleport,
## a spawn or an event dropping an actor somewhere is a [i]forced[/i] placement that
## cannot be refused, and two blockers left standing on one cell that way is intentional
## rather than an error. Only a voluntary step is refused. See open-questions 34.

## cell -> Array[StringName], in arrival order. An empty list is erased rather than
## kept, so [method is_empty] and [method size] mean what they say.
var _cells: Dictionary[Vector3i, Array] = {}

## Actors that neither block nor are blocked. Symmetric by decision (open-questions 35):
## one flag, both directions, so there is no ghost that others can still bump into.
var _phasing: Dictionary[StringName, bool] = {}


## Declare whether [param actor_id] phases through other actors. Called once by [Actor]
## when it registers; an actor never named here blocks, which is what keeps a bare
## [Occupancy] in a test behaving like the solid-by-default world.
func set_phasing(actor_id: StringName, phasing: bool) -> void:
	if phasing:
		_phasing[actor_id] = true
	else:
		_phasing.erase(actor_id)


func phases(actor_id: StringName) -> bool:
	return _phasing.has(actor_id)


## Everyone standing on [param cell], in the order they arrived. The caller gets a copy,
## so iterating it while committing is safe.
func actors_at(cell: Vector3i) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _cells.get(cell, []):
		out.append(id)
	return out


## Only those on [param cell] who stop a step. This is the list a movement check reads;
## [method actors_at] is the list an interact or a trigger reads.
func blockers_at(cell: Vector3i) -> Array[StringName]:
	var out: Array[StringName] = []
	for id: StringName in _cells.get(cell, []):
		if not phases(id):
			out.append(id)
	return out


## Nobody at all is standing here - through actors included.
func is_empty(cell: Vector3i) -> bool:
	return not _cells.has(cell)


## Nothing here stops a step. A cell holding only through actors is clear but not empty.
func is_clear(cell: Vector3i) -> bool:
	return blockers_at(cell).is_empty()


## May [param actor_id] voluntarily step onto [param cell]?
##
## True when the actor phases (it is stopped by nobody), or when nothing blocking is
## standing there but itself. An actor never blocks itself, which matters for a move
## that ends where it started.
func is_free_for(cell: Vector3i, actor_id: StringName) -> bool:
	if phases(actor_id):
		return true
	for id: StringName in blockers_at(cell):
		if id != actor_id:
			return false
	return true


## Every cell [param actor_id] holds. Usually one; a multi-cell actor holds several.
func cells_of(actor_id: StringName) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cell: Vector3i in _cells:
		if (_cells[cell] as Array).has(actor_id):
			out.append(cell)
	return out


## Apply a set of cell changes atomically.
##
## [param changes] maps a cell to the actor that claims it. Because the keys are cells,
## two actors cannot claim the same cell in one set - which is a limit on the shape of a
## batch, not on how many actors may end up sharing a cell.
##
## [b]A commit re-declares a participant's whole footprint.[/b] Every claimant is lifted
## off all of its current cells first, so a step needs only the claim on its destination
## and there is nothing to release explicitly. That is also what makes the interesting
## cases work: two actors swapping places both appear as claimants, so each may take the
## other's cell, and a push chain lists the pusher and every block, so the whole chain
## moves or none of it does.
##
## [b]The refusal rule, in one sentence:[/b] a claim is refused when a [i]blocking[/i]
## actor is standing on that cell and is not itself taking part. Stepping into a
## stationary NPC is exactly that and is refused. A through actor standing there is not,
## and neither is an actor who is moving out of the way in this same set.
##
## Returns false and changes nothing if any claim collides.
func commit(changes: Dictionary[Vector3i, StringName]) -> bool:
	var movers: Dictionary[StringName, bool] = {}
	for cell: Vector3i in changes:
		var claimant := changes[cell]
		if claimant != &"":
			movers[claimant] = true

	for cell: Vector3i in changes:
		var claimant := changes[cell]
		if claimant == &"" or phases(claimant):
			continue
		for holder: StringName in blockers_at(cell):
			if holder == claimant or movers.has(holder):
				continue
			return false

	# Past this point nothing can fail, so the writes are safe to make in place.
	for actor_id: StringName in movers:
		_lift(actor_id)

	for cell: Vector3i in changes:
		var claimant := changes[cell]
		if claimant != &"":
			_put(cell, claimant)
	return true


## Convenience for the overwhelmingly common case: one actor leaving [param from] for
## [param to]. Equal cells are a no-op that still reports whether staying put is legal.
func commit_step(actor_id: StringName, from: Vector3i, to: Vector3i) -> bool:
	if from == to:
		return is_free_for(to, actor_id)
	var changes: Dictionary[Vector3i, StringName] = {}
	changes[to] = actor_id
	return commit(changes)


## Two actors trading cells. Legal even though both destinations are occupied, which is
## the case a reserve-as-you-go occupancy cannot express.
func commit_swap(a_id: StringName, a_cell: Vector3i, b_id: StringName, b_cell: Vector3i) -> bool:
	var changes: Dictionary[Vector3i, StringName] = {}
	changes[a_cell] = b_id
	changes[b_cell] = a_id
	return commit(changes)


## Put [param actor_id] on [param cell] whatever is already there, lifting it off
## wherever it was.
##
## This cannot be refused, and that is the decision rather than an oversight: a spawn, a
## teleport or an event placing an actor is a statement, not a request. Two blockers on
## one cell is then representable, they are presumed intentional, and they walk off
## normally because only a [i]voluntary[/i] step consults [method is_free_for].
func place(actor_id: StringName, cell: Vector3i) -> void:
	_lift(actor_id)
	_put(cell, actor_id)


## Like [method place], but for an occupant spanning several cells at once - a large
## static prop, or a rigid body whose collider straddles more than one cell. Forced for
## the same reason [method place] is: an authored multi-cell footprint is a statement,
## not a request, and refusing it half-placed would leave the table inconsistent.
func place_many(actor_id: StringName, cells: Array[Vector3i]) -> void:
	_lift(actor_id)
	for cell: Vector3i in cells:
		_put(cell, actor_id)


## Drop every cell [param actor_id] holds - called when an actor leaves the map, so a
## dead monster does not keep blocking the corridor it died in. Its phasing flag goes
## with it, since nothing else would ever clear it.
func release_actor(actor_id: StringName) -> void:
	_lift(actor_id)
	_phasing.erase(actor_id)


func clear() -> void:
	_cells.clear()
	_phasing.clear()


## How many cells have anyone standing on them. Not a count of actors - one cell holding
## three actors is one.
func size() -> int:
	return _cells.size()


## Every cell at least one blocking occupant holds - a prop, a standing actor - as a set
## rather than one cell at a time. For [DebugPassabilityView]'s overlay, which wants to
## draw a box over every cell a step would be refused on, terrain included or not.
func blocking_cells() -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cell: Vector3i in _cells:
		if not blockers_at(cell).is_empty():
			out.append(cell)
	return out


# -- Internals ----------------------------------------------------------------

func _lift(actor_id: StringName) -> void:
	for cell: Vector3i in cells_of(actor_id):
		var here: Array = _cells[cell]
		here.erase(actor_id)
		if here.is_empty():
			_cells.erase(cell)


func _put(cell: Vector3i, actor_id: StringName) -> void:
	if not _cells.has(cell):
		var fresh: Array[StringName] = []
		_cells[cell] = fresh
	var here: Array = _cells[cell]
	if not here.has(actor_id):
		here.append(actor_id)
