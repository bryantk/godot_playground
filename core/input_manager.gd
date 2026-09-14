extends Node

## Forwards named actions to whoever currently owns input. Autoloaded as
## [code]InputManager[/code].
##
## Ownership is a stack rather than a single target, so an exclusive event runner
## pushes itself (or a skip-cutscene handler) and pops on finish, and the dialogue
## window pushes itself while open - and no system has to know what the previous owner
## was. [ModeStack] is the arbiter of which mode owns input; this is the mechanism it
## drives.

@export var target: Node = null

var _is_down := {}
var _stack: Array[Node] = []

func attach(node: Node) -> void:
	target = node

## Take input until [method pop_target]. Pushing null is deliberate and useful: it is
## how a cutscene swallows input without needing a handler for it.
func push_target(node: Node) -> void:
	_stack.append(target)
	target = node
	EventBus.input_lock_changed.emit(true)

func pop_target() -> void:
	if _stack.is_empty():
		return
	target = _stack.pop_back()
	_is_down.clear()
	EventBus.input_lock_changed.emit(not _stack.is_empty())

func is_locked() -> bool:
	return not _stack.is_empty()

func is_down(action: String) -> bool:
	return _is_down.get(action, false)

func _ready() -> void:
	self.process_mode = Node.PROCESS_MODE_ALWAYS

func _input(event: InputEvent) -> void:
	# Ignore mouse movement
	if event is InputEventMouseMotion:
		return
	# Held keys emit repeat events; they are neither a press nor a release.
	if event.is_echo():
		return

	#print("  ->%s %s" % [event.as_text(), "down" if event.is_pressed() else "up"])

	if event is InputEventMouseButton:
		return

	if event.is_action_pressed(&"quit"):
		get_tree().quit()
	elif event.is_action(&"action"):
		_send(&"action", event.is_pressed())
	elif event.is_action(&"cancel"):
		_send(&"cancel", event.is_pressed())
	elif event.keycode == KEY_R:
		_send(&"debug", event.is_pressed())
	elif event.keycode == KEY_T:
		_send(&"debug2", event.is_pressed())
	elif event.keycode == KEY_P:
		_send(&"pause", event.is_pressed())

func _send(method: StringName, pressed: bool) -> bool:
	if target == null or not target.has_method(method):
		return false

	_is_down[method] = pressed
	target.call(method, pressed)
	return true
