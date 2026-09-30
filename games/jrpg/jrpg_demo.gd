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
## What is left here is behaviour: the pathing overlay toggle and the escape key.
##
## The player and both NPCs are one prefab, [code]actor_jrpg.tscn[/code]. What makes
## the player the player is the [PlayerController] hanging off its [Actor]. Neither
## NPC has one: one stands there with nothing to drive it, and the other paces because
## a sibling [GameEvent] compiles and runs its page's own [code]route[/code]
## (event-pages.md §3, stage-c-plan.md segment 7).
##
## Collision is hand-painted, not derived from the art: the [code]Pathing[/code] layer
## carries one tile per cell saying which of its four sides may be crossed, and
## [Passability] asks both cells of every step. It starts empty, which reads as open
## ground everywhere - see [method Passability.directions].
##
## Controls: WASD/arrows step, Shift runs, X+direction turns in place, . wait a step,
## 1 pathing overlay, Esc back.

## Read externally by tests (reflection, [code]demo.get("_player")[/code]) as this
## demo's own "the player" accessor - every demo root exposes one, even where (as
## here, since the pathing-overlay toggle above is the only other thing this scene
## does) nothing inside this file itself still reads it.
@onready var _player: Actor = $Actors/Player/Actor
@onready var _pathing: TileMapLayer = $Pathing


## The pathing layer is hidden in a built game and shown here on demand: the arrows are
## how the map author reads back what was painted, and the only way to see a one-way
## side short of walking into it.
func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	# toggle_a (key 1) is this scene's own shortcut above, but the same key also
	# drives DebugFlags's own debug-category menu while it is open (~ to open) -
	# deferring to it here is what stops "toggle the actor-debug category" from also
	# flipping this scene's pathing overlay out from under it.
	if DebugFlags.is_menu_open():
		return
	if event.is_action("toggle_a"):
		_pathing.visible = not _pathing.visible
	elif event.is_action("back"):
		DemoLauncher.back_to_menu(self)
