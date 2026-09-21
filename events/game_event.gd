class_name GameEvent extends Node

## Places an authored event document in the world - event-pages.md §4.3. Owns the
## document, evaluates which page is active, applies that page's art on a switch,
## registers its cell with [MapContext], and starts a runner through [EventScheduler]
## when one of the seven triggers (decision 44) fires.
##
## [b]An event with an [Actor] child is an NPC, monster, chest or door; one without is
## a bodiless region trigger[/b] - the same node either way, which is what keeps "what
## is at this cell?" one lookup regardless of which kind answers it.
##
## [b]`player_touch`/`event_touch` fire two ways.[/b] [method _on_actor_stepped] is the
## precise one, off [signal EventBus.actor_stepped] - but that signal only exists for a
## [GridMotion] actor, so [method _check_continuous_touch] is the fallback a per-frame
## cell-equality check gives free motion, on either side: a free player walking into
## this event, or this event's own free actor walking into the player.
##
## [b]Page switches defer to graph completion[/b] (question 23): while this event's own
## runner is still running, neither a new trigger nor a flag change already known to
## point at a different page does anything until that runner finishes. `re_validate`
## (the authored escape hatch) is not wired to force an early recheck yet - it is still
## the generic no-op fallback segment 4 gave every command with no executor.
##
## [b]Known gap:[/b] [signal GameState.changed] is a blanket subscription here, not the
## narrow one [method EventCondition.keys] could derive from this event's own
## conditions. Correct, since a page switch cannot be missed, but re-checks every
## event's pages on every flag or variable change in the game rather than only the
## ones a page's `conditions` actually mention.
##
## [b]The actor faces whoever approached[/b] ([method _face_interactor]) the moment
## `action`/`player_touch`/`event_touch` fires, for free - an author does not have to
## put a `face_to` at the top of every page just to look at the player. A page's own
## `lock_facing` (event-pages.md) suppresses this the same way it suppresses any other
## facing command, since both go through [method Actor.set_facing]. And because facing
## is captured before this happens and restored after (see [method
## _restore_facing_if_untouched]), a page with no move or facing command of its own
## still ends the interaction facing whichever way it started - the look is visible
## during the interaction, not left behind after it.
##
## [b]`lock_player` locks input for exactly one run.[/b] Unlike `lock_facing`/`through`/
## `through_terrain`, which describe the actor for as long as the page is active, this
## describes the triggered run itself: [constant ModeStack.Mode.CUTSCENE] is pushed the
## moment [method _maybe_fire] commits to running and popped the moment [method poll]
## sees that run finish (see [method _release_control_if_locked]) - the same
## capture/restore shape `lock_facing` already uses, aimed at [ModeStack] instead of
## [method Actor.set_facing]. `halt_control`/`return_control` (event_command.gd) are the
## manual equivalent, for locking past a run's own end on purpose.
##
## [b]The actor's own brain is the runner's business, not this file's.[/b] [EventRunner]
## suspends [method Actor.brain] and cancels whatever motion was already happening the
## moment it [method EventRunner.begin]s or [method EventRunner.restore]s, and gives
## both back on every path that ends it - see its own class doc. That used to live
## here, gated on [method poll] noticing the runner finish; moving it into the runner
## itself is what makes [method EventScheduler.reset]/a save restore also un-suspend
## correctly, not only the ordinary finish this file's own polling would have caught.
##
## [b]A page's autonomous route (event-pages.md §3) is this file's business, though[/b] -
## [method _start_route]/[method _stop_route] compile it ([EventRoute], stage-c-plan.md
## segment 7) and run it as its own background [EventRunner], leased the same way the
## triggered graph is. The two runners never coexist on the same actor: the moment
## [method _maybe_fire] is about to start a triggered run, [method
## _suspend_route_for_lease] captures the route runner's own progress onto [member
## Actor.suspended_route] (question 52's bookmark, at route granularity - the same
## "restart is always a legal downgrade" rule as a whole document's save) and discards
## it, and [method poll] starts a fresh one back up - resumed if the route has not
## changed underneath it, restarted from its own beginning if it has.

