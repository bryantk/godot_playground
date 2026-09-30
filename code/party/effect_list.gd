class_name EffectList

## The operations on an [code]Array[ActiveEffect][/code] - a battler's effects, or a party
## member's - kept static and in one place so a fight and the field treat them identically.


## Puts [param effect] on [param list] under its own stacking rule. Returns the
## [ActiveEffect] now representing it, or null when [constant StatusEffect.Stack.IGNORE]
## left a running one alone.
static func add(list: Array[ActiveEffect], effect: StatusEffect) -> ActiveEffect:
	for active in list:
		if active.effect.id != effect.id:
			continue
		match effect.stacking:
			StatusEffect.Stack.IGNORE:
				return null
			StatusEffect.Stack.STACK:
				active.stacks = mini(active.stacks + 1, maxi(1, effect.max_stacks))
		active.remaining = effect.duration
		return active

	var fresh := ActiveEffect.new(effect)
	list.append(fresh)
	return fresh


## Counts down every effect whose unit is [param unit] by one, drops those that have run
## out or whose [member StatusEffect.until_flag] is now set, and returns what expired.
static func tick(list: Array[ActiveEffect], unit: StatusEffect.Unit) -> Array[StatusEffect]:
	var expired: Array[StatusEffect] = []
	for active in list.duplicate():
		var done := false
		if active.effect.duration > 0 and active.effect.unit == unit:
			active.remaining -= 1
			done = active.remaining <= 0
		if not done and active.effect.until_flag != &"":
			done = GameState.flag(active.effect.until_flag)
		if done:
			list.erase(active)
			expired.append(active.effect)
	return expired


## [param base] with every effect in [param list] applied, in the order they were added.
static func effective(base: Stats, list: Array[ActiveEffect]) -> Stats:
	var out := base
	for active in list:
		out = active.effect.modify(out, active.stacks)
	return out


static func has(list: Array[ActiveEffect], effect_id: StringName) -> bool:
	for active in list:
		if active.effect.id == effect_id:
			return true
	return false


static func to_save(list: Array[ActiveEffect]) -> Array:
	var out: Array = []
	for active in list:
		out.append(active.to_save())
	return out


## The inverse of [method to_save]. [param resolve] turns a saved id back into its
## [StatusEffect] (null drops the entry - an effect no longer in the game).
static func from_save(saved: Array, resolve: Callable) -> Array[ActiveEffect]:
	var out: Array[ActiveEffect] = []
	for entry: Variant in saved:
		var data := entry as Dictionary
		var effect: StatusEffect = resolve.call(StringName(str(data.get("id", ""))))
		if effect == null:
			continue
		var active := ActiveEffect.new(effect)
		active.stacks = int(data.get("stacks", 1))
		active.remaining = int(data.get("remaining", effect.duration))
		out.append(active)
	return out
