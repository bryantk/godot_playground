class_name FadeOverlay extends ColorRect

## The one full-screen fade rig every fade-driven command shares - [code]fade[/code],
## [code]fade_in[/code], [code]fade_out[/code] (events/commands/presentation_execs.gd)
## and [code]change_map[/code]/[code]change_map_marker[/code]'s own optional fade legs
## (events/commands/map_execs.gd). Owned by [code]GameUI[/code] (core/game_ui.gd), the
## one autoloaded [CanvasLayer] this project already has, so the overlay survives a
## [code]change_map[/code]'s own [method SceneTree.change_scene_to_file] untouched.
##
## [b]A dissolve, not a cross-fade[/b]: [member fade_overlay.gdshader]'s own doc explains
## the mechanic. [param texture] is that shader's mask - a plain black-to-white
## [GradientTexture2D], built once and reused, when a command gives none of its own.
##
## [b]Never awaited on[/b] (event_command_exec.gd's "commands never await" rule) - a
## [Tween] does the work and [method is_fading] is the polling half every executor's
## own [method EventCommandExec.tick] reads instead.

const _SHADER := preload("res://code/world/fade_overlay.gdshader")

var _tween: Tween = null
var _material: ShaderMaterial = null
var _default_mask: GradientTexture2D = null


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	color = Color(0, 0, 0, 0)

	_material = ShaderMaterial.new()
	_material.shader = _SHADER
	material = _material
	_material.set_shader_parameter("mask", _default_mask_texture())
	_material.set_shader_parameter("reveal", 1.0)
	_material.set_shader_parameter("fade_color", Color.BLACK)


func _default_mask_texture() -> GradientTexture2D:
	if _default_mask == null:
		var gradient := Gradient.new()
		gradient.colors = PackedColorArray([Color.BLACK, Color.WHITE])
		_default_mask = GradientTexture2D.new()
		_default_mask.gradient = gradient
		_default_mask.width = 256
		_default_mask.height = 1
	return _default_mask


## Tweens toward [param reveal] (0 = fully covered, 1 = fully clear) over [param
## seconds], through [param texture] (the default grayscale gradient when null),
## replacing whatever fade is already in flight. [param seconds] of 0 or less snaps
## instantly - the "or instant" half of a map transfer's own fade option.
func start(reveal: float, seconds: float, texture: Texture2D = null) -> void:
	_material.set_shader_parameter("mask", texture if texture != null else _default_mask_texture())

	if _tween != null and _tween.is_valid():
		_tween.kill()

	if seconds <= 0.0:
		_material.set_shader_parameter("reveal", reveal)
		_tween = null
		return

	var from: float = _material.get_shader_parameter("reveal")
	_tween = create_tween()
	_tween.tween_method(_set_reveal, from, reveal, seconds)


func _set_reveal(value: float) -> void:
	_material.set_shader_parameter("reveal", value)


func is_fading() -> bool:
	return _tween != null and _tween.is_valid()
