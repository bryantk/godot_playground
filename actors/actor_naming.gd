class_name ActorNaming

## Gives a placed actor an id, and puts that id in the node's name.
##
## [b]The problem this solves.[/b] Every actor needs a map-unique [member Actor.actor_id]
## or [method MapContext.register] refuses it, and an event graph addresses actors by
## that id - so an unnamed actor is invisible to every command that would drive it. Left
## to hand-typing, the failure is silent at authoring time and confusing at runtime: two
## guards both called [code]""[/code] look identical in the inspector, and the second one
## to load is the one that fails.
##
## [b]Generated ids are plain numbers[/b] - [code]1[/code], [code]2[/code],
## [code]3[/code] - because that is what most actors need: a handle that is unique and
## short, written [code]@1[/code] in a command. An actor that earns a real name gets one
## typed by hand ([code]player[/code], [code]north_door[/code]), and this never
## overwrites it.
##
## [b]Two halves, deliberately.[/b] The id is data the game reads; the node name is for
## the person looking at the scene tree. Assigning one without the other is what makes a
## map where the inspector and the tree disagree about which guard is which, so
## [method assign] always does both.
##
## [b]Idempotent.[/b] Re-running over a map that has already been named changes nothing
## and stacks no suffixes - [code]Event__3[/code] does not become [code]Event__3__3[/code].
## That matters because this is meant to be wired to an editor button, and a button that
## punishes a second click is a button nobody trusts.
##
## Static and UI-free, so an [code]@tool[/code] script in the editor and a test in a
## headless run reach it the same way.

## What separates a node's name from the id appended to it.
##
## Doubled so it cannot be confused with the single underscores inside a name that
## already has them - [code]north_door__4[/code] is unambiguous about where the id
## starts, where [code]north_door_4[/code] would not be.
const SEPARATOR := "__"

## Generated ids start here and count up. One rather than zero because these are read and
## typed by a person, and the third actor placed being [code]3[/code] is the whole appeal
## of numbering them at all.
const FIRST_ID := 1

## What a node is called before its number, when it has nothing better.
##
## A freshly placed prefab is called whatever the prefab is - [code]ActorIsoish[/code] -
## which says what it was instanced from and nothing about what it is in this map. The
## first time an actor is given a generated id, its node becomes [code]event__3[/code]
## instead.
##
## [b]Only the first time.[/b] Once an actor has an id, later renames keep whatever stem
## the node has, so a node deliberately called [code]Guard[/code] stays
## [code]Guard__4[/code] rather than being flattened back to the default on every edit.
const DEFAULT_STEM := "event"

## True when [param id] is one of the generated numbers rather than a hand-typed name.
## A name is a deliberate act and keeps its node's stem; a number is not.
static func is_number_id(id: StringName) -> bool:
	var text := String(id)
	return text != "" and text.is_valid_int()

## The one actor whose node is named [i]for[/i] its id rather than after it.
##
## Every other actor reads [code]Event__3[/code], because the number is the only thing
## telling two of them apart. There is exactly one player, its id is the one an author
## types from memory, and [code]Player__player[/code] says the same word twice for no
## gain - so the player's node is simply [code]Player[/code].
##
## It is also the name the three demo scenes already use, so this matches what a
## hand-authored map does rather than imposing something new on it.
const PLAYER_ID := &"player"
const PLAYER_NODE_NAME := "Player"

## True when [param id] names the player, compared case-insensitively.
##
## [b]The comparison is loose and the id is left alone.[/b] An author who types
## [code]Player[/code] means the player and should get a node called [code]Player[/code];
## rewriting their id to lower case as well would be a second, silent edit they did not
## ask for. Worth knowing, though: a graph that says [code]@player[/code] will not resolve
## an actor whose id is [code]Player[/code], because ids themselves are matched exactly.
static func is_player_id(id: StringName) -> bool:
	return String(id).to_lower() == String(PLAYER_ID)


# -- Reading a map -------------------------------------------------------------

## Every [Actor] under [param root], in tree order.
##
## The tree rather than [MapContext] because this runs in the editor, where nothing has
## called [method Actor._ready] and the context's registry is empty. At runtime the two
## agree, so the tree is the answer that works in both places.
static func actors_under(root: Node) -> Array[Actor]:
	var found: Array[Actor] = []
	if root == null:
		return found
	_collect(root, found)
	return found


