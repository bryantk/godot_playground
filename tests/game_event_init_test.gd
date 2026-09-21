extends Node

## Headless assertions that [GameEvent] is the master of an actor/sprite's
## initialization data (docs/events/ authoring note): its own exported fields land on
## the [Actor]/[ActorView] it owns before that [Actor]'s own [method Node._ready] runs,
## a blank [member GameEvent.actor_id] derives one from the placement node's own name
## rather than registering blank - but never over a hand-set [member Actor.actor_id]
## from before this field existed - and through/through_terrain/facing_locked are the
## actor's resting default whenever no page's document is active to say otherwise.
##
##     godot --headless --path . res://tests/game_event_init_test.tscn

const FIXTURES := "res://tests/fixtures/"

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("events -- GameEvent pushes its own fields onto the Actor/ActorView it owns")
	print("")

	_test_actor_id_pushed_before_actor_ready_registers()
	_test_blank_actor_id_derives_from_placement_node_name()
	_test_blank_event_actor_id_keeps_a_hand_set_actor_id()
	_test_sprite_init_pushed_to_view()
	_test_flags_fall_back_to_event_defaults_when_no_page_is_active()
	_test_page_settings_still_override_event_defaults()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- actor_id lands before Actor._ready registers it ---------------------------------

func _test_actor_id_pushed_before_actor_ready_registers() -> void:
	_section("actor_id -- pushed before Actor._ready, so registration sees it")

	var world := _build_world()
	var ctx: MapContext = world["ctx"]

	# The Actor node itself is left with no id at all - exactly the shape a GameEvent-
	# authored placement has, now that actor_id belongs on GameEvent. If the push landed
	# too late, Actor._ready would register under "" and MapContext would refuse it
	# (core/map_context.gd's own push_error), and this lookup would come back null.
	var rig := _build_sibling_event(world, &"", Vector3i(0, 0, 0), "")
	var event: GameEvent = rig["event"]
	event.actor_id = &"npc_pushed"
	world["root"].add_child(rig["body"])

	_ok(ctx.has_actor(&"npc_pushed"), "registered under the id GameEvent pushed, not blank")
	_eq(ctx.actor(&"npc_pushed"), rig["actor"], "and it is this event's own actor")

	world["root"].free()


# -- a blank actor_id falls back to the placement node's own name --------------------

func _test_blank_actor_id_derives_from_placement_node_name() -> void:
	_section("actor_id -- blank everywhere derives from the placement node's own name")

	var world := _build_world()
	var ctx: MapContext = world["ctx"]

	# Neither GameEvent.actor_id nor the Actor's own actor_id is set - nobody named
	# this placement anywhere. _build_sibling_event names the body node "body".
	var rig := _build_sibling_event(world, &"", Vector3i(4, 0, 0), "")
	world["root"].add_child(rig["body"])

	_ok(ctx.has_actor(&"body"), "registered under the placement node's own name")
	_eq(ctx.actor(&"body"), rig["actor"], "and it is this event's own actor")

	world["root"].free()


func _test_blank_event_actor_id_keeps_a_hand_set_actor_id() -> void:
	_section("actor_id -- a blank GameEvent field never overwrites a hand-set Actor one")

	var world := _build_world()
	var ctx: MapContext = world["ctx"]

	# A scene authored before this field existed: the Actor node carries its own id
	# directly, and GameEvent.actor_id is left at its default blank.
	var rig := _build_sibling_event(world, &"hand_set_id", Vector3i(5, 0, 0), "")
	world["root"].add_child(rig["body"])

	_ok(ctx.has_actor(&"hand_set_id"), "still registered under the hand-set id")
	_ok(not ctx.has_actor(&"body"), "not clobbered by the placement node's own name")

	world["root"].free()


# -- y_level / visible land on the view -----------------------------------------------

func _test_sprite_init_pushed_to_view() -> void:
	_section("y_level / visible -- pushed onto the ActorView before it draws a frame")

	var world := _build_world()
	var rig := _build_sibling_event(world, &"npc_sprite", Vector3i(1, 0, 0), "")
	var event: GameEvent = rig["event"]
	event.y_level = 7
	event.visible = false
	world["root"].add_child(rig["body"])

	var view: ActorView = (rig["actor"] as Actor).view()
	_eq(view.y_level, 7, "y_level reached the view")
	_ok(not (view.visual() as CanvasItem).visible, "and visible=false hid the sprite")

	world["root"].free()


# -- through/through_terrain/facing_locked fall back to GameEvent's own fields --------

