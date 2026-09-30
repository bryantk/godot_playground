extends Node

## The hand-off between the field and the battle scene - what [code]start_battle[/code]'s
## own executor (events/commands/battle_execs.gd) writes before swapping scenes, and
## what battle_scene.gd reads on ready and writes back before swapping back. Autoloaded
## as [code]BattleTransfer[/code], the same "a global carries what a plain scene reload
## cannot" reasoning [code]change_map_marker[/code]'s own lookup avoids needing at all,
## except here there really is no destination-scene node to search: battle_scene.tscn
## is generic, not authored per-troop.
##
## Also the troop catalogue, since resolving [code]start_battle[/code]'s own
## [code]troop[/code] string is exactly this file's business - see [method troop].

## Set by [code]change_map[/code]... no: set by [StartBattle] before swapping to the
## battle scene. The scene the executor should return to on outcome.
var return_scene: String = ""

## What to fight - read by battle_scene.gd on ready, cleared once read.
var pending_troop: Troop = null

## "" while a fight is in progress or none has run yet; "victory"/"defeat" the moment
## battle_scene.gd resolves one - [StartBattle] polls this.
var outcome: StringName = &""

## Set by [StartBattle] alongside [member pending_troop] - true means a defeat is just
## another outcome (battle_scene.gd sets [member outcome] to [code]&"defeat"[/code] and
## the executor swaps back to the field, same as a victory); false (the default) means
## a defeat is final and [method BattleScene._finish] swaps straight to the game-over
## scene instead, leaving [code]start_battle[/code]'s own runner to hang forever - which
## is fine, since nothing should resume a graph past a defeat that ended the run.
var allow_defeat: bool = false

var _troop_catalogue: Dictionary = {}
var _enemy_catalogue: Dictionary = {}


func _ready() -> void:
	_seed_demo_troops()
	# Authored data under res://data/ (heroes, enemies, troops, items) joins the catalogues
	# the demo data above already filled - Party is loaded before this, so its half is ready.
	BattleData.apply_to_game()


func register_troop(troop: Troop) -> void:
	_troop_catalogue[troop.id] = troop


func troop(id: StringName) -> Troop:
	return _troop_catalogue.get(id)


func troop_catalogue() -> Array[Troop]:
	var out: Array[Troop] = []
	for id: Variant in _troop_catalogue:
		out.append(_troop_catalogue[id])
	return out


## Registered alongside every troop that names it (see [method _seed_demo_troops]) so
## an individual enemy can also be picked on its own - what the battle sandbox tool
## (tools/battle_sandbox.gd) builds an ad hoc [Troop] from, rather than only ever
## fighting a whole pre-authored one.
func register_enemy(enemy: EnemyDef) -> void:
	_enemy_catalogue[enemy.id] = enemy


func enemy_catalogue() -> Array[EnemyDef]:
	var out: Array[EnemyDef] = []
	for id: Variant in _enemy_catalogue:
		out.append(_enemy_catalogue[id])
	return out


## A small default bestiary, matching the troop ids docs/events/slime_a.event.json's
## own worked example already calls [code]start_battle[/code] with. A loose system seeds
## something playable by
## default rather than starting empty.
func _seed_demo_troops() -> void:
	_troop_catalogue.clear()
	_enemy_catalogue.clear()

	var slime := EnemyDef.new()
	slime.id = &"slime"
	slime.display_name = "Slime"
	slime.stats = _stats(10, 0, 3, 2, 1, 3)
	slime.stats.elements = {&"fire": 2.0}
	var slime_attack := Ability.new()
	slime_attack.id = &"tackle"
	slime_attack.display_name = "Tackle"
	slime_attack.power = 0.8
	slime.abilities = [slime_attack]
	slime.gold_reward = 8
	register_enemy(slime)

	var slime_pair := Troop.new()
	slime_pair.id = &"slime_pair"
	slime_pair.enemies = [{"enemy": slime, "count": 2}]
	register_troop(slime_pair)

	var awakened := EnemyDef.new()
	awakened.id = &"slime_awakened"
	awakened.display_name = "Awakened Slime"
	awakened.stats = _stats(22, 0, 5, 3, 2, 4)
	awakened.stats.elements = {&"fire": 2.0}
	awakened.abilities = [slime_attack]
	awakened.gold_reward = 20
	register_enemy(awakened)

	var slime_awakened := Troop.new()
	slime_awakened.id = &"slime_awakened"
	slime_awakened.enemies = [{"enemy": awakened, "count": 1}]
	register_troop(slime_awakened)


static func _stats(hp: int, mp: int, atk: int, def: int, mag: int, spd: int) -> Stats:
	var s := Stats.new()
	s.max_hp = hp
	s.max_mp = mp
	s.atk = atk
	s.def = def
	s.mag = mag
	s.spd = spd
	return s
