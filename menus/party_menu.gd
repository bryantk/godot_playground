class_name PartyMenu extends ModalMenu

## Party status and equipment, combined into one screen rather than two - selecting a
## member and re-gearing them is one motion in almost every game this is modeled on, and
## splitting it into a second modal would only mean [GameUI.open_menu]'s own "one modal
## at a time" rule getting in its own way. A dedicated shop screen (shop_menu.gd) is the
## only other menu - buying is a different enough motion (gold, a fixed catalogue) to
## earn its own screen.

@onready var _member_list: VBoxContainer = %MemberList
@onready var _stats_label: Label = %StatsLabel
@onready var _slot_box: VBoxContainer = %SlotBox
@onready var _bench_button: Button = %BenchButton
@onready var _close_button: Button = %CloseButton

var _selected: PartyMember = null


func _ready() -> void:
	_close_button.pressed.connect(close)
	_bench_button.pressed.connect(_on_bench_pressed)
	_refresh()


func _refresh() -> void:
	_refresh_member_list()
	if _selected == null and not (Party.active + Party.reserve).is_empty():
		_selected = (Party.active + Party.reserve)[0]
	_refresh_details()


func _refresh_member_list() -> void:
	for child in _member_list.get_children():
		child.queue_free()

	_add_section(_member_list, "Active")
	for m in Party.active:
		_add_member_button(m)
	_add_section(_member_list, "Reserve")
	for m in Party.reserve:
		_add_member_button(m)


func _add_member_button(m: PartyMember) -> void:
	var button := Button.new()
	button.text = m.display_name
	button.toggle_mode = true
	button.button_pressed = m == _selected
	button.pressed.connect(_select.bind(m))
	_member_list.add_child(button)


func _select(m: PartyMember) -> void:
	_selected = m
	_refresh()


func _refresh_details() -> void:
	for child in _slot_box.get_children():
		child.queue_free()

	if _selected == null:
		_stats_label.text = "No party members yet."
		_bench_button.visible = false
		return

	var stats := _selected.effective_stats()
	var hp := _selected.current_hp if _selected.current_hp >= 0 else stats.max_hp
	var mp := _selected.current_mp if _selected.current_mp >= 0 else stats.max_mp
	_stats_label.text = "%s\nHP %d/%d  MP %d/%d\nATK %d  DEF %d  MAG %d  SPD %d" % [
		_selected.display_name, hp, stats.max_hp, mp, stats.max_mp,
		stats.atk, stats.def, stats.mag, stats.spd]

	for slot in [Equipment.Slot.WEAPON, Equipment.Slot.ARMOR, Equipment.Slot.ACCESSORY]:
		_slot_box.add_child(_build_slot_row(slot))

	_bench_button.visible = true
	_bench_button.text = "Move to Reserve" if Party.active.has(_selected) else "Move to Active"


func _build_slot_row(slot: Equipment.Slot) -> HBoxContainer:
	var row := HBoxContainer.new()

	var current: Equipment = _selected.equipped.get(slot)
	var label := Label.new()
	label.text = "%s: %s" % [Equipment.Slot.keys()[slot], current.display_name if current != null else "(none)"]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var candidates := _owned_for_slot(slot)
	if not candidates.is_empty():
		var change := Button.new()
		change.text = "Equip %s" % candidates[0].display_name
		change.pressed.connect(_on_equip_pressed.bind(candidates[0].id))
		row.add_child(change)

	if current != null:
		var unequip := Button.new()
		unequip.text = "Unequip"
		unequip.pressed.connect(_on_unequip_pressed.bind(slot))
		row.add_child(unequip)

	return row


func _owned_for_slot(slot: Equipment.Slot) -> Array[Equipment]:
	var out: Array[Equipment] = []
	for item in Party.equipment_catalogue():
		if item.slot == slot and int(Party.owned_equipment.get(item.id, 0)) > 0:
			out.append(item)
	return out


func _on_equip_pressed(item_id: StringName) -> void:
	Party.equip_from_inventory(_selected, item_id)
	_refresh_details()


func _on_unequip_pressed(slot: Equipment.Slot) -> void:
	Party.unequip_to_inventory(_selected, slot)
	_refresh_details()


func _on_bench_pressed() -> void:
	if Party.active.has(_selected):
		Party.active.erase(_selected)
		Party.reserve.append(_selected)
	elif Party.active.size() < Party.MAX_ACTIVE:
		Party.reserve.erase(_selected)
		Party.active.append(_selected)
	Party.changed.emit()
	_refresh()


func _add_section(container: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	container.add_child(label)
