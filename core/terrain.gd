class_name Terrain

## What the ground is doing at a cell, for grid movement in 3D.
##
## [b]3D grid only.[/b] Everything here reads [member MapContext.floor_node], a [GridMap]
## of walkable cells, and a map that does not declare one gets the flat answer it has
## always had - a step stays on its own Y. [FreeMotion] never asks; it has real gravity
## already, and none of this may reach it.
##
## [b]The GridMap is the authority on levels; the mesh is the authority on looks.[/b] A
## cell's presence says where the ground is and its item name says what kind of ground,
## which keeps the passability answer exact and cheap. How far up a ramp's surface has
## risen by its centre is a presentation question and lives in [method surface_offset].
## The alternative - raycasting the mesh and inferring a level from where the ray landed -
## needs a continuity tolerance to tune and gives a fuzzy answer to a question that has a
## crisp one.
##
## [b]Kinds come from the mesh library item's name, direction from the cell's
## orientation.[/b] Godot 4's [MeshLibrary] has no custom-data table the way [TileSet]
## does, so the name is the available hook; the orientation is already in the GridMap
## editor's hands, which means one [code]ramp[/code] item rotated four ways is the whole
## authoring story rather than four items plus a convention to remember.

enum Kind {
	VOID,   ## Nothing here. Air, or off the map.
	FLOOR,  ## Flat ground. The surface is exactly the cell's own Y.
	RAMP,   ## Ground rising one cell across this cell, toward [method facing_of].
}

## Item-name prefixes. Matched with [method String.begins_with], so "ramp_stone" and
## "ramp" both read as a ramp and an author can name variants freely.
const NAME_RAMP := "ramp"
const NAME_STAIRS := "stairs"

## Matched on the [i]floor[/i] layer only, and only to rule the cell out - a ladder there
## is a mis-placed cell, not ground. Climbing reads [member MapContext.ladder_node]; see
## [method _kind_of_item].
const NAME_LADDER := "ladder"

## How far above its cell's own Y a ramp's surface sits at the cell centre, in cells.
##
## Half, because a ramp climbs exactly one cell across exactly one cell and the actor
## stands in the middle of it. This is the only number in this file the eye can see and
## the step rules cannot - a ramp's [i]logical[/i] cell is its lower end
## ([method resolve_step]), so without this the sprite would stand at the bottom of a
## slope it is visibly halfway up.
const RAMP_RISE := 0.5

## The direction a [code]ramp[/code] or [code]ladder[/code] item is modelled facing at
## orientation 0, so a rotated cell reads back as a world direction. North is -Z here as
## it is everywhere else - see [constant Passability.STEPS].
const MODELLED_FACING := Vector3(0, 0, -1)

const UP := Vector3i(0, 1, 0)


## The map's walkable-cell [GridMap], or null on a map that declares none - which is
## every 2D map and any 3D map that has not opted into height.
static func floor_map(ctx: MapContext) -> GridMap:
	if ctx == null or not ctx.supports_height or ctx.floor_node.is_empty():
		return null
	return ctx.get_node_or_null(ctx.floor_node) as GridMap


## Does this map answer height questions at all? Everything else here is meaningless
## when this is false, and every caller is expected to check it rather than rely on the
## flat answers the individual queries happen to return.
static func governs(ctx: MapContext) -> bool:
	return floor_map(ctx) != null


## The map's ladder [GridMap], or null. A separate layer from the floor, so a cell can
## carry ground and a ladder at once - see [member MapContext.ladder_node].
static func ladder_map(ctx: MapContext) -> GridMap:
	if ctx == null or not ctx.supports_height or ctx.ladder_node.is_empty():
		return null
	return ctx.get_node_or_null(ctx.ladder_node) as GridMap


static func kind_at(ctx: MapContext, cell: Vector3i) -> Kind:
	var gm := floor_map(ctx)
	if gm == null:
		return Kind.VOID
	var item := gm.get_cell_item(cell)
	if item == GridMap.INVALID_CELL_ITEM:
		return Kind.VOID
	return _kind_of_item(gm, item)


