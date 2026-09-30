@tool
class_name RouteTracer

## Walks a node graph - a page's [code]graph[/code] or [code]route[/code] - without running
## it, and reports where its movement commands would take an actor, for the editor overlay
## to draw. Static and headless: it reads only the node dictionaries and never touches a
## scene, so it can be tested and used anywhere.
##
## [b]One path, not every path.[/b] At a branch it follows the first wired output
## ([constant _PREFERRED_FLOWS], else the first flow that has a target) - so an
## [code]if[/code] goes down "true", an [code]ask[/code] down its first choice, a move
## command down "reached". It stops when it would enter a node it has already been
## through (a loop), marking where it closed, and after [constant MAX_NODES] regardless.
##
## [b]What it cannot know is marked, not guessed[/b]: a [code]random[/code]/[code]wander[/code]
## step is a [code]random[/code] segment (the overlay draws an X compass there) and
## [code]towards_player[/code]/[code]away_from_player[/code]/[code]route_seek[/code] an
## [code]unknown[/code] one (a "?"); neither moves the traced position. [code]move_route[/code]
## and [code]jump[/code] draw a dashed line, since A* or an arc decides what is between.
##
## Each entry is [code]{kind, ...}[/code]: [code]line[/code] ([code]from[/code], [code]to[/code],
## [code]dashed[/code]), [code]random[/code] / [code]unknown[/code] / [code]loop[/code]
## ([code]at[/code]). Cells are actor-grid cells.

const MAX_NODES := 400

## Ports tried in order at a branch before settling for whichever wired one comes first.
const _PREFERRED_FLOWS: PackedStringArray = ["next", "reached", "immediate", "true"]


static func trace(nodes: Array, start_cell: Vector3i,
		facing: Vector3i = Vector3i(0, 0, 1)) -> Array[Dictionary]:
	var segments: Array[Dictionary] = []
	var by_id := {}
	var start_id := ""
	for entry: Variant in nodes:
		if not (entry is Dictionary):
			continue
		var node: Dictionary = entry
		by_id[str(node.get("id", ""))] = node
		if start_id == "" and str(node.get("command", "")) == EventCommand.START_COMMAND:
			start_id = str(node.get("id", ""))
	if start_id == "" and by_id.is_empty():
		return segments
	if start_id == "" or not by_id.has(start_id):
		start_id = str(by_id.keys()[0])

	var cell := start_cell
	var look := facing
	var visited := {}
	var id := start_id
	var steps := 0
	while by_id.has(id) and steps < MAX_NODES:
		steps += 1
		if visited.has(id):
			segments.append({"kind": "loop", "at": cell})
			break
		visited[id] = true

		var node: Dictionary = by_id[id]
		var args: Dictionary = node.get("args", {}) if node.get("args") is Dictionary else {}
		match str(node.get("command", "")):
			"move_to", "route_move_to":
				var to := _cell(args.get("cell"), cell)
				_line(segments, cell, to, false)
				look = _heading(cell, to, look)
				cell = to
			"move_route":
				var to := _cell(args.get("cell"), cell)
				_line(segments, cell, to, true)
				look = _heading(cell, to, look)
				cell = to
			"jump":
				var to := _cell(args.get("cell"), cell)
				_line(segments, cell, to, true)
				cell = to
			"teleport":
				cell = _cell(args.get("cell"), cell)
			"route_step":
				var dir := EventCommand.direction_of(args.get("direction"))
				_line(segments, cell, cell + dir, false)
				if dir != Vector3i.ZERO:
					look = dir
				cell += dir
			"face_direction":
				var dir := EventCommand.direction_of(args.get("direction"))
				if dir != Vector3i.ZERO:
					look = dir
			"move_by":
				var result := _move_by(segments, args.get("cells"), cell, look)
				look = _heading(cell, result, look)
				cell = result
			"route_seek":
				segments.append({"kind": "unknown", "at": cell})

		id = _next(node, by_id)

	return segments


## One [code]move_by[/code]'s [code]cells[/code] applied to [param cell], returning where
## the traced position ends up - unchanged for a step that is random or unknowable.
static func _move_by(segments: Array[Dictionary], cells: Variant, cell: Vector3i,
		look: Vector3i) -> Vector3i:
	if cells is String:
		var split := EventCommand.split_move_token(cells)
		var legs := maxi(1, int(split["count"]))
		match str(split["token"]):
			"forward":
				var to := cell + look * legs
				_line(segments, cell, to, false)
				return to
			"random", "wander":
				segments.append({"kind": "random", "at": cell})
				return cell
			_:
				segments.append({"kind": "unknown", "at": cell})
				return cell

	var to := cell + _cell(cells, Vector3i.ZERO)
	_line(segments, cell, to, false)
	return to


static func _line(segments: Array[Dictionary], from: Vector3i, to: Vector3i, dashed: bool) -> void:
	if from != to:
		segments.append({"kind": "line", "from": from, "to": to, "dashed": dashed})


## The compass step from [param from] toward [param to], or [param fallback] for no
## movement - what a later "forward" is measured against.
static func _heading(from: Vector3i, to: Vector3i, fallback: Vector3i) -> Vector3i:
	var delta := to - from
	if delta == Vector3i.ZERO:
		return fallback
	if absi(delta.x) >= absi(delta.z):
		return Vector3i(signi(delta.x), 0, 0)
	return Vector3i(0, 0, signi(delta.z))


## [param value] - a [Vector3i], or a three-element array of numbers - as a cell, or
## [param fallback] when it is neither.
static func _cell(value: Variant, fallback: Vector3i) -> Vector3i:
	if value is Vector3i:
		return value
	if value is Array and (value as Array).size() >= 3:
		var a: Array = value
		return Vector3i(int(a[0]), int(a[1]), int(a[2]))
	return fallback


## The id [param node] continues to: its preferred port if wired, else the first wired
## one in port order; "" when nothing is wired (the end of this path).
static func _next(node: Dictionary, by_id: Dictionary) -> String:
	var targets := {}
	for output: Variant in node.get("outputs", []) as Array:
		if output is Dictionary and str((output as Dictionary).get("target", "")) != "":
			targets[str((output as Dictionary).get("flow", ""))] = str((output as Dictionary)["target"])

	for flow in _PREFERRED_FLOWS:
		if targets.has(flow) and by_id.has(targets[flow]):
			return targets[flow]
	for flow in EventCommand.flows_of(node):
		if targets.has(flow) and by_id.has(targets[flow]):
			return targets[flow]
	return ""
