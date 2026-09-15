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
## [b]Two halves, deliberately.[/b] The id is data the game reads; the node name is for
## the person looking at the scene tree. Assigning one without the other is what makes a
## map where the inspector and the tree disagree about which guard is which, so
## [method assign] always does both.
##
## [b]Idempotent.[/b] Re-running over a map that has already been named changes nothing
## and stacks no suffixes - [code]Guard__event_3[/code] does not become
## [code]Guard__event_3__event_3[/code]. That matters because this is meant to be wired to
## an editor button, and a button that punishes a second click is a button nobody trusts.
##
## Static and UI-free, so an [code]@tool[/code] script in the editor and a test in a
## headless run reach it the same way.

## What a generated id is called before its number. Ids read [code]event_3[/code], which
## is the [code]@event_3[/code] term form minus its sigil (question 40).
const DEFAULT_PREFIX := "event"

## Characters Godot refuses in a node name. A prefix carrying one of these would produce
## a node whose name silently does not match the id inside it.
const ILLEGAL_IN_NAMES := [".", ":", "@", "/", "\"", "%"]


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


## How many actors are placed under [param root]. This is the count a new id is numbered
## from.
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

## The next free id under [param root].
##
## [b]Numbering starts at the number of ids already handed out, then counts up until the
## id is free.[/b]
##
## [b]Ids already handed out, not actors placed[/b] - the distinction is the whole
## correctness of this. A freshly placed map of three unnamed actors has three actors and
## zero ids, and wants [code]event_0[/code], [code]event_1[/code], [code]event_2[/code].
## Counting actors instead would number them 3, 4, 5, because the actor being named is
## itself in the count - every id in a new map would be off by the number of actors in it.
##
## Then the search upward, which is what keeps it correct after a deletion: with
## [code]event_0[/code] and [code]event_2[/code] in use, the count is 2 and
## [code]event_2[/code] is taken, so the next free one is [code]event_3[/code]. Without
## the search that id would be handed out twice and [method MapContext.register] would
## refuse the second at runtime - an authoring mistake that only shows up on load.
static func next_id(root: Node, prefix: String = DEFAULT_PREFIX) -> StringName:
	var taken := existing_ids(root)
	return next_id_avoiding(taken, taken.size(), prefix)


## [method next_id] against a caller's own set, for naming several actors in one pass
## without re-walking the tree between each.
static func next_id_avoiding(taken: Dictionary, from: int,
		prefix: String = DEFAULT_PREFIX) -> StringName:
	var safe := _safe_prefix(prefix)
	var n := maxi(0, from)
	while taken.has(StringName("%s_%d" % [safe, n])):
		n += 1
	return StringName("%s_%d" % [safe, n])


## A prefix that cannot produce an unusable node name. Returns [constant DEFAULT_PREFIX]
## rather than a mangled string when the caller's prefix is empty or illegal, so the
## failure is a visible fallback instead of a node named [code]__3[/code].
static func _safe_prefix(prefix: String) -> String:
	var text := prefix.strip_edges()
	if text == "":
		return DEFAULT_PREFIX
	for bad in ILLEGAL_IN_NAMES:
		if text.contains(bad):
			push_warning("ActorNaming: prefix '%s' contains '%s', which Godot refuses in a node name - using '%s'."
				% [prefix, bad, DEFAULT_PREFIX])
			return DEFAULT_PREFIX
	return text


# -- Node names ----------------------------------------------------------------

## The node an id belongs on: the placed scene instance, not the [Actor] inside it.
##
## Actors are placed as instances of one prefab - [code]Player[/code],
## [code]Npc_17_9[/code] - each with an [Actor] child that is always just called
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
## The strip is what makes a second click harmless. It removes a trailing
## [code]__<prefix>_<number>[/code] whatever the number, so re-naming an actor that was
## [code]event_3[/code] and is now [code]event_5[/code] leaves [code]Guard__event_5[/code]
## rather than [code]Guard__event_3__event_5[/code].
static func node_name_for(base: String, id: StringName,
		prefix: String = DEFAULT_PREFIX) -> String:
	var stem := strip_id(base, prefix)
	if stem == "":
		# A node called nothing but its old id still deserves a readable name.
		stem = "Actor"
	return "%s__%s" % [stem, id]


