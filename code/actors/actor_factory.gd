class_name ActorFactory

## Builds an actor's axis children from a [GameProfile]. This is the cost of the
## profile naming its implementation classes rather than only describing them: something
## has to instantiate them. It is also what a future [code]spawn[/code] command uses to
## create a monster from an event graph.
##
## It does not add a [PlayerController], and that is the line: this fills in the axis
## children an actor needs to exist, while what drives it is the caller's decision. A
## [code]spawn[/code] command that wants the monster to patrol gives it a route or a
## [GameEvent] after equipping, not a controller - only the player ever gets one of
## those.
##
## Precedence, stated once here so the two declarations cannot disagree:
## [b]map overrides profile[/b]. [member MapContext.default_motion] wins over
## [member GameProfile.motion_script], which is what keeps grid movement in a 3D town
## possible.


## Give [param actor] a space adapter, a motion controller and a view, skipping any it
## already has - so a hand-built scene stays authoritative and the factory only fills
## gaps.
static func equip(actor: Actor, profile: GameProfile, ctx: MapContext = null) -> void:
	if actor == null or profile == null:
		return
	if ctx == null:
		ctx = actor.context()

	if actor.adapter() == null and profile.space_script != null:
		_add(actor, profile.space_script, "Space")

	if actor.motion() == null:
		var script := _motion_script_for(actor, profile, ctx)
		if script != null:
			_add(actor, script, "Motion")

	if actor.view() == null and profile.view_script != null:
		_add(actor, profile.view_script, "View")


## The map's motion wins; the profile is the default. An actor that names its own mode
## explicitly wins over both, since [method Actor.effective_motion] resolves INHERIT
## against the map before we get here.
static func _motion_script_for(actor: Actor, profile: GameProfile, ctx: MapContext) -> Script:
	var mode := actor.motion_mode
	if mode == Actor.MotionMode.INHERIT and ctx != null:
		mode = ctx.default_motion

	match mode:
		Actor.MotionMode.GRID:
			return GridMotion
		Actor.MotionMode.FREE:
			return FreeMotion
		_:
			return profile.motion_script


static func _add(actor: Actor, script: Script, name_hint: String) -> Node:
	var node := Node.new()
	node.set_script(script)
	node.name = name_hint
	actor.add_child(node)
	return node
