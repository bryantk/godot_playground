extends Node

## Headless assertions over [ActorNaming] - id generation, node renaming, and the
## idempotence that makes it safe to wire to a button.
##
##     godot --headless --path . res://tests/actor_naming_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("actors -- auto naming")
	print("")

	_test_ids()
	_test_names()
	_test_placement_root()
	_test_assign()
	_test_assign_all()
	_test_prefix()
	_test_rename_for()
	_test_setter_hook()
	_test_player()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- Ids -----------------------------------------------------------------------

func _test_ids() -> void:
	_section("next_id -- numbered from the ids already handed out")

	var empty := _map([])
	_eq(ActorNaming.count(empty), 0, "an empty map has no actors")
	_eq(ActorNaming.next_id(empty), &"event_0", "the first actor is event_0")
	empty.free()

	# Three actors, but zero ids handed out - so the next id is 0, not 3. Numbering from
	# the actor count instead would make every id in a fresh map off by the number of
	# actors in it, because the actor being named is itself in that count.
	var three := _map(["", "", ""])
	_eq(ActorNaming.count(three), 3, "three placed actors")
	_eq(ActorNaming.next_id(three), &"event_0", "  but no ids yet, so the next id is event_0")
	three.free()

	_section("  and searched upward, so a deletion cannot hand one out twice")

	# The case the count alone gets wrong: two actors remain, but the ids in use are
	# event_0 and event_2 because event_1 was deleted. Numbering from the count alone
	# would return event_2, which MapContext.register refuses at runtime.
	var gappy := _map(["event_0", "event_2"])
	_eq(ActorNaming.count(gappy), 2, "two ids in use")
	_eq(ActorNaming.next_id(gappy), &"event_3", "so the search skips the taken event_2")
	gappy.free()

	var crowded := _map(["event_0", "event_1", "event_2"])
	_eq(ActorNaming.next_id(crowded), &"event_3", "a full set counts past the end")
	crowded.free()

	# An unnamed actor must not make the empty string look taken.
	var mixed := _map(["player", ""])
	var ids := ActorNaming.existing_ids(mixed)
	_eq(ids.size(), 1, "existing_ids ignores the unnamed actor")
	_ok(ids.has(&"player"), "  and keeps the named one")
	mixed.free()


# -- Node names ----------------------------------------------------------------

func _test_names() -> void:
	_section("node_name_for -- the id appended after a double underscore")

	_eq(ActorNaming.node_name_for("Guard", &"event_3"), "Guard__event_3",
		"the id goes on the end after __")
	_eq(ActorNaming.node_name_for("Npc_17_9", &"event_1"), "Npc_17_9__event_1",
		"a name with single underscores is left alone")

	_section("  idempotence -- a second click changes nothing")

	# The whole reason strip_id exists: this is meant to be a button, and a button that
	# grows the name every time it is pressed is one nobody presses twice.
	var once := ActorNaming.node_name_for("Guard", &"event_3")
	var twice := ActorNaming.node_name_for(once, &"event_3")
	_eq(twice, "Guard__event_3", "naming an already-named node is a no-op")

	var renumbered := ActorNaming.node_name_for(once, &"event_5")
	_eq(renumbered, "Guard__event_5", "and a new id replaces the old rather than stacking")

	_eq(ActorNaming.strip_id("Guard__event_12"), "Guard", "strip_id takes any number")
	_eq(ActorNaming.strip_id("Guard"), "Guard", "and leaves a plain name alone")
	_eq(ActorNaming.strip_id("Guard_of_the_north"), "Guard_of_the_north",
		"a hand-written name with single underscores survives")
	_eq(ActorNaming.strip_id("Guard__event_3__event_4"), "Guard__event_3",
		"only the trailing id is stripped, one layer at a time")

	# The bug this caught: node_name_for only knew the generated __event_N shape, so an id
	# that does not look generated was re-appended on every pass. A second run over a map
	# produced Guard__npc_guard__npc_guard, and a third added another.
	_eq(ActorNaming.node_name_for("Guard__npc_guard", &"npc_guard"), "Guard__npc_guard",
		"a hand-typed id is idempotent too, not just a generated one")
	_eq(ActorNaming.node_name_for(
		ActorNaming.node_name_for("Guard", &"npc_guard"), &"npc_guard"),
		"Guard__npc_guard", "  applied twice in a row")

	_eq(ActorNaming.node_name_for("__event_3", &"event_4"), "Actor__event_4",
		"a node that was nothing but its id still gets a readable stem")


