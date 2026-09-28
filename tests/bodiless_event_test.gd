extends Node

## Headless assertions that a bodiless [GameEvent] (no [Actor] at all - a plain
## region trigger) reads its own cell from its placement root's real position,
## instead of always reading [constant Vector3i.ZERO] regardless of where it sits -
## games/jrpg/jrpg_demo.tscn's own MapTransfer/BattleTrigger/PartyMenuTrigger/
## ShopTrigger placements are exactly this shape (see that scene's own note on why
## they carry no Actor or Sprite, unlike a real NPC such as Npc_8_12__nada).
##
##     godot --headless --path . res://tests/bodiless_event_test.tscn

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("GameEvent -- a bodiless region trigger's own cell, and firing action on one")
	print("")

	_test_bodiless_cell_reads_the_placement_root_position()
	_test_bodiless_event_fires_action_when_the_player_is_there()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


func _build_world() -> Dictionary:
	var root := Node2D.new()
	add_child(root)

	var ctx := MapContext.new()
	ctx.map_id = &"bodiless_test"
	ctx.cell_size = Vector3.ONE
	ctx.default_motion = Actor.MotionMode.GRID
	root.add_child(ctx)

	return {"root": root, "ctx": ctx}


## A plain positioned [Node2D] with a [GameEvent] child and nothing else - no [Actor],
## no [Sprite2D] - at [param cell]'s own centre. [param doc_path] loads through the
## normal [method GameEvent._ready]/[method GameEvent._load_document] path, same as a
## real placement, rather than reaching into [member GameEvent._doc] by hand.
func _build_bodiless_trigger(world: Dictionary, cell: Vector3i, doc_path: String = "") -> GameEvent:
	var ctx: MapContext = world["ctx"]

	var placement := Node2D.new()
	placement.name = "Trigger"
	placement.position = Space.as_v2(ctx.cell_centre(cell))

	var event := GameEvent.new()
	event.name = "GameEvent"
	event.document_path = doc_path
	placement.add_child(event)

	world["root"].add_child(placement)
	return event


func _build_player(world: Dictionary, cell: Vector3i) -> Actor:
	var ctx: MapContext = world["ctx"]

	var body := Node2D.new()
	body.name = "player_body"
	body.position = Space.as_v2(ctx.cell_centre(cell))

	var actor := Actor.new()
	actor.name = "Actor"
	actor.actor_id = &"player"
	actor.facing_count = 4
	body.add_child(actor)

	var adapter := Space2D.new()
	adapter.name = "Space"
	actor.add_child(adapter)

	var motion := GridMotion.new()
	motion.name = "Motion"
	motion.direction_count = 4
	actor.add_child(motion)

	var controller := PlayerController.new()
	controller.name = "PlayerController"
	actor.add_child(controller)

	world["root"].add_child(body)
	return actor


func _test_bodiless_cell_reads_the_placement_root_position() -> void:
	_section("GameEvent.cell() -- no Actor at all, reads the placement root's own cell")

	var world := _build_world()
	var event := _build_bodiless_trigger(world, Vector3i(3, 0, 2))

	_eq(event.cell(), Vector3i(3, 0, 2), "matches the Node2D placement root it sits under")

	world["root"].free()


## [b]Adjacent and faced, not same-cell.[/b] [method GameEvent._through_actors] reads
## [member Actor.through_actors] off [member GameEvent._actor] - null for a bodiless
## trigger, so it always answers false regardless of the page's own [code]through[/code]
## (see that method's own doc: "matching Actor.through_actors's own default"). A
## bodiless trigger's own [code]action[/code] fires the same way an ordinary NPC's
## does, then: the player must be one cell away and facing it - never sitting on top of
## it - which is why every trigger in games/jrpg/jrpg_demo.tscn sits one cell off its own
## map's player spawn rather than on it.
func _test_bodiless_event_fires_action_when_the_player_is_there() -> void:
	_section("GameEvent -- a bodiless trigger's own page fires 'action' when faced, one cell off")

	var world := _build_world()
	_build_bodiless_trigger(world, Vector3i(1, 0, 1),
		"res://tests/fixtures/bodiless_trigger.event.json")

	# A fresh Actor faces south (0, 0, 1) by default - one cell north of the trigger
	# means that default facing already looks straight at it, no turn needed.
	_build_player(world, Vector3i(1, 0, 0))
	GameState.clear()

	EventBus.player_interacted.emit()
	for i in 5:
		EventScheduler.tick(1.0 / 60.0)

	_ok(GameState.flag(&"trigger_fired"), "the trigger's own page ran")

	world["root"].free()
	GameState.clear()
	EventScheduler.reset()


func _section(title: String) -> void:
	print("  %s" % title)


func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1


func _eq(got: Variant, want: Variant, what: String) -> void:
	_ok(got == want, "%s (got %s, want %s)" % [what, got, want] if got != want else what)
