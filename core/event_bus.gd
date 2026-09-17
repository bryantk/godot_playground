extends Node

## Project-wide signal hub. Nothing here holds game state or reaches into nodes - it
## just lets a sender fire an event without knowing who, if anyone, is listening.
##
## Autoloaded as [code]EventBus[/code].

## Asks for [param text] to be shown in the dialogue window. [param options] is a
## free-form bag the dialogue reader understands; unknown keys are ignored.
## Recognised keys:
## [codeblock]
## location: int  # index into Dialogue's locations, see Dialogue.Location
## append: bool   # follow the message before it, no outro/intro between
## [/codeblock]
## [param key] identifies this message so the sender can recognise its own
## completion; empty means the sender does not care.
signal dialogue_enqueue(text: String, options: Dictionary, key: String)

## Fired once a queued message has been read through and the window has closed.
## [param key] is the one the message was queued with, so a sender can await its
## own message finishing:
## [codeblock]
## var key := EventBus.say("Hello.")
## while await EventBus.dialogue_finished != key:
##     pass
## [/codeblock]
signal dialogue_finished(key: String)

## Convenience wrapper so callers can say [code]EventBus.say("...")[/code] instead of
## emitting by hand. Returns the key the message was queued under - the one passed
## in, or a fresh one from [method new_key] when [param key] is left empty.
func say(text: String, options: Dictionary = {}, key: String = "") -> String:
	if key == "":
		key = _new_key()
	dialogue_enqueue.emit(text, options, key)
	return key

func append_say(text: String, options: Dictionary = {}, key: String = "") -> String:
	options = options.duplicate()
	options["append"] = true
	return say(text, options, key)

func wait_for(key: String) -> void:
	if key == "":
		return

	while true:
		var finished_key: String = await dialogue_finished
		if finished_key == key:
			return

## Generic completion, mirroring [signal dialogue_finished]. Every long-running call
## in the project returns a key and reports it here, which is what lets a round be a
## join over keys rather than a mechanism of its own.
signal command_finished(key: String)


# -- What a grid actor did -----------------------------------------------------------
#
# Four moments, each a trigger rather than a clock: every one of these fires for every
# grid actor, always, with no mode or per-actor flag suppressing it. There used to be a
# distinction here - a "pulse" that only the player published, gated by a per-actor
# publishes_pulse flag and by ModeStack.suppresses_pulse(), plus a separate always-on
# cell_entered a trap could listen to instead. That distinction is gone as of
# 2026-09-14: publishes_pulse is deleted, actor_stepped always fires, and cell_entered
# is deleted because actor_stepped now does its job.
#
# What this meant for "does event-driven movement drive the monsters" (question 9),
# which the old gate answered at the emitter: that question did not go away, it moved -
# and then, on 2026-09-14, the thing it was going to move to was struck as well. The
# round gate, the step pulse and speed classes are all gone from the design (question
# 42), so there is no StepResponder to check anything, and "what drives a monster" is
# open question 46 rather than something this file has an opinion about.
#
# What survives is the rule that made the gate removable in the first place: EventBus
# is a dumb hub with no state (architecture.md 7.7), one signal per moment, and the
# consumer decides what the moment means to it - rather than the emitter deciding for
# every consumer at once. Whatever answers 46 will be a listener like any other.

## A committed step. Fired once per cell entered, at commit time - which is step
## [i]start[/i], since the body is authoritative and snaps to the destination
## immediately. Firing here rather than at visual settle is what makes monsters able to
## move [i]with[/i] the player, for whichever listener chooses to.
@warning_ignore("unused_signal")
signal actor_stepped(actor_id: StringName, from: Vector3i, to: Vector3i)

## The step has settled: the sprite has caught up to the body, [method Actor.cell] and
## the visual agree, and any zone the actor stepped out of is now visually left too (see
## [method Actor.settle_areas]). This is the "land-on-it" moment - a footfall sound, a
## camera nudge, a graph's [code]wait_settle[/code] joining the step's completion key
## from the other side.
##
## [param cell] is where the actor now visually is. A zero-duration step (no view, or a
## teleport-like [code]move_to[/code]) settles synchronously in the same frame as
## [signal actor_stepped], so a listener must not assume a frame gap between the two.
@warning_ignore("unused_signal")
signal actor_settled(actor_id: StringName, cell: Vector3i)

