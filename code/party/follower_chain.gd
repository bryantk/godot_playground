extends Node

## The party caterpillar: the actors that walk in a line behind the player. Autoloaded as
## [code]FollowerChain[/code].
##
## [b]Who is in it.[/b] Every member of [member Party.active] that has a [member
## PartyMember.follower_sheet], in party order, is built as a follower automatically -
## followers are not placements, so there is nothing to author on a map. Commands can also
## take a member out ([method remove_member]) or back in ([method add_member]), and add any
## ordinary actor already on the map ([method add_actor] - an NPC who joins the party's
## walk, say) which then trails behind the party followers.
##
## [b]How they walk.[/b] The leader (the player) leaves a trail of the cells it has just
## stood on, most recent first. The follower at chain position [code]i[/code] heads for
## [code]trail[i][/code] - so they queue up on the player's own footprints, one cell apart,
## and stop where they are when it does. A follower already next to its slot takes a step;
## one further off (after a cutscene moved it) walks the line. A leader that teleports
## resets the trail and the followers are placed on it.
##
## [b]Collision.[/b] [method Occupancy.set_follower] marks them: the player walks through a
## follower, followers walk through each other and the player, but any other actor is
## blocked by a follower like a solid (and blocks it).
##
## [b]Maps and battles.[/b] Followers belong to a map, so changing map rebuilds them on the
## new one, stacked on the player's cell, and they fan out as it walks. They are hidden while
## [ModeStack] is in BATTLE, and [method show_followers] hides or shows them on demand.
##
## [b]Saved[/b] by [method to_save]: who was taken out, who was added, what was hidden.
## Positions are not - on load they rebuild on the player and fan out again.

signal changed()

## Cells of trail kept behind the last follower, beyond one per follower.
const _TRAIL_SLACK := 2

var _map: MapContext = null
var _player: Actor = null
var _dirty := true

## The party-member followers this has built, id -> actor.
var _party_followers: Dictionary[StringName, Actor] = {}
## Ordinary actors added with [method add_actor], by actor id, in the order added.
var _extras: Array[StringName] = []
## Party members taken out of the chain - they stay out until [method add_member].
var _excluded: Dictionary[StringName, bool] = {}

## The leader's last cells, most recent first, not counting the one it stands on now.
var _trail: Array[Vector3i] = []
var _last_leader_cell := Vector3i.ZERO
var _has_last := false

var _hidden_all := false
var _hidden: Dictionary[StringName, bool] = {}

## Followers that have been told to stop following ([method break_follow]) - they stay in
## the chain but nothing moves them except the events that address them, until [method
## regroup] brings them back.
var _broken: Dictionary[StringName, bool] = {}

## Followers [method regroup] has sent somewhere and that are still on their way. Ordinary
## following skips them so the two do not pull against each other; once they have all
## stopped, they are no longer broken and follow again.
var _regrouping: Dictionary[StringName, bool] = {}

## Followers [method regroup] put on the player's cell: they stay there until the player
## walks away, instead of stepping back to their place behind it at once.
var _holding: Dictionary[StringName, bool] = {}


func _ready() -> void:
	Party.changed.connect(func() -> void: _dirty = true)
	ModeStack.mode_changed.connect(func(_mode: ModeStack.Mode) -> void: _apply_visibility())


func _physics_process(_delta: float) -> void:
	var found := get_tree().get_first_node_in_group(&"map_context") as MapContext
	if found != _map:
		_on_map_changed(found)
	if _map == null:
		return

	if not is_instance_valid(_player):
		_player = _find_player()
		_dirty = true
	if _player == null:
		return

	if _dirty:
		_sync_membership()
	_record_trail()

	if not _regrouping.is_empty() and _regroup_done():
		for id: StringName in _regrouping:
			_broken.erase(id)
			if _regrouping[id]:
				_holding[id] = true
		_regrouping.clear()
	_drive()


# -- Membership ---------------------------------------------------------------------

## Puts [param member_id] back in the chain (clearing an earlier [method remove_member]).
## A member with no follower sheet still has no follower to show.
func add_member(member_id: StringName) -> void:
	_excluded.erase(member_id)
	_dirty = true


## Takes [param member_id] out of the chain and removes their follower, until
## [method add_member] puts them back.
func remove_member(member_id: StringName) -> void:
	_excluded[member_id] = true
	_dirty = true


## Makes [param actor] - an ordinary actor on the map, not a party member - follow the
## party, behind the party followers. Whatever else was moving it (a patrol route) is
## its author's to stop; this only takes over when it is idle.
func add_actor(actor: Actor) -> void:
	if actor == null or _extras.has(actor.actor_id):
		return
	_extras.append(actor.actor_id)
	_dirty = true


## Stops [param actor] following. A party follower is treated as [method remove_member].
func remove_actor(actor: Actor) -> void:
	if actor == null:
		return
	if _party_followers.has(actor.actor_id):
		remove_member(actor.actor_id)
		return
	_extras.erase(actor.actor_id)
	if _map != null:
		_map.occupancy.set_follower(actor.actor_id, false)
	_dirty = true


