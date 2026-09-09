class_name Passability

## Can an actor enter a cell? Two sources of truth, both consulted, in cost order:
## static terrain, then occupancy, then physics as the escape hatch.
##
## Steps 1 and 2 are cheap lookups and reject most moves. Step 3 is what keeps
## physics-driven objects honest - a pushed crate, a door body, a temporary barrier -
## without making them author tile data. Free-movement actors skip 1 and 2 entirely
## and let physics do its job.

## Tile custom-data layer names read from a [TileMapLayer] or [GridMap]. Kept here so
## the strings are written once and the map author has one spelling to match.
const DATA_PASSABLE := "passable"
const DATA_HEIGHT := "height"


static func can_enter(ctx: MapContext, cell: Vector3i, actor: Actor) -> bool:
	if ctx == null:
		return true

	# A move onto a floor a flat map does not have is an authoring error, not a
	# silent no-op. supports_height() is how it surfaces.
	if cell.y != 0 and not ctx.supports_height:
		push_warning("Passability: cell %s has a non-zero Y on flat map '%s'." % [cell, ctx.map_id])
		return false

	if not _terrain_allows(ctx, cell):
		return false

	if actor != null and actor.solid and not ctx.occupancy.is_free_for(cell, actor.actor_id):
		return false

	return not _physics_blocks(ctx, cell, actor)


## 1. Static terrain. [TileMapLayer] custom data in 2D, [GridMap] cell metadata or a
## shape probe in 3D. A map with no data layer at all is open ground, which is what
## makes a bare test scene usable.
static func _terrain_allows(ctx: MapContext, cell: Vector3i) -> bool:
	if ctx.collision_node.is_empty():
		return true
	var layer := ctx.get_node_or_null(ctx.collision_node)

	if layer is TileMapLayer:
		var tile_data: TileData = (layer as TileMapLayer).get_cell_tile_data(Space.as_v2i(cell))
		if tile_data == null:
			return true
		var passable: Variant = tile_data.get_custom_data(DATA_PASSABLE)
		return true if passable == null else bool(passable)

	if layer is GridMap:
		return (layer as GridMap).get_cell_item(cell) == GridMap.INVALID_CELL_ITEM

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
