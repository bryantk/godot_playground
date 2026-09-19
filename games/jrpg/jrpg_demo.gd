extends Node2D

## Game 1 MVP: 2D grid movement, 4-way, snap-and-tween, over a map whose collision is
## painted rather than inferred from its art.
##
## The map, the actors, the camera and the HUD are all authored in
## [code]jrpg_demo.tscn[/code]. Two [TileMapLayer]s and no more: [code]Floor[/code] is
## the art, painted with [code]jrpg_tiles.tres[/code] whose 32x32 sources are cut into
## 16x16 tiles so the decided 16 px per tile is used at native resolution and yields four
## variants of each, and [code]Pathing[/code] is the data. There is no third layer for
## walls: a wall is a tile you painted no way into, so the art of one is just art.
## What is left here is behaviour: the pulse counter, the escape key, and the HUD text.
##
## The player and both NPCs are one prefab, [code]actor_jrpg.tscn[/code]. What makes
## one of them the player is the [Brain] hanging off its [Actor] - a [PlayerBrain]
## here, a [RouteBrain] pacing the NPC at the bottom of the map, and no brain at all on
## the other, which is why it stands there.
##
## Collision is hand-painted, not derived from the art: the [code]Pathing[/code] layer
## carries one tile per cell saying which of its four sides may be crossed, and
## [Passability] asks both cells of every step. It starts empty, which reads as open
## ground everywhere - see [method Passability.directions].
##
## Controls: WASD/arrows step, Shift runs, X+direction turns in place, . wait a step,
## 1 pathing overlay, Esc back.

const TILE := 16

@onready var _player: Actor = $Actors/Player/Actor
@onready var _pathing: TileMapLayer = $Pathing
@onready var _main_ui: MainUI = GameUI.main_ui

var _steps := 0


func _ready() -> void:
	EventBus.actor_stepped.connect(_on_stepped)


func _on_stepped(_id: StringName, _from: Vector3i, _to: Vector3i) -> void:
	_steps += 1


## The pathing layer is hidden in a built game and shown here on demand: the arrows are
## how the map author reads back what was painted, and the only way to see a one-way
## side short of walking into it.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("toggle_a"):
		_pathing.visible = not _pathing.visible
	elif event.is_action("back"):
		DemoLauncher.back_to_menu(self)


func _process(_delta: float) -> void:
	var ctx := _player.context()
	if ctx == null:
		return
	_main_ui.set_debug_text("\n".join([
		"JRPG   cell %s   facing %s   %s" % [
			_player.cell(), _player.facing(),
			"stepping" if _player.is_moving() else "idle"],
		"pulses %d   occupied cells %d   tile %d px, 4-way" % [
			_steps, ctx.occupancy.size(), TILE],
		"sides open here: %s" % _sides(ctx),
		"",
		"WASD/arrows step   Shift run   X+dir turn   . wait",
		"1 pathing overlay: %s   Esc back" % ["on" if _pathing.visible else "OFF"],
	]))


## The painted mask under the player, spelled out. Unpainted cells read as all four
## sides open, which is what an empty pathing layer means everywhere.
func _sides(ctx: MapContext) -> String:
	var mask := Passability.directions(ctx, _player.cell())
	var out := ""
	for i in 4:
		if (mask & (1 << i)) != 0:
			out += "NESW"[i]
	return out if out != "" else "none (walled in)"
