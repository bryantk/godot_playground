## Presentation executors.
##
## [code]play_anim[/code], [code]play_sound[/code] and [code]play_music[/code] have no
## executor yet - there is no animation hookup and no audio subsystem at all today.
## Left to the generic fallback.


## Tweens the shared [FadeOverlay] (GameUI's own) to a reveal level - 0 is fully covered
## by [code]fade_color[/code]/[code]texture[/code], 1 is the game fully visible.
## [code]fade_in[/code]/[code]fade_out[/code] below are this with [code]to[/code] pinned
## to 1/0; a bare [code]fade[/code] node is the escape hatch for anything in between (a
## partial dim, say). Never awaits (event_command_exec.gd's own rule) - [FadeOverlay]'s
## own [Tween] does the work and [method tick] only polls whether it has finished.
class Fade extends EventCommandExec:
	func start() -> void:
		var to := float(args.get("to", 0.0))
		var seconds := float(args.get("seconds", FadeConstants.DEFAULT_SECONDS))
		GameUI.fade_to(to, seconds, load_texture_arg(args.get("texture", "")))

	func tick(_delta: float) -> int:
		return Status.RUNNING if GameUI.is_fading() else Status.DONE


## [code]fade[/code] with [code]to[/code] pinned to 1.0 (fully visible).
class FadeIn extends Fade:
	func start() -> void:
		var seconds := float(args.get("seconds", FadeConstants.DEFAULT_SECONDS))
		GameUI.fade_to(1.0, seconds, load_texture_arg(args.get("texture", "")))


## [code]fade[/code] with [code]to[/code] pinned to 0.0 (fully covered).
class FadeOut extends Fade:
	func start() -> void:
		var seconds := float(args.get("seconds", FadeConstants.DEFAULT_SECONDS))
		GameUI.fade_to(0.0, seconds, load_texture_arg(args.get("texture", "")))


## Toggles [member ActorView.step_in_place] mid-graph, without waiting for the next
## page switch to reapply the page's own [code]step_in_place[/code] (see [method
## GameEvent._apply_actor_flags]) - the same runtime-override relationship
## [code]set_visible[/code] already has with a page's own [code]art[/code].
class SetStepInPlace extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a != null:
			a.view().set_step_in_place(bool(args.get("step_in_place", false)))


## Freezes an actor's sprite sheet on one exact (row, col) frame, through [method
## ActorView.hold_frame] - a held pose (pointing, sitting, surprised) rather than a step
## of the walk cycle. Completes in the tick it starts: the pose holds until something
## else changes it (another [code]hold_frame[/code], or [member SpriteSheet.paused]
## cleared by whatever resumes the walk cycle), not for the duration of this command.
class HoldFrame extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a != null:
			a.view().hold_frame(
				int(args.get("row", 0)), int(args.get("col", 0)), bool(args.get("flip", false)))


## Swaps an actor's sprite sheet texture at runtime, independent of the page-level
## [code]art[/code] block (which is only re-applied on page activation) - a mid-graph
## costume change. [code]facing[/code] is optional and resolved the same way
## [code]face_direction[/code]'s own argument is (a compass token, "random", or a
## relative turn), because a new sheet's frames do not always agree with whatever
## direction the actor last faced under the old one.
class SetSheet extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a == null:
			return
		a.view().apply_art({"sheet": str(args.get("sheet", ""))})
		if not args.has("facing"):
			return
		var count: int = a.facing_count
		var m := a.motion()
		if m is GridMotion:
			count = (m as GridMotion).direction_count
		var dir := EventCommand.resolve_turn(args.get("facing"), a.facing(), count)
		if dir != Vector3i.ZERO:
			ctx.mark_actor_touched(a)
			m.face(dir)


## Shows or hides an actor's visual, through [method ActorView.set_visible].
class SetVisible extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a != null:
			a.view().set_visible(bool(args.get("visible", true)))


## Changes an actor's draw order relative to other actors and sprites on the map,
## through [method ActorView.set_y_level]. Higher draws over lower; a map's floor and
## "above" tile layers bracket the whole range with their own z_index, so this alone
## cannot draw an actor over the trees or under the floor.
class SetYLevel extends EventCommandExec:
	func start() -> void:
		var a := actor()
		if a != null:
			a.view().set_y_level(int(args.get("y_level", 0)))


static func table() -> Dictionary:
	return {
		"set_visible": SetVisible,
		"set_y_level": SetYLevel,
		"hold_frame": HoldFrame,
		"set_sheet": SetSheet,
		"set_step_in_place": SetStepInPlace,
		"fade": Fade,
		"fade_in": FadeIn,
		"fade_out": FadeOut,
	}
