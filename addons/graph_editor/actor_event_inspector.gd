@tool
extends EditorInspectorPlugin

## Adds an "Open Event Graph" button to an [Actor]'s, a [GameEvent]'s, or a placement's
## own top-level scene's inspector, so opening - or creating - the event file any of the
## three plays does not need the graph editor dock open and the right node re-selected
## there a second time.
##
## [b]An [Actor] carries no document path of its own[/b] - that is [GameEvent]'s
## business. For an [Actor], this seeks the [GameEvent] sibling [method
## GameEvent._find_actor]'s own fallback expects (an event retrofitted onto an actor
## prefab that predates having one), creating one there first if none exists yet, and
## opens that.
##
## [b]The placement root[/b] - [code]Npc_8_12__nada[/code], not the [code]Actor[/code]
## node inside it - is what the Scene dock actually shows a name for and what an author
## normally clicks. It carries no script of its own (see [method ActorNaming.
## placement_root]'s own doc: an actor prefab's root is an instanced sub-scene, not
## something this project scripts directly), so [method _can_handle] cannot key on its
## class the way it does for [Actor]/[GameEvent] and instead looks for an instanced
## scene ([member Node.scene_file_path] set) with an [Actor] somewhere under it -
## [method ActorNaming.actors_under] run from the root down, the mirror of [method
## ActorNaming.placement_root]'s own walk from an actor up. [method _parse_begin]
## resolves that down to the actor once, so [method _on_pressed] still only ever sees an
## [Actor] or a [GameEvent] and needs no third branch of its own.
##
## The open-or-create logic itself stays on [member _panel] ([method
## GraphEditorPanel.open_or_create_game_event] / [method
## GraphEditorPanel.find_or_create_game_event_for_actor]) - this only reaches for it, so
## there is still exactly one place that decides a default path or writes an empty
## file, whether the trigger was this button or the toolbar's own "Load Actor Event".

var _panel: Object = null
var _reveal: Callable


## Called once by [code]plugin.gd[/code] after both this plugin and the bottom-panel
## graph editor exist. [param reveal] brings the panel into view - it is a [Callable]
## rather than the owning [EditorPlugin] itself, since [method
## EditorPlugin.make_bottom_panel_item_visible] needs the panel control as an argument
## the caller already has and this script otherwise has no reason to hold a reference
## to the plugin.
func setup(panel: Object, reveal: Callable) -> void:
	_panel = panel
	_reveal = reveal


func _can_handle(object: Object) -> bool:
	return object is Actor or object is GameEvent or _placement_actor(object) != null


## The [Actor] inside [param object], when [param object] is itself a placement's
## top-level scene rather than the actor or its event directly - null for anything else,
## including an [Actor]/[GameEvent] itself (those are their own case, not this one) and
## an ordinary container that merely has actors somewhere under it, like a map's whole
## "Actors" node. [member Node.scene_file_path] is what tells the two apart: a placement
## root is always an instanced sub-scene, and a map's own grouping nodes are not.
func _placement_actor(object: Object) -> Actor:
	if not (object is Node) or object is Actor or object is GameEvent:
		return null
	var node := object as Node
	if node.scene_file_path == "":
		return null
	var actors := ActorNaming.actors_under(node)
	return actors[0] if not actors.is_empty() else null


func _parse_begin(object: Object) -> void:
	# Resolved once, here, so _on_pressed keeps its original two-branch shape (Actor or
	# GameEvent) and never needs to know a placement root was ever involved.
	var target: Object = object if (object is Actor or object is GameEvent) \
		else _placement_actor(object)
	if target == null:
		return

	var button := Button.new()
	button.text = "Open Event Graph"
	button.tooltip_text = (
		"Opens this event's document .json in the graph editor - creating it at a default path first if it has none."
		if target is GameEvent else
		"Opens this actor's event in the graph editor - finding (or creating) the GameEvent beside it first.")
	button.pressed.connect(_on_pressed.bind(target))
	add_custom_control(button)


func _on_pressed(object: Object) -> void:
	if _panel == null or not is_instance_valid(_panel):
		return
	if _reveal.is_valid():
		_reveal.call()

	if object is Actor:
		var event: GameEvent = _panel.find_or_create_game_event_for_actor(object as Actor)
		_panel.open_or_create_game_event(event)
	elif object is GameEvent:
		_panel.open_or_create_game_event(object as GameEvent)
