extends Node

## Writes the two [GameProfile] resources. Run rather than hand-authored, so the
## typed enum arrays and script references serialise exactly as Godot expects:
##
##     godot --headless --path . res://tools/make_profiles.tscn
##
## Each game ships as its own executable with one profile compiled in, so these are
## two separate declarations rather than two branches of one.

const OUT := {
	"jrpg": "res://games/jrpg/jrpg.tres",
	"isoish": "res://games/isoish/isoish.tres",
}


func _ready() -> void:
	var failed := 0
	failed += _write(_jrpg(), OUT["jrpg"])
	failed += _write(_isoish(), OUT["isoish"])
	get_tree().quit(failed)


func _jrpg() -> GameProfile:
	var p := GameProfile.new()
	p.id = &"jrpg"
	p.display_name = "JRPG"
	p.capabilities = [
		GameProfile.Capability.GRID_MOTION,
		GameProfile.Capability.PATHFINDER,
		GameProfile.Capability.BATTLE_SCENE,
	]
	p.modes = [&"field", &"cutscene", &"battle", &"menu"]
	# Pixels. A 2D map's cells are pixels and a 3D map's are metres; nothing compares
	# a distance across maps, so the two never have to agree.
	p.default_cell_size = Vector3(16, 0, 16)
	p.texels_per_unit = 16
	p.texels_per_unit_vertical = 16
	p.space_script = Space2D
	p.motion_script = GridMotion
	p.view_script = SpriteView2D
	p.camera_script = RoomCamera2D
	p.input_profile = _make_input(4, false, "res://games/jrpg/jrpg_input.tres")
	return p


func _isoish() -> GameProfile:
	var p := GameProfile.new()
	p.id = &"isoish"
	p.display_name = "Iso-ish"
	p.capabilities = [
		GameProfile.Capability.FREE_MOTION,
		GameProfile.Capability.HEIGHT,
		GameProfile.Capability.ROTATABLE_VIEW,
	]
	p.modes = [&"field", &"cutscene", &"menu"]
	p.default_cell_size = Vector3.ONE
	p.texels_per_unit = 16
	# At pitch 30 a vertical face is 13.856 px per world unit, so art authored at 16
	# loses ~14% of its rows unevenly. 14 maps to a 1% squash instead.
	p.texels_per_unit_vertical = 14
	p.space_script = Space3D
	p.motion_script = FreeMotion
	p.view_script = SpriteView3D
	p.camera_script = OrthoPixelRig
	# 8 facings, and view-relative because the camera rotates - the moment it does,
	# "up" on the stick is no longer -Z.
	p.input_profile = _make_input(8, true, "res://games/isoish/isoish_input.tres")
	return p


## Written as its own file rather than embedded in the profile, so a map scene can point
## a [PlayerController] at the same resource the profile uses. A sub-resource inside a .tres
## has no path and cannot be referenced from anywhere else, which would have meant the
## scenes carrying a second copy of the same numbers.
func _make_input(directions: int, view_relative: bool, path: String) -> InputProfile:
	var ip := InputProfile.new()
	ip.direction_count = directions
	ip.view_relative = view_relative
	var err := ResourceSaver.save(ip, path)
	if err != OK:
		printerr("failed to write %s (%d)" % [path, err])
		return ip
	print("wrote %s" % path)
	return load(path)


func _write(profile: GameProfile, path: String) -> int:
	var err := ResourceSaver.save(profile, path)
	if err != OK:
		printerr("failed to write %s (%d)" % [path, err])
		return 1
	print("wrote %s" % path)
	return 0
