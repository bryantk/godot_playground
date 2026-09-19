extends Node

## Whether the game should blow through timed content right now. Autoloaded as
## [code]DebugFlags[/code].
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

## Test hook. A headless suite cannot hold a physical key down, so this forces the
## answer without touching [Input] at all.
var force_fast_forward: bool = false

func is_fast_forward() -> bool:
	return force_fast_forward or Input.is_physical_key_pressed(KEY_QUOTELEFT)


## Whether debug visuals - [DebugPassabilityView]'s impassable-cell overlay today -
## should be showing right now. Starts off; [code]debug_toggle[/code] turns it on, same
## key as [method is_fast_forward] holds for the opposite reason.
var _show_debug_view: bool = false

## Fired when [method show_debug_view] changes, so a view already in the tree can react
## instead of polling every frame.
signal debug_view_toggled(shown: bool)

func show_debug_view() -> bool:
	return _show_debug_view

func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	if event.is_action(&"debug_toggle"):
		_show_debug_view = not _show_debug_view
		debug_view_toggled.emit(_show_debug_view)
