extends Node

## The two axes, crossed: game 2's presentation with game 1's motion.
##
## Same [Space3D], same [OrthoPixelRig] at pitch 30, same billboarded [SpriteView3D] -
## but the actors step cell to cell instead of moving continuously. This is the
## "3D town, ortho cam, tile steps" square of architecture.md's matrix, and the point of
## building it is that it costs a different [MapContext.default_motion] and a different
## controller child, with nothing above the actor layer touched.
##
## The map is authored in [code]isoish_grid_demo.tscn[/code]. Two [GridMap]s: Floor is
## decoration, Blocks is both the walls and the terrain data [Passability] reads, which
## is why [MapContext.collision_node] points at it. Every actor on it - the player and
## both NPCs - is [code]actor_isoish_grid.tscn[/code], whose [Actor] is left on
## [code]INHERIT[/code] so the map's [code]default_motion[/code] is what decides - the
## precedence rule that keeps "grid movement in a 3D town" possible.
##
## What separates the three: the player carries a [PlayerController]. Neither NPC has
## one - the one standing in the doorway simply has nothing driving it, and the guard
## north of the wall paces because a sibling [GameEvent] compiles and runs its page's
## own [code]route[/code] (event-pages.md §3, stage-c-plan.md segment 7) instead of
## the [code]RouteBrain[/code] this scene used to carry.
##
## Controls: WASD/arrows step, X+direction turns in place, Shift runs, Q/E rotate the view,
## 1 4-way/8-way, 2 sub-texel smoothing, 3 terrain data on/off, Esc back.

@onready var _rig: OrthoPixelRig = $Upscale/World/Map/Camera/Rig
@onready var _ctx: MapContext = $Upscale/World/Map/MapContext
@onready var _blocks: GridMap = $Upscale/World/Map/Blocks
@onready var _player_controller: PlayerController = $Upscale/World/Map/Actors/Player/Actor/PlayerController
@onready var _player: Actor = $Upscale/World/Map/Actors/Player/Actor
@onready var _motion: GridMotion = $Upscale/World/Map/Actors/Player/Actor/Motion

var _terrain_data := true


func _ready() -> void:
	_rig.yaw_changed.connect(_on_yaw_changed)


func _on_yaw_changed(yaw: float) -> void:
	# Every sprite in the map re-picks its frame; nothing else about the world cares
	# that the view rotated, and in particular no cell changes.
	for who: Actor in _ctx.actors():
		var v := who.view()
		if v is SpriteView3D:
			(v as SpriteView3D).set_camera_yaw(yaw)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	# toggle_a/b/c (keys 1/2/3) are this scene's own cycling shortcuts below, but the
	# same three keys also drive DebugFlags's own debug-category menu while it is open
	# (~ to open) - deferring to it here is what stops "toggle the actor-debug
	# category" from also flipping this scene's direction count out from under it.
	if DebugFlags.is_menu_open():
		return

	if event.is_action("yaw_ccw"):
		_rig.rotate_by_stops(-1)
	elif event.is_action("yaw_cw"):
		_rig.rotate_by_stops(1)
	elif event.is_action("toggle_a"):
		_cycle_directions()
	elif event.is_action("toggle_b"):
		_rig.subtexel_smoothing = not _rig.subtexel_smoothing
	elif event.is_action("toggle_c"):
		_cycle_terrain_data()
	elif event.is_action("back"):
		DemoLauncher.back_to_menu(self)


## 4-way is game 1's rule; 8-way is what a grid game in an iso view can afford, since a
## diagonal reads as a diagonal here rather than as a stair. Both are exact against the
## four yaw stops, so the sprite always has a frame.
##
## The profile resource is marked local to scene, so this edits this map's copy rather
## than the file every other map would load.
func _cycle_directions() -> void:
	var count := 8 if _motion.direction_count == 4 else 4
	_motion.direction_count = count
	_player.facing_count = count
	_player_controller.profile.direction_count = count


## Turning the terrain layer off leaves occupancy and physics still consulted, which is
## the "both sources, together" rule made visible: the walls keep blocking, via
## test_move against the GridMap's own collision instead of via its cell data.
func _cycle_terrain_data() -> void:
	_terrain_data = not _terrain_data
	_ctx.collision_node = _ctx.get_path_to(_blocks) if _terrain_data else NodePath()
