@tool
extends VBoxContainer

## A dock for picking one exact frame off a sprite sheet texture by clicking a cell in a
## grid overlay, rather than counting frames by hand.
##
## Owns no opinion about *what* the pick is for - [method request_pick] hands it a
## texture and a grid size and arms a one-shot callback for the next click, so two
## different callers (the page art inspector's "Pick Frame" button today, a graph
## node's own row/col arguments later) can each ask for a pick without stepping on each
## other. [method show_sheet] alone, with no callback, just previews a texture - what
## opening the dock cold, or switching the hframes/vframes spinboxes, does.
##
## Feeds the same (row, col) address [code]hold_frame[/code]/[code]set_sheet[/code]
## (events/event_command.gd) and a page's [code]art.frame_row[/code]/[code]frame_col[/code]
## (see [method GraphEditorPanel._build_page_inspector]) already use - this is the one
## place that address is chosen by eye instead of typed in.
##
## [b]A pick also assumes a facing[/b], from [param facing_offsets] - the same array
## [SpriteSheet]/[SpriteSheet3D] read to turn a facing into a row (a negative entry
## means "this row, mirrored"). A shared row (this project's default [code][0, -2, 1,
## 2][/code] mirrors one side-on row into both Left and Right) draws as [b]two[/b]
## rows here, one of them flipped for real - see [method _rebuild_display_rows] - so
## clicking either half of the pair reads back the correct facing token and
## [code]flip[/code] together, rather than a raw row number an author has to know is
## shared.

signal frame_picked(row: int, col: int, facing: String, flip: bool)

## How large one sheet pixel draws as, so a small sheet (this project's actors are
## 3x3 grids of a few dozen pixels a cell) is not a postage stamp in the dock.
const ZOOM := 4.0

## [SpriteSheet]'s own script default, and what every actor prefab in this project
## (games/jrpg/actor_jrpg.tscn, both isoish ones) leaves unoverridden - the fallback
## used whenever a caller does not know a more specific one either.
const DEFAULT_FACING_OFFSETS: Array = [0, -2, 1, 2]

## Display labels for [enum FacingUtils.Facings], index-matched - mirrors the comment
## every [member facing_offsets] carries ("DOWN, RIGHT, UP, LEFT order").
const _FACING_LABELS: PackedStringArray = ["Down", "Right", "Up", "Left"]

## [FacingUtils.FROM_COMPASS]'s own index order (Space's N, E, S, W) - reversing that
## array is how a screen-relative facing becomes the compass token [code]art.facing[/code]
## and [code]set_sheet[/code]'s own [code]facing[/code] argument both expect.
const _COMPASS_ORDER: PackedStringArray = ["n", "e", "s", "w"]

var _texture_picker: EditorResourcePicker
var _hframes_spin: SpinBox
var _vframes_spin: SpinBox
var _grid: Control
var _readout: Label

var _texture: Texture2D = null
var _hframes := 3
var _vframes := 3
var _facing_offsets: Array = DEFAULT_FACING_OFFSETS.duplicate()

## The current selection. [member _row]/[member _col] are always the real sheet
## coordinates [code]hold_frame[/code] wants; [member _facing] is the
## [enum FacingUtils.Facings] value [member _facing_offsets] maps that row to (-1 if
## none does), and [member _flip] is which of a shared row's two entries was clicked -
## see [method _rebuild_display_rows].
var _row := 0
var _col := 0
var _facing := -1
var _flip := false

## One entry per drawn row - more than [member _vframes] whenever a row is shared by
## two facings (see [method _rebuild_display_rows]), each
## [code]{physical: int, flip: bool, facing: int}[/code].
var _display_rows: Array = []

## Armed by [method request_pick], consumed by the next click - see [method
## _on_grid_gui_input].
var _callback: Callable = Callable()


func _init() -> void:
	name = "Frames"


func _ready() -> void:
	if get_child_count() == 0:
		_build_ui()


func _build_ui() -> void:
	custom_minimum_size = Vector2(260, 0)

	var sheet_row := HBoxContainer.new()
	add_child(sheet_row)

	_texture_picker = EditorResourcePicker.new()
	_texture_picker.base_type = "Texture2D"
	_texture_picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_texture_picker.tooltip_text = "The sprite sheet to pick a frame from."
	_texture_picker.resource_changed.connect(_on_texture_changed)
	sheet_row.add_child(_texture_picker)

	var frames_row := HBoxContainer.new()
	add_child(frames_row)

	frames_row.add_child(Label.new())
	(frames_row.get_child(-1) as Label).text = "H:"
	_hframes_spin = SpinBox.new()
	_hframes_spin.min_value = 1
	_hframes_spin.max_value = 64
	_hframes_spin.value = _hframes
	_hframes_spin.tooltip_text = "Columns in the sheet (Sprite2D/3D's own hframes)."
	_hframes_spin.value_changed.connect(_on_hframes_changed)
	frames_row.add_child(_hframes_spin)

	frames_row.add_child(Label.new())
	(frames_row.get_child(-1) as Label).text = "V:"
	_vframes_spin = SpinBox.new()
	_vframes_spin.min_value = 1
	_vframes_spin.max_value = 64
	_vframes_spin.value = _vframes
	_vframes_spin.tooltip_text = "Rows in the sheet (Sprite2D/3D's own vframes)."
	_vframes_spin.value_changed.connect(_on_vframes_changed)
	frames_row.add_child(_vframes_spin)

	var scroll := ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(scroll)

	_grid = Control.new()
	_grid.name = "Grid"
	_grid.draw.connect(_on_grid_draw)
	_grid.gui_input.connect(_on_grid_gui_input)
	scroll.add_child(_grid)

	_readout = Label.new()
	_readout.text = "Row 0, Col 0"
	add_child(_readout)


