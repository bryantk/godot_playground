class_name ShopMenu extends ModalMenu

## Buy/sell against [member Party.gold] - the one other menu screen, kept separate from
## [PartyMenu] because buying is a different motion (a fixed catalogue, a price, gold
## going the other way) rather than picking through what is already owned.
##
## Sells every [Equipment] [Party] knows about (its whole catalogue, not a per-shop
## list of its own yet - honing in on "this shop only stocks these three things" is a
## later pass) plus a flat "Potion" item, at [member Equipment.price]/[constant
## POTION_PRICE]. Selling gear back pays half its price - loose, not tuned.

const POTION_PRICE := 10
const SELL_FRACTION := 0.5

@onready var _gold_label: Label = %GoldLabel
@onready var _buy_list: VBoxContainer = %BuyList
@onready var _sell_list: VBoxContainer = %SellList
@onready var _close_button: Button = %CloseButton


func _ready() -> void:
	_close_button.pressed.connect(close)
	_refresh()


func _refresh() -> void:
	_gold_label.text = "Gold: %d" % Party.gold
	_refresh_buy_list()
	_refresh_sell_list()


func _refresh_buy_list() -> void:
	for child in _buy_list.get_children():
		child.queue_free()

	_header(_buy_list, "For sale")
	_buy_row(_buy_list, "Potion", POTION_PRICE, _on_buy_potion)
	for item in Party.equipment_catalogue():
		_buy_row(_buy_list, item.display_name, item.price, _on_buy_equipment.bind(item.id))


func _refresh_sell_list() -> void:
	for child in _sell_list.get_children():
		child.queue_free()

	_header(_sell_list, "Sell")
	for item in Party.equipment_catalogue():
		var count := int(Party.owned_equipment.get(item.id, 0))
		if count <= 0:
			continue
		var price := roundi(item.price * SELL_FRACTION)
		_buy_row(_sell_list, "%s x%d" % [item.display_name, count], price,
			_on_sell_equipment.bind(item.id, price), "Sell")


func _buy_row(container: Container, label_text: String, price: int, callback: Callable,
		verb: String = "Buy") -> void:
	var row := HBoxContainer.new()
	var label := Label.new()
	label.text = "%s (%d g)" % [label_text, price]
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var button := Button.new()
	button.text = verb
	button.pressed.connect(callback)
	row.add_child(button)
	container.add_child(row)


func _on_buy_potion() -> void:
	if Party.gold < POTION_PRICE:
		return
	Party.add_gold(-POTION_PRICE)
	Party.add_item(&"potion")
	_refresh()


func _on_buy_equipment(item_id: StringName) -> void:
	var item: Equipment = null
	for candidate in Party.equipment_catalogue():
		if candidate.id == item_id:
			item = candidate
	if item == null or Party.gold < item.price:
		return
	Party.add_gold(-item.price)
	Party.owned_equipment[item_id] = int(Party.owned_equipment.get(item_id, 0)) + 1
	Party.changed.emit()
	_refresh()


func _on_sell_equipment(item_id: StringName, price: int) -> void:
	var count := int(Party.owned_equipment.get(item_id, 0))
	if count <= 0:
		return
	if count == 1:
		Party.owned_equipment.erase(item_id)
	else:
		Party.owned_equipment[item_id] = count - 1
	Party.add_gold(price)
	_refresh()


func _header(container: Container, text: String) -> void:
	var label := Label.new()
	label.text = text
	container.add_child(label)
