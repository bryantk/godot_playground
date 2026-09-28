## Menu executors. Only [code]open_menu[/code] has one.

const _SCENES := {
	"party": "res://menus/party_menu.tscn",
	"shop": "res://menus/shop_menu.tscn",
}


## Opens one of [constant _SCENES] through [method GameUI.open_menu] and blocks until
## the player closes it - the same "wait for the player" shape [code]say[/code]/
## [code]ask[/code] already have, just over a full-screen menu instead of the dialogue
## window.
class OpenMenu extends EventCommandExec:
	func start() -> void:
		var name := str(args.get("menu", ""))
		var path: String = _SCENES.get(name, "")
		if path == "":
			push_warning("EventRunner: open_menu - unknown menu \"%s\"." % name)
			return
		if GameUI.open_menu(load(path)) == null:
			push_warning("EventRunner: open_menu - a menu is already open.")

	func tick(_delta: float) -> int:
		return Status.RUNNING if GameUI.is_menu_open() else Status.DONE


static func table() -> Dictionary:
	return {
		"open_menu": OpenMenu,
	}