## [constant Kind.FLOOR] and [constant Kind.RAMP] are both ground: an actor may stand on
## them and step onto them from a neighbour at the same level.
static func is_ground(kind: Kind) -> bool:
	return kind == Kind.FLOOR or kind == Kind.RAMP


## Is there a ladder on this cell? Independent of what the ground is doing there - a
## ladder's foot usually sits on floor and its rungs usually hang in the air against a
## wall, and both are the same question to this.
static func has_ladder(ctx: MapContext, cell: Vector3i) -> bool:
	var gm := ladder_map(ctx)
	return gm != null and gm.get_cell_item(cell) != GridMap.INVALID_CELL_ITEM


## Which way a ladder is climbed: the direction [i]into[/i] the wall it is mounted on, so
## it is also the direction an actor presses to mount from the ground and to climb.
## Pressing away from it descends. See [method resolve_step].
static func ladder_facing(ctx: MapContext, cell: Vector3i) -> Vector3i:
	return _facing(ladder_map(ctx), cell)


## Which way a ramp rises, read from the cell's orientation in the floor GridMap.
static func facing_of(ctx: MapContext, cell: Vector3i) -> Vector3i:
	return _facing(floor_map(ctx), cell)


static func _facing(gm: GridMap, cell: Vector3i) -> Vector3i:
	if gm == null:
		return Vector3i.ZERO
	var ori := gm.get_cell_item_orientation(cell)
	if ori < 0:
		return Vector3i.ZERO
	return Space.quantise(gm.get_basis_with_orthogonal_index(ori) * MODELLED_FACING, 4)


## How far above [method MapContext.cell_centre] this cell's surface renders, in world
## units. Zero for everything except a ramp; see [constant RAMP_RISE].
static func surface_offset(ctx: MapContext, cell: Vector3i) -> float:
	if ctx == null or kind_at(ctx, cell) != Kind.RAMP:
		return 0.0
	return RAMP_RISE * ctx.cell_size.y


