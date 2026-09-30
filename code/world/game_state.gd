extends Node

## Flags, variables and self flags. Autoloaded as [code]GameState[/code].
##
## Variables are declared in a manifest rather than being bare strings, so the graph
## editor and the event dock can offer a picker instead of a text field. A manifest is
## cheap when written early and awkward to retrofit once graphs reference names
## nothing can enumerate.
##
## [signal changed] is what makes conditional page selection affordable: an event
## subscribes to exactly the keys its conditions mention, derived from the condition
## entries, so nothing is wired by hand and no event polls.

signal changed(key: StringName)

## The declared variables. [code]{name: {"type": TYPE_*, "default": value,
## "values": [...] }}[/code] - [code]values[/code] is optional and turns a variable
## into an enum the editor can offer as a dropdown.
@export var manifest: Dictionary = {}

var _flags: Dictionary[StringName, bool] = {}
var _vars: Dictionary[StringName, Variant] = {}

## "map_id:event_id:flag" -> true. The classic "talk once, then change permanently"
## mechanism without polluting global flag space.
var _self_flags: Dictionary[String, bool] = {}

## "map_id:actor_id" -> true - actors [code]erase_event[/code] (actor_execs.gd) has
## removed, durable enough to survive a save/load of the same map (it rides along in
## [method to_save]/[method from_save] like everything else here), but scoped per map
## and cleared the moment that map is left ([method MapContext._exit_tree]) rather than
## kept for the rest of the file - a return visit finds every placement as authored.
var _erased: Dictionary[String, bool] = {}


# -- Flags --------------------------------------------------------------------

func flag(key: StringName) -> bool:
	return _flags.get(key, false)


func set_flag(key: StringName, value: bool = true) -> void:
	if _flags.get(key, false) == value:
		return
	if value:
		_flags[key] = true
	else:
		_flags.erase(key)
	changed.emit(key)


# -- Variables ----------------------------------------------------------------

func var_get(key: StringName) -> Variant:
	if _vars.has(key):
		return _vars[key]
	if manifest.has(key) and (manifest[key] as Dictionary).has("default"):
		return (manifest[key] as Dictionary)["default"]
	return 0


func var_set(key: StringName, value: Variant) -> void:
	if not manifest.is_empty() and not manifest.has(key):
		push_warning("GameState: '%s' is not in the manifest." % key)
	# Same-type first: comparing across types (a float variable handed a bool, say -
	# eval_var's own doc, events/commands/state_execs.gd) throws in GDScript rather than
	# just reading false, and a type change is "changed" on its face regardless.
	if _vars.has(key) and typeof(_vars[key]) == typeof(value) and _vars[key] == value:
		return
	_vars[key] = value
	changed.emit(key)


func var_add(key: StringName, delta: float) -> void:
	var_set(key, float(var_get(key)) + delta)


## Every declared variable name, for the editor's picker.
func declared() -> Array[StringName]:
	var out: Array[StringName] = []
	for key: Variant in manifest:
		out.append(StringName(key))
	return out


# -- Self flags ---------------------------------------------------------------

static func self_key(map_id: StringName, event_id: StringName, flag_name: StringName) -> String:
	return "%s:%s:%s" % [map_id, event_id, flag_name]


func self_flag(map_id: StringName, event_id: StringName, flag_name: StringName) -> bool:
	return _self_flags.get(self_key(map_id, event_id, flag_name), false)


func set_self_flag(map_id: StringName, event_id: StringName, flag_name: StringName, value: bool = true) -> void:
	var key := self_key(map_id, event_id, flag_name)
	if _self_flags.get(key, false) == value:
		return
	if value:
		_self_flags[key] = true
	else:
		_self_flags.erase(key)
	changed.emit(StringName(key))


# -- Erased actors --------------------------------------------------------------

static func erased_key(map_id: StringName, actor_id: StringName) -> String:
	return "%s:%s" % [map_id, actor_id]


func is_erased(map_id: StringName, actor_id: StringName) -> bool:
	return _erased.get(erased_key(map_id, actor_id), false)


func set_erased(map_id: StringName, actor_id: StringName) -> void:
	_erased[erased_key(map_id, actor_id)] = true


## Forgets every actor erased on [param map_id] - called once when that map is left
## ([method MapContext._exit_tree]), so a later visit (or a scene reload once this
## session ends) is not filtered against a removal that no longer means anything.
func clear_erased(map_id: StringName) -> void:
	var prefix := "%s:" % map_id
	for key: String in _erased.keys():
		if key.begins_with(prefix):
			_erased.erase(key)


# -- Save ---------------------------------------------------------------------

## The shared envelope's state half. Self flags are in here because they are the
## easiest thing in the design to omit and only notice much later - nothing else can
## derive them.
func to_save() -> Dictionary:
	return {
		"flags": _flags.keys(),
		"vars": _vars.duplicate(),
		"self_flags": _self_flags.keys(),
		"erased": _erased.keys(),
	}


func from_save(data: Dictionary) -> void:
	_flags.clear()
	_vars.clear()
	_self_flags.clear()
	_erased.clear()

	for key: Variant in data.get("flags", []):
		_flags[StringName(key)] = true
	for key: Variant in (data.get("vars", {}) as Dictionary):
		_vars[StringName(key)] = (data["vars"] as Dictionary)[key]
	for key: Variant in data.get("self_flags", []):
		_self_flags[str(key)] = true
	for key: Variant in data.get("erased", []):
		_erased[str(key)] = true


func clear() -> void:
	_flags.clear()
	_vars.clear()
	_self_flags.clear()
	_erased.clear()
