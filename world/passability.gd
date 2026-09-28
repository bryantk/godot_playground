class_name Passability

## Can an actor enter a cell? Two sources of truth, both consulted, in cost order:
## static terrain, then occupancy, then physics as the escape hatch.
##
## Steps 1 and 2 are cheap lookups and reject most moves. Step 3 is what keeps
## physics-driven objects honest - a pushed crate, a door body, a temporary barrier -
## without making them author tile data. Free-movement actors skip 1 and 2 entirely
## and let physics do its job.
##
## [b]2D terrain is a hand-painted direction mask; 3D terrain is geometry.[/b] A 2D map
## carries a [TileMapLayer] of pathing tiles, one per walkable cell, each saying which of
## its four sides may be crossed - see [method directions]. A 3D map lets its colliders
## and its [GridMap] answer. The split is deliberate: painting a tile per cell is how a
## Lufia-style map is authored, and modelling a collider per doorway is how a 3D one is.
##
## [b]The two through flags each switch off one step.[/b] [member Actor.through_terrain]
## skips 1 and 3 - both are terrain, one painted and one modelled, and skipping only the
## first would let physics re-impose the wall. [member Actor.through_actors] is not tested
## here at all: it is [Occupancy]'s to know, because blocking is symmetric and both halves
## of it belong to the same table.

## Tile custom-data layer names read from a [TileMapLayer] or [GridMap]. Kept here so
## the strings are written once and the map author has one spelling to match.
const DATA_PATHING := "pathing"
const DATA_HEIGHT := "height"

## Which sides of a cell may be crossed, as bit flags on the pathing tile. Binary
## 1 / 10 / 100 / 1000, so a painted tile reads as a nibble.
const NORTH := 1
const EAST := 2
const SOUTH := 4
const WEST := 8

## An unpainted cell. A map with no pathing layer at all is open ground, which is what
## makes a bare test scene usable and what lets a map be painted a room at a time.
const OPEN := NORTH | EAST | SOUTH | WEST

## Cell deltas, in the order the flags are numbered. North is -Z, matching "up" on the
## stick and the facing an actor spawns with.
const STEPS: Array[Vector3i] = [
	Vector3i(0, 0, -1),
	Vector3i(1, 0, 0),
	Vector3i(0, 0, 1),
	Vector3i(-1, 0, 0),
]


static func can_enter(ctx: MapContext, cell: Vector3i, actor: Actor) -> bool:
	if ctx == null:
		return true

	# A move onto a floor a flat map does not have is an authoring error, not a
	# silent no-op. supports_height() is how it surfaces.
	if cell.y != 0 and not ctx.supports_height:
		push_warning("Passability: cell %s has a non-zero Y on flat map '%s'." % [cell, ctx.map_id])
		return false

	# The actor's own cell is the origin. Taken from the actor rather than passed in
	# because every caller already asks "can *this actor* enter", and a directional rule
	# needs to know which side it would be crossing from.
	var from := actor.cell() if actor != null else cell
	if (actor == null or not actor.through_terrain) and not _terrain_allows(ctx, from, cell):
		return false

	if actor != null and not ctx.occupancy.is_free_for(cell, actor.actor_id):
		return false

	# Physics is terrain too, so an actor that walks through walls walks through the
	# colliders that represent them. Without this the escape hatch would quietly
	# re-impose what step 1 was just told to ignore.
	if actor != null and actor.through_terrain:
		return true

	# A map that declares a floor GridMap has said where its ground is, and said it
	# exactly. Asking physics to second-guess that does not add an escape hatch, it
	# takes one away: the floor slabs and the ramp and stair meshes are themselves
	# colliders, so a legitimate climb onto a ramp reads as walking into it.
	#
	# The cost is real and worth naming - a pushable crate or a swinging door on a
	# height map is not caught here, and has to be an actor in [Occupancy] instead of a
	# bare body. Step 2 is where such a thing belongs anyway; step 3 was always the
	# hatch for what nothing had modelled.
	if Terrain.governs(ctx):
		return true

	return not _physics_blocks(ctx, cell, actor)


## [method can_enter], for a whole footprint moving at once. [param from_cells] and
## [param to_cells] are parallel - [code]to_cells[i] == from_cells[i] + d[/code] for
## the step's own direction [code]d[/code] - so each pair is exactly the one-cell edge
## [method allows_step] already knows how to check; checking every pair rather than
## only the leading edge is redundant for a footprint's interior cells but correct by
## construction, and a footprint is small enough (2-4 cells) that the redundancy costs
## nothing worth avoiding.
##
## The physics escape hatch (step 3) is checked once, from [param to_cells][0] (the
## footprint's own anchor) rather than once per cell - a multi-shape physics query is a
## 3D-geometry concern the footprint pass does not attempt yet (see [Actor]'s own
## [member Actor.footprint] doc).
static func can_enter_footprint(ctx: MapContext, from_cells: Array[Vector3i],
		to_cells: Array[Vector3i], actor: Actor) -> bool:
	if ctx == null:
		return true

	for cell: Vector3i in to_cells:
		if cell.y != 0 and not ctx.supports_height:
			push_warning("Passability: cell %s has a non-zero Y on flat map '%s'." % [cell, ctx.map_id])
			return false

	if actor == null or not actor.through_terrain:
		for i in from_cells.size():
			if not _terrain_allows(ctx, from_cells[i], to_cells[i]):
				return false

	if actor != null and not ctx.occupancy.is_free_for_cells(to_cells, actor.actor_id):
		return false

	if actor != null and actor.through_terrain:
		return true

	if Terrain.governs(ctx):
		return true

	return not _physics_blocks(ctx, to_cells[0], actor)


