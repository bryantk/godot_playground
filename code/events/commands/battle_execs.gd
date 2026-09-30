## Battle executors. Only [code]start_battle[/code] has one.

const _BATTLE_SCENE := "res://code/battle/battle_scene.tscn"

## [code]core/save_game.gd[/code]'s own guard, mirrored - see map_execs.gd's identical
## constant for why this polls rather than [code]await[/code]s.
const _WAIT_TICKS := 600


## Swaps to the battle scene against [code]troop[/code], waits for an outcome, then
## swaps back to whichever scene it left - the same "swap, wait, resolve" shape
## [ChangeMapBase] uses, small enough here not to share it: there is no player to place
## afterward (the field scene's own authored positions are exactly where everyone
## already was), and no marker variant to factor out. See battle/battle_transfer.gd for
## the hand-off this drives through.
##
## [b][constant ModeStack.Mode.TRANSITION][/b] brackets each of the two scene swaps
## separately, nested inside [constant ModeStack.Mode.BATTLE] rather than one pair
## spanning the whole command - [code]BATTLE[/code] already spans the entire fight, not
## just the swap either side of it, and popping has to stay strictly LIFO against it.
## [EventBus.map_exiting]/[code]map_loaded[/code]/[code]map_arrived[/code] only fire
## around the [i]field[/i] half of the round trip - the battle scene carries no
## [MapContext] of its own, so there is no "map" to announce leaving or arriving at
## on that leg, only a pause worth enforcing while it loads.
class StartBattle extends EventCommandExec:
	enum _Phase { FADE_OUT, WAIT_BATTLE, WAIT_OUTCOME, WAIT_FIELD, FADE_IN, DONE }
	var _phase: int = _Phase.DONE
	var _guard := 0

	func survives_teardown() -> bool:
		return true

	func start() -> void:
		var troop_id := StringName(str(args.get("troop", "")))
		var troop: Troop = BattleTransfer.troop(troop_id)
		if troop == null:
			push_warning("EventRunner: start_battle - no troop named \"%s\"." % str(troop_id))
			_phase = _Phase.DONE
			return

		var tree := Engine.get_main_loop() as SceneTree
		BattleTransfer.return_scene = tree.current_scene.scene_file_path \
			if tree.current_scene != null else ""
		BattleTransfer.pending_troop = troop
		BattleTransfer.outcome = &""
		BattleTransfer.allow_defeat = bool(args.get("allow_defeat", false))
		ModeStack.push(ModeStack.Mode.BATTLE)
		# "on map exit" - leaving the field for the battle scene. Popped the instant
		# WAIT_BATTLE below confirms the battle scene loaded; BATTLE stays pushed
		# underneath for the whole fight.
		ModeStack.push(ModeStack.Mode.TRANSITION)
		EventBus.map_exiting.emit(ctx.map)

		var seconds := float(args.get("fade_out", 0.0))
		if seconds > 0.0:
			GameUI.fade_to(0.0, seconds, load_texture_arg(args.get("texture", "")))
			_phase = _Phase.FADE_OUT
		else:
			_swap_to_battle()

	func _swap_to_battle() -> void:
		(Engine.get_main_loop() as SceneTree).change_scene_to_file(_BATTLE_SCENE)
		_phase = _Phase.WAIT_BATTLE
		_guard = 0

	func _swap_to_field() -> void:
		(Engine.get_main_loop() as SceneTree).change_scene_to_file(BattleTransfer.return_scene)
		_phase = _Phase.WAIT_FIELD
		_guard = 0

	func _begin_fade_in() -> void:
		var seconds := float(args.get("fade_in", 0.0))
		if seconds > 0.0:
			GameUI.fade_to(1.0, seconds, load_texture_arg(args.get("texture", "")))
			_phase = _Phase.FADE_IN
		else:
			_phase = _Phase.DONE

	func tick(_delta: float) -> int:
		var tree := Engine.get_main_loop() as SceneTree

		if _phase == _Phase.FADE_OUT:
			if GameUI.is_fading():
				return Status.RUNNING
			_swap_to_battle()

		if _phase == _Phase.WAIT_BATTLE:
			if tree.current_scene == null or tree.current_scene.scene_file_path != _BATTLE_SCENE:
				_guard += 1
				if _guard > _WAIT_TICKS:
					push_warning("EventRunner: start_battle - the battle scene never loaded.")
					ModeStack.pop()  # TRANSITION
					ModeStack.pop()  # BATTLE
					_phase = _Phase.DONE
					return Status.DONE
				return Status.RUNNING
			# The battle scene is up - TRANSITION's job here is done; BATTLE stays
			# pushed underneath for the fight itself.
			ModeStack.pop()
			_phase = _Phase.WAIT_OUTCOME
			_guard = 0

		if _phase == _Phase.WAIT_OUTCOME:
			if BattleTransfer.outcome == &"":
				return Status.RUNNING
			# Re-pushed for the return leg's own swap - no map_exiting this time
			# (see this class's own doc): there is no MapContext on the battle side to
			# announce leaving, only a pause worth enforcing while the field reloads.
			ModeStack.push(ModeStack.Mode.TRANSITION)
			_swap_to_field()

		if _phase == _Phase.WAIT_FIELD:
			var found: MapContext = tree.get_first_node_in_group(&"map_context")
			if found == null:
				_guard += 1
				if _guard > _WAIT_TICKS:
					push_warning("EventRunner: start_battle - the field scene never registered a MapContext.")
					ModeStack.pop()  # TRANSITION
					ModeStack.pop()  # BATTLE
					_phase = _Phase.DONE
					return Status.DONE
				return Status.RUNNING
			EventBus.map_loaded.emit(found)
			ctx.rebind_map(found)
			ModeStack.pop()  # TRANSITION - background processing resumes with the fade-in
			EventBus.map_arrived.emit(found)
			ModeStack.pop()  # BATTLE - the fight itself is over
			_begin_fade_in()

		if _phase == _Phase.FADE_IN:
			if GameUI.is_fading():
				return Status.RUNNING
			_phase = _Phase.DONE

		return Status.DONE if _phase == _Phase.DONE else Status.RUNNING


static func table() -> Dictionary:
	return {
		"start_battle": StartBattle,
	}
