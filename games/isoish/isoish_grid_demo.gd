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
## What separates the three is the [Brain] child each placement carries: a [PlayerBrain]
## on the player, a [RouteBrain] pacing the guard north of the wall, and nothing at all
## on the one standing in the doorway.
##
## Controls: WASD/arrows step, Shift+direction turns in place, Q/E rotate the view,
## 1 4-way/8-way, 2 sub-texel smoothing, 3 terrain data on/off, Esc back.

@onready var _rig: OrthoPixelRig = $Upscale/World/Map/Camera/Rig
@onready var _ctx: MapContext = $Upscale/World/Map/MapContext
@onready var _blocks: GridMap = $Upscale/World/Map/Blocks
@onready var _brain: PlayerBrain = $Upscale/World/Map/Actors/Player/Actor/Brain
@onready var _player: Actor = $Upscale/World/Map/Actors/Player/Actor
@onready var _view: SpriteView3D = $Upscale/World/Map/Actors/Player/Actor/View
@onready var _motion: GridMotion = $Upscale/World/Map/Actors/Player/Actor/Motion
@onready var _hud: Label = $HUD/Label

var _terrain_data := true
var _steps := 0


func _ready() -> void:
	_rig.yaw_changed.connect(_on_yaw_changed)
	EventBus.actor_stepped.connect(_on_stepped)


func _on_yaw_changed(yaw: float) -> void:
	# Every sprite in the map re-picks its frame; nothing else about the world cares
	# that the view rotated, and in particular no cell changes.
	for who: Actor in _ctx.actors():
		var v := who.view()
		if v is SpriteView3D:
			(v as SpriteView3D).set_camera_yaw(yaw)


func _on_stepped(_id: StringName, _from: Vector3i, _to: Vector3i) -> void:
	_steps += 1


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
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
	_brain.profile.direction_count = count


## Turning the terrain layer off leaves occupancy and physics still consulted, which is
## the "both sources, together" rule made visible: the walls keep blocking, via
## test_move against the GridMap's own collision instead of via its cell data.
func _cycle_terrain_data() -> void:
	_terrain_data = not _terrain_data
	_ctx.collision_node = _ctx.get_path_to(_blocks) if _terrain_data else NodePath()


func _process(_delta: float) -> void:
	_hud.text = "\n".join([
		"ISO-ISH + GRID   cell %s   facing %s   %s" % [
			_player.cell(), _player.facing(),
			"stepping" if _player.is_moving() else "idle"],
		"yaw stop %d of 4   frame %d of 8   steps %d   occupied cells %d" % [
			_rig.yaw_stop, _view.frame_index(), _steps, _ctx.occupancy.size()],
		"%d-way   step %.0f ms   terrain data %s (occupancy and physics always on)" % [
			_motion.direction_count, _motion.step_duration() * 1000.0,
			"on" if _terrain_data else "OFF"],
		"",
		"WASD/arrows step   Shift+dir turn   Q/E rotate the view",
		"1 %d-way   2 sub-texel smooth: %s   3 terrain data: %s   Esc back" % [
			8 if _motion.direction_count == 4 else 4,
			"on" if _rig.subtexel_smoothing else "OFF",
			"on" if _terrain_data else "OFF"],
	])
