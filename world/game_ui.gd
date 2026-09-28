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

const MAIN_UI_SCENE := preload("res://ui/text_box/main_ui.tscn")

var main_ui: MainUI


func _ready() -> void:
	main_ui = MAIN_UI_SCENE.instantiate()
	add_child(main_ui)


func _process(_delta: float) -> void:
	main_ui.visible = get_tree().get_first_node_in_group(&"map_context") != null