@export_file("*.event.json") var document_path: String = ""

var _map: MapContext = null
var _actor: Actor = null
var _view: ActorView = null

var _doc: Dictionary = {}
var _active_page: int = -1
var _registered_cell: Vector3i = Vector3i.ZERO
var _registered := false
var _fired_once: Dictionary = {}

var _runner: EventRunner = null
var _runner_ctx: EventContext = null
var _player_cache: Actor = null

## The active page's own autonomous route, running as its own background [EventRunner] -
## see the class doc's note on [method _start_route]/[method _stop_route]. Never held
## at the same time as [member _runner]: whichever fires first takes the actor.
var _route_runner: EventRunner = null

## Cell equality with the player as of last frame - [method _check_continuous_touch]'s
## own edge detector, so overlapping for many frames fires once, at entry, the same as
## [method _on_actor_stepped]'s signal-driven version does.
var _touching := false

## The facing captured just before an interaction starts, restored once it ends -
## unless a movement/facing executor touched this event's own actor during the run
## ([member EventContext.self_actor_touched]), in which case that is treated as
## deliberate and left alone. [member _has_pre_facing] is false whenever there is
## nothing to restore (no [Actor], or nothing currently in flight).
var _pre_interaction_facing: Vector3i = Vector3i.ZERO
var _has_pre_facing := false

## Whether this run pushed [constant ModeStack.Mode.CUTSCENE] for the active page's own
## [code]lock_player[/code] - true from the moment [method _maybe_fire] commits to
## running until [method poll] sees the runner finish (or the run is refused), which is
## when the matching pop happens. Tracked here rather than inferred from the page,
## because the page that started a run can switch under it (question 23's deferred
## switch aside, a flag change mid-run still cannot retarget which run this pop belongs
## to) before that run's own pop is due.
var _locked_player := false


func _ready() -> void:
	_map = MapContext.of(self)
	_actor = _find_actor()
	_view = _actor.view() if _actor != null else null
	_load_document()

	EventBus.actor_stepped.connect(_on_actor_stepped)
	EventBus.player_interacted.connect(_on_player_interacted)
	GameState.changed.connect(_on_state_changed)

	_refresh_active_page()
	_register()
	_maybe_fire(&"on_load")
	_maybe_fire(&"auto")
	_start_route()


func _exit_tree() -> void:
	_unregister()


func _process(_delta: float) -> void:
	poll()
	_check_continuous_touch()


## Notices a finished runner and re-checks the deferred page switch. A real frame
## calls this through [method Node._process]; a headless test - which drives
## [EventScheduler] by hand rather than waiting on real frames - calls it directly.
func poll() -> void:
	if _runner != null and _runner.finished:
		if _actor != null:
			EventScheduler.release_lease(_actor.actor_id, _runner)
		_runner = null
		_restore_facing_if_untouched()
		_release_control_if_locked()
		_refresh_active_page()
		_start_route()


## Restores the facing captured just before this interaction, but only if no
## movement/facing executor touched the actor while it ran - a graph that faced or
## walked its own actor on purpose (a greeting's own [code]face_to[/code], a patrol
## resuming) is left as is, since reverting it would undo something the graph
## deliberately did.
func _restore_facing_if_untouched() -> void:
	var touched := _runner_ctx != null and _runner_ctx.self_actor_touched
	if _has_pre_facing and not touched and _actor != null:
		_actor.set_facing(_pre_interaction_facing)
	_has_pre_facing = false
	_runner_ctx = null


## The other half of [member _locked_player] - pops [constant ModeStack.Mode.CUTSCENE]
## if [method _maybe_fire] pushed one for this run, and clears the flag either way.
func _release_control_if_locked() -> void:
	if _locked_player:
		ModeStack.pop()
	_locked_player = false


