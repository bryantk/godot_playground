extends Node

## Headless assertions over the sprite-offset correction [Actor] pushes to its own
## view on [method Node._ready]: [member MapContext.actor_visual_offset] (a map-wide
## manual nudge, for when [member MapContext.map_cell_size] and [member
## MapContext.cell_size] disagree) summed with [method Actor.footprint_visual_offset]
## (automatic, from a multi-cell [member Actor.footprint] reading as centred on its
## anchor corner instead of its whole footprint).
##
## [b]Deliberately built with no [GameEvent] anywhere in the rig[/b] - this used to
## live there, and the regression it caused (the player, which has no [GameEvent] of
## its own, never got pushed a correction at all) is exactly what these prove does
## not happen from [Actor] instead.
##
##     godot --headless --path . res://tests/visual_offset_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("actors -- Actor's own pushed visual offset (map nudge + footprint centring)")
	print("")

	_test_default_footprint_and_no_map_offset_is_zero()
	_test_footprint_centres_the_sprite_on_the_whole_footprint()
	_test_map_offset_and_footprint_correction_both_apply()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_default_footprint_and_no_map_offset_is_zero() -> void:
	_section("visual_offset -- a plain 1x1x1 actor with no map offset gets none")

	var rig := _build(Vector3.ONE, Vector3i.ONE)
	_eq((rig["view"] as ActorView).visual_offset, Vector2.ZERO,
		"nothing to correct, nothing pushed")
	(rig["body"] as Node).free()


func _test_footprint_centres_the_sprite_on_the_whole_footprint() -> void:
	_section("visual_offset -- a 2x1x2 footprint at cell_size=8 shifts by half a cell, no GameEvent needed")

	var rig := _build(Vector3(8, 0, 8), Vector3i(2, 1, 2))
	_eq((rig["view"] as ActorView).visual_offset, Vector2(4, 4),
		"half of the one extra cell in each of X and Z")
	(rig["body"] as Node).free()


func _test_map_offset_and_footprint_correction_both_apply() -> void:
	_section("visual_offset -- MapContext.actor_visual_offset adds on top of the footprint term")

	var rig := _build(Vector3(8, 0, 8), Vector3i(2, 1, 2), Vector2(-1, 3))
	_eq((rig["view"] as ActorView).visual_offset, Vector2(3, 7),
		"the map's own manual nudge plus the automatic footprint correction")
	(rig["body"] as Node).free()


# -- Test rig ------------------------------------------------------------------------

## Builds one actor (with a real [SpriteView2D]/[Sprite2D] visual) - and nothing
## else beside it, matching the player's own real shape (an [Actor] under a
## [PlayerController], never a [GameEvent]) - on a [MapContext] with the given
## [param cell_size] and [param map_offset], and returns the pushed [ActorView] for
## inspection.
func _build(cell_size: Vector3, footprint: Vector3i, map_offset: Vector2 = Vector2.ZERO) -> Dictionary:
	var root := Node2D.new()
	add_child(root)

	var ctx := MapContext.new()
	ctx.map_id = &"visual_offset_test"
	ctx.cell_size = cell_size
	ctx.actor_visual_offset = map_offset
	root.add_child(ctx)

	# Built off-tree and added to root only once complete: the whole subtree then
	# enters the tree in one call, so every _enter_tree fires before any _ready does
	# (see tests/game_event_init_test.gd's own rig for the same reasoning) - added
	# to body piecemeal while body is already live would run Actor._ready() before
	# the View/Sprite it looks for even exist.
	var body := Node2D.new()
	body.name = "body"

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = &"who"
	actor.footprint = footprint
	body.add_child(actor)

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	body.add_child(sprite)

	var view := Node.new()
	view.set_script(load("res://actors/views/sprite_view_2d.gd"))
	view.name = "View"
	view.set("visual_path", NodePath("../Sprite"))
	actor.add_child(view)

	root.add_child(body)
	return {"body": body, "actor": actor, "view": view}


# -- Assertion helpers ---------------------------------------------------------------

func _section(title: String) -> void:
	print("  %s" % title)

func _eq(got: Variant, want: Variant, what: String) -> void:
	var same: bool = got == want
	print(("    ok    " if same else "    FAIL  ") + what
		+ ("" if same else "  (got %s, want %s)" % [got, want]))
	if same:
		_passed += 1
	else:
		_failed += 1
