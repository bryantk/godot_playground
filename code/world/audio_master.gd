extends Node

## Project-wide sound-effect player. Nothing here is spatial or musical - just a name
## to a one-shot, non-positional [AudioStream] and a small pool of players so two
## effects overlapping never cut each other off.
##
## Autoloaded as [code]AudioMaster[/code]. There is no music/positional-audio system
## yet - this is deliberately the smallest thing that lets a gameplay script say
## [code]AudioMaster.play_sound_effect(&"push", 80.0)[/code] without knowing or caring
## how many players exist or which one is free.

## Name -> stream. Authored by hand on the autoload node in the editor; a name with no
## entry warns and does nothing rather than crashing a caller that assumed every sound
## it asks for exists.
@export var sounds: Dictionary[StringName, AudioStream] = {}

## How many effects can overlap before the oldest one still playing is cut off. Eight
## is generous for a top-down game where "the player pushed a crate" and "a zone's
## footstep sound" are about the busiest this ever gets.
const POOL_SIZE := 8

var _players: Array[AudioStreamPlayer] = []
var _next := 0


func _ready() -> void:
	for i in POOL_SIZE:
		var p := AudioStreamPlayer.new()
		p.name = "Player%d" % i
		add_child(p)
		_players.append(p)


## Plays [param name] once at [param volume] (0-100, linear) on the next player in the
## pool - round-robin, not "first free", so a long effect still gets cut off by its own
## kind eventually rather than starving every other sound behind it.
func play_sound_effect(name: StringName, volume: float = 100.0) -> void:
	var stream: AudioStream = sounds.get(name)
	if stream == null:
		push_warning("AudioMaster: no sound registered for '%s'." % name)
		return

	var player := _players[_next]
	_next = (_next + 1) % _players.size()
	player.stream = stream
	player.volume_db = linear_to_db(clampf(volume, 0.0, 100.0) / 100.0)
	player.play()
