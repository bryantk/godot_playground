class_name ActorView extends Node

## What an actor looks like, independent of what space it lives in. A sibling of
## [MotionController] under [Actor].
##
## This exists because presentation is its own axis: game 2 is sprites in a 3D world,
## which neither the space axis nor the motion axis has anywhere to put. It is also
## where the grid-step offset lands - [method set_step_offset] rather than a
## [SpaceAdapter] method - because the offset is a lie told to the eye, and keeping it
## off the adapter is what keeps the adapter thin.

## The node actually displaced by the step tween and the texel rounding. Left null it
## takes the first child, which is the normal arrangement.
@export var visual_path: NodePath = NodePath()

## Height, faked: higher draws over lower. Exported so a placement can start elevated
## (an actor standing on a platform), and reachable at runtime through
## [method set_y_level] - the `set_y_level` event command's target.
##
## Meaningful only relative to the other actors and sprites on the same map; a map's
## floor and "above" tile layers bracket the whole range with their own z_index rather
## than agreeing on it with this, so an actor stays between them regardless of where its
## own y_level sits.
@export var y_level: int = 0:
	set(value):
		y_level = value
		_write_y_level()

## Whether the visual is shown. Exported so a placement can start hidden - a chest not
## yet revealed, a cutscene actor's stand-in - and reachable at runtime through
## [method set_visible]. A stored property rather than a one-shot write for the same
## reason [member y_level] is: something (a [GameEvent]'s own init push, event-pages.md
## §4.3) may set this before [member visual_path] has resolved anything to write it
## into, and [method _after_bind] re-applies it the moment that changes, so the value
## is never silently dropped for having arrived early.
@export var visible: bool = true:
	set(value):
		visible = value
		_write_visible()

## A resting pixel nudge for the visual, independent of [member set_step_offset]'s own
## [member _offset] - that one is a lie told during a step and gets overwritten every
## frame it is in flight; this one is permanent, the same idea as [Sprite2D]'s own
## built-in [code]offset[/code] (which is exactly where [method _write_visual_offset]
## writes it for a 2D visual). [Actor] pushes [member MapContext.actor_visual_offset]
## here summed with its own footprint's centring correction ([method
## Actor.footprint_visual_offset]) the moment it resolves a view - every actor, not
## only one with a [GameEvent] beside it (the player has none) - so a multi-cell
## actor's sprite reads as centred on its whole footprint rather than on just its
## anchor cell.
@export var visual_offset: Vector2 = Vector2.ZERO:
	set(value):
		visual_offset = value
		_write_visual_offset()

var _visual: Node = null
var _offset: Vector3 = Vector3.ZERO
var _bound := false

## Numbers the completion keys [method play] hands out. Subclasses use it; the step
## offset no longer does, because it no longer finishes on its own.
var _keys := 0


## Binding happens once, and [method _ready] must not redo it.
##
## A code-built actor calls [method bind_visual] before this node is ready, and a
## subclass caches the visual's [i]resting[/i] position when it binds. Running the bind
## a second time here would re-read that position after something had already written a
## correction into it, folding the correction into the rest pose - which then drifts a
## little further every time it happens.
func _ready() -> void:
	if _visual == null:
		_visual = get_node_or_null(visual_path) if not visual_path.is_empty() else _first_child()
	if not _bound:
		_after_bind()


## Point this view at its visual explicitly. Needed when the actor is built in code,
## because [method Node._ready] has already run by the time the visual is added.
func bind_visual(node: Node) -> void:
	_visual = node
	_after_bind()


func visual() -> Node:
	return _visual


## Called whenever [member _visual] changes, so subclasses can cache typed references
## once rather than casting on every call.
func _after_bind() -> void:
	_bound = true
	_warn_if_detached()
	_write_y_level()
	_write_visible()
	_write_visual_offset()


func _first_child() -> Node:
	return get_child(0) if get_child_count() > 0 else null


## [Actor], [ActorView] and [MotionController] are plain [Node]s on purpose - that is
## what lets one script serve both spaces. The consequence, which is invisible until
## something renders in the wrong place, is that a [Node3D] or [Node2D] whose parent
## chain passes through a plain [Node] becomes its own transform root: it ignores the
## body entirely and sits at the world origin.
##
## So the visual belongs under the body, as a sibling of [Actor], with this view
## pointed at it by [member visual_path] or [method bind_visual] - never nested under
## the view itself. Catching it here turns a baffling "my sprite is at 0,0" into a
## message that says what to do.
func _warn_if_detached() -> void:
	if _visual == null:
		return
	if not (_visual is Node2D or _visual is Node3D):
		return
	var parent := _visual.get_parent()
	if parent is Node2D or parent is Node3D:
		return
	push_warning(
		"ActorView: visual '%s' is parented to '%s', which has no transform, so it " % [
			_visual.name, parent.name if parent != null else "<none>"]
		+ "will render at the world origin instead of following the actor. Parent it "
		+ "to the body and point visual_path (or bind_visual) at it.")