static func _collect(node: Node, into: Array[Actor]) -> void:
	if node is Actor:
		into.append(node as Actor)
	for child in node.get_children():
		_collect(child, into)


## How many actors are placed under [param root].
static func count(root: Node) -> int:
	return actors_under(root).size()


## The ids already taken under [param root], as a set. An actor with no id contributes
## nothing, which is what lets an unnamed actor be given the first free number rather
## than colliding with the empty string.
static func existing_ids(root: Node) -> Dictionary:
	var taken: Dictionary = {}
	for who in actors_under(root):
		if who.actor_id != &"":
			taken[who.actor_id] = true
	return taken


# -- Generating an id ----------------------------------------------------------

## The lowest free number under [param root], as a [StringName].
##
## [b]It fills gaps rather than counting past the end.[/b] With 1, 2 and 4 in use the
## next id is 3, because an author reading a map expects the numbers to be the small
## contiguous set they look like, and a map edited for an hour should not be numbered
## into the forties.
##
## [b]The cost, stated rather than discovered:[/b] a number can be reused. Delete the
## actor called 3 and place another, and the new one is also 3 - so a graph that still
## says [code]@3[/code] now drives the new actor instead of failing to find the old one.
## An actor referenced across a map is one that has earned a real name, which is what
## hand-typed ids are for.
static func next_id(root: Node) -> StringName:
	return next_id_avoiding(existing_ids(root))


## [method next_id] against a caller's own set, for naming several actors in one pass
## without re-walking the tree between each.
static func next_id_avoiding(taken: Dictionary) -> StringName:
	var n := FIRST_ID
	while taken.has(StringName(str(n))):
		n += 1
	return StringName(str(n))


# -- Node names ----------------------------------------------------------------

## The node an id belongs on: the placed scene instance, not the [Actor] inside it.
##
## Actors are placed as instances of one prefab - [code]Player[/code],
## [code]Event__2[/code] - each with an [Actor] child that is always just called
## [code]Actor[/code]. Renaming that child would put the id on the node nobody picks in
## the scene tree, so this walks up to the nearest ancestor that is its own scene
## instance and names that instead.
##
## Falls back to the actor itself when nothing above it is an instance, which is the
## hand-built case: better to name the actor than to rename the container it happens to
## sit in and take every sibling's parent with it.
static func placement_root(actor: Actor) -> Node:
	if actor == null:
		return null

	var node: Node = actor
	while node != null:
		if node.scene_file_path != "":
			return node
		node = node.get_parent()
	return actor


## [param base] with [param id] appended, having first removed any id already there.
##
## The strip is what makes a second click harmless, and it removes two things: the id
## being applied, and any trailing number. Without the first, an id that is not a number -
## [code]north_door[/code] - is re-appended on every pass, so a second run over a map
## produces [code]Door__north_door__north_door[/code] and a third adds another.
##
## [b]The player is the exception[/b] and gets [constant PLAYER_NODE_NAME] with nothing
## appended - see [constant PLAYER_ID]. The base is discarded entirely in that case, so a
## node called anything at all becomes [code]Player[/code] the moment it is given that id.
static func node_name_for(base: String, id: StringName) -> String:
	if is_player_id(id):
		return PLAYER_NODE_NAME

	var stem := strip_id(strip_exact(base, id))
	if stem == "":
		# A node called nothing but its old id still deserves a readable name.
		stem = "Actor"
	return "%s%s%s" % [stem, SEPARATOR, id]


## [param name] with a trailing generated id - the separator and digits - removed. Any
## other name is returned unchanged, so a hand-named [code]Guard_of_the_north[/code]
## survives, and so does a name whose id is a word rather than a number.
static func strip_id(name: String) -> String:
	var expression := RegEx.new()
	expression.compile("%s[0-9]+$" % SEPARATOR)
	return expression.sub(name, "", false)


## [param name] with a trailing [code]__<id>[/code] removed, for one specific id.
##
## [method strip_id] only knows the generated shape - the separator and digits - so it
## cannot remove an id that is a word. Renaming away from one would stack:
## [code]Door__north_door__side_door[/code]. Knowing the id being replaced avoids it, and
## a hook that fires on every change to an id always knows that.
static func strip_exact(name: String, id: StringName) -> String:
	if id == &"":
		return name
	return name.trim_suffix("%s%s" % [SEPARATOR, id])


