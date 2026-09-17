class_name EventContext extends RefCounted

## What a running graph carries beyond [GameState], which is global and needs no
## threading at all - any executor or condition reaches it directly. What isn't global:
##
## - [b]Identity[/b] ([member map_id], [member event_id]) - fixed the moment a runner is
##   created and never reassigned after, including across a [code]call[/code] (question
##   49) or a [code]change_map[/code] (question 51). Every [code]self_flag[/code] read
##   or written for the life of a runner resolves against this, not whatever map or
##   document happens to be executing at the time.
## - [b]A live map reference[/b] ([member map]) - the current [MapContext], for
##   [code]@[/code]-resolution and cell lookups. Fixed for an ordinary runner; rebound
##   exactly once, on [code]change_map[/code] completion, for a runner that survives one.
##
## [method condition_ctx] produces the exact shape [method EventCondition.evaluate]/
## [method EventCondition.keys] already expect - one function feeding both a page's
## [method EventDocument.active_page] check and a running [code]if[/code]/[code]eval[/code]
## node, so the two can never disagree about what "self" means.

var map_id: StringName = &""
var event_id: StringName = &""

## The current live map. Rebound on change_map (51); never on anything else.
var map: MapContext = null

## @self - null for a bodiless region trigger.
var self_actor: Actor = null

## Optional predicate providers EventCondition asks for leaves whose systems don't exist
## yet (item, party_has) - forwarded verbatim into condition_ctx().
var has_item: Callable
var party_has: Callable

## Set by a movement/facing executor (face_direction, face_to, step, move_to, move_by,
## jump, teleport) when it acts on [member self_actor] specifically - GameEvent reads
## this once the runner finishes to decide whether a facing it captured before an
## interaction should be restored. Deliberately narrower than "did actor_turned fire
## for this actor at all": that would also catch something unrelated nudging the same
## actor mid-interaction, which is not what "a movement command was received" means.
var self_actor_touched := false


## Call from a movement/facing executor's own start(), with whichever actor it just
## acted on. A no-op for any actor other than [member self_actor], so calling it
## unconditionally is always safe.
func mark_actor_touched(acted_on: Actor) -> void:
	if acted_on != null and self_actor != null and acted_on == self_actor:
		self_actor_touched = true


static func for_event(a_map: MapContext, a_map_id: StringName, a_event_id: StringName,
		actor: Actor = null) -> EventContext:
	var ctx := EventContext.new()
	ctx.map = a_map
	ctx.map_id = a_map_id
	ctx.event_id = a_event_id
	ctx.self_actor = actor
	return ctx


## "@player" / "@self" / "@npc_scout" -> a live Actor, or null when it cannot resolve.
## A bare, non-"@" string is never accepted here - question 40 makes that a literal, and
## resolving one anyway would silently paper over an authoring mistake the validator
## already catches.
func resolve(term: String) -> Actor:
	if not EventCommand.is_term(term):
		return null

	var name := EventCommand.term_name(term)
	if name == "self":
		return self_actor
	if map == null:
		return null
	if name == "player":
		for a in map.actors():
			if a.is_player():
				return a
		return null
	return map.actor(StringName(name))


## The exact shape [method EventCondition.evaluate]/[method EventCondition.keys] expect.
func condition_ctx() -> Dictionary:
	var out := {"map": map_id, "event": event_id}
	if has_item.is_valid():
		out["has_item"] = has_item
	if party_has.is_valid():
		out["party_has"] = party_has
	return out


## Rebind the live map on change_map completion (question 51). Identity is untouched -
## self flags keep meaning whatever they meant before the map changed.
func rebind_map(new_map: MapContext) -> void:
	map = new_map
