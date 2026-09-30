extends Node

## Game 2 MVP: pixel-perfect orthographic 3D, pitch 30, four 90-degree yaw stops,
## billboarded sprite with 8 facings, free movement with jumping.
##
## Everything constructible is authored in [code]isoish_demo.tscn[/code]: the low-res
## [SubViewport] and its upscale, the level as two [GridMap]s painted from
## [code]pixel_blocks.tres[/code], the player, the camera rig and the HUD. The numbers
## that matter - texel density, ortho pitch, per-face UV scale - are properties on those
## nodes and on that mesh library rather than constants in here.
##
## The player is [code]actor_isoish.tscn[/code] with a [PlayerController] child - the
## same prefab an NPC here would use, minus that controller.
##
## Vertical faces are authored at 14 texels per world unit rather than 16, because at
## pitch 30 a face is 13.856 px per unit and art drawn at 16 loses about one row in
## seven. That now lives in the block materials inside [code]pixel_blocks.tres[/code],
## where it can be seen and changed, instead of being a runtime toggle.
##
## Controls: WASD move, Space jump, Shift run, Q/E rotate the view,
## 1 camera texel snap, 2 sub-texel smoothing, Esc back.

@onready var _rig: OrthoPixelRig = $Upscale/World/Map/Camera/Rig
@onready var _player: Actor = $Upscale/World/Map/Actors/Player/Actor


func _ready() -> void:
	_rig.yaw_changed.connect(_on_yaw_changed)


func _on_yaw_changed(yaw: float) -> void:
	# Every sprite re-picks its frame on a yaw change; nothing else about the world
	# cares that the view rotated.
	var ctx := _player.context()
	if ctx == null:
		return
	for who: Actor in ctx.actors():
		var v := who.view()
		if v is SpriteView3D:
			(v as SpriteView3D).set_camera_yaw(yaw)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	# toggle_a/b (keys 1/2) are this scene's own cycling shortcuts below, but the same
	# keys also drive DebugFlags's own debug-category menu while it is open (~ to
	# open) - deferring to it here is what stops "toggle the actor-debug category"
	# from also flipping this scene's camera snap out from under it.
	if DebugFlags.is_menu_open():
		return

	if event.is_action("yaw_ccw"):
		_rig.rotate_by_stops(-1)
	elif event.is_action("yaw_cw"):
		_rig.rotate_by_stops(1)
	elif event.is_action("toggle_a"):
		_rig.quantise_camera = not _rig.quantise_camera
	elif event.is_action("toggle_b"):
		_rig.subtexel_smoothing = not _rig.subtexel_smoothing
	elif event.is_action("back"):
		DemoLauncher.back_to_menu(self)