func event_id() -> StringName:
	return StringName(name)


func cell() -> Vector3i:
	return _actor.cell() if _actor != null else Vector3i.ZERO


func is_busy() -> bool:
	return _runner != null and not _runner.finished


## Whether this event's active page is currently driving its actor through a
## background route runner - what distinguishes an autonomously-patrolling actor from
## one that is merely scenery or interaction-only, now that neither has a [Brain] of
## its own to tell them apart by (see [method _start_route]'s class-doc note).
func is_routed() -> bool:
	return _route_runner != null


func active_page() -> int:
	return _active_page


func _find_actor() -> Actor:
	for child in get_children():
		if child is Actor:
			return child

	# event-pages.md §4.3's diagram has GameEvent as the parent of the Actor it owns -
	# the shape to build fresh. Retrofitting one onto an actor prefab that already
	# exists (an NPC scene instanced elsewhere, its own Actor already the root's
	# child) is realistically a sibling addition instead, so this falls back to
	# checking there before giving up.
	var parent := get_parent()
	if parent != null:
		for child in parent.get_children():
			if child is Actor:
				return child
	return null


# -- The document, the active page ------------------------------------------------

func _load_document() -> void:
	if document_path == "":
		return
	_doc = EventDocument.parse(FileAccess.get_file_as_string(document_path))


func _pages() -> Array:
	return _doc.get("pages", [])


func _condition_ctx() -> Dictionary:
	return {"map": _map.map_id if _map != null else &"", "event": event_id()}


func _refresh_active_page() -> void:
	if is_busy():
		return  # deferred to graph completion - question 23

	var pages := _pages()
	if pages.is_empty():
		return

	var index := EventDocument.active_page(pages, _condition_ctx())
	if index == _active_page:
		return
	_stop_route()
	_active_page = index
	_apply_art()
	_apply_actor_flags()
	_start_route()


func _apply_art() -> void:
	if _view == null or _active_page < 0:
		return
	_view.apply_art((_pages()[_active_page] as Dictionary).get("art", {}))


## Applies a page's [code]lock_facing[/code]/[code]through[/code]/[code]through_terrain[/code]
## to the actor GameEvent owns, on activation - siblings of [code]art[/code], applied the
## same way. [code]through[/code] also updates [Occupancy]'s own phasing table directly,
## not just the export property: [method Actor._claim_spawn_cell] only ever reads
## [member Actor.through_actors] once, at spawn, so a page switch has to push the change
## to where pathing actually looks for it.
func _apply_actor_flags() -> void:
	if _actor == null or _active_page < 0:
		return
	var page: Dictionary = _pages()[_active_page]
	_actor.facing_locked = bool(page.get("lock_facing", false))
	_actor.through_terrain = bool(page.get("through_terrain", false))

	var through := bool(page.get("through", false))
	_actor.through_actors = through
	if _map != null:
		_map.occupancy.set_phasing(_actor.actor_id, through)


func _settings() -> Dictionary:
	if _active_page < 0:
		return {}
	return (_pages()[_active_page] as Dictionary).get("settings", {})


## Whether the active page's actor currently phases through other actors - the "other
## actors (and props) will not block this actor's pathing" flag. [code]false[/code] with
## no [Actor] or nothing active, matching [method Actor.through_actors]'s own default.
func _through_actors() -> bool:
	return _actor != null and _actor.through_actors


# -- Registration -------------------------------------------------------------------

func _register() -> void:
	if _map == null or _registered:
		return
	_registered_cell = cell()
	_map.add_event_at(_registered_cell, self)
	_registered = true


func _unregister() -> void:
	if _map == null or not _registered:
		return
	_map.remove_event_at(_registered_cell, self)
	_registered = false


func _reregister_at(to: Vector3i) -> void:
	if not _registered:
		return
	_map.remove_event_at(_registered_cell, self)
	_map.add_event_at(to, self)
	_registered_cell = to