## [param name] with a trailing generated id removed. Any other name is returned
## unchanged, so a hand-named [code]Guard_of_the_north[/code] survives.
static func strip_id(name: String, prefix: String = DEFAULT_PREFIX) -> String:
	var expression := RegEx.new()
	# The prefix is escaped rather than interpolated raw: a prefix with a regex
	# metacharacter in it would otherwise match far more than it should.
	expression.compile(r"__%s_\d+$" % _escape(_safe_prefix(prefix)))
	return expression.sub(name, "", false)


static func _escape(text: String) -> String:
	var out := ""
	for i in text.length():
		var c := text[i]
		out += ("\\" + c) if r"\^$.|?*+()[]{}".contains(c) else c
	return out


## [param name] with a trailing [code]__<id>[/code] removed, for one specific id.
##
## [method strip_id] only knows the generated [code]__<prefix>_<number>[/code] shape, so
## it cannot remove an id that does not look generated - a hand-typed
## [code]player[/code], or a [code]chest_2[/code] written while the prefix was
## [code]event[/code]. Renaming from one of those would stack:
## [code]Guard__chest_2__chest_3[/code]. Knowing the id being replaced is what avoids it.
static func strip_exact(name: String, id: StringName) -> String:
	if id == &"":
		return name
	return name.trim_suffix("__%s" % id)


## Renames [param node] for [param id], removing [param previous] first.
##
## This is the setter's form of [method node_name_for]: a hook that fires on every change
## to an id knows what the id used to be, and that is strictly better information than a
## pattern match. Returns the name the node ended up with.
##
## Does nothing and returns the current name when the result would be identical, so an
## edit that changes nothing does not mark the scene dirty.
static func rename_for(node: Node, id: StringName, previous: StringName = &"",
		prefix: String = DEFAULT_PREFIX) -> String:
	if node == null:
		return ""

	var stem := strip_exact(node.name, previous)
	var wanted := node_name_for(stem, id, prefix) if id != &"" else strip_id(stem, prefix)
	if wanted == "":
		wanted = "Actor"
	if node.name != wanted:
		node.name = wanted
	return node.name


# -- Assigning -----------------------------------------------------------------

## Gives [param actor] an id and renames its placement node to match.
##
## Returns the id the actor ended up with, or [code]&""[/code] if it was left alone.
##
## [param root] is the scene to count and check against - the edited scene in the editor,
## the map at runtime. Left null, the actor's own scene root is used.
##
## [b]An actor that already has an id keeps it[/b] unless [param overwrite] is true. That
## is what stops a pass over the map renaming [code]player[/code] to
## [code]event_0[/code] and breaking every graph that names it. The node is still renamed
## to match, because an actor whose id and node name disagree is the thing this exists to
## prevent.
static func assign(actor: Actor, root: Node = null, prefix: String = DEFAULT_PREFIX,
		overwrite: bool = false) -> StringName:
	if actor == null:
		return &""
	if root == null:
		root = actor.owner if actor.owner != null else actor.get_tree().current_scene \
			if actor.is_inside_tree() else actor

	var id := actor.actor_id
	if id == &"" or overwrite:
		var taken := existing_ids(root)
		# Its own current id must not block it from being renumbered.
		taken.erase(actor.actor_id)
		id = next_id_avoiding(taken, taken.size(), prefix)
		actor.actor_id = id

	var node := placement_root(actor)
	if node != null:
		node.name = node_name_for(node.name, id, prefix)
	return id


## Names every unnamed actor under [param root], in tree order.
##
## Returns [code]{actor_id: node_name}[/code] for the ones it touched, so a caller can
## report what it did rather than the author having to diff the scene to find out.
##
## The taken-set is built once and added to as it goes, rather than re-walked per actor:
## the ids handed out in this pass are not yet visible to a fresh [method existing_ids]
## in the order this runs, and two actors named [code]event_3[/code] is exactly the
## collision the numbering exists to avoid.
static func assign_all(root: Node, prefix: String = DEFAULT_PREFIX,
		overwrite: bool = false) -> Dictionary:
	var named: Dictionary = {}
	if root == null:
		return named

	var all := actors_under(root)
	var taken := existing_ids(root)

	for who in all:
		if who.actor_id != &"" and not overwrite:
			continue

		taken.erase(who.actor_id)
		var id := next_id_avoiding(taken, taken.size(), prefix)
		taken[id] = true
		who.actor_id = id

		var node := placement_root(who)
		if node != null:
			node.name = node_name_for(node.name, id, prefix)
			named[id] = node.name
		else:
			named[id] = ""

	return named