## Renames [param node] for [param id], removing [param previous] first. Returns the name
## the node ended up with.
##
## Does nothing when the result would be identical, so an edit that changes nothing does
## not mark the scene dirty.
static func rename_for(node: Node, id: StringName, previous: StringName = &"") -> String:
	if node == null:
		return ""

	var stem := strip_exact(node.name, previous)
	# An actor getting its first id has no stem worth keeping - the node is still named
	# after the prefab it came from. One that already had an id does, so it keeps it.
	if previous == &"" and is_number_id(id) and strip_id(stem) == stem:
		stem = DEFAULT_STEM
	var wanted := node_name_for(stem, id) if id != &"" else strip_id(stem)
	if wanted == "":
		wanted = "Actor"
	if node.name != wanted:
		node.name = wanted
	return node.name



## The name to build on. [constant DEFAULT_STEM] for an actor whose id was just
## generated and whose node is still called after the prefab it came from; otherwise the
## node's own name, so a deliberate one survives.
static func _base_for(node: Node, id: StringName, generated: bool) -> String:
	if generated and is_number_id(id) and strip_id(node.name) == node.name:
		return DEFAULT_STEM
	return node.name

# -- Assigning -----------------------------------------------------------------

## Gives [param actor] an id and renames its placement node to match.
##
## Returns the id the actor ended up with, or [code]&""[/code] if it was left alone.
##
## [param root] is the scene to check against - the edited scene in the editor, the map
## at runtime. Left null, the actor's own scene root is used.
##
## [b]An actor that already has an id keeps it[/b] unless [param overwrite] is true. That
## is what stops a pass over the map renaming [code]player[/code] to [code]1[/code] and
## breaking every graph that names it. The node is still renamed to match, because an
## actor whose id and node name disagree is the thing this exists to prevent.
static func assign(actor: Actor, root: Node = null, overwrite: bool = false) -> StringName:
	if actor == null:
		return &""
	if root == null:
		root = actor.owner if actor.owner != null else actor.get_tree().current_scene \
			if actor.is_inside_tree() else actor

	var id := actor.actor_id
	var generated := false
	if id == &"" or overwrite:
		var taken := existing_ids(root)
		# Its own current id must not block it from being renumbered.
		taken.erase(actor.actor_id)
		id = next_id_avoiding(taken)
		actor.actor_id = id
		generated = true

	var node := placement_root(actor)
	if node != null:
		node.name = node_name_for(_base_for(node, id, generated), id)
	return id


## Brings every actor under [param root] into line, in tree order: an id for the ones
## without one, and a matching node name for all of them.
##
## Returns [code]{actor_id: node_name}[/code] for every node it renamed, so a caller can
## report what it did rather than the author having to diff the scene to find out. A map
## that is already in order returns an empty dictionary, which makes a second run a
## visible no-op rather than a silent one.
##
## The taken-set is built once and added to as it goes, rather than re-walked per actor:
## the ids handed out in this pass are not yet visible to a fresh [method existing_ids]
## in the order this runs, and two actors both called [code]3[/code] is exactly the
## collision the numbering exists to avoid.
static func assign_all(root: Node, overwrite: bool = false) -> Dictionary:
	var changed: Dictionary = {}
	if root == null:
		return changed

	var all := actors_under(root)
	var taken := existing_ids(root)

	for who in all:
		var id := who.actor_id

		# An authored id is kept; only the node name is brought into line. Skipping a
		# named actor outright was the first version of this, and it left the player's
		# node called whatever it had been while every other node carried its id - which
		# is the tree-and-inspector disagreement this whole class exists to prevent.
		var generated := false
		if id == &"" or overwrite:
			taken.erase(id)
			id = next_id_avoiding(taken)
			who.actor_id = id
			generated = true
		taken[id] = true

		var node := placement_root(who)
		if node == null:
			continue

		var before := node.name
		node.name = node_name_for(_base_for(node, id, generated), id)
		if node.name != before:
			changed[id] = node.name

	return changed