## The triggers that mean someone approached this event, rather than the event's own
## page settling or a flag elsewhere changing - what "look at whoever started the
## interaction" applies to.
const _FACING_TRIGGERS: Array[StringName] = [&"action", &"player_touch", &"event_touch"]

## Turns this event's own actor to face the player as an interaction begins - the
## default an author gets for free, so a plain "say something" page does not also have
## to author its own [code]face_to[/code]. [method Actor.set_facing] is the actual gate
## ([member Actor.facing_locked], question "lock facing"), so this needs no lock check
## of its own - calling it while locked is already a no-op.
##
## [b]Deliberately not routed through a command executor.[/b] This is the interaction
## starting, not something the graph asked for, so it must never set [member
## EventContext.self_actor_touched] - the whole point of capturing facing before this
## call is that a page with no move or facing command of its own still restores to
## what it was before, even though it visibly turned to look at the player first.
func _face_interactor(trigger_name: StringName) -> void:
	if not _FACING_TRIGGERS.has(trigger_name):
		return
	var player := _player()
	if player == null:
		return
	var delta := Vector3(player.cell() - _actor.cell())
	if delta.length_squared() > 0.0001:
		_actor.set_facing(Space.quantise(delta, _actor.facing_count))


func _player() -> Actor:
	if _player_cache != null and is_instance_valid(_player_cache):
		return _player_cache
	if _map == null:
		return null
	for a in _map.actors():
		if a.is_player():
			_player_cache = a
			return a
	return null


# -- The seven triggers --------------------------------------------------------------

func _on_actor_stepped(actor_id: StringName, from: Vector3i, to: Vector3i) -> void:
	var my_cell := cell()

	if _actor != null and actor_id == _actor.actor_id and to == my_cell:
		_reregister_at(to)
		var watching := _player()
		if watching != null and to == watching.cell():
			_maybe_fire(&"event_touch")
		return

	var player := _player()
	if player == null or actor_id != player.actor_id:
		return

	if to == my_cell:
		_maybe_fire(&"player_touch")
	if from == my_cell:
		_maybe_fire(&"leave_cell")


## [method _on_actor_stepped] is signal-driven off [signal EventBus.actor_stepped],
## which only a [GridMotion] actor ever publishes - a free actor has no discrete step
## to hang a signal off, so a free-motion player walking into this event, or this
## event's own actor (free motion) walking into the player, would never fire
## [code]player_touch[/code]/[code]event_touch[/code] at all. This is the fallback: a
## plain per-frame cell-equality check, edge-triggered on [member _touching] the same
## way the signal path is edge-triggered on a step actually landing.
##
## Tries both trigger names rather than picking one - cell equality alone cannot say
## which side did the moving, and [method _maybe_fire] already no-ops on whichever name
## does not match this page's own [code]settings.trigger[/code], so trying the wrong one
## first costs nothing. Harmless alongside [method _on_actor_stepped] for two grid
## actors too: whichever fires first leaves the event busy, and the other's attempt
## no-ops on that instead of on the name mismatch.
func _check_continuous_touch() -> void:
	if _actor == null or _active_page < 0:
		return
	var player := _player()
	if player == null or player == _actor:
		return

	var touching := _actor.cell() == player.cell()
	if touching and not _touching:
		_maybe_fire(&"player_touch")
		_maybe_fire(&"event_touch")
	_touching = touching