## Every follower in chain order - party followers first, then added actors.
func followers() -> Array[Actor]:
	var out: Array[Actor] = []
	if _map == null:
		return out
	for member in Party.active:
		var f: Actor = _party_followers.get(member.id)
		if is_instance_valid(f):
			out.append(f)
	for id in _extras:
		var extra := _map.actor(id)
		if extra != null:
			out.append(extra)
	return out


func _desired_party() -> Array[PartyMember]:
	var out: Array[PartyMember] = []
	for member in Party.active:
		if member.follower_sheet != null and not _excluded.has(member.id):
			out.append(member)
	return out


func _sync_membership() -> void:
	_dirty = false
	var desired := _desired_party()
	var keep := {}
	for member in desired:
		keep[member.id] = true

	for id: StringName in _party_followers.keys():
		if not keep.has(id) or not is_instance_valid(_party_followers[id]):
			var gone := _party_followers[id]
			_party_followers.erase(id)
			if is_instance_valid(gone):
				_map.occupancy.set_follower(id, false)
				gone.get_parent().queue_free()

	for member in desired:
		if not _party_followers.has(member.id):
			var built := _spawn(member)
			if built != null:
				_party_followers[member.id] = built

	# An added actor that has left the map (or was erased) simply stops being one.
	for id in _extras.duplicate():
		if _map.actor(id) == null:
			_extras.erase(id)

	_map.occupancy.set_leader(_player.actor_id, true)
	for f in followers():
		_map.occupancy.set_follower(f.actor_id, true)

	_apply_visibility()
	changed.emit()


# -- Building a follower ------------------------------------------------------------

## A follower for [param member], built to look like the player's own placement: a body
## node of the same kind (2D or 3D) beside the player's, with the player's own axis scripts
## and a copy of its visual wearing the member's sheet. It needs no [GameProfile] that
## way, and a sheet laid out like the player's works unchanged.
func _spawn(member: PartyMember) -> Actor:
	var template_root := _player.get_parent()
	if template_root == null or template_root.get_parent() == null:
		return null

	var root: Node = Node2D.new() if template_root is Node2D else Node3D.new()
	root.name = "Follower_%s" % member.id

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = member.id
	actor.motion_mode = Actor.MotionMode.GRID
	actor.set_meta(&"party_follower", true)
	root.add_child(actor)

	var adapter := _player.adapter()
	if adapter != null:
		_add_axis(actor, "Space", adapter.get_script())
	_add_axis(actor, "Motion", GridMotion)

	var player_view := _player.view()
	var view_node: Node = null
	var visual: Node = null
	if player_view != null and player_view.visual() != null:
		visual = player_view.visual().duplicate()
		visual.set("texture", member.follower_sheet)
		root.add_child(visual)
		view_node = _add_axis(actor, "View", player_view.get_script())

	if root is Node2D and template_root is Node2D:
		(root as Node2D).position = (template_root as Node2D).position
	elif root is Node3D and template_root is Node3D:
		(root as Node3D).position = (template_root as Node3D).position

	template_root.get_parent().add_child(root)
	if view_node != null and visual != null:
		(view_node as ActorView).bind_visual(visual)
	return actor


static func _add_axis(actor: Actor, node_name: String, script: Script) -> Node:
	var node := Node.new()
	node.name = node_name
	node.set_script(script)
	actor.add_child(node)
	return node


func _find_player() -> Actor:
	for a in _map.actors():
		if a.is_player() and not a.has_meta(&"party_follower"):
			return a
	return null


func _on_map_changed(found: MapContext) -> void:
	# Followers lived on the old map and went with it.
	_party_followers.clear()
	_trail.clear()
	_has_last = false
	_broken.clear()
	_regrouping.clear()
	_holding.clear()
	_player = null
	_map = found
	_dirty = true


# -- Trail and movement -------------------------------------------------------------

func _record_trail() -> void:
	var cell := _player.cell()
	if not _has_last:
		_last_leader_cell = cell
		_has_last = true
		return
	if cell == _last_leader_cell:
		return

	if ActorQueries.manhattan(cell, _last_leader_cell) > 1:
		# A teleport or a map-internal jump: no footprints to follow. Start a fresh trail
		# and put everyone on the leader.
		_trail.clear()
		_last_leader_cell = cell
		for f in followers():
			_place(f, cell)
		return

	_holding.clear()
	_trail.push_front(_last_leader_cell)
	_last_leader_cell = cell
	var limit := followers().size() + _TRAIL_SLACK
	while _trail.size() > limit:
		_trail.pop_back()


func _place(follower: Actor, cell: Vector3i) -> void:
	var motion := follower.motion()
	if motion != null:
		motion.move_to(cell, {"path": "raw"})


## The cell chain position [param index] should be standing on: its own footprint on the
## trail, or - while the trail is shorter than the chain (just spawned) - the leader's.
func slot_for(index: int) -> Vector3i:
	if index < _trail.size():
		return _trail[index]
	return _player.cell() if is_instance_valid(_player) else Vector3i.ZERO