## Where one step in [param dir] from [param from] actually lands, and whether a fall
## follows it. The whole height rule set, in one place, so it can be tested without a
## body, a view or a frame.
##
## Returns [code]{ok, cell, fall, on_ladder}[/code]. [code]cell[/code] is where the step
## commits; [code]fall[/code] is how many cells the actor then drops, which
## [GridMotion] pays out one cell at a time (open-questions 37). [code]ok[/code] false
## means the step is refused and nothing else in the dictionary matters except
## [code]cell[/code], which names the cell that was refused so a bump can report it.
##
## [b]The rules, in the order they are tried:[/b]
## [codeblock]
## on a ladder   -> climb, descend, or dismount at either end
## off a ramp    -> up one, but only in the direction the ramp rises
## into a ladder -> mount it, but only from the side it is mounted on
## level ground  -> across, no change of Y
## onto a ramp   -> down one, onto the high edge of a ramp that rises back at us
## onto a ladder -> down one, onto the top rung, over the edge it is mounted against
## nothing there -> fall, if the floor below is within max_fall
## [/codeblock]
##
## [b]There is no climb tolerance[/b] (open-questions 36): the only way up is a ramp or a
## ladder, so a one-cell lip in a flat floor is a wall from below and a drop from above.
## That asymmetry is deliberate and is the thing 2D's painted mask could not express -
## see [method Passability.allows_step], which says so and points here.
static func resolve_step(ctx: MapContext, from: Vector3i, dir: Vector3i,
		max_fall: int) -> Dictionary:
	var ahead := from + dir

	if not governs(ctx) or dir == Vector3i.ZERO:
		return _step_to(ahead)

	# A ladder adds moves, it does not replace them. An actor at the foot of one is
	# standing on ordinary floor and may walk off in any direction; pressing into the
	# wall is the extra thing the ladder offers. Only an actor hanging on a rung - over
	# air, with nothing under it - is restricted to the ladder's own moves.
	if has_ladder(ctx, from):
		var climbed := _from_ladder(ctx, from, dir)
		if climbed["ok"] or not is_ground(kind_at(ctx, from)):
			return climbed

	# Off the top of a ramp. The ramp must rise the way we are walking, or this is just
	# a step across its face.
	if kind_at(ctx, from) == Kind.RAMP and facing_of(ctx, from) == dir \
			and is_ground(kind_at(ctx, ahead + UP)):
		return _step_to(ahead + UP)

	# Onto a ladder, from either end of the axis it is climbed.
	#
	# [b]Either end, not just the low one.[/b] Walking into a ladder from the ground below
	# goes the same way it is climbed; stepping onto it from the ledge above goes the
	# opposite way. Requiring the first only worked for a ladder whose top rung is tucked
	# one cell under the ledge - run the rungs up flush with the top surface, which is how
	# a ladder actually looks, and the step off the ledge matched no rule at all and the
	# actor fell past it.
	#
	# Perpendicular is still refused: you cannot walk onto the side of a ladder. And a
	# cell that is ground in its own right is left to the level step below, which arrives
	# there standing rather than hanging.
	if has_ladder(ctx, ahead) and not is_ground(kind_at(ctx, ahead)):
		var face := ladder_facing(ctx, ahead)
		if face == dir or face == -dir:
			return _step_to(ahead, 0, true)

	# Ground straight ahead wins over anything below it. Both rules under this one step
	# *down* into the next column, and an actor with somewhere to walk at its own level
	# should walk there - looking down first would turn a floor with a ramp tucked
	# beneath it into a trapdoor.
	if is_ground(kind_at(ctx, ahead)):
		return _step_to(ahead)

	var below := ahead - UP

	# Down onto the high edge of a ramp that rises back toward us.
	if kind_at(ctx, below) == Kind.RAMP and facing_of(ctx, below) == -dir:
		return _step_to(below)

	# Down onto the top rung of a ladder, over the edge it is mounted against. The exact
	# reverse of the dismount in [method _from_ladder], and it has to be: a player who
	# climbs out at the top and immediately turns around expects to get back on, and
	# without this the top rung is reachable only from the bottom of the ladder.
	if has_ladder(ctx, below) and ladder_facing(ctx, below) == -dir:
		return _step_to(below, 0, true)

	var drop := drop_below(ctx, ahead, max_fall)
	if drop > 0:
		return _step_to(ahead, drop)

	return {"ok": false, "cell": ahead, "fall": 0, "on_ladder": false}


## How many cells an actor standing at [param cell] would fall before landing, or 0 if
## there is ground within one cell of it already or nothing to land on inside
## [param max_fall].
##
## [b]Measured before anything commits[/b] (open-questions 37). A drop deeper than the
## limit has to refuse the step that starts it, and the only way to refuse a fall is to
## know its depth before leaving the cell you are standing on - discovering it halfway
## down leaves the actor in mid-air with nowhere legal to be.
static func drop_below(ctx: MapContext, cell: Vector3i, max_fall: int) -> int:
	if not governs(ctx) or max_fall <= 0:
		return 0
	for n in range(1, max_fall + 1):
		if is_ground(kind_at(ctx, cell - UP * n)):
			return n
	return 0


