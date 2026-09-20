extends Node

## One save slot, on top of the hooks stage C's segment 5 built. Autoloaded as
## [code]SaveGame[/code].
##
## [b]The envelope[/b] is [code]{format, scene_path, game_state, scheduler, actors}[/code]:
## [member GameState.to_save]/[method EventScheduler.to_save] compose straight in, and
## [code]scene_path[/code] is read off [member SceneTree.current_scene] rather than a
## separate map-id-to-scene registry - there is nothing else to keep in sync as maps are
## added. [code]actors[/code] is [code]actor_id -> [method Actor.to_save][/code] for every
## actor the current map has registered.
##
## [b]Restore order is deliberate[/b]: change scene, wait for the new map to actually
## register itself (reusing [code]&"map_context"[/code], the same group
## [DebugPassabilityView] already finds the current map by), [GameState] (a restored
## runner's doc reload or a page's own conditions may read a flag), then every actor's
## position and facing, and only then [EventScheduler] - which leases actors and can push
## [constant ModeStack.Mode.CUTSCENE], and should only do either once everyone involved is
## standing where they belong rather than mid-teleport.
##
## [b]Known gap:[/b] a [FreeMotion] actor's own mid-flight state (velocity, an
## in-progress jump) is not captured - [method Actor.to_save] restores position only, the
## same "restart is a legal downgrade" (question 39) segments 5a/5b already lean on.

const FORMAT := 1
const SLOT_PATH := "user://save_slot_1.json"


func can_load() -> bool:
	return FileAccess.file_exists(SLOT_PATH)


## False if the save was refused outright - during BATTLE, or with no current map to
## save from at all - rather than silently writing an empty or partial slot.
func save() -> bool:
	var scene := get_tree().current_scene
	if scene == null or scene.scene_file_path == "":
		push_error("SaveGame: no current scene to save.")
		return false

	var scheduler_state := EventScheduler.to_save()
	if scheduler_state.is_empty():
		# EventScheduler already logged why (BATTLE) - nothing more to add.
		return false

	var actors := {}
	# Not MapContext.of(scene): that walks scene's own children then upward, which
	# never finds a MapContext sitting *below* the scene root (Upscale/World/Map/
	# MapContext, three levels down here) - the same group DebugPassabilityView and
	# this file's own load() already use is what actually answers "the current map".
	var ctx: MapContext = get_tree().get_first_node_in_group(&"map_context")
	if ctx != null:
		for a in ctx.actors():
			actors[str(a.actor_id)] = a.to_save()

	var envelope := {
		"format": FORMAT,
		"scene_path": scene.scene_file_path,
		"game_state": GameState.to_save(),
		"scheduler": scheduler_state,
		"actors": actors,
	}

	var f := FileAccess.open(SLOT_PATH, FileAccess.WRITE)
	if f == null:
		push_error("SaveGame: could not open '%s' for writing." % SLOT_PATH)
		return false
	f.store_string(JSON.stringify(envelope))
	f.close()
	return true


## Awaitable - the scene change it starts is deferred by Godot itself, so the caller
## has to wait for the new map before anything here can touch it.
func load() -> bool:
	if not can_load():
		return false

	var envelope: Variant = JSON.parse_string(FileAccess.get_file_as_string(SLOT_PATH))
	if not (envelope is Dictionary):
		push_error("SaveGame: '%s' is not valid JSON." % SLOT_PATH)
		return false
	var data: Dictionary = envelope

	# Drop whatever the map being left behind was doing before abandoning it - the same
	# reasoning EventScheduler.reset's own doc gives for calling it here.
	EventScheduler.reset()
	ModeStack.reset()

	get_tree().change_scene_to_file(str(data.get("scene_path", "")))

	var ctx: MapContext = null
	var guard := 0
	while ctx == null and guard < 600:
		await get_tree().process_frame
		ctx = get_tree().get_first_node_in_group(&"map_context")
		guard += 1
	if ctx == null:
		push_error("SaveGame: the loaded scene never registered a MapContext.")
		return false

	GameState.from_save(data.get("game_state", {}))

	var actor_states: Dictionary = data.get("actors", {})
	for a in ctx.actors():
		var saved: Variant = actor_states.get(str(a.actor_id))
		if saved is Dictionary:
			a.from_save(saved as Dictionary)

	EventScheduler.from_save(data.get("scheduler", {}), ctx)
	return true
