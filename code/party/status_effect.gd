@tool
class_name StatusEffect extends Resource

## A temporary change to a combatant's stats - a buff, a debuff - applied by an ability in
## battle or by an item or event in the field. Plain data; [EffectList] applies, stacks and
## expires them and [ActiveEffect] is one running instance.
##
## [b]How it changes stats.[/b] Per stack, [member flat] is added to a stat and [member
## percent] scales it (+50 is half again as much, -30 is 30% less), flat first, so
## [code]{"atk": 3}[/code] with [code]{"atk": 50}[/code] on base 10 is (10 + 3) * 1.5.
## Keys are the six stat names in [constant STATS].
##
## [b]How long it lasts.[/b] [member duration] counts down in [member unit]: rounds tick at
## the end of each battle round, steps tick as the player walks. An effect only ticks in its
## own unit, so a STEPS effect is frozen during a fight and a ROUNDS effect applied in the
## field waits for one. A [member duration] of 0 or less never runs out by itself, and
## [member until_flag] ends it the moment that global flag is true, whichever comes first.

enum Unit { ROUNDS, STEPS }
enum Stack { REFRESH, STACK, IGNORE }

const STATS: PackedStringArray = ["max_hp", "max_mp", "atk", "def", "mag", "spd"]

@export var id: StringName = &""
@export var display_name: String = ""
@export_multiline var description: String = ""

## stat name -> amount added per stack.
@export var flat: Dictionary = {}

## stat name -> percent change per stack.
@export var percent: Dictionary = {}

@export var duration: int = 3
@export var unit: Unit = Unit.ROUNDS
@export var until_flag: StringName = &""

## Applying it again while it is already on: REFRESH restarts the timer, STACK adds a stack
## (up to [member max_stacks]) and restarts it, IGNORE leaves the running one alone.
@export var stacking: Stack = Stack.REFRESH
@export var max_stacks: int = 3


## [param base] with this effect at [param stacks] stacks applied - a new [Stats], the
## original untouched. Elements come across unchanged.
func modify(base: Stats, stacks: int = 1) -> Stats:
	var out := Stats.new()
	out.elements = base.elements.duplicate()
	for stat in STATS:
		var value := float(int(base.get(stat)))
		value += float(flat.get(stat, 0)) * stacks
		value *= 1.0 + float(percent.get(stat, 0)) * stacks / 100.0
		out.set(stat, maxi(1 if stat == "max_hp" else 0, roundi(value)))
	return out
