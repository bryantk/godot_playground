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
	if _vars.has(key) and _vars[key] == value:
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


# -- Save ---------------------------------------------------------------------

## The shared envelope's state half. Self flags are in here because they are the
## easiest thing in the design to omit and only notice much later - nothing else can
## derive them.
func to_save() -> Dictionary:
	return {
		"flags": _flags.keys(),
		"vars": _vars.duplicate(),
		"self_flags": _self_flags.keys(),
	}


func from_save(data: Dictionary) -> void:
	_flags.clear()
	_vars.clear()
	_self_flags.clear()

	for key: Variant in data.get("flags", []):
		_flags[StringName(key)] = true
	for key: Variant in (data.get("vars", {}) as Dictionary):
		_vars[StringName(key)] = (data["vars"] as Dictionary)[key]
	for key: Variant in data.get("self_flags", []):
		_self_flags[str(key)] = true


func clear() -> void:
	_flags.clear()
	_vars.clear()
	_self_flags.clear()