## A ladder is climbed by pressing into the wall and descended by pressing away from it,
## which is the whole control scheme - a 4-way grid game has no up and down to press.
##
## Both ends dismount rather than dead-ending: the top steps out over the edge onto the
## floor beside it, the bottom steps back off the way it was mounted. A ladder whose top
## has no floor beside it is an authoring error that reads in-game as a ladder you cannot
## leave, which is why open-questions 38 files it as a validator check.
static func _from_ladder(ctx: MapContext, from: Vector3i, dir: Vector3i) -> Dictionary:
	var climb := ladder_facing(ctx, from)

	if dir == climb:
		if has_ladder(ctx, from + UP):
			return _step_to(from + UP, 0, true)
		# Off the top, and the floor beside the last rung may be at either height: one
		# cell up if the rungs stop under the ledge, or level with it if they run up
		# flush with the top surface. Both are how someone would build it, so both
		# dismount rather than one being a ladder you cannot get off.
		if is_ground(kind_at(ctx, from + UP + dir)):
			return _step_to(from + UP + dir)
		if is_ground(kind_at(ctx, from + dir)):
			return _step_to(from + dir)
		return {"ok": false, "cell": from + UP, "fall": 0, "on_ladder": true}

	if dir == -climb:
		# Descending only when there is a rung below *and* nothing to stand on here.
		# At the foot of a ladder the actor is on floor, and stepping away from the
		# wall should walk away rather than burrow down the shaft.
		if has_ladder(ctx, from - UP) and not is_ground(kind_at(ctx, from)):
			return _step_to(from - UP, 0, true)
		# Off the bottom, at either height for the same reason as the top.
		if is_ground(kind_at(ctx, from + dir)):
			return _step_to(from + dir)
		if is_ground(kind_at(ctx, from - UP + dir)):
			return _step_to(from - UP + dir)
		return {"ok": false, "cell": from + dir, "fall": 0, "on_ladder": true}

	# Sideways off a ladder is not a move. Letting go is, and that is `jump`.
	return {"ok": false, "cell": from + dir, "fall": 0, "on_ladder": true}


## How far letting go of a ladder drops the actor. [member MapContext.max_fall_cells]
## does not apply (open-questions 38): the limit exists so a player does not walk off a
## lethal ledge by accident, and releasing a ladder is not an accident.
##
## [b]It slides down the rungs first, then keeps falling.[/b] A ladder cell is not ground
## ([method is_ground]), so a plain downward search for ground would pass straight
## through the column's own lower rungs and report the empty air under them - releasing
## the second rung of a two-rung ladder would find nothing to land on and the actor would
## not move at all. Letting go lands you at the foot of the ladder, and only past that
## does open air below it count.
static func drop_from_ladder(ctx: MapContext, cell: Vector3i) -> int:
	if not governs(ctx):
		return 0

	var rungs := 0
	while has_ladder(ctx, cell - UP * (rungs + 1)) \
			and not is_ground(kind_at(ctx, cell - UP * rungs)):
		rungs += 1

	# Standing on the foot is standing on the ground: there is nowhere further to go, and
	# asking drop_below would only walk the empty column under the map.
	var foot := cell - UP * rungs
	if is_ground(kind_at(ctx, foot)):
		return rungs

	# Bounded only so a column with no bottom terminates. A map deeper than this has a
	# missing floor, not a long fall.
	return rungs + drop_below(ctx, foot, 1024)


static func _kind_of_item(gm: GridMap, item: int) -> Kind:
	var lib := gm.mesh_library
	if lib == null:
		return Kind.FLOOR
	var item_name := lib.get_item_name(item)
	if item_name.begins_with(NAME_RAMP) or item_name.begins_with(NAME_STAIRS):
		return Kind.RAMP

	# [b]A ladder painted into the floor layer is not floor.[/b] It belongs on
	# [member MapContext.ladder_node] and the cell here is almost always a leftover from
	# before that layer existed - but "anything not a ramp is ground" turned that leftover
	# into an invisible platform, which is worse than ignoring it in a specific way:
	# the rung read as solid, so the guard that keeps an actor hanging on a ladder from
	# stepping sideways stopped applying, and pressing a perpendicular direction walked
	# the actor off the rung into open air and fell.
	#
	# VOID rather than a warning because this is a hot path, and because VOID is the
	# truth: there is no ground there. A validator is the place to say so out loud.
	if item_name.begins_with(NAME_LADDER):
		return Kind.VOID

	return Kind.FLOOR


static func _step_to(cell: Vector3i, fall: int = 0, on_ladder: bool = false) -> Dictionary:
	return {"ok": true, "cell": cell, "fall": fall, "on_ladder": on_ladder}
