extends Node3D

## Game 3 MVP: full 3D, free movement, jumping, player-driven orbit camera.
##
## Deliberately the thinnest of the three. Game 3 is the same runtime as game 2 with
## the simpler presentation, so if the shared spine is right this costs almost nothing
## to stand up - which is exactly what makes it the cheapest test of whether it is.
## The same textures are used at full resolution with filtering, since nothing here is
## pixel art.
##
## Controls: WASD move, Space jump, Shift run, mouse look, 1 release mouse, Esc back.

const GRID: Array[String] = [
	"XXXXXXXXXXXXXXXXXXXX",
	"X..................X",
	"X...##....X........X",
	"X...##....X....##..X",
	"X.........X....##..X",
	"X..XX.....X........X",
	"X..XX........####..X",
	"X..................X",
	"X....##...X........X",
	"X....##...X...XX...X",
	"X.........X...XX...X",
	"X........###.......X",
	"X..................X",
	"XXXXXXXXXXXXXXXXXXXX",
]

var _player: Actor = null
var _rig: OrbitRig = null
var _hud: Label = null
var _captured := true


func _ready() -> void:
	var profile: GameProfile = load("res://games/action/action.tres")
	_build(profile)
	_capture(true)


func _build(profile: GameProfile) -> void:
	var ctx := MapContext.new()
	ctx.name = "MapContext"
	ctx.map_id = &"action_demo"
	ctx.cell_size = profile.default_cell_size
	ctx.supports_height = true
	ctx.default_motion = Actor.MotionMode.FREE
	add_child(ctx)

	var opts := PixelLevel.Opts.new()
	opts.floor_texture = load("res://art/test_floor_tile.png")
	opts.wall_texture = load("res://art/test_wall_tile.png")
	# Same density both ways: there is no projection to pre-compensate for when the
	# camera is free, so the 14-texel correction would just distort the texture.
	opts.texels_per_unit = 16
	opts.texels_per_unit_vertical = 16
	opts.collision = true

	var level := Node3D.new()
	level.name = "Level"
	add_child(level)
	PixelLevel.build(level, GRID, opts)

	# Light it, since this is the one demo that is not unshaded.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.rotation = Vector3(deg_to_rad(-50.0), deg_to_rad(35.0), 0.0)
	sun.light_energy = 1.1
	add_child(sun)

	var env := WorldEnvironment.new()
	var e := Environment.new()
	e.background_mode = Environment.BG_COLOR
	e.background_color = Color(0.10, 0.12, 0.16)
	e.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	e.ambient_light_color = Color(0.4, 0.45, 0.55)
	e.ambient_light_energy = 0.6
	env.environment = e
	add_child(env)

	# -- Player --------------------------------------------------------------
	var body := CharacterBody3D.new()
	body.name = "Player"
	body.position = Vector3(7.5, 0.0, 7.5)
	var shape := CollisionShape3D.new()
	var capsule := CapsuleShape3D.new()
	capsule.radius = 0.35
	capsule.height = 1.6
	shape.shape = capsule
	shape.position = Vector3(0.0, 0.8, 0.0)
	body.add_child(shape)
	add_child(body)

	_player = Actor.new()
	_player.name = "Actor"
	_player.actor_id = &"player"
	_player.solid = false
	_player.motion_mode = Actor.MotionMode.FREE
	body.add_child(_player)

	var adapter := Space3D.new()
	adapter.name = "Space"
	_player.add_child(adapter)

	var motion := FreeMotion.new()
	motion.name = "Motion"
	motion.speed = 5.0
	motion.direction_count = 0    # fully analog
	motion.jump_strength = 7.0
	motion.gravity = 22.0
	_player.add_child(motion)

	# MeshView3D rotates the model to its true continuous heading, so no direction
	# count ever applied to game 3.
	var view := MeshView3D.new()
	view.name = "View"
	view.turn_speed = 14.0
	_player.add_child(view)

	var mesh := MeshInstance3D.new()
	mesh.name = "Body"
	var caps := CapsuleMesh.new()
	caps.radius = 0.35
	caps.height = 1.6
	mesh.mesh = caps
	mesh.position = Vector3(0.0, 0.8, 0.0)
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.85, 0.35, 0.35)
	mesh.material_override = mat
	body.add_child(mesh)

	# A nose, so the continuous heading is actually visible on a capsule.
	var nose := MeshInstance3D.new()
	nose.name = "Nose"
	var box := BoxMesh.new()
	box.size = Vector3(0.16, 0.16, 0.4)
	nose.mesh = box
	nose.position = Vector3(0.0, 0.3, 0.28)
	var nose_mat := StandardMaterial3D.new()
	nose_mat.albedo_color = Color(0.95, 0.85, 0.4)
	nose.material_override = nose_mat
	mesh.add_child(nose)
	view.bind_visual(mesh)

	# -- Camera --------------------------------------------------------------
	var arm := SpringArm3D.new()
	arm.name = "Arm"
	arm.spring_length = 5.0
	arm.position = Vector3(7.5, 1.2, 7.5)
	add_child(arm)

	var cam := Camera3D.new()
	cam.name = "Camera"
	arm.add_child(cam)

	_rig = OrbitRig.new()
	_rig.name = "Rig"
	_rig.arm_length = 5.0
	arm.add_child(_rig)
	_rig.follow(&"player")

	var driver := InputDriver.new()
	driver.name = "Input"
	driver.actor_id = &"player"
	driver.profile = profile.input_profile
	driver.camera_rig = _rig
	add_child(driver)

	var layer := CanvasLayer.new()
	layer.name = "HUD"
	add_child(layer)
	_hud = Label.new()
	_hud.position = Vector2(8, 6)
	_hud.add_theme_font_size_override("font_size", 12)
	_hud.add_theme_color_override("font_color", Color(1, 1, 1))
	_hud.add_theme_color_override("font_outline_color", Color(0, 0, 0))
	_hud.add_theme_constant_override("outline_size", 4)
	layer.add_child(_hud)


func _capture(on: bool) -> void:
	_captured = on
	Input.mouse_mode = Input.MOUSE_MODE_CAPTURED if on else Input.MOUSE_MODE_VISIBLE


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseMotion and _captured:
		var motion := event as InputEventMouseMotion
		# The rig consumes a look delta; sensitivity and clamping are its business.
		_rig.look(motion.relative * 0.06, 1.0 / 60.0)
		return

	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action("toggle_a"):
		_capture(not _captured)
	elif event.is_action("back"):
		_capture(false)
		DemoLauncher.back_to_menu(self)


func _process(_delta: float) -> void:
	if _player == null:
		return
	_hud.text = "\n".join([
		"ACTION   cell %s   yaw %.1f deg   analog movement" % [
			_player.cell(), rad_to_deg(_rig.yaw())],
		"the cell is computed on demand purely so events can address a free actor",
		"WASD move   Space jump   Shift run   mouse look   1 release mouse   Esc back",
	])