## Preview [param texture] laid out as [param hframes] columns by [param vframes] rows,
## against [param facing_offsets] (defaulting to [constant DEFAULT_FACING_OFFSETS]),
## with no pick armed - what switching the spinboxes, or a caller that only wants to
## show a sheet, does.
func show_sheet(
		texture: Texture2D, hframes: int, vframes: int,
		facing_offsets: Array = DEFAULT_FACING_OFFSETS) -> void:
	_texture = texture
	_hframes = maxi(1, hframes)
	_vframes = maxi(1, vframes)
	_facing_offsets = facing_offsets
	if is_instance_valid(_texture_picker):
		_texture_picker.edited_resource = texture
	if is_instance_valid(_hframes_spin):
		_hframes_spin.set_value_no_signal(_hframes)
	if is_instance_valid(_vframes_spin):
		_vframes_spin.set_value_no_signal(_vframes)
	_row = clampi(_row, 0, _vframes - 1)
	_col = clampi(_col, 0, _hframes - 1)
	_resize_grid()
	_update_readout()


## Preloads [param texture]/[param hframes]/[param vframes]/[param facing_offsets] and
## arms [param callback] for the very next cell click - called once, with the row,
## column, assumed facing token ("" if the row clicked maps to none) and whether that
## row was the flipped half of a shared pair, then discarded. A second
## [method request_pick] before any click replaces the pending one rather than queuing
## both.
func request_pick(
		texture: Texture2D, hframes: int, vframes: int, callback: Callable,
		facing_offsets: Array = DEFAULT_FACING_OFFSETS) -> void:
	show_sheet(texture, hframes, vframes, facing_offsets)
	_callback = callback


func selected_frame() -> Vector2i:
	return Vector2i(_row, _col)


## Groups [member _facing_offsets] by the physical row each resolves to
## ([code]abs(offset)[/code]), then walks every physical row in order: a row nothing
## maps to draws once, plain; a row exactly one facing maps to draws once, in that
## facing's own orientation (still flipped, if that lone offset happens to be
## negative); a row *two* facings share (the default's Left/Right pair) draws
## [b]twice[/b] - the direct one first, its mirror second - so the pair is visibly two
## distinct, clickable choices instead of one ambiguous row.
func _rebuild_display_rows() -> void:
	var by_row: Dictionary = {}
	for facing in range(_facing_offsets.size()):
		var offset := int(_facing_offsets[facing])
		var physical := absi(offset)
		if physical >= _vframes:
			continue
		var uses: Array = by_row.get(physical, [])
		uses.append({"facing": facing, "flip": offset < 0})
		by_row[physical] = uses

	_display_rows.clear()
	for physical in range(_vframes):
		var uses: Array = by_row.get(physical, [])
		if uses.is_empty():
			_display_rows.append({"physical": physical, "flip": false, "facing": -1})
			continue
		uses.sort_custom(func(a, b) -> bool: return int(a["flip"]) < int(b["flip"]))
		for use in uses:
			_display_rows.append(
				{"physical": physical, "flip": use["flip"], "facing": use["facing"]})


## Keeps the current selection valid after the sheet, grid size or facing offsets
## change - preferring whatever [member _row]/[member _flip] already were if that exact
## pairing still exists, falling back to the row's other entry, then to the first
## display row of all.
func _sync_selection() -> void:
	if _display_rows.is_empty():
		_facing = -1
		_flip = false
		return

	for row in _display_rows:
		if row["physical"] == _row and row["flip"] == _flip:
			_facing = row["facing"]
			return
	for row in _display_rows:
		if row["physical"] == _row:
			_flip = row["flip"]
			_facing = row["facing"]
			return

	var first: Dictionary = _display_rows[0]
	_row = first["physical"]
	_flip = first["flip"]
	_facing = first["facing"]


func _cell_size() -> Vector2:
	if _texture == null:
		return Vector2.ZERO
	return Vector2(
		_texture.get_width() * ZOOM / float(_hframes),
		_texture.get_height() * ZOOM / float(_vframes))


