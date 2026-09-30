extends Node

## Records "consumed" player input frame by frame, saves/loads it as a rotating log, and
## replays it back deterministically. Autoloaded as [code]InputReplay[/code].
##
## [code]todo.txt[/code]'s own item: "capture 'consumed' input and log it - rotate log
## files 1,2,3 for now. should be able to replay input files deterministically." Dev-tool
## scope, matching [DebugFlags]/[DebugPassabilityView] - no UI here, just the mechanism;
## something wires [method start_recording]/[method save]/[method start_replay] to a
## debug key or console.
##
## [b]What "deterministic" actually covers.[/b] [InputIntent] (code/world/input_intent.gd)
## is already exactly "the consumed input" for one frame - captured verbatim, every
## frame, not a sparse diff of changes, since replay needs the same frame count as much
## as the same values. The one thing recording the intent alone would miss: [GridMotion]
## reads a real, live per-frame delta directly from Godot, not from whatever
## [PlayerController] happens to be doing - so replay does not just re-feed [param intent]
## fields, it takes over [PlayerController]'s and its actor's [GridMotion]'s own automatic
## processing (both already toggle [method Node.set_process] themselves) and drives both
## by hand, once per recorded frame, with the recorded delta rather than the replaying
## machine's real one. [FreeMotion] needs no such handling - its [method
## Node._physics_process] already runs on Godot's fixed physics tick regardless of render
## rate. The RNG seed in use at recording start is captured and re-seeded at replay
## start, closing the other real non-determinism source in this codebase (a handful of
## unseeded [method @GlobalScope.randi] calls - event_command.gd, battle_state.gd,
## route_execs.gd). Godot's own physics solver ([FreeMotion]'s [method
## CharacterBody3D.move_and_slide]) is not covered - not something this project controls
## closely enough to guarantee bit-exact.

const SLOT_COUNT := 3
const SLOT_PATH_FORMAT := "user://input_replay_%d.json"
const META_PATH := "user://input_replay_meta.json"

var _recording := false
var _frames: Array = []
var _seed: int = 0

var _replaying := false
var _cursor := 0

## The pair replay drives, wired by [method bind] before [method start_replay].
## [member _motion] is null for a [FreeMotion] actor (or none at all) - [method
## step_replay] simply skips the manual-processing half then, since nothing there
## needs it.
var _player: PlayerController = null
var _motion: GridMotion = null


# -- Recording --------------------------------------------------------------------

## Starts a fresh recording - clears any previous in-memory log and pins down a real
## seed for [method @GlobalScope.randi]/[method @GlobalScope.randf] going forward, so
## replay can put the RNG back where recording found it.
func start_recording() -> void:
	_frames.clear()
	_seed = randi()
	seed(_seed)
	_recording = true


func is_recording() -> bool:
	return _recording


func stop_recording() -> void:
	_recording = false


## Called once per frame from [method PlayerController._process], right after [method
## PlayerController._think] fills [param intent] - the exact input consumed this frame,
## paired with the [param delta] it was consumed against. A flat array, not a dict -
## matching this project's own preference for terse array encoding (an event graph
## node's own cell args) over a verbose per-field object repeated every frame.
func capture_frame(delta: float, intent: InputIntent) -> void:
	if not _recording:
		return
	_frames.append([
		delta,
		intent.move.x, intent.move.y, intent.move.z,
		intent.jump, intent.run, intent.interact,
		intent.step.x, intent.step.y, intent.step.z,
		intent.turn.x, intent.turn.y, intent.turn.z,
		intent.wait, intent.step_locked(),
	])


# -- Saving, with rotation ---------------------------------------------------------

## The slot [method save] will use next - kept in [constant META_PATH] so the rotation
## survives an engine restart instead of depending on file modified-times.
func _next_slot() -> int:
	if not FileAccess.file_exists(META_PATH):
		return 1
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(META_PATH))
	return int((parsed as Dictionary).get("next_slot", 1)) if parsed is Dictionary else 1


