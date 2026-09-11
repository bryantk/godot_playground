class_name DemoLauncher extends Control

## Picks one of the two presentation demos.
##
## This is a development convenience, not the shipping arrangement: each game ships as
## its own executable with one profile compiled in, selected by a feature-tagged
## [code]run/main_scene[/code] override rather than by a menu. Being able to see the
## two side by side is worth a launcher while the spine is being built.

const DEMOS := [
	{
		"key": "1",
		"title": "JRPG",
		"blurb": "2D grid, 4-way, snap-and-tween, real tile passability",
		"scene": "res://games/jrpg/jrpg_demo.tscn",
	},
	{
		"key": "2",
		"title": "Iso-ish",
		"blurb": "pixel-perfect ortho 3D, pitch 30, 4 yaw stops, 8 facings",
		"scene": "res://games/isoish/isoish_demo.tscn",
	},
]

const MENU := "res://demos/demo_launcher.tscn"


static func back_to_menu(from: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ModeStack.reset()
	from.get_tree().change_scene_to_file(MENU)


func _ready() -> void:
	set_anchors_preset(Control.PRESET_FULL_RECT)

	var bg := ColorRect.new()
	bg.color = Color(0.07, 0.08, 0.10)
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)

	var margin := MarginContainer.new()
	margin.set_anchors_preset(Control.PRESET_FULL_RECT)
	margin.add_theme_constant_override("margin_left", 24)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 24)
	margin.add_theme_constant_override("margin_bottom", 20)
	add_child(margin)

	var col := VBoxContainer.new()
	col.add_theme_constant_override("separation", 10)
	margin.add_child(col)

	col.add_child(_label("2026Dev - presentation demos", 16, Color(1, 1, 1)))
	col.add_child(_label("one shared spine, two presentations", 10, Color(0.6, 0.66, 0.72)))

	for demo: Dictionary in DEMOS:
		var button := Button.new()
		button.text = "%s.  %s" % [demo["key"], demo["title"]]
		button.tooltip_text = demo["blurb"]
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.pressed.connect(_open.bind(str(demo["scene"])))
		col.add_child(button)
		col.add_child(_label("     " + str(demo["blurb"]), 9, Color(0.55, 0.6, 0.66)))

	col.add_child(_label("press 1 or 2 - Esc returns here from any demo", 9,
		Color(0.5, 0.55, 0.6)))


func _label(text: String, size: int, colour: Color) -> Label:
	var l := Label.new()
	l.text = text
	l.add_theme_font_size_override("font_size", size)
	l.add_theme_color_override("font_color", colour)
	return l


func _open(scene: String) -> void:
	if not ResourceLoader.exists(scene):
		push_error("DemoLauncher: %s is missing." % scene)
		return
	get_tree().change_scene_to_file(scene)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	for i in DEMOS.size():
		var action := "toggle_%s" % ["a", "b", "c"][i]
		if event.is_action(action):
			_open(str(DEMOS[i]["scene"]))
			return
	if event.is_action("quit"):
		get_tree().quit()