## Facing-and-adjacent by default - the interact button aimed at a wall-like thing. A
## through event has no adjacent side that means anything (there is nothing stopping
## the player from standing on or passing through it), so it switches to "standing on
## the same cell" instead - grass, an item, a floor switch.
##
## [b]A free-motion player gets a distance check instead of either.[/b] A grid player's
## body is always exactly on a cell, so cell arithmetic is exact; a free player can stop
## anywhere, and the same arithmetic reads as a miss for one a few pixels short of
## "aligned" - which is what it felt like to press the button next to an event and have
## nothing happen. See [method _in_range_free].
func _on_player_interacted() -> void:
	var player := _player()
	if player == null or _map == null:
		return
	var in_range := _in_range_free(player) if player.motion() is FreeMotion \
		else (player.cell() == cell() if _through_actors() \
			else player.cell() + player.facing() == cell())
	if in_range:
		_maybe_fire(&"action")


## Interact range for a free-motion player: world distance to this event's own cell
## centre, with no facing requirement - the same reasoning [member _through_actors]
## already applies to a grid player (there is no meaningful "side" to face), extended
## to every free-motion interaction rather than only a through one, since a free
## player's facing is wherever it was last walking, not necessarily where it meant to
## press the button. The reach is generous on purpose: "standing next to it" should
## always be enough, whether or not the player's continuous position happens to have
## crossed into the event's own cell.
func _in_range_free(player: Actor) -> bool:
	var reach := maxf(_map.cell_size.x, _map.cell_size.z) * 1.25
	var offset := Space.flatten(_map.cell_centre(cell()) - player.world_position())
	return offset.length() <= reach


func _on_state_changed(_key: StringName) -> void:
	var previous := _active_page
	_refresh_active_page()
	if _active_page != previous:
		return  # the page switch itself is the reaction; no separate on_flag firing
	_maybe_fire(&"on_flag")


func _maybe_fire(trigger_name: StringName) -> void:
	if is_busy() or _active_page < 0:
		return

	var settings := _settings()
	if str(settings.get("trigger", "")) != str(trigger_name):
		return
	if bool(settings.get("once", false)) and _fired_once.get(_active_page, false):
		return

	var page: Dictionary = _pages()[_active_page]
	var graph: Array[Dictionary] = page.get("graph", [])
	if graph.is_empty():
		return

	# The two runners never coexist on one actor - see the class doc. A route already
	# holding the lease has to give it up before the triggered graph can take it.
	_suspend_route_for_lease()

	var ctx := EventContext.for_event(
		_map, _map.map_id if _map != null else &"", event_id(), _actor)
	var runner := EventRunner.new(ctx)

	if _actor != null and not EventScheduler.try_lease(_actor.actor_id, runner):
		runner.latch.detach()
		return

	# Armed before the runner actually starts, not after: a trivial graph (this
	# segment's own greeting, for instance) can run to completion synchronously
	# inside run_exclusive()/run_background() below.
	_fired_once[_active_page] = true
	_runner = runner
	_runner_ctx = ctx
	if _actor != null:
		_pre_interaction_facing = _actor.facing()
		_has_pre_facing = true
		_face_interactor(trigger_name)

	# Armed alongside facing, for the same reason: a synchronous run below can finish
	# before this function returns, and poll() must already see the flag it is about
	# to release.
	_locked_player = bool(page.get("lock_player", false))
	if _locked_player:
		ModeStack.push(ModeStack.Mode.CUTSCENE)

	# The actor's own brain is EventRunner.begin()'s business, not this file's - see the
	# class doc. Its in-flight route was already handed off above, by
	# _suspend_route_for_lease().
	var parallel := trigger_name == &"auto" and bool(settings.get("parallel", false))
	if parallel:
		EventScheduler.run_background(runner, graph, document_path, _active_page)
	else:
		if not EventScheduler.run_exclusive(runner, graph, document_path, _active_page):
			# Refused - the exclusive slot is already held. Give back the lease and
			# the fields just armed rather than leaving the actor claimed by, and
			# this event waiting on, a runner that never actually ran.
			if _actor != null:
				EventScheduler.release_lease(_actor.actor_id, runner)
			runner.latch.detach()
			_runner = null
			_runner_ctx = null
			_has_pre_facing = false
			_release_control_if_locked()
			_fired_once[_active_page] = false
			return

	# A synchronous run (no blocking node in it) is already finished by the time
	# either scheduler call above returns - poll() picks that up on its own next
	# pass, including the facing restore, so nothing further happens here.


