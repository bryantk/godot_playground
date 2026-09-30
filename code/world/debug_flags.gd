extends Node

## Whether the game should blow through timed content right now, and which debug
## overlays are showing. Autoloaded as [code]DebugFlags[/code].
##
## Held down on backtick rather than toggled, and read directly off [Input] rather than
## routed through [InputManager]'s owned-input stack (question 48,
## docs/stage-c-plan.md segment 4) - the whole point is that it has to keep working
## precisely when nobody owns input, mid-cutscene or mid-dialogue, exactly when a
## developer wants to skip a segment they have already seen.
##
## Every blocking, [code]RESUME_STATE[/code] command executor checks [method
## is_fast_forward] at the top of its own [code]tick()[/code] and collapses to its own
## end state on that tick if it is held. [GridMotion] and the dialogue window are not
## [code]tick()[/code]-shaped, so they read this flag themselves.

## Test hook, and a graph's own [code]set_fast_forward[/code] command
## ([code]events/commands/state_execs.gd[/code]'s own [code]SetFastForward[/code]) -
## either way, a settable override that forces the answer without touching [Input] at
## all, which is what lets a headless suite (which cannot hold a physical key down) or
## an authored graph (skipping a stretch known safe, no human needed) drive this the
## same as a held key would.
var force_fast_forward: bool = false

## True while [member force_fast_forward] is being forced on by [member _process]'s own
## key-0 hold check specifically - not by a test or [code]set_fast_forward[/code]
## command - so releasing key 0 clears only what key 0 itself set, rather than
## stomping a manual override [member _process] had nothing to do with.
var _fast_forward_from_key := false

func is_fast_forward() -> bool:
	#TODO: change hard coded key to an input map
	return force_fast_forward or Input.is_physical_key_pressed(KEY_QUOTELEFT)


## Key 0 is a second, dedicated hold-to-fast-forward key alongside backtick - backtick
## already does this (see [method is_fast_forward]) but also opens/closes the debug
## menu on the initial press, which is unwanted noise when all that's wanted is to
## blow through a stretch already seen. Written through [member force_fast_forward]
## itself (not a second physical-key check ORed into [method is_fast_forward]) so the
## debug menu's own line for it ([code]code/world/debug/debug_menu.gd[/code]) can show
## one flag's real state instead of re-deriving it.
func _process(_delta: float) -> void:
	if not OS.is_debug_build():
		return
	if Input.is_physical_key_pressed(KEY_0):
		force_fast_forward = true
		_fast_forward_from_key = true
	elif _fast_forward_from_key:
		force_fast_forward = false
		_fast_forward_from_key = false


# -- Debug overlays -------------------------------------------------------------------
#
# One on/off per category rather than [DebugArea2D]/[DebugArea3D]/[DebugPassabilityView]/
# [DebugInteractView] all sharing a single flag - toggled from the menu below
# ([code]debug_toggle[/code], backtick, opens it; [code]toggle_a[/code].."f" (keys 1-6)
# flip one category each while it is open), so a developer chasing one kind of overlay
# is not stuck looking at all of them at once. Every category starts on ([method
# _ready]) - the menu is for dismissing what's in the way, not opting into anything.
#
# Nothing draws in-game while the menu itself is closed, regardless of which categories
# are on - [method is_category_visible]'s own guard. The menu is what asks to see debug
# drawing at all; a category's own on/off only decides which of it shows once the menu
# is open, not whether any of it leaks into ordinary play with the menu closed.

## What a [DebugArea2D]/[DebugArea3D] box is marking. [DebugArea2D]/[DebugArea3D]'s own
## [code]type[/code] export is a plain [code]@export_enum[/code] int, not this enum by
## static type - Godot has no clean way to spell "an autoload's own nested enum" as a
## cross-file type - so the two are kept in this exact order by hand; [method
## is_box_type_visible]/[member BOX_TYPE_COLORS] are the only readers that give the
## ints here meaning, [DebugArea2D]/[DebugArea3D]'s own [code]_sync_target[/code]/
## [code]_sync_footprint[/code] never read it.
enum BoxType { NONE, EVENT, AREA, TRANSFER_MARKER, ACTOR }

## [constant BoxType]'s own default [member DebugArea2D.color] - blue for an event,
## green for a region trigger, orange for a map transfer marker, purple for a bare
## actor/collider, white for [constant BoxType.NONE] (nothing chosen yet).
const BOX_TYPE_COLORS := {
	BoxType.NONE: Color(1.0, 1.0, 1.0, 0.9),
	BoxType.EVENT: Color(0.35, 0.55, 1.0, 0.9),
	BoxType.AREA: Color(0.3, 0.85, 0.35, 0.9),
	BoxType.TRANSFER_MARKER: Color(0.95, 0.55, 0.15, 0.9),
	BoxType.ACTOR: Color(0.65, 0.35, 0.85, 0.9),
}

