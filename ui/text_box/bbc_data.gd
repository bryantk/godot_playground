@tool
class_name BBC_Data
extends RichTextEffect

## Data-carrying BBCode for [RichTextBlock].
##
## Format:  [dc {hash}] ... [/dc]
## The tag itself is invisible; it only carries data read by the owning block.
##
## Supported hash options:
##   wait : float  — seconds the typewriter pauses when it reaches this tag.
##
## Example:  "Hold on[dc wait=0.75].[/dc][dc wait=0.75].[/dc] here it is!"

const WAIT_TAG = &'wait'
## Key added to the data dict holding the glyph count wrapped by the [dc ..] tag.
const LENGTH_TAG = &'length'

# The BBCode tag name. Godot matches [dc ...] against this string.
var bbcode := &"dc"

# Set by the owning RichTextBlock so parsed data can be pushed back to it.
# Left untyped to avoid a circular class_name dependency with RichTextBlock.
var block

# Tag regions already registered this display, keyed by start glyph index.
# Each value is the tag's parsed attribute dictionary (a copy of char_fx.env).
# _process_custom_fx runs every frame per glyph, so this keeps register once.
var _registered: Dictionary = {}


## Clear the once-per-tag tracking. Called by the block when new text is shown.
func reset() -> void:
	_registered.clear()

## The parsed attributes of the [dc ..] tag that begins at [param index],
## or an empty dictionary if no tag starts there.
func data_at(index: int) -> Dictionary:
	if _registered.has(index):
		return _registered[index]
	return {}

func _process_custom_fx(char_fx: CharFXTransform) -> bool:
	if block == null:
		return true
	# Called every frame for every glyph in the region. range.x is that glyph's
	# absolute index and relative_index is its offset from the tag start, so the
	# region start is range.x - relative_index. char_fx.range spans a single glyph
	# (width 1), so length can't be read from it directly — instead we grow it as
	# glyphs with higher relative_index arrive: length = max(relative_index) + 1.
	var start := char_fx.range.x - char_fx.relative_index
	if not _registered.has(start):
		_registered[start] = char_fx.env.duplicate()
	var span := char_fx.relative_index + 1
	if span > int(_registered[start].get(LENGTH_TAG, 0)):
		_registered[start][LENGTH_TAG] = span
	return true