## The actor wanted to take a step and could not - the wall bump, terrain or occupancy.
## Published for what a bump legitimately feeds: a thud, an "it's locked" bark, a
## tutorial noticing the player pushing at the same wall. [param to] is the cell that was
## refused; the actor is still on [param from]. Opens no round (open-questions 7) - the
## explicit "wait one step" input is how time is passed on purpose, not this.
@warning_ignore("unused_signal")
signal actor_blocked(actor_id: StringName, from: Vector3i, to: Vector3i)

## The actor's facing changed - as part of a step, or a turn in place with no step at
## all. Fires for [i]any[/i] facing change, so a listener that means "turned in place"
## checks the actor is not moving. Opens no round either way (open-questions 6): turning
## changes no cell.
@warning_ignore("unused_signal")
signal actor_turned(actor_id: StringName, from_dir: Vector3i, to_dir: Vector3i)

## A fall is about to start: the actor is on nothing at [param from] and will land on
## [param to]. 3D grid maps only - see [Terrain].
##
## [b]Fired before the drop and before [member GridMotion.fall_delay] is waited out[/b],
## which is what turns that delay into a window a listener can use: play the hang, pull
## the camera back, start the sound. The actor still falls on its own afterwards; this
## announces a fall rather than asking permission for one.
@warning_ignore("unused_signal")
signal actor_falling(actor_id: StringName, from: Vector3i, to: Vector3i)

## The interact button, pressed for this actor - [member InputIntent.interact], read
## and cleared by [Brain] the same frame it fires. What [GameEvent]'s `action` trigger
## (decision 44) listens for: facing it or standing on a through event is the rest of
## that check, done by the listener, not here.
@warning_ignore("unused_signal")
signal actor_interacted(actor_id: StringName)


# -- The player's four ---------------------------------------------------------------
#
# Shorthand, because most listeners only ever care about the player: a HUD, a minimap,
# a footstep, a music cue, a "have you been here before" flag. Written out, every one of
# them is the same four lines - connect the actor_* signal, compare the id, drop the
# argument - and four lines repeated thirty times is thirty places to get the player
# test subtly wrong. Who counts as the player is Actor.is_player(), one definition;
# connect to the actor_* form or the player_* form for a given moment, never both, or a
# listener handles the player twice.
#
# One moment, one signal - there is no player_entered_cell and there will not be
# another player_step_completed-shaped variant of an existing one either. A listener
# that wants a subset of an event's payload drops the rest with an underscore; Godot
# will not connect a shorter callable to a signal (it logs and drops the call), so the
# underscore is required, and it is still cheaper than a second name for one event.

## The player committed a step. See [signal actor_stepped].
@warning_ignore("unused_signal")
signal player_stepped(from: Vector3i, to: Vector3i)

## The player's step settled. See [signal actor_settled].
@warning_ignore("unused_signal")
signal player_settled(cell: Vector3i)

## The player's step was refused. See [signal actor_blocked].
@warning_ignore("unused_signal")
signal player_blocked(from: Vector3i, to: Vector3i)

## The player's facing changed. See [signal actor_turned].
@warning_ignore("unused_signal")
signal player_turned(from_dir: Vector3i, to_dir: Vector3i)

## The player is about to fall. See [signal actor_falling].
@warning_ignore("unused_signal")
signal player_falling(from: Vector3i, to: Vector3i)

## The player pressed interact. See [signal actor_interacted].
@warning_ignore("unused_signal")
signal player_interacted()

@warning_ignore("unused_signal")
signal event_started(runner_id: String, exclusive: bool)
@warning_ignore("unused_signal")
signal event_finished(runner_id: String)
@warning_ignore("unused_signal")
signal map_changing(from_id: StringName, to_id: StringName)
@warning_ignore("unused_signal")
signal input_lock_changed(locked: bool)


## Await a completion key from any system, the same shape as [method wait_for].
## Returns at once on an empty key, so a caller need not check whether the command it
## issued was actually long-running.
func wait_for_command(key: String) -> void:
	if key == "":
		return

	while true:
		var finished_key: String = await command_finished
		if finished_key == key:
			return


## A random identifier, unique enough to tell one in-flight message from another.
func _new_key() -> String:
	var bytes := PackedByteArray()
	bytes.resize(16)
	for i in bytes.size():
		bytes[i] = randi() % 256
	return bytes.hex_encode()
