class_name ModalMenu extends Control

## The shared base every full-screen menu (party/stats, equipment, shop) builds on -
## party_menu.gd, equipment_menu.gd, shop_menu.gd all extend this rather than each
## reinventing the push-[ModeStack.Mode.MENU]/close dance.
##
## [method GameUI.open_menu] is the one thing that instances one of these: it adds the
## menu as a child, pushes [constant ModeStack.Mode.MENU], and removes the menu again
## the moment [signal closed] fires, popping the mode stack back with it - so a concrete
## menu only ever has to call [method close], never touch [ModeStack] itself.

signal closed()


func close() -> void:
	closed.emit()