func _drive() -> void:
	var leader_motion := _player.motion()
	var index := 0
	for f in followers():
		var slot := slot_for(index)
		index += 1

		if _broken.has(f.actor_id) or _regrouping.has(f.actor_id) or _holding.has(f.actor_id):
			continue
		var motion := f.motion() as GridMotion
		if motion == null or motion.is_busy() or f.cell() == slot:
			continue
		if leader_motion != null:
			motion.speed = leader_motion.speed

		var delta := slot - f.cell()
		if ActorQueries.manhattan(f.cell(), slot) == 1:
			motion.step(delta)
		else:
			motion.move_to(slot)


## The follower at chain position [param n], counting from 1 - what [code]@follower_1[/code],
## [code]@follower_2[/code] ... resolve to ([method EventContext.resolve]), so an event can
## move or face any of them whether or not it is following. Null past the end of the chain.
func follower_at(n: int) -> Actor:
	var all := followers()
	return all[n - 1] if n >= 1 and n <= all.size() else null


## Stops [param actor] following - or every follower if null. They stay where they are and
## in the chain (so [code]@follower_N[/code] still names them), free for move commands, until
## [method regroup] brings them back.
func break_follow(actor: Actor = null) -> void:
	if actor != null:
		_broken[actor.actor_id] = true
		return
	for f in followers():
		_broken[f.actor_id] = true


## Whether [param actor] is currently not following ([method break_follow]).
func is_broken(actor: Actor) -> bool:
	return actor != null and _broken.has(actor.actor_id)


## Brings followers back: [param mode] "line" walks each to its place behind the leader,
## "player" walks each onto the leader's own cell (they pass through it). [param actor] null
## means every follower. Each then follows normally again. A follower that cannot get there
## (something in the way) stops short; it does not hold the others up.
func regroup(mode: String = "line", actor: Actor = null) -> void:
	if _map == null or not is_instance_valid(_player):
		return
	var index := 0
	for f in followers():
		var slot := slot_for(index) if mode != "player" else _player.cell()
		index += 1
		if actor != null and f != actor:
			continue
		_regrouping[f.actor_id] = mode == "player"
		var motion := f.motion() as GridMotion
		if motion != null and f.cell() != slot:
			motion.cancel()
			motion.move_to(slot)


## True while a [method regroup] is still bringing anyone back.
func is_regrouping() -> bool:
	return not _regrouping.is_empty()


func _regroup_done() -> bool:
	for f in followers():
		if _regrouping.has(f.actor_id):
			var motion := f.motion()
			if motion != null and motion.is_busy():
				return false
	return true


# -- Visibility ---------------------------------------------------------------------

## Shows or hides every follower ([param actor] null), or just [param actor]. Independent
## of the automatic hiding during battle.
func show_followers(visible_now: bool, actor: Actor = null) -> void:
	if actor == null:
		_hidden_all = not visible_now
		_hidden.clear()
	elif visible_now:
		_hidden.erase(actor.actor_id)
	else:
		_hidden[actor.actor_id] = true
	_apply_visibility()


func _apply_visibility() -> void:
	var in_battle := ModeStack.current() == ModeStack.Mode.BATTLE
	for f in followers():
		var view := f.view()
		if view != null:
			view.set_visible(not (_hidden_all or in_battle or _hidden.has(f.actor_id)))


# -- Save ---------------------------------------------------------------------------

func to_save() -> Dictionary:
	var excluded: Array = []
	for id: StringName in _excluded:
		excluded.append(str(id))
	var extras: Array = []
	for id in _extras:
		extras.append(str(id))
	var hidden: Array = []
	for id: StringName in _hidden:
		hidden.append(str(id))
	var broken: Array = []
	for id: StringName in _broken:
		broken.append(str(id))
	return {"excluded": excluded, "extras": extras, "hidden_all": _hidden_all, "hidden": hidden,
		"broken": broken}


func from_save(state: Dictionary) -> void:
	_excluded.clear()
	for id: Variant in state.get("excluded", []):
		_excluded[StringName(str(id))] = true
	_extras.clear()
	for id: Variant in state.get("extras", []):
		_extras.append(StringName(str(id)))
	_hidden_all = bool(state.get("hidden_all", false))
	_hidden.clear()
	for id: Variant in state.get("hidden", []):
		_hidden[StringName(str(id))] = true
	_broken.clear()
	for id: Variant in state.get("broken", []):
		_broken[StringName(str(id))] = true
	_regrouping.clear()
	_holding.clear()
	_trail.clear()
	_has_last = false
	_dirty = true


## Forget everything - a new game. Does not touch the current map's followers until the
## next sync rebuilds them.
func reset() -> void:
	from_save({})


## Which one a follow_add/follow_remove node means: [code]{member, actor}[/code] with one
## of them empty - a party member id from its [code]member[/code] argument, else the actor
## its [code]actor[/code] argument resolves to.
static func target_of(node_args: Dictionary, ctx: EventContext) -> Dictionary:
	if node_args.has("member") and str(node_args["member"]) != "":
		return {"member": StringName(str(node_args["member"])), "actor": null}
	if node_args.has("actor") and ctx != null:
		return {"member": &"", "actor": ctx.resolve(str(node_args["actor"]))}
	return {"member": &"", "actor": null}
