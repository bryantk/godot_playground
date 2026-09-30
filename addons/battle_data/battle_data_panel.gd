@tool
extends VBoxContainer

## The Battle Data dock's contents - see plugin.gd. One [ItemList] per kind under a
## [TabContainer]; selecting an entry opens it in the inspector, and the buttons below
## create, copy, save and delete files in that kind's folder under [constant
## BattleData.ROOT]. "Check" runs [method BattleData.validate] and lists what it finds.

const TITLES := {
	BattleData.HEROES: "Heroes",
	BattleData.ENEMIES: "Enemies",
	BattleData.TROOPS: "Troops",
	BattleData.ITEMS: "Items",
	BattleData.ABILITIES: "Abilities",
	BattleData.EFFECTS: "Effects",
	BattleData.EQUIPMENT: "Equipment",
}

var _tabs: TabContainer
var _lists: Dictionary = {}
var _problems: ItemList
var _confirm: ConfirmationDialog

## The path a pending Delete is asking about.
var _pending_delete := ""


func _init() -> void:
	name = "Battle Data"
	custom_minimum_size = Vector2(0, 260)

	_tabs = TabContainer.new()
	_tabs.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_tabs)

	for kind in BattleData.KINDS:
		var list := ItemList.new()
		list.name = TITLES[kind]
		list.size_flags_vertical = Control.SIZE_EXPAND_FILL
		list.item_selected.connect(_on_selected.bind(kind))
		_tabs.add_child(list)
		_lists[kind] = list

	var buttons := HBoxContainer.new()
	add_child(buttons)
	var party_button := Button.new()
	party_button.text = "Party setup"
	party_button.tooltip_text = "Open the starting party (res://data/party.tres) in the inspector."
	party_button.pressed.connect(_on_party_setup)
	add_child(party_button)

	for entry in [["New", _on_new], ["Duplicate", _on_duplicate], ["Save", _on_save],
			["Delete", _on_delete], ["Refresh", refresh]]:
		var button := Button.new()
		button.text = entry[0]
		button.pressed.connect(entry[1])
		buttons.add_child(button)

	var check := Button.new()
	check.text = "Check data"
	check.pressed.connect(_on_check)
	add_child(check)

	_problems = ItemList.new()
	_problems.custom_minimum_size = Vector2(0, 80)
	_problems.auto_height = false
	add_child(_problems)

	_confirm = ConfirmationDialog.new()
	_confirm.confirmed.connect(_on_delete_confirmed)
	add_child(_confirm)


func _ready() -> void:
	refresh()


## Re-reads every kind's folder into its list. Each entry shows its id, then its file.
func refresh() -> void:
	for kind in BattleData.KINDS:
		var list: ItemList = _lists[kind]
		list.clear()
		for path in BattleData.files(kind):
			var entry := load(path) as Resource
			var id := str(entry.get("id")) if entry != null else "?"
			list.add_item("%s   (%s)" % [id if id != "" else "<no id>", path.get_file()])
			list.set_item_metadata(list.item_count - 1, path)


func _kind() -> StringName:
	return BattleData.KINDS[_tabs.current_tab]


func _selected_path() -> String:
	var list: ItemList = _lists[_kind()]
	var picked := list.get_selected_items()
	return "" if picked.is_empty() else str(list.get_item_metadata(picked[0]))


func _on_selected(index: int, kind: StringName) -> void:
	var path := str((_lists[kind] as ItemList).get_item_metadata(index))
	var entry := load(path) as Resource
	if entry != null:
		EditorInterface.edit_resource(entry)


## A fresh entry of the current kind, saved under a free name and opened for editing.
func _on_new() -> void:
	var kind := _kind()
	var entry: Resource = BattleData.script_for(kind).new()
	var id := _free_id(kind, "new_%s" % BattleData.singular(kind))
	entry.set("id", StringName(id))
	entry.set("display_name", id.capitalize())
	_save_as(kind, entry, id)


func _on_duplicate() -> void:
	var path := _selected_path()
	var source := load(path) as Resource if path != "" else null
	if source == null:
		return
	var kind := _kind()
	var copy := source.duplicate(true)
	var id := _free_id(kind, "%s_copy" % str(source.get("id")))
	copy.set("id", StringName(id))
	_save_as(kind, copy, id)


## Writes the selected entry back to its file - inspector edits live in the open resource
## until this (or Godot's own save) puts them on disk.
func _on_save() -> void:
	var path := _selected_path()
	if path == "":
		return
	var entry := load(path) as Resource
	if entry != null:
		ResourceSaver.save(entry, path)
		refresh()


func _on_delete() -> void:
	_pending_delete = _selected_path()
	if _pending_delete == "":
		return
	_confirm.dialog_text = "Delete %s?" % _pending_delete
	_confirm.popup_centered()


func _on_delete_confirmed() -> void:
	if _pending_delete != "" and DirAccess.remove_absolute(_pending_delete) == OK:
		EditorInterface.get_resource_filesystem().scan()
	_pending_delete = ""
	refresh()


func _on_check() -> void:
	_problems.clear()
	var found := BattleData.validate()
	if found.is_empty():
		_problems.add_item("No problems found.")
		return
	for line in found:
		_problems.add_item(line)


## An id (and so a filename) not already used in [param kind]'s folder, starting from
## [param wanted] and adding _2, _3... as needed.
func _free_id(kind: StringName, wanted: String) -> String:
	var candidate := wanted
	var n := 2
	while FileAccess.file_exists("%s/%s.tres" % [BattleData.folder(kind), candidate]):
		candidate = "%s_%d" % [wanted, n]
		n += 1
	return candidate


func _save_as(kind: StringName, entry: Resource, id: String) -> void:
	DirAccess.make_dir_recursive_absolute(BattleData.folder(kind))
	var path := "%s/%s.tres" % [BattleData.folder(kind), id]
	if ResourceSaver.save(entry, path) != OK:
		push_warning("Battle Data: could not save %s." % path)
		return
	EditorInterface.get_resource_filesystem().update_file(path)
	refresh()
	EditorInterface.edit_resource(load(path))


## Opens the starting party ([constant Party.SETUP_PATH]) in the inspector, creating an
## empty one first if the file does not exist yet.
func _on_party_setup() -> void:
	if not ResourceLoader.exists(Party.SETUP_PATH):
		DirAccess.make_dir_recursive_absolute(Party.SETUP_PATH.get_base_dir())
		ResourceSaver.save(PartySetup.new(), Party.SETUP_PATH)
		EditorInterface.get_resource_filesystem().update_file(Party.SETUP_PATH)
	EditorInterface.edit_resource(load(Party.SETUP_PATH))
