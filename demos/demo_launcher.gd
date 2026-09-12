class_name DemoLauncher extends Control

## Picks one of the presentation demos.
##
## This is a development convenience, not the shipping arrangement: each game ships as
## its own executable with one profile compiled in, selected by a feature-tagged
## [code]run/main_scene[/code] override rather than by a menu. Being able to see them
## side by side is worth a launcher while the spine is being built.
##
## Two games, three demos: the third crosses game 2's presentation with game 1's motion,
## which is the axis split of architecture.md being exercised rather than asserted.
##
## The buttons live in [code]demo_launcher.tscn[/code], each carrying its target scene
## as metadata - so adding a demo is adding a button and dragging a scene onto it, with
## nothing here to edit. Number keys follow button order.

const MENU := "res://demos/demo_launcher.tscn"

## Where the buttons live. Anything in here carrying a [code]scene[/code] metadata entry
## becomes a demo, in tree order.
@export var button_container: NodePath = ^"Margin/Column"


static func back_to_menu(from: Node) -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	ModeStack.reset()
	from.get_tree().change_scene_to_file(MENU)


func _ready() -> void:
	for button in _buttons():
		button.pressed.connect(_open.bind(button.get_meta("scene") as PackedScene))


func _buttons() -> Array[Button]:
	var out: Array[Button] = []
	var host := get_node_or_null(button_container)
	if host == null:
		push_error("DemoLauncher: no button container at '%s'." % button_container)
		return out
	for child in host.get_children():
		if child is Button and child.has_meta("scene"):
			out.append(child as Button)
	return out


func _open(scene: PackedScene) -> void:
	if scene == null:
		push_error("DemoLauncher: a button has no scene in its metadata.")
		return
	get_tree().change_scene_to_packed(scene)


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var buttons := _buttons()
	for i in buttons.size():
		if i < 3 and event.is_action("toggle_%s" % ["a", "b", "c"][i]):
			_open(buttons[i].get_meta("scene") as PackedScene)
			return
	if event.is_action("quit"):
		get_tree().quit()
