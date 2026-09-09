class_name Occupancy extends RefCounted

## Which solid actor is holding which cell, for one map.
##
## The only way to change it is [method commit], which takes a whole set of cell
## changes and applies all of them or none. A single step is only two changes and
## could have been two dictionary writes - but pushing a block is a chain that must
## not half-apply, and if the ordinary step does not already go through [method
## commit] then push arrives as a rewrite instead of a caller. So there is one path.

## cell -> actor_id
var _cells: Dictionary[Vector3i, StringName] = {}


## Who is holding [param cell], or [code]&""[/code] if nobody is.
func at(cell: Vector3i) -> StringName:
	return _cells.get(cell, &"")


func is_free(cell: Vector3i) -> bool:
	return not _cells.has(cell)


## True when [param cell] is free or already held by [param actor_id] - an actor never
## blocks itself, which matters for a move that ends where it started.
func is_free_for(cell: Vector3i, actor_id: StringName) -> bool:
	var holder := at(cell)
	return holder == &"" or holder == actor_id


## Every cell [param actor_id] holds. Usually one; a multi-cell actor holds several.
func cells_of(actor_id: StringName) -> Array[Vector3i]:
	var out: Array[Vector3i] = []
	for cell: Vector3i in _cells:
		if _cells[cell] == actor_id:
			out.append(cell)
	return out


## Apply a set of cell changes atomically.
##
## [param changes] maps a cell to the actor that should hold it afterwards, or to
## [code]&""[/code] to release it. Because the keys are cells, two actors can never
## claim the same cell in one set - so the only collision left to check is a claim on
## a cell held by an actor that is [i]not[/i] taking part.
##
## That rule is what makes the interesting cases work. Two actors swapping places both
## appear as claimants, so each may take the other's cell. A push chain lists the
## pusher and every block, so the whole chain moves or none of it does. But stepping
## into a stationary NPC is a claim against a holder who is not in the set, and is
## refused.
##
## A commit re-declares a participant's whole footprint: any cell a claimant held
## before and does not claim here is released. For the single-cell actors this project
## has, that is simply what you want.
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
		if claimant == &"":
			continue
		var holder := at(cell)
		if holder == &"" or holder == claimant:
			continue
		if not movers.has(holder):
			return false

	# Past this point nothing can fail, so the writes are safe to make in place.
	for actor_id: StringName in movers:
		for cell in cells_of(actor_id):
			_cells.erase(cell)

	for cell: Vector3i in changes:
		var claimant := changes[cell]
		if claimant == &"":
			_cells.erase(cell)
		else:
			_cells[cell] = claimant
	return true


## Convenience for the overwhelmingly common case: one actor leaving [param from] for
## [param to]. Equal cells are a no-op that still reports success.
func commit_step(actor_id: StringName, from: Vector3i, to: Vector3i) -> bool:
	if from == to:
		return is_free_for(to, actor_id)
	var changes: Dictionary[Vector3i, StringName] = {}
	changes[from] = &""
	changes[to] = actor_id
	return commit(changes)


## Two actors trading cells. Legal even though both destinations are occupied, which
## is the case a reserve-as-you-go occupancy cannot express.
func commit_swap(a_id: StringName, a_cell: Vector3i, b_id: StringName, b_cell: Vector3i) -> bool:
	var changes: Dictionary[Vector3i, StringName] = {}
	changes[a_cell] = b_id
	changes[b_cell] = a_id
	return commit(changes)


func reserve(actor_id: StringName, cell: Vector3i) -> bool:
	var changes: Dictionary[Vector3i, StringName] = {}
	changes[cell] = actor_id
	return commit(changes)


## Drop every cell [param actor_id] holds - called when an actor leaves the map, so a
## dead monster does not keep blocking the corridor it died in.
func release_actor(actor_id: StringName) -> void:
	for cell in cells_of(actor_id):
		_cells.erase(cell)


func clear() -> void:
	_cells.clear()


func size() -> int:
	return _cells.size()
