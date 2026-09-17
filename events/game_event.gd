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

## The facing captured just before an interaction starts, restored once it ends -
## unless a movement/facing executor touched this event's own actor during the run
## ([member EventContext.self_actor_touched]), in which case that is treated as
## deliberate and left alone. [member _has_pre_facing] is false whenever there is
## nothing to restore (no [Actor], or nothing currently in flight).
var _pre_interaction_facing: Vector3i = Vector3i.ZERO
var _has_pre_facing := false


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


func _exit_tree() -> void:
	_unregister()


func _process(_delta: float) -> void:
	poll()


## Notices a finished runner and re-checks the deferred page switch. A real frame
## calls this through [method Node._process]; a headless test - which drives
## [EventScheduler] by hand rather than waiting on real frames - calls it directly.
func poll() -> void:
	if _runner != null and _runner.finished:
		if _actor != null:
			EventScheduler.release_lease(_actor.actor_id, _runner)
		_runner = null
		_restore_facing_if_untouched()
		_refresh_active_page()


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


func event_id() -> StringName:
	return StringName(name)


func cell() -> Vector3i:
	return _actor.cell() if _actor != null else Vector3i.ZERO


func is_busy() -> bool:
	return _runner != null and not _runner.finished


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
	_active_page = index
	_apply_art()


func _apply_art() -> void:
	if _view == null or _active_page < 0:
		return
	_view.apply_art((_pages()[_active_page] as Dictionary).get("art", {}))


func _settings() -> Dictionary:
	if _active_page < 0:
		return {}
	return (_pages()[_active_page] as Dictionary).get("settings", {})


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


func _on_player_interacted() -> void:
	var player := _player()
	if player != null and player.cell() + player.facing() == cell():
		_maybe_fire(&"action")


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

	var parallel := trigger_name == &"auto" and bool(settings.get("parallel", false))
	if parallel:
		EventScheduler.run_background(runner, graph)
	else:
		if not EventScheduler.run_exclusive(runner, graph):
			# Refused - the exclusive slot is already held. Give back the lease and
			# the fields just armed rather than leaving the actor claimed by, and
			# this event waiting on, a runner that never actually ran.
			if _actor != null:
				EventScheduler.release_lease(_actor.actor_id, runner)
			runner.latch.detach()
			_runner = null
			_runner_ctx = null
			_has_pre_facing = false
			_fired_once[_active_page] = false
			return

	# A synchronous run (no blocking node in it) is already finished by the time
	# either scheduler call above returns - poll() picks that up on its own next
	# pass, including the facing restore, so nothing further happens here.