# -- Which node gets renamed ---------------------------------------------------

func _test_placement_root() -> void:
	_section("placement_root -- the placed instance, not the Actor inside it")

	# The real shape: an instance called Guard, with an Actor child always called Actor.
	# Renaming that child would put the id on the node nobody clicks in the scene tree.
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


# -- Assigning -----------------------------------------------------------------

func _test_assign() -> void:
	_section("assign -- id and node name together")

	var map := _map([""])
	var actor := ActorNaming.actors_under(map)[0]
	var body := actor.get_parent()

	var id := ActorNaming.assign(actor, map)
	_eq(id, &"event_0", "an unnamed actor is given the first free id")
	_eq(actor.actor_id, &"event_0", "  written to the actor")
	_eq(body.name, "Guard_0__event_0", "  and appended to the node name")
	map.free()

	_section("  an existing id is kept, because a graph may name it")

	# The failure this prevents: a pass over the map renames player to event_0, and every
	# graph that says @player stops resolving.
	var named := _map(["player"])
	var who := ActorNaming.actors_under(named)[0]
	var kept := ActorNaming.assign(who, named)
	_eq(kept, &"player", "assign leaves an authored id alone")
	_eq(who.actor_id, &"player", "  the actor keeps it")
	_eq(who.get_parent().name, "Player",
		"  and the node becomes plain Player, with nothing appended")
	named.free()

	_section("  overwrite renumbers, without colliding with itself")

	var forced := _map(["event_7"])
	var one := ActorNaming.actors_under(forced)[0]
	var fresh := ActorNaming.assign(one, forced, ActorNaming.DEFAULT_PREFIX, true)
	_eq(fresh, &"event_0", "overwrite renumbers from the ids in use")
	_ok(fresh != &"event_7", "  and its own old id did not block it")
	forced.free()

	_eq(ActorNaming.assign(null), &"", "a null actor is answered, not crashed on")


func _test_assign_all() -> void:
	_section("assign_all -- a whole map in one pass")

	var map := _map(["player", "", "", "npc_guard", ""])
	var named := ActorNaming.assign_all(map)

	# Five renames, not three: the two already-named actors keep their ids but still have
	# their nodes brought into line, which is the disagreement this class exists to stop.
	_eq(named.size(), 5, "every node was brought into line")

	var ids: Array[StringName] = []
	for who in ActorNaming.actors_under(map):
		ids.append(who.actor_id)

	_ok(ids.has(&"player") and ids.has(&"npc_guard"), "the authored ids survive")

	# The collision this pass has to avoid: ids handed out during the walk are not yet
	# visible to a fresh scan, so a naive implementation names two actors the same.
	var seen: Dictionary = {}
	var duplicate := false
	for id in ids:
		if seen.has(id):
			duplicate = true
		seen[id] = true
	_ok(not duplicate, "every id in the map is unique (%s)" % str(ids))
	_eq(ids.size(), 5, "  across all five actors")

	# Running it again must do nothing at all.
	var again := ActorNaming.assign_all(map)
	_eq(again.size(), 0, "a second pass names nothing")
	map.free()

	_eq(ActorNaming.assign_all(null).size(), 0, "a null root is answered, not crashed on")


func _test_prefix() -> void:
	_section("prefixes -- a bad one falls back rather than making a bad node name")

	var map := _map([""])
	var actor := ActorNaming.actors_under(map)[0]
	var id := ActorNaming.assign(actor, map, "chest")
	_eq(id, &"chest_0", "a custom prefix is used")
	_eq(actor.get_parent().name, "Guard_0__chest_0", "  and reaches the node name")
	map.free()

	# "@" is one of the characters Godot refuses in a node name, and it is the likely
	# mistake here, because @event_3 is how the id is written inside a command.
	var bad := _map([""])
	var who := ActorNaming.actors_under(bad)[0]
	var fallback := ActorNaming.assign(who, bad, "@event")
	_eq(fallback, &"event_0", "an illegal prefix falls back to the default")
	bad.free()



# -- The setter hook -----------------------------------------------------------