## The sides of [param cell]'s own map/tile cell ([method MapContext.map_cell_of]) that
## may be crossed, as [constant NORTH] etc. combined.
##
## [param cell] is an actor-grid cell, not necessarily the map/tile cell painted -
## [method MapContext.map_cell_of] translates it first, which is the identity function
## (and this reads exactly the cell it is given) on every map that has never set
## [member MapContext.map_cell_size] to anything other than its own [member
## MapContext.cell_size].
##
## An unpainted cell is [constant OPEN]: no pathing layer, no tile in it, or a tile that
## carries no pathing data all read as open ground. Painting is therefore purely
## subtractive, and a half-painted map is walkable everywhere it has not been touched
## rather than walled off everywhere it has.
static func directions(ctx: MapContext, cell: Vector3i) -> int:
	if ctx == null or ctx.collision_node.is_empty():
		return OPEN
	var layer := ctx.get_node_or_null(ctx.collision_node) as TileMapLayer
	if layer == null:
		return OPEN

	var map_cell: Vector3i = ctx.map_cell_of(cell)
	var tile_data: TileData = layer.get_cell_tile_data(Space.as_v2i(map_cell))
	if tile_data == null:
		return OPEN
	var mask: Variant = tile_data.get_custom_data(DATA_PATHING)
	return OPEN if mask == null else int(mask)


## Is the one-cell step from [param from] to [param to] allowed by the paint?
##
## [b]Both cells have to agree, and that is the whole rule.[/b] The cell being left must
## permit crossing the side it is leaving by, and the cell being entered must permit
## crossing the side it is entered by - "the actor can move into the target cell, and the
## target cell can move into the actor's".
##
## What that buys is that [b]a boundary painted from either side holds[/b]. Painting the
## wall's own tile without its south flag blocks the step up into it even though the
## floor tile below was never touched, so a map can be walled by painting only the walls
## or only the floor, whichever is fewer tiles, and the two agree where they meet.
##
## The rule is therefore symmetric by construction: the same two flags are consulted in
## both directions, so this scheme cannot express a ledge you may drop off but not climb.
## [b]Height is what expresses that[/b], and only in 3D: [method Terrain.resolve_step]
## has no climb tolerance and a fall limit, so a ledge is a drop from above and a wall
## from below without anything being painted twice. A 2D map still cannot say it.
##
## A step that is not one cardinal cell - a diagonal, a teleport, a query about some
## distant cell - has no side to cross, so it only asks whether the destination is
## enterable at all. A cell painted with no flags is a wall.
##
## [b]Compares map cells, not the actor cells passed in.[/b] [param from]/[param to]
## are actor-grid cells; when [method MapContext.map_cell_of] puts both inside the
## same map cell, the step is entirely internal to one painted tile and the mask has
## nothing to say about it - allowed unconditionally. Only a step that actually
## crosses a map cell boundary reaches the flag check below, against that boundary's
## own two map cells. On a map with no [member MapContext.map_cell_size] of its own
## this is the identity translation, so [param from]/[param to] and their map cells
## are the same cells, exactly as before this existed.
static func allows_step(ctx: MapContext, from: Vector3i, to: Vector3i) -> bool:
	var map_from: Vector3i = ctx.map_cell_of(from)
	var map_to: Vector3i = ctx.map_cell_of(to)
	if map_from == map_to:
		return true

	var delta: Vector3i = map_to - map_from
	var dir := STEPS.find(delta)
	if dir < 0:
		return directions(ctx, to) != 0

	var out_flag := 1 << dir
	var back_flag := 1 << ((dir + 2) % 4)
	return (directions(ctx, from) & out_flag) != 0 \
		and (directions(ctx, to) & back_flag) != 0


## The cardinal directions [param dir] is heading in, as [constant NORTH] etc. combined.
##
## One cardinal for an axis-aligned direction, two for a diagonal, none for standing
## still. The flags do double duty - a side of a cell in [method allows_step], a heading
## here - because they are the same four directions and having them spelled twice is how
## the two drift apart.
static func cardinals(dir: Vector3) -> int:
	var mask := 0
	if dir.x > 0.0001:
		mask |= EAST
	elif dir.x < -0.0001:
		mask |= WEST
	if dir.z > 0.0001:
		mask |= SOUTH
	elif dir.z < -0.0001:
		mask |= NORTH
	return mask


## 1. Static terrain. The hand-painted pathing layer in 2D; the [GridMap]'s own cells in
## 3D. A map with no data layer is open ground.
##
## [b]An occupied cell of the 3D layer is a wall[/b], which is right because
## [member MapContext.collision_node] is the [i]wall[/i] layer. Ground is a different
## question with a different node - [member MapContext.floor_node], read by [Terrain] -
## so the two never have to disagree about what an occupied cell means. Pointing
## `collision_node` at a floor GridMap would still be backwards; point `floor_node` at it
## instead.
static func _terrain_allows(ctx: MapContext, from: Vector3i, to: Vector3i) -> bool:
	if ctx.collision_node.is_empty():
		return true
	var layer := ctx.get_node_or_null(ctx.collision_node)

	if layer is TileMapLayer:
		return allows_step(ctx, from, to)

	if layer is GridMap:
		return (layer as GridMap).get_cell_item(to) == GridMap.INVALID_CELL_ITEM

	return true


## 3. Physics, for anything neither tile data nor occupancy knows about.
static func _physics_blocks(ctx: MapContext, cell: Vector3i, actor: Actor) -> bool:
	if actor == null:
		return false
	var adapter := actor.adapter()
	if adapter == null:
		return false
	var from := adapter.world_position()
	return adapter.body_test_move(from, ctx.cell_centre(cell) - from)
