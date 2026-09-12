extends Node2D

## Game 1 MVP: 2D grid movement, 4-way, snap-and-tween, a real [TileMapLayer] with a
## [code]passable[/code] custom data layer so [Passability] step 1 runs against actual
## tile data rather than the open-ground fallback.
##
## The map, the actors, the camera and the HUD are all authored in
## [code]jrpg_demo.tscn[/code] - the floor and collision layers are painted with
## [code]jrpg_tiles.tres[/code], whose 32x32 sources are cut into 16x16 tiles so the
## decided 16 px per tile is used at native resolution and yields four variants of each.
## What is left here is behaviour: the pulse counter, the escape key, and the HUD text.
##
## Controls: WASD/arrows step, tap to turn in place, . wait a step, Esc back.

const TILE := 16

@onready var _player: Actor = $Actors/Player/Actor
@onready var _hud: Label = $HUD/Label

var _steps := 0


func _ready() -> void:
	EventBus.actor_stepped.connect(_on_stepped)


func _on_stepped(_id: StringName, _from: Vector3i, _to: Vector3i) -> void:
	_steps += 1


func _unhandled_input(event: InputEvent) -> void:
	if event.is_pressed() and not event.is_echo() and event.is_action("back"):
		DemoLauncher.back_to_menu(self)


func _process(_delta: float) -> void:
	var ctx := _player.context()
	if ctx == null:
		return
	_hud.text = "\n".join([
		"JRPG   cell %s   facing %s   %s" % [
			_player.cell(), _player.facing(),
			"stepping" if _player.is_moving() else "idle"],
		"pulses %d   occupied cells %d   tile %d px, 4-way" % [
			_steps, ctx.occupancy.size(), TILE],
		"WASD/arrows step, tap to turn   . wait   Esc back",
	])
