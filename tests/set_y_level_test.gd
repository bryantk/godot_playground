extends Node

## Headless assertion that the `set_y_level` event command actually changes draw
## order, not just a number nobody reads.
##
##     godot --headless --path . res://tests/set_y_level_test.tscn
##
## [CanvasItem.z_index] is the mechanism Godot itself uses to decide what draws over
## what - a higher z_index always draws over a lower one, regardless of tree order
## (docs/CanvasItem.z_index). So "the behind sprite now draws on top" is exactly
## "the behind sprite's z_index is now the larger of the two", which this asserts
## before and after the command runs.

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("events -- the set_y_level command forces a behind sprite to draw on top")
	print("")

	_test_set_y_level_draws_behind_actor_on_top()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _test_set_y_level_draws_behind_actor_on_top() -> void:
	_section("set_y_level -- raising a behind actor's y_level puts it over the front one")

	var root := Node2D.new()
	add_child(root)

	var ctx := MapContext.new()
	ctx.map_id = &"test_map"
	ctx.cell_size = Vector3.ONE
	root.add_child(ctx)

	# "front" sits closer to the camera on screen (larger Y) and "behind" sits farther
	# back (smaller Y) - the ordinary y-sort would already draw front over behind, so
	# behind ending up on top can only be the command's own z_index push, not y-sort.
	var front := _build_sprite_actor(root, &"front", Vector2(0, 32))
	var behind := _build_sprite_actor(root, &"behind", Vector2(0, 0))

	_eq((front["sprite"] as Sprite2D).z_index, (behind["sprite"] as Sprite2D).z_index,
		"both start at the same z_index")

	var nodes: Array[Dictionary] = [
		{"id": "start", "command": "start", "args": {},
			"outputs": [{"flow": "next", "target": "lvl"}]},
		{"id": "lvl", "command": "set_y_level", "args": {"actor": "@behind", "y_level": 5},
			"outputs": [{"flow": "next", "target": ""}]},
	]

	var event_ctx := EventContext.for_event(ctx, &"test_map", &"y_level_test",
		front["actor"] as Actor)
	var runner := EventRunner.new(event_ctx)
	runner.begin(nodes)

	_ok(runner.finished, "the command runs to completion synchronously")
	_eq(runner.error, "", "with no error")

	var front_z: int = (front["sprite"] as Sprite2D).z_index
	var behind_z: int = (behind["sprite"] as Sprite2D).z_index
	_eq(behind_z, 5, "the behind actor's sprite picked up the new y_level")
	_ok(behind_z > front_z, "and now outranks the front actor's z_index, so it draws on top")


# -- Test rig ------------------------------------------------------------------------

## An actor wired up the way [code]actor_jrpg.tscn[/code] is: [Actor] and a
## [SpriteView2D] under a [Node2D] body, pointed at a [Sprite2D] sibling.
func _build_sprite_actor(root: Node, id: StringName, position: Vector2) -> Dictionary:
	var body := Node2D.new()
	body.name = str(id)
	body.position = position
	root.add_child(body)

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	body.add_child(sprite)

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = id
	body.add_child(actor)

	var view := Node.new()
	view.set_script(load("res://actors/views/sprite_view_2d.gd"))
	view.name = "View"
	view.set("visual_path", NodePath("../../Sprite"))
	actor.add_child(view)

	return {"actor": actor, "sprite": sprite, "view": view}


# -- Assertion helpers ---------------------------------------------------------------

func _section(title: String) -> void:
	print("  %s" % title)

func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1

func _eq(got: Variant, want: Variant, what: String) -> void:
	var same: bool = got == want
	print(("    ok    " if same else "    FAIL  ") + what
		+ ("" if same else "  (got %s, want %s)" % [got, want]))
	if same:
		_passed += 1
	else:
		_failed += 1
