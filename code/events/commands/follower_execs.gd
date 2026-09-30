## The party caterpillar's four commands - [code]follow_add[/code], [code]follow_remove[/code],
## [code]follow_show[/code], [code]follow_group[/code] (event_command.gd) - all thin calls into
## [FollowerChain], which owns the followers themselves.
##
## [code]follow_add[/code]/[code]follow_remove[/code] name either a party member
## ([code]member[/code]: "melina" - back into, or out of, the automatic party chain) or an
## ordinary actor already on the map ([code]actor[/code]: "@npc_scout" - who then trails the
## party). Exactly one of the two is given.


class FollowAdd extends EventCommandExec:
	func start() -> void:
		var target := FollowerChain.target_of(args, ctx)
		if target["member"] != &"":
			FollowerChain.add_member(target["member"])
		elif target["actor"] != null:
			FollowerChain.add_actor(target["actor"])
		else:
			push_warning("follow_add: give a party \"member\" or an \"actor\" that exists.")


class FollowRemove extends EventCommandExec:
	func start() -> void:
		var target := FollowerChain.target_of(args, ctx)
		if target["member"] != &"":
			FollowerChain.remove_member(target["member"])
		elif target["actor"] != null:
			FollowerChain.remove_actor(target["actor"])
		else:
			push_warning("follow_remove: give a party \"member\" or an \"actor\" that exists.")


## Shows or hides every follower, or just the one named by "actor".
class FollowShow extends EventCommandExec:
	func start() -> void:
		var who: Actor = ctx.resolve(str(args["actor"])) if args.has("actor") else null
		FollowerChain.show_followers(bool(args.get("visible", true)), who)


## Walks every follower to its place behind the leader. "reached" once they have all
## stopped moving; wired "immediate", the graph does not wait for them.
class FollowGroup extends EventCommandExec:
	func start() -> void:
		FollowerChain.gather()

	func tick(_delta: float) -> int:
		if immediate_wired():
			return Status.DONE
		return Status.RUNNING if FollowerChain.is_grouping() else Status.DONE

	func flow_port() -> String:
		return reached_immediate_flow_port()

	func cancel() -> void:
		# Nothing of its own to undo: the followers simply carry on following.
		pass


static func table() -> Dictionary:
	return {
		"follow_add": FollowAdd,
		"follow_remove": FollowRemove,
		"follow_show": FollowShow,
		"follow_group": FollowGroup,
	}