func _test_rename_for() -> void:
	_section("rename_for -- what the actor_id setter calls")

	var node := Node.new()
	node.name = "Guard"

	_eq(ActorNaming.rename_for(node, &"event_2"), "Guard__event_2",
		"a first id is appended")
	_eq(ActorNaming.rename_for(node, &"event_5", &"event_2"), "Guard__event_5",
		"a change replaces the old id rather than stacking")

	# The case strip_id alone cannot handle: a hand-typed id looks nothing like a
	# generated one, so only knowing what it was lets it be removed.
	node.name = "Guard__player"
	_eq(ActorNaming.rename_for(node, &"event_1", &"player"), "Guard__event_1",
		"moving away from a hand-typed id strips it exactly")

	node.name = "Guard__chest_2"
	_eq(ActorNaming.rename_for(node, &"chest_3", &"chest_2", "event"), "Guard__chest_3",
		"even when the id does not match the prefix in play")

	# Clearing the id takes the suffix off rather than leaving a dangling one.
	node.name = "Guard__event_4"
	_eq(ActorNaming.rename_for(node, &"", &"event_4"), "Guard",
		"clearing the id removes the suffix")

	node.name = "Guard__event_9"
	_eq(ActorNaming.rename_for(node, &"event_9", &"event_9"), "Guard__event_9",
		"setting the same id again changes nothing")

	_eq(ActorNaming.rename_for(null, &"event_0"), "", "null is answered, not crashed on")
	node.free()

	_section("  strip_exact")

	_eq(ActorNaming.strip_exact("Guard__player", &"player"), "Guard", "removes that id")
	_eq(ActorNaming.strip_exact("Guard__player", &"other"), "Guard__player",
		"and leaves a different one alone")
	_eq(ActorNaming.strip_exact("Guard", &""), "Guard", "an empty id removes nothing")


func _test_setter_hook() -> void:
	_section("Actor.actor_id -- the hook does NOT fire at run time")

	# This is the assertion that protects every demo script: they reach actors by node
	# path (`$Upscale/World/Map/Actors/Player/Actor`), so a rename on the frame an id is
	# set would break every @onready that names one. The rename is an authoring
	# convenience and is guarded by Engine.is_editor_hint(), which is false here.
	var map := _map(["player"])
	add_child(map)
	var actor := ActorNaming.actors_under(map)[0]
	var body := actor.get_parent()
	var before := body.name

	actor.actor_id = &"event_9"
	_eq(actor.actor_id, &"event_9", "the id changes at run time")
	_eq(body.name, before, "  but the node keeps its name (%s)" % before)

	remove_child(map)
	map.free()


func _test_player() -> void:
	_section("the player -- named Player, with nothing appended")

	_eq(ActorNaming.node_name_for("Guard", &"player"), "Player",
		"the id is not appended, and the old name is dropped entirely")
	_eq(ActorNaming.node_name_for("Anything_At_All", &"player"), "Player",
		"whatever the node was called")

	_section("  matched case-insensitively")

	_ok(ActorNaming.is_player_id(&"player"), "player")
	_ok(ActorNaming.is_player_id(&"Player"), "Player")
	_ok(ActorNaming.is_player_id(&"PLAYER"), "PLAYER")
	_ok(not ActorNaming.is_player_id(&"player_two"), "but not player_two")
	_ok(not ActorNaming.is_player_id(&"the_player"), "and not the_player")

	_eq(ActorNaming.node_name_for("Guard", &"Player"), "Player",
		"an id typed with a capital still gets the plain node name")

	_section("  through the setter path too")

	var node := Node.new()
	node.name = "Guard__event_3"
	_eq(ActorNaming.rename_for(node, &"player", &"event_3"), "Player",
		"promoting an actor to the player renames it Player")

	# And back out again. The stem is the bare "Player", so the result reads
	# Player__event_4 - which is honest about what the node used to be, and is one
	# hand-edit away from whatever the author would rather call it.
	_eq(ActorNaming.rename_for(node, &"event_4", &"player"), "Player__event_4",
		"and demoting it builds on the name it had")
	node.free()

	_section("  and through assign_all")

	var map := _map(["player", "", ""])
	ActorNaming.assign_all(map)

	var names: Array[String] = []
	for who in ActorNaming.actors_under(map):
		names.append(who.get_parent().name)

	_ok(names.has("Player"), "the player's node is Player (%s)" % str(names))
	_eq(ActorNaming.actors_under(map)[0].actor_id, &"player", "  and keeps its id")
	map.free()

# -- Helpers -------------------------------------------------------------------

## A map root holding one instance per entry in [param ids], shaped the way a real scene
## is: a container, an instance per actor, and an [Actor] child inside each.
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
