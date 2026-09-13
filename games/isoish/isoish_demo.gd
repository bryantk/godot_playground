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
## The player is [code]actor_isoish.tscn[/code] with a [PlayerBrain] child - the same
## prefab an NPC here would use, minus that brain.
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
@onready var _view: SpriteView3D = $Upscale/World/Map/Actors/Player/Actor/View
@onready var _hud: Label = $HUD/Label


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


func _process(_delta: float) -> void:
	_hud.text = "\n".join([
		# roundi, not int: 16 * sin(30 deg) is 7.99999... in floating point, and
		# truncating it reports a 7 px tile for a pitch chosen precisely to give 8.
		"ISO-ISH   pitch %.2f  |  yaw stop %d of 4  |  tile %d x %d px" % [
			_rig.pitch_degrees, _rig.yaw_stop, _rig.texels_per_unit,
			roundi(_rig.floor_depth_px())],
		"facing %s  frame %d of 8   (sheet has 4, so a diagonal shows the nearer one)" % [
			_player.facing(), _view.frame_index()],
		"wall face %.3f px/unit   %s" % [
			_rig.wall_px_per_unit(),
			"walking" if _player.is_travelling() else "still"],
		"",
		"WASD move   Space jump   Shift run   Q/E rotate",
		"1 texel snap: %s   2 sub-texel smooth: %s   Esc back" % [
			"on" if _rig.quantise_camera else "OFF",
			"on" if _rig.subtexel_smoothing else "OFF"],
	])
