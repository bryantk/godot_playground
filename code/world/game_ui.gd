extends CanvasLayer

## The one [MainUI] instance for the whole game - dialogue, pause menu, debug readout -
## autoloaded as [code]GameUI[/code] so it exists before any demo scene loads and
## survives switching between them, instead of every demo scene carrying its own copy.
##
## A [CanvasLayer] rather than a bare [Node] parent: an autoload is added to the root
## viewport ahead of whatever scene [code]run/main_scene[/code] points at, so a plain
## sibling [Control] would draw *underneath* that scene's own canvas items. Godot sorts
## [CanvasLayer]s by [member CanvasLayer.layer] independent of tree order, and the
## default layer (1) already sits above the base layer (0) every map scene draws on -
## the same reason [code]jrpg_demo.tscn[/code] wrapped its own, now-removed, MainUI in a
## CanvasLayer.
##
## Hidden whenever no map is loaded - the demo launcher, most obviously - since the
## dialogue box and debug readout have nothing to say about a screen with no
## [MapContext] on it.

const MAIN_UI_SCENE := preload("res://code/ui/text_box/main_ui.tscn")

var main_ui: MainUI

## The shared screen-fade rig - see [FadeOverlay]'s own doc. Added after [member
## main_ui] so it draws on top: a map transfer's fade-out must cover the dialogue box
## too, not just the map underneath it.
var _fade: FadeOverlay

## The one open [ModalMenu], if any - see [method open_menu]. Only ever one at a time;
## a party/equipment/shop screen does not stack on top of another today.
var _menu: ModalMenu = null


func _ready() -> void:
	main_ui = MAIN_UI_SCENE.instantiate()
	add_child(main_ui)

	_fade = FadeOverlay.new()
	add_child(_fade)


func _process(_delta: float) -> void:
	main_ui.visible = get_tree().get_first_node_in_group(&"map_context") != null


## See [method FadeOverlay.start] - the one entry point every fade-driven command
## (fade/fade_in/fade_out, change_map/change_map_marker's own fade legs) drives the
## shared overlay through.
func fade_to(reveal: float, seconds: float, texture: Texture2D = null) -> void:
	_fade.start(reveal, seconds, texture)


func is_fading() -> bool:
	return _fade.is_fading()


## Instances [param scene] (a [ModalMenu]), adds it above everything else in this
## layer, pushes [constant ModeStack.Mode.MENU], and tears both back down the moment
## the menu's own [signal ModalMenu.closed] fires - see [ModalMenu]'s own doc. Returns
## null, opening nothing, if a menu is already up; refused rather than stacked, the
## same "one at a time" rule [method EventScheduler.run_exclusive] holds its own slot to.
func open_menu(scene: PackedScene) -> ModalMenu:
	if _menu != null:
		return null

	_menu = scene.instantiate() as ModalMenu
	add_child(_menu)
	ModeStack.push(ModeStack.Mode.MENU)
	_menu.closed.connect(_on_menu_closed)
	return _menu


func is_menu_open() -> bool:
	return _menu != null


func _on_menu_closed() -> void:
	if _menu == null:
		return
	_menu.queue_free()
	_menu = null
	ModeStack.pop()
