class_name ActorNaming

## Reads a map's placements - which node an id belongs on, and what is already placed
## there.
##
## [b]Ids used to be generated and stacked onto a node's name by this class[/b]
## ([code]assign[/code]/[code]assign_all[/code]/[code]rename_for[/code], all since
## removed): a fresh actor got the next free number and a node renamed to
## [code]event__3[/code]. That direction is retired - [member Actor.actor_id] now reads
## the other way, derived from the placement root's own name (see [method
## Actor._id_from_parent_name]), so an id is never generated or hand-typed onto the
## actor at all. What is left here is what still has nothing to do with that: finding
## the node an id belongs on, and answering what a map already holds.
##
## Static and UI-free, so an [code]@tool[/code] script in the editor and a test in a
## headless run reach it the same way.

## What separates a placement's own meaningful name from a descriptive suffix hand-added
## after it - [code]npc_greeting[/code] in [code]Npc_17_9__npc_greeting[/code]. [method
## Actor._id_from_parent_name] is the reader; nothing here writes one any more.
const SEPARATOR := "__"


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
## nothing, which is what lets an unnamed actor be told apart from one colliding with
## the empty string.
static func existing_ids(root: Node) -> Dictionary:
	var taken: Dictionary = {}
	for who in actors_under(root):
		if who.actor_id != &"":
			taken[who.actor_id] = true
	return taken


# -- Which node an id belongs on ------------------------------------------------

## The node an id belongs on: the placed scene instance, not the [Actor] inside it.
##
## Actors are placed as instances of one prefab - [code]Player[/code],
## [code]Npc_17_9__npc_greeting[/code] - each with an [Actor] child that is always just
## called [code]Actor[/code]. [method Actor._id_from_parent_name] reads straight off
## [method Node.get_parent] instead of this (event-pages.md's two authored shapes both
## put the actor directly under the placement root), but editor tooling that starts from
## the [Actor] and needs the node an author actually clicks in the Scene dock still
## walks up through this.
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