func _write_next_slot(next_slot: int) -> void:
	var f := FileAccess.open(META_PATH, FileAccess.WRITE)
	if f == null:
		push_error("InputReplay: could not open '%s' for writing." % META_PATH)
		return
	f.store_string(JSON.stringify({"next_slot": next_slot}))
	f.close()


## Writes the recorded log to the next rotating slot (1, 2, 3, 1, ...) and returns the
## slot number it wrote, or -1 on failure.
func save() -> int:
	var slot := _next_slot()
	var path := SLOT_PATH_FORMAT % slot
	var f := FileAccess.open(path, FileAccess.WRITE)
	if f == null:
		push_error("InputReplay: could not open '%s' for writing." % path)
		return -1
	f.store_string(JSON.stringify({"seed": _seed, "frames": _frames}))
	f.close()
	_write_next_slot((slot % SLOT_COUNT) + 1)
	return slot


# -- Loading and replay -------------------------------------------------------------

## Loads [param slot]'s log (1-based) without starting playback.
func load_slot(slot: int) -> bool:
	var path := SLOT_PATH_FORMAT % slot
	if not FileAccess.file_exists(path):
		push_warning("InputReplay: no log at '%s'." % path)
		return false
	var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(path))
	if not (parsed is Dictionary):
		push_warning("InputReplay: '%s' is not a valid log." % path)
		return false
	var doc: Dictionary = parsed
	_seed = int(doc.get("seed", 0))
	_frames = doc.get("frames", [])
	return true


## Wires the [PlayerController]/[GridMotion] pair replay drives, and disables their own
## automatic processing for the duration - real [code]Input.*[/code] reads and Godot's
## own live frame delta must not also reach them while a recorded frame is being fed in
## by hand (see [method step_replay]).
func bind(player: PlayerController) -> void:
	_player = player
	_motion = player.motion() as GridMotion
	player.set_process(false)
	if _motion != null:
		_motion.set_process(false)


## Hands control back to the real input/processing loop - called automatically once
## [method step_replay] exhausts the log, or by hand to cut a replay short.
func unbind() -> void:
	if _player != null:
		_player.set_process(true)
	if _motion != null:
		_motion.set_process(true)
	_player = null
	_motion = null


func start_replay(slot: int) -> bool:
	if not load_slot(slot):
		return false
	seed(_seed)
	_replaying = true
	_cursor = 0
	return true


func is_replaying() -> bool:
	return _replaying


func is_finished() -> bool:
	return _cursor >= _frames.size()


## Feeds one recorded frame to whatever [method bind] wired up, in the same shape
## [method PlayerController._process] would have used live - [method
## PlayerController.apply_intent] then [GridMotion._process], both handed the recorded
## delta rather than whatever delta the caller's own loop happens to be running at. A
## no-op once nothing is bound or the log is exhausted - check [method is_finished]
## first, or just call this every frame and let it unbind itself when done.
func step_replay() -> void:
	if not _replaying or _player == null or is_finished():
		return

	var f: Array = _frames[_cursor]
	_cursor += 1

	var intent := _player.intent
	var delta: float = f[0]
	intent.move = Vector3(f[1], f[2], f[3])
	intent.jump = f[4]
	intent.run = f[5]
	intent.interact = f[6]
	intent.turn = Vector3i(f[10], f[11], f[12])
	intent.wait = f[13]
	# lock_step() zeroes step the instant it locks - set after, or the recorded step
	# below would be clobbered right back to ZERO.
	intent.lock_step(f[14])
	intent.step = Vector3i(f[7], f[8], f[9])

	_player.apply_intent(delta)
	if _motion != null:
		_motion._process(delta)

	if is_finished():
		_replaying = false
		unbind()


# -- Status and cancel (for the debug menu) ----------------------------------------

## Frames in the log - recorded so far while recording, total while replaying.
func frame_count() -> int:
	return _frames.size()


## Frames of the loaded log already fed back during a replay.
func replay_cursor() -> int:
	return _cursor


## Cuts a replay short, handing control back to real input and processing. A no-op when
## nothing is replaying.
func stop_replay() -> void:
	if not _replaying:
		return
	_replaying = false
	unbind()