# -- The active page's own route (event-pages.md §3, stage-c-plan.md segment 7) ----

## [code]page.get("route", {})[/code] is not enough on its own: every worked example in
## docs/events/ authors an empty route as [code][][/code] (an array), event-pages.md §2's
## "a page with no route stands still" having predated this dictionary shape entirely -
## so a page with no real route at all is read as stationary rather than raising a type
## error against [EventRoute].
func _route_of_page(page: Dictionary) -> Dictionary:
	var raw: Variant = page.get("route", {})
	return EventRoute.resolve(raw as Dictionary) if raw is Dictionary else {}


## Starts the active page's route as a background runner, resuming [member
## Actor.suspended_route] if it still matches what the page compiles to today and
## starting fresh otherwise. A no-op whenever one is already running - both call sites
## ([method _ready], [method poll]) call this unconditionally, and only one of them
## needs to actually do anything on a given call.
func _start_route() -> void:
	if _route_runner != null or _actor == null or _active_page < 0:
		return

	var route := _route_of_page(_pages()[_active_page])
	if EventRoute.is_stationary(route):
		return
	var nodes := EventRoute.compile(route)
	if nodes.is_empty():
		return

	var ctx := EventContext.for_event(
		_map, _map.map_id if _map != null else &"", event_id(), _actor)
	var runner := EventRunner.new(ctx)
	if not EventScheduler.try_lease(_actor.actor_id, runner):
		# Something else already holds this actor (a triggered graph mid-run reaching
		# here through a re-entrant poll, in practice) - the route stays idle until a
		# later _start_route call, once whatever holds the lease lets it go.
		runner.latch.detach()
		return
	_route_runner = runner

	var suspended := _actor.suspended_route
	if not suspended.is_empty() and str(suspended.get("hash", "")) == EventCommand.doc_hash(nodes):
		_actor.suspended_route = {}
		runner.restore(suspended.get("frames", []) as Array)
		EventScheduler.adopt_background(runner)
	else:
		# Either nothing was suspended, or the route has changed shape since it was -
		# "restart is always a legal downgrade" at route granularity (question 52).
		_actor.suspended_route = {}
		EventScheduler.run_background(runner, nodes)

	if runner.finished:
		EventScheduler.release_lease(_actor.actor_id, runner)
		_route_runner = null


## Discards the current route runner outright, with no bookmark left behind - a page
## switch (event-pages.md's own art/logic/route triple all changing together) means the
## old route is not coming back, so there is nothing worth resuming it into later.
func _stop_route() -> void:
	if _route_runner == null:
		return
	EventScheduler.release_lease(_actor.actor_id, _route_runner)
	_route_runner.stop()
	_route_runner = null


## The other half of preemption: a lease being taken away captures where the route was
## and writes it to [member Actor.suspended_route] (question 52) instead of discarding
## it, since this route - unlike a page switch's - is coming right back the moment the
## lease is released. [method EventRunner.to_save] is called before [method
## EventRunner.stop], not after: [code]stop()[/code] cancels whatever the runner's
## current node is mid-executing, which is exactly the in-flight state
## [code]to_save()[/code]'s own per-node [method EventCommandExec.capture] needs to see
## first.
func _suspend_route_for_lease() -> void:
	if _route_runner == null:
		return

	var route := _route_of_page(_pages()[_active_page]) if _active_page >= 0 else {}
	var nodes := EventRoute.compile(route)
	var saved := _route_runner.to_save()
	_actor.suspended_route = {
		"hash": EventCommand.doc_hash(nodes),
		"frames": saved.get("frames", []),
	}

	EventScheduler.release_lease(_actor.actor_id, _route_runner)
	_route_runner.stop()
	_route_runner = null