## [method GameEvent._apply_actor_flags] only ever runs once a page is active - and
## [method EventDocument.parse] always writes [code]through[/code]/
## [code]through_terrain[/code]/[code]lock_facing[/code] explicitly onto every parsed
## page (an omitted key normalizes to [code]false[/code], not "unset"), so a page
## always has a real opinion the moment one is active. What GameEvent's own fields
## actually govern is the actor before any of that: a bodied event with no document at
## all, where no page is ever active and [method _push_init]'s push is the only thing
## that ever touches these three.
func _test_flags_fall_back_to_event_defaults_when_no_page_is_active() -> void:
	_section("through/through_terrain/facing_locked -- the actor's only setting with no active page")

	var world := _build_world()
	var rig := _build_sibling_event(world, &"npc_default", Vector3i(2, 0, 0), "")
	var event: GameEvent = rig["event"]
	event.through_actors = true
	event.through_terrain = true
	event.facing_locked = true
	world["root"].add_child(rig["body"])

	var npc: Actor = rig["actor"]
	_eq((rig["event"] as GameEvent).active_page(), -1, "no document means no active page")
	_ok(npc.through_actors, "through_actors is the event's own pushed true")
	_ok(npc.through_terrain, "and so is through_terrain")
	_ok(npc.facing_locked, "and facing_locked")

	world["root"].free()


func _test_page_settings_still_override_event_defaults() -> void:
	_section("through -- a page that does specify it still wins over GameEvent's own field")
	GameState.clear()

	var world := _build_world()
	var rig := _build_sibling_event(world, &"npc_override", Vector3i(3, 0, 0),
		FIXTURES + "sched_through.event.json")
	var event: GameEvent = rig["event"]
	event.through_actors = false  # the event's own resting default
	world["root"].add_child(rig["body"])

	var player := _build_actor(world, &"player", Vector3i(3, 0, 0))
	EventBus.player_interacted.emit()

	var npc: Actor = rig["actor"]
	_ok(GameState.flag(&"fired_through"), "sched_through's action page ran")
	_ok(npc.through_actors, "through=true on the page overrode the event's own false")

	player.get_parent().queue_free()
	world["root"].free()
	GameState.clear()


# -- Test rig ------------------------------------------------------------------------

func _build_world() -> Dictionary:
	var root := Node2D.new()
	add_child(root)

	var ctx := MapContext.new()
	ctx.map_id = &"init_test"
	ctx.cell_size = Vector3.ONE
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)

	return {"root": root, "ctx": ctx}


func _build_actor(world: Dictionary, id: StringName, cell: Vector3i) -> Actor:
	var ctx: MapContext = world["ctx"]

	var body := Node2D.new()
	body.name = str(id)
	body.position = Space.as_v2(ctx.cell_centre(cell))

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = id
	actor.facing_count = 4
	body.add_child(actor)

	var adapter := Space2D.new()
	adapter.name = "Space"
	actor.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = 4
	actor.add_child(motion)

	(world["root"] as Node).add_child(body)
	return actor


## The shape [games/jrpg/jrpg_demo.tscn] actually authors, not event-pages.md §4.3's own
## diagram: [Actor] and [GameEvent] as siblings under one body, [Actor] first in child
## order - the harder ordering for [method GameEvent._push_init] to still land ahead of
## [method Actor._ready] on, and so the one worth testing against.
##
## Returned with its body [b]not yet added[/b] to [param world]'s root, so the caller
## can finish configuring the event's exported fields before the whole rig enters the
## tree in one call - matching how a real [PackedScene] enters (see
## [method GameEvent._push_init]'s own doc).
func _build_sibling_event(world: Dictionary, id: StringName, cell: Vector3i,
		doc_path: String) -> Dictionary:
	var ctx: MapContext = world["ctx"]

	var body := Node2D.new()
	body.name = "body"
	body.position = Space.as_v2(ctx.cell_centre(cell))

	var actor := Actor.new()
	actor.name = "Actor"
	if id != &"":
		actor.actor_id = id
	actor.facing_count = 4
	body.add_child(actor)

	var adapter := Space2D.new()
	adapter.name = "Space"
	actor.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = 4
	actor.add_child(motion)

	var sprite := Sprite2D.new()
	sprite.name = "Sprite"
	body.add_child(sprite)

	var view := Node.new()
	view.set_script(load("res://actors/views/sprite_view_2d.gd"))
	view.name = "View"
	view.set("visual_path", NodePath("../../Sprite"))
	actor.add_child(view)

	var event := GameEvent.new()
	event.name = "GameEvent"
	event.document_path = doc_path
	body.add_child(event)

	return {"body": body, "actor": actor, "event": event}


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