func _resize_grid() -> void:
	_rebuild_display_rows()
	_sync_selection()
	if _texture == null:
		_grid.custom_minimum_size = Vector2.ZERO
	else:
		var cell := _cell_size()
		_grid.custom_minimum_size = Vector2(cell.x * _hframes, cell.y * _display_rows.size())
	_grid.queue_redraw()


func _on_texture_changed(resource: Resource) -> void:
	show_sheet(resource as Texture2D, _hframes, _vframes, _facing_offsets)


func _on_hframes_changed(value: float) -> void:
	_hframes = maxi(1, int(value))
	_col = clampi(_col, 0, _hframes - 1)
	_resize_grid()
	_update_readout()


func _on_vframes_changed(value: float) -> void:
	_vframes = maxi(1, int(value))
	_row = clampi(_row, 0, _vframes - 1)
	_resize_grid()
	_update_readout()


func _on_grid_gui_input(event: InputEvent) -> void:
	if _texture == null or not (event is InputEventMouseButton):
		return
	var mouse := event as InputEventMouseButton
	if not mouse.pressed or mouse.button_index != MOUSE_BUTTON_LEFT:
		return

	var cell := _cell_size()
	if cell.x <= 0 or cell.y <= 0 or _display_rows.is_empty():
		return

	var display_index := clampi(int(mouse.position.y / cell.y), 0, _display_rows.size() - 1)
	var row: Dictionary = _display_rows[display_index]
	_col = clampi(int(mouse.position.x / cell.x), 0, _hframes - 1)
	_row = row["physical"]
	_flip = row["flip"]
	_facing = row["facing"]
	_grid.queue_redraw()
	_update_readout()

	var token := _compass_token(_facing)
	frame_picked.emit(_row, _col, token, _flip)
	if _callback.is_valid():
		var callback := _callback
		_callback = Callable()
		callback.call(_row, _col, token, _flip)


func _on_grid_draw() -> void:
	var cell := _cell_size()
	if _texture == null or cell.x <= 0 or cell.y <= 0:
		return

	var row_height_tex := _texture.get_height() / float(_vframes)
	for i in range(_display_rows.size()):
		var row: Dictionary = _display_rows[i]
		var src := Rect2(0, row["physical"] * row_height_tex, _texture.get_width(), row_height_tex)
		var dst := Rect2(0, i * cell.y, cell.x * _hframes, cell.y)
		if row["flip"]:
			dst.position.x += dst.size.x
			dst.size.x = -dst.size.x
		_grid.draw_texture_rect_region(_texture, dst, src)

	var line_color := Color(1, 1, 1, 0.35)
	for c in range(_hframes + 1):
		var x := c * cell.x
		_grid.draw_line(Vector2(x, 0), Vector2(x, _display_rows.size() * cell.y), line_color)
	for r in range(_display_rows.size() + 1):
		var y := r * cell.y
		_grid.draw_line(Vector2(0, y), Vector2(_hframes * cell.x, y), line_color)

	var font := get_theme_default_font()
	var font_size := get_theme_default_font_size()
	for i in range(_display_rows.size()):
		var label := _row_label(_display_rows[i])
		if label != "":
			_grid.draw_string(font, Vector2(4, i * cell.y + font_size + 2), label,
				HORIZONTAL_ALIGNMENT_LEFT, -1, font_size, Color(1, 0.95, 0.6))

	var selected_index := _selected_display_index()
	if selected_index >= 0:
		_grid.draw_rect(
			Rect2(_col * cell.x, selected_index * cell.y, cell.x, cell.y),
			Color(1, 0.9, 0.2, 0.9), false, 2.0)


func _selected_display_index() -> int:
	for i in range(_display_rows.size()):
		var row: Dictionary = _display_rows[i]
		if row["physical"] == _row and row["flip"] == _flip:
			return i
	return -1


func _row_label(row: Dictionary) -> String:
	if row["facing"] < 0:
		return ""
	var label: String = _FACING_LABELS[row["facing"]]
	return "%s (flip)" % label if row["flip"] else label


## The compass token ("n"/"e"/"s"/"w") [param facing] - an [enum FacingUtils.Facings]
## value - resolves to, the reverse of [method FacingUtils.from_compass]. "" for -1
## (the row picked maps to no facing).
func _compass_token(facing: int) -> String:
	if facing < 0:
		return ""
	var index := FacingUtils.FROM_COMPASS.find(facing)
	return _COMPASS_ORDER[index] if index >= 0 else ""


func _update_readout() -> void:
	var token := _compass_token(_facing)
	var suffix := ""
	if token != "":
		suffix = " - facing %s%s" % [token, " (flipped)" if _flip else ""]
	_readout.text = "Row %d, Col %d%s" % [_row, _col, suffix]