# -- To implement -------------------------------------------------------------

func set_facing(_dir: Vector3i) -> void:
	pass


## Re-applied on page activation, so a chest that changes art between pages does not
## need its own mechanism. See event-pages.md.
func apply_art(_art: Dictionary) -> void:
	pass


## Set [member visible] and apply it immediately. What the `set_visible` event command
## calls; the export exists for a placement's resting visibility, this for changing it
## while the map is live.
func set_visible(v: bool) -> void:
	visible = v


func _write_visible() -> void:
	if _visual is CanvasItem:
		(_visual as CanvasItem).visible = visible
	elif _visual is Node3D:
		(_visual as Node3D).visible = visible


## Set [member visual_offset] and apply it immediately.
func set_visual_offset(v: Vector2) -> void:
	visual_offset = v


## Writes into whichever of the three visual kinds this project's prefabs actually
## use - [Sprite2D] (and [SpriteSheet], which extends it), [AnimatedSprite2D], and
## [Sprite3D] - all three of which carry their own native [code]offset[/code] pixel
## nudge already, the same mechanism [code]actor_jrpg.tscn[/code]'s hand-tuned
## [code]Vector2(0, -4)[/code] already uses. Lives in the base rather than a
## subclass override: unlike [member y_level]/[member visible], which mean something
## different (or nothing) per space, an offset in pixels is the same idea in 2D and 3D.
func _write_visual_offset() -> void:
	if _visual is Sprite2D:
		(_visual as Sprite2D).offset = visual_offset
	elif _visual is AnimatedSprite2D:
		(_visual as AnimatedSprite2D).offset = visual_offset
	elif _visual is Sprite3D:
		(_visual as Sprite3D).offset = visual_offset


## Set [member y_level] and apply it immediately. What the `set_y_level` event command
## calls; the export exists for a placement's resting height, this for changing it -
## a lift rising a step, a pit sinking one - while the map is live.
func set_y_level(v: int) -> void:
	y_level = v


## Subclasses write [member y_level] into whatever their visual understands. The base
## does nothing because [SpriteView3D]'s billboards are already depth-sorted by the 3D
## renderer and have no equivalent of [CanvasItem.z_index] worth touching.
func _write_y_level() -> void:
	pass


## Plays [param anim] and returns a completion key, matching the pattern
## [method EventBus.say] uses - the caller awaits it or ignores it. A key is what lets
## a round join over a view's animation exactly as it joins over a step.
func play(_anim: StringName) -> String:
	return ""


# -- The step offset ----------------------------------------------------------

## How far behind its body the sprite currently is. Written every frame by
## [GridMotion] while a step is in flight; the body has already snapped to the
## destination cell, and this is the sprite catching up.
##
## [b]The view does not own the clock.[/b] It used to: this was a [Tween] over a
## duration handed in at commit. A tween's duration is fixed the moment it starts,
## which made a speed change mid-cell impossible to express - an actor stepping onto
## mud would finish the step at its old speed and only slow down on the next one. The
## controller now advances the offset itself, at whatever speed the actor has [i]this
## frame[/i], so a modifier that registers at commit slows the step that is entering
## and one that unregisters mid-cell speeds up the rest of it.
##
## Nothing is interpolated here, so there is no easing to configure. Constant velocity
## is what joins consecutive steps into continuous motion - a sprite that decelerated
## to a stop in the middle of every cell reads as step-pause-step even when the steps
## are back to back - and it is what cell-stepping games have always done.
func set_step_offset(v: Vector3) -> void:
	_set_offset(v)


## Drop the offset immediately - a cutscene that teleports an actor mid-step wants the
## sprite where the body is, not still sliding toward where it used to be going.
func cancel_step_offset() -> void:
	_offset = Vector3.ZERO
	_write_offset()


func offset() -> Vector3:
	return _offset


func _set_offset(v: Vector3) -> void:
	_offset = v
	_write_offset()


## Subclasses write the offset into whatever their visual understands, and are the
## place any texel rounding happens.
func _write_offset() -> void:
	pass
