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
