extends Node

## Headless assertions over [ActorNaming] (reading a map, finding a placement root) and
## [Actor]'s own [member Actor.actor_id] derivation, which replaced the id generation
## and node renaming this file used to cover.
##
##     godot --headless --path . res://tests/actor_naming_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("actors -- naming and id derivation")
	print("")

	_test_actors_under_and_count()
	_test_existing_ids()
	_test_placement_root()
	_test_id_derives_from_parent_name()
	_test_id_keeps_a_name_with_no_separator()
	_test_id_never_overwrites_one_already_set()
	_test_player()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- Reading a map ---------------------------------------------------------------

func _test_actors_under_and_count() -> void:
	_section("actors_under / count -- every Actor in a tree, regardless of id")

	var empty := _map([])
	_eq(ActorNaming.count(empty), 0, "an empty map has no actors")
	empty.free()

	var three := _map(["", "", ""])
	_eq(ActorNaming.count(three), 3, "three placed actors, none of them named")
	_eq(ActorNaming.actors_under(three).size(), 3, "actors_under agrees")
	three.free()


func _test_existing_ids() -> void:
	_section("existing_ids -- the ids already taken, ignoring an unnamed actor")

	var mixed := _map(["player", ""])
	var ids := ActorNaming.existing_ids(mixed)
	_eq(ids.size(), 1, "existing_ids ignores the unnamed actor")
	_ok(ids.has(&"player"), "  and keeps the named one")
	mixed.free()


# -- Which node an id belongs on ---------------------------------------------------

func _test_placement_root() -> void:
	_section("placement_root -- the placed instance, not the Actor inside it")

	# The real shape: an instance called Guard, with an Actor child always called Actor.
	var container := Node.new()
	container.name = "Actors"
	var body := Node.new()
	body.name = "Guard"
	body.scene_file_path = "res://games/jrpg/actor_jrpg.tscn"
	var actor := Actor.new()
	actor.name = "Actor"
	body.add_child(actor)
	container.add_child(body)

	_eq(ActorNaming.placement_root(actor), body, "the instance is the placement root")

	# Hand-built, with no instance anywhere above it: naming the container would rename
	# every sibling's parent, so the actor names itself instead.
	var loose := Actor.new()
	loose.name = "Loose"
	container.add_child(loose)
	_eq(ActorNaming.placement_root(loose), loose,
		"with no instance above it, the actor is its own placement root")

	_eq(ActorNaming.placement_root(null), null, "and null is answered, not crashed on")
	container.free()


# -- Actor.actor_id's own derivation -------------------------------------------------

## [method Actor._id_from_parent_name] fires the moment the actor enters a live tree
## ([method Node._enter_tree]), so these build the placement, then [code]add_child[/code]
## it here rather than only constructing it - unlike [method _map]'s own helper, which
## never adds its map to a live tree and so never triggers it (see that method's own
## doc).
func _test_id_derives_from_parent_name() -> void:
	_section("Actor.actor_id -- derives from the placement root's own name, minus __ and trailing")

	var placement := Node.new()
	placement.name = "Npc_17_9__npc_greeting"
	var actor := Actor.new()
	placement.add_child(actor)

	add_child(placement)
	_eq(actor.actor_id, &"npc_17_9",
		"the descriptive suffix after __ is dropped, and the rest lower-cased")

	remove_child(placement)
	placement.free()


func _test_id_keeps_a_name_with_no_separator() -> void:
	_section("Actor.actor_id -- a name with no __ at all still lower-cases")

	var placement := Node.new()
	placement.name = "MapTransfer"
	var actor := Actor.new()
	placement.add_child(actor)

	add_child(placement)
	_eq(actor.actor_id, &"maptransfer", "nothing to strip, so the whole name becomes the id")

	remove_child(placement)
	placement.free()


func _test_id_never_overwrites_one_already_set() -> void:
	_section("Actor.actor_id -- derivation only ever fills in a still-blank id")

	var placement := Node.new()
	placement.name = "Npc_1_1__whatever"
	var actor := Actor.new()
	actor.actor_id = &"hand_typed"
	placement.add_child(actor)

	add_child(placement)
	_eq(actor.actor_id, &"hand_typed",
		"an id set before entering the tree survives - GameEvent's own push relies on this")

	remove_child(placement)
	placement.free()


func _test_player() -> void:
	_section("the player -- Player's own node name lower-cases to exactly is_player()'s fallback")

	var placement := Node.new()
	placement.name = "Player"
	var actor := Actor.new()
	placement.add_child(actor)

	add_child(placement)
	_eq(actor.actor_id, &"player", "derived and lower-cased, matching is_player()'s own check")
	_ok(actor.is_player(), "so is_player()'s id fallback is true with no PlayerController at all")

	remove_child(placement)
	placement.free()

	_section("  a hand-typed id still works, same as it always did")

	var placement2 := Node.new()
	placement2.name = "SomethingElse"
	var actor2 := Actor.new()
	actor2.actor_id = &"player"
	placement2.add_child(actor2)

	add_child(placement2)
	_ok(actor2.is_player(), "is_player() is true regardless of the node's own name")
	_eq(actor2.actor_id, &"player", "and derivation left the hand-typed id alone")

	remove_child(placement2)
	placement2.free()


# -- Helpers -------------------------------------------------------------------

## A map root holding one instance per entry in [param ids], shaped the way a real scene
## is: a container, an instance per actor, and an [Actor] child inside each.
##
## [b]Never added to a live tree[/b] - every id here is exactly what [param ids] says,
## whether blank or not, because [method Actor._enter_tree] (where derivation happens)
## never fires for a node that is never part of the live [SceneTree]. Tests that need
## derivation itself build their own placement and [code]add_child[/code] it instead -
## see [method _test_id_derives_from_parent_name].
func _map(ids: Array) -> Node:
	var root := Node.new()
	root.name = "Map"
	var container := Node.new()
	container.name = "Actors"
	root.add_child(container)

	for i in ids.size():
		var body := Node.new()
		body.name = "Guard_%d" % i
		# Set rather than instanced, so the test needs no scene file on disk.
		body.scene_file_path = "res://games/jrpg/actor_jrpg.tscn"
		var actor := Actor.new()
		actor.name = "Actor"
		actor.actor_id = StringName(str(ids[i]))
		body.add_child(actor)
		container.add_child(body)

	return root


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