## The six toggleable categories, in [code]toggle_a[/code].."f" (keys 1-6) order - the
## four [constant BoxType] values that mean something ([constant BoxType.NONE] has no
## group of its own, see [method is_box_type_visible]) plus the two other existing
## overlays that were reading the single old flag directly.
const CATEGORIES: Array[StringName] = [
	&"event", &"area", &"transfer_marker", &"actor", &"passability", &"interact", &"route",
]

## [member CATEGORIES], in order, to the input action each one's toggle key is bound to.
const _TOGGLE_ACTIONS: Array[StringName] = [
	&"toggle_a", &"toggle_b", &"toggle_c", &"toggle_d", &"toggle_e", &"toggle_f", &"toggle_g",
]

## category (from [constant CATEGORIES]) -> shown right now. Absent reads as off, same
## as every category starting false below - [method is_category_visible] never needs a
## default fallback for a category no one has toggled yet.
var _category_visible: Dictionary = {}

var _menu_open: bool = false

## Fired when [member _menu_open] changes - the menu overlay's own cue to show/hide,
## nothing else needs it.
signal menu_opened_changed(open: bool)

## Fired whenever one category flips, so an overlay already in the tree - or the menu
## repainting its own label - can react instead of polling every frame.
signal category_toggled(category: StringName, shown: bool)

const _DebugMenu := preload("res://code/world/debug/debug_menu.gd")


## Builds the debug-menu overlay only in a debug build - nothing to remember to strip
## by hand when cutting a release export template ([method OS.is_debug_build] is false
## there), unlike every overlay's own runtime gate above, which only ever answers
## "off" in that build anyway since nothing can reach the toggle handler below to turn
## one on.
##
## Every category starts visible, not off - a debug build is exactly where a developer
## wants to see everything by default and dismiss what's in the way, not opt into each
## category one at a time before any of it shows up.
func _ready() -> void:
	if not OS.is_debug_build():
		return
	for category in CATEGORIES:
		_category_visible[category] = true
	add_child(_DebugMenu.new())


func is_menu_open() -> bool:
	return _menu_open


## False outright while the menu itself is closed - a category being switched "on" only
## ever meant "show this the next time the menu is open," never "leave it drawn in the
## background forever." [member _category_visible] still remembers each category's own
## state across an open/close so reopening the menu picks up exactly where it left off;
## this is what makes that state inert rather than a second, silent on/off behind the
## menu's own visible one.
func is_category_visible(category: StringName) -> bool:
	if not _menu_open:
		return false
	return bool(_category_visible.get(category, false))


## [constant BoxType.NONE] has no category key of its own to look up in [member
## CATEGORIES] - but that must not read as "always on regardless of the menu": with
## every placed box left at its authored default (nothing re-categorized yet, or an
## honestly uncategorized one-off), "always on" would mean the whole debug-category
## menu never visibly does anything, which is worse than not having it. So a
## [constant BoxType.NONE] box instead follows [method show_debug_view] - shown
## whenever *any* category is switched on, hidden the moment every category is back
## off, the same on/off boundary every other overlay in the project already answers
## to. Every other value maps straight to [member CATEGORIES] by its own enum
## position minus one ([constant BoxType.NONE] is first and owns no slot there).
##
## [param t] is a plain [int], not [constant BoxType], so [DebugArea2D]/[DebugArea3D]
## can each declare their own [code]@export_enum[/code]-backed [code]type[/code]
## (matching [constant BoxType]'s own ordering by hand) without a static cross-file
## type reference to an autoload's nested enum - Godot has no clean way to spell that.
func is_box_type_visible(t: int) -> bool:
	if not OS.is_debug_build():
		return false
	if t == BoxType.NONE:
		return show_debug_view()
	return is_category_visible(CATEGORIES[t - 1])


## Whether *any* debug category is currently on - the catch-all [code]games/jrpg/
## debug_only.gd[/code] reads, for a node that hides/shows with "is debugging
## happening at all" rather than one specific overlay.
func show_debug_view() -> bool:
	if not OS.is_debug_build():
		return false
	for category in CATEGORIES:
		if is_category_visible(category):
			return true
	return false


func _unhandled_input(event: InputEvent) -> void:
	if not OS.is_debug_build():
		return
	if not event.is_pressed() or event.is_echo():
		return

	if event.is_action(&"debug_toggle"):
		_menu_open = not _menu_open
		menu_opened_changed.emit(_menu_open)
		return

	if not _menu_open:
		return
	for i in _TOGGLE_ACTIONS.size():
		if event.is_action(_TOGGLE_ACTIONS[i]):
			var category := CATEGORIES[i]
			var shown := not is_category_visible(category)
			_category_visible[category] = shown
			category_toggled.emit(category, shown)
			return
