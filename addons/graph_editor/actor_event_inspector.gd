@tool
extends EditorInspectorPlugin

## Adds an "Open Event Graph" button to an [Actor]'s or a [GameEvent]'s own inspector,
## so opening - or creating - the event file either one plays does not need the graph
## editor dock open and the right node re-selected there a second time.
##
## [b]An [Actor] carries no document path of its own[/b] - that is [GameEvent]'s
## business. For an [Actor], this seeks the [GameEvent] sibling [method
## GameEvent._find_actor]'s own fallback expects (an event retrofitted onto an actor
## prefab that predates having one), creating one there first if none exists yet, and
## opens that.
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
	return object is Actor or object is GameEvent


func _parse_begin(object: Object) -> void:
	var button := Button.new()
	button.text = "Open Event Graph"
	button.tooltip_text = (
		"Opens this actor's event in the graph editor - finding (or creating) the GameEvent beside it first."
		if object is Actor else
		"Opens this event's document .json in the graph editor - creating it at a default path first if it has none.")
	button.pressed.connect(_on_pressed.bind(object))
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
