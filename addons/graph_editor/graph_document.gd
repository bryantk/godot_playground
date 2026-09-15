@tool
extends RefCounted

## The data side of the node graph: the JSON shape, the types an output port can
## carry, id generation and validation.
##
## Deliberately static and UI-free. The panel keeps no parallel copy of the document -
## it reads the graph off screen when it saves and builds the graph back up when it
## loads - so everything that decides what a well-formed document is lives here, where
## it can also be reused at runtime by whatever walks these graphs.
##
## A document is a JSON array of nodes:
## [codeblock]
## [
##   {
##     "id": "n1",
##     "title": "Start",
##     "position": {"x": 0, "y": 0},
##     "command": "say",
##     "args": {"text": "Halt."},
##     "blocking": true,
##     "key": "cam",
##     "outputs": [{"flow": "next", "target": "n2"}]
##   }
## ]
## [/codeblock]
## [code]id[/code] and [code]outputs[/code] are the contract. [code]title[/code] and
## [code]position[/code] are editor bookkeeping: they are written so a graph reopens
## laid out the way it was left, and they default in when a hand-written file omits
## them. [code]target[/code] is the [code]id[/code] of the node the port points at, or
## [code]""[/code] for a port that is not wired up yet - a port always exists whether
## or not it has been connected, since the port list is what gives each output its
## index. [code]flow[/code] names the port - [code]"next"[/code] for a linear command,
## [code]"true"[/code]/[code]"false"[/code] for a branch, a choice's own label for
## [code]ask[/code] - and is [EventCommand]'s business: [method EventCommand.flows_of]
## is authoritative for how many ports a node has and what each is named, this file only
## carries whatever a port's [code]flow[/code] says without understanding it. Question
## 47's follow-up merged what used to be a separate per-node [code]flows[/code] array
## into each output's own [code]flow[/code] name, since the two always had to agree
## anyway - one per port, not two lists a caller had to zip together.
##
## [code]command[/code] and [code]args[/code] are [EventCommand]'s business and always
## present, defaulting to [code]""[/code] and [code]{}[/code]. [code]blocking[/code] and
## [code]key[/code] are [i]that command's[/i] business too, and optional - present only
## when the node authored one, absent otherwise, so a round trip never invents a
## [code]"blocking": false[/code] nobody wrote. This file carries all four without
## understanding any of them: it is the schema's data layer, not its validator.
##
## [b]Unknown keys survive too.[/b] A [code]"//"[/code] comment, or any key this parser
## does not recognise, is kept verbatim under [member _unknown] on the node in memory
## and written back at the end of the entry on save - repair-and-report extends to
## "don't understand" as well as "malformed".

## The slot type value [GraphEdit] connects a flow port on, and its colour. Every output
## port is a flow port - there is no other kind any more (question 47's follow-up), so
## this is one value each rather than a table a per-port [code]type[/code] used to pick
## from.
const FLOW_SLOT_TYPE := 1
const FLOW_COLOR := Color("e0e0e0")

## The colour of the untyped input side, which accepts any output.
const UNTYPED_COLOR := Color("9a9a9a")

const DEFAULT_TITLE := "Node"

## Prefix for generated ids. See [method generate_id].
const ID_PREFIX := "n"

## Node keys this file understands. Anything else in a raw node object is passenger
## data, kept under [code]_unknown[/code] rather than dropped - see [method _extract_unknown].
const NODE_KEYS: PackedStringArray = [
	"id", "title", "position", "command", "args", "blocking", "key", "outputs",
]

# --- Documents ----------------------------------------------------------------

static func empty_document() -> String:
	return "[\n]\n"

## A blank node, ready to be added to a graph. [param id] is expected to be unused -
## see [method generate_id].
static func default_node(id: String, position: Vector2) -> Dictionary:
	return {
		"id": id,
		"title": DEFAULT_TITLE,
		"position": position,
		"command": "",
		"args": {},
		"outputs": [],
		"_unknown": {},
	}

static func default_output(flow: String = "") -> Dictionary:
	return {"flow": flow, "target": ""}

## An id not in [param used], whose keys - or values, if it is an Array - are the ids
## already taken. Counts up from 1 rather than using a random or time-based id: these
## end up in a file a person reads and edits by hand, and the graph is small enough
## that collisions are not a concern once uniqueness is checked here.
static func generate_id(used: Variant) -> String:
	var taken := func(id: String) -> bool:
		if used is Dictionary:
			return used.has(id)
		if used is Array or used is PackedStringArray:
			return used.has(id)
		return false

	var n := 1
	while taken.call(ID_PREFIX + str(n)):
		n += 1
	return ID_PREFIX + str(n)

## Reads [param text] into a list of nodes.
##
## Returns [code]{"nodes": Array[Dictionary], "problems": Array[String]}[/code].
## Anything recoverable is repaired rather than rejected - a missing title gets the
## default, an unknown type falls back to the first primitive, a duplicate id is
## renamed - and each repair is reported. That way opening a file someone typed by
## hand shows the graph plus a list of what had to be assumed, instead of an error and
## an empty canvas. Only text that is not a JSON array at all comes back with no nodes.
##
## Targets are resolved last, once every id is known: a port pointing at a node that
## is not in the file is reported and cleared, so what loads is always internally
## consistent.
static func parse(text: String) -> Dictionary:
	var problems: Array[String] = []

	var json := JSON.new()
	if json.parse(text) != OK:
		problems.append("Line %d: %s" % [json.get_error_line(), json.get_error_message()])
		return {"nodes": [], "problems": problems}

	var data: Variant = json.data
	if typeof(data) != TYPE_ARRAY:
		problems.append("Top level must be an array of nodes, found %s."
			% type_string(typeof(data)))
		return {"nodes": [], "problems": problems}

	return parse_nodes(data)

## The part of [method parse] that runs once the JSON is already decoded into an
## array - what [code]event_document.gd[/code] calls for a page's [code]graph[/code],
## which arrives already parsed as part of the larger document.
static func parse_nodes(data: Array) -> Dictionary:
	var problems: Array[String] = []
	var nodes: Array[Dictionary] = []

	# Every id and target the file mentions, gathered before anything is repaired. A
	# generated id has to dodge all of them, not just the ones already read: renaming a
	# duplicate onto an id some port was already targeting would silently wire the two
	# together, which is worse than the duplicate.
	var reserved := _mentioned_ids(data)

	var ids := {}
	for i in data.size():
		var node := _read_node(data[i], i, ids, reserved, problems)
		ids[node["id"]] = true
		reserved[node["id"]] = true
		nodes.append(node)

	_resolve_targets(nodes, ids, problems)
	return {"nodes": nodes, "problems": problems}

## Every string the document uses as an id or a target, as a set. Deliberately loose
## about the shapes it walks: it runs before validation, on data that may be malformed
## anywhere.
static func _mentioned_ids(data: Array) -> Dictionary:
	var mentioned := {}

	for raw in data:
		if typeof(raw) != TYPE_DICTIONARY:
			continue

		var id := str((raw as Dictionary).get("id", ""))
		if id != "":
			mentioned[id] = true

		var outputs: Variant = (raw as Dictionary).get("outputs")
		if typeof(outputs) != TYPE_ARRAY:
			continue

		for output in outputs as Array:
			if typeof(output) != TYPE_DICTIONARY:
				continue
			var target := str((output as Dictionary).get("target", ""))
			if target != "":
				mentioned[target] = true

	return mentioned

## Repairs one raw entry into the node shape.
##
## [param ids] holds the ids taken by earlier entries, so a clash can be spotted;
## [param reserved] holds those plus every id mentioned anywhere in the document, so
## the replacement cannot land on one of them.
static func _read_node(raw: Variant, index: int, ids: Dictionary, reserved: Dictionary,
		problems: Array[String]) -> Dictionary:
	var where := "Node %d" % index

	if typeof(raw) != TYPE_DICTIONARY:
		problems.append("%s must be an object, found %s - replaced with an empty node."
			% [where, type_string(typeof(raw))])
		return default_node(generate_id(reserved), Vector2.ZERO)

	var source: Dictionary = raw
	var id := str(source.get("id", ""))

	if id == "":
		id = generate_id(reserved)
		problems.append("%s has no id - generated \"%s\"." % [where, id])
	elif ids.has(id):
		var replacement := generate_id(reserved)
		problems.append("%s repeats id \"%s\" - renamed to \"%s\". Ports targeting \"%s\" still reach the first one."
			% [where, id, replacement, id])
		id = replacement

	var of := "Node %d (%s)" % [index, id]

	var node := default_node(id, _read_position(source.get("position")))
	node["title"] = str(source.get("title", DEFAULT_TITLE))
	node["command"] = str(source.get("command", ""))
	node["args"] = _read_args(source.get("args", {}), of, problems)

	if source.has("blocking"):
		var raw_blocking: Variant = source.get("blocking")
		if typeof(raw_blocking) == TYPE_BOOL:
			node["blocking"] = raw_blocking
		else:
			problems.append("%s: \"blocking\" must be true or false, found %s - ignored."
				% [of, type_string(typeof(raw_blocking))])

	if source.has("key"):
		var raw_key: Variant = source.get("key")
		if raw_key is String:
			node["key"] = raw_key
		else:
			problems.append("%s: \"key\" must be text, found %s - ignored."
				% [of, type_string(typeof(raw_key))])

	node["outputs"] = _read_outputs(source.get("outputs", []), of, problems)
	node["_unknown"] = _extract_unknown(source, NODE_KEYS)
	return node

static func _read_args(raw: Variant, where: String, problems: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		problems.append("%s: args must be an object, found %s - dropped."
			% [where, type_string(typeof(raw))])
		return {}
	return (raw as Dictionary).duplicate(true)

## Every key in [param source] that is not in [param known], as a dictionary - the
## passenger data a reader does not understand, kept rather than dropped. A [code]"//"[/code]
## comment is just another entry here; there is nothing special-cased about it.
static func _extract_unknown(source: Dictionary, known: PackedStringArray) -> Dictionary:
	var extra := {}
	for key: Variant in source:
		if not known.has(str(key)):
			extra[key] = source[key]
	return extra

static func _read_position(raw: Variant) -> Vector2:
	# Objects are what this writes; two-element arrays are accepted because they are
	# the other obvious way to hand-write a point.
	if typeof(raw) == TYPE_DICTIONARY:
		return Vector2(float(raw.get("x", 0.0)), float(raw.get("y", 0.0)))
	if typeof(raw) == TYPE_ARRAY and (raw as Array).size() >= 2:
		return Vector2(float(raw[0]), float(raw[1]))
	return Vector2.ZERO

static func _read_outputs(raw: Variant, where: String,
		problems: Array[String]) -> Array[Dictionary]:
	var outputs: Array[Dictionary] = []

	if typeof(raw) != TYPE_ARRAY:
		problems.append("%s: outputs must be an array, found %s - dropped."
			% [where, type_string(typeof(raw))])
		return outputs

	for i in (raw as Array).size():
		var entry: Variant = raw[i]
		if typeof(entry) != TYPE_DICTIONARY:
			problems.append("%s: output %d must be an object, found %s - dropped."
				% [where, i, type_string(typeof(entry))])
			continue

		var output := default_output()
		output["flow"] = str((entry as Dictionary).get("flow", ""))
		output["target"] = str((entry as Dictionary).get("target", ""))
		outputs.append(output)

	return outputs

## Clears every target that names a node the document does not contain, reporting each
## one. Runs after the whole file is read so that a port may point forwards.
static func _resolve_targets(nodes: Array[Dictionary], ids: Dictionary,
		problems: Array[String]) -> void:
	for node in nodes:
		for i in (node["outputs"] as Array).size():
			var output: Dictionary = node["outputs"][i]
			var target: String = output["target"]
			if target == "" or ids.has(target):
				continue

			problems.append("Node \"%s\": output %d targets \"%s\", which is not in this file - disconnected."
				% [node["id"], i, target])
			output["target"] = ""

## Serialises [param nodes] back to the on-disk form.
static func stringify(nodes: Array[Dictionary]) -> String:
	# sort_keys off so the keys stay in the order to_data() wrote them in, which reads
	# as id first and the wiring last.
	return JSON.stringify(to_data(nodes), "\t", false) + "\n"

## [param nodes] as the plain arrays and dictionaries [JSON] stringifies, without
## turning them to text yet - what [code]event_document.gd[/code] needs to embed a
## page's graph inside the larger document rather than stringifying it twice.
##
## Positions are rounded: they come from dragging, so the fractional part is noise that
## would otherwise churn the file on every save. [code]blocking[/code] and [code]key[/code]
## are written only when the node carries one, so a round trip never invents a value
## nobody authored; anything under [member _unknown] - a [code]"//"[/code] comment
## included - is written back last, verbatim.
static func to_data(nodes: Array[Dictionary]) -> Array:
	var out: Array = []
	for node in nodes:
		var position: Vector2 = node.get("position", Vector2.ZERO)
		var outputs: Array = []
		for output in node.get("outputs", []):
			outputs.append({"flow": output.get("flow", ""), "target": output["target"]})

		var entry := {
			"id": node["id"],
			"title": node.get("title", DEFAULT_TITLE),
			"position": {"x": roundi(position.x), "y": roundi(position.y)},
			"command": node.get("command", ""),
			"args": node.get("args", {}),
		}
		if node.has("blocking"):
			entry["blocking"] = node["blocking"]
		if node.has("key"):
			entry["key"] = node["key"]
		entry["outputs"] = outputs

		for key: Variant in node.get("_unknown", {}):
			entry[key] = node["_unknown"][key]

		out.append(entry)

	return out

## Messages naming every unrecognised key still carried on [param nodes], for an editor
## surface that wants to show what a round trip is silently keeping.
static func unknown_report(nodes: Array[Dictionary]) -> Array[String]:
	var lines: Array[String] = []
	for node in nodes:
		for key: Variant in node.get("_unknown", {}):
			lines.append("Node \"%s\": unknown key \"%s\"." % [node.get("id", ""), key])
	return lines

## [param nodes] with every unrecognised key discarded. Leaves the input untouched.
static func strip_unknown(nodes: Array[Dictionary]) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for node in nodes:
		var copy: Dictionary = (node as Dictionary).duplicate(true)
		copy["_unknown"] = {}
		out.append(copy)
	return out

## [param data] - raw, freshly [method JSON.parse_string]'d entries, not the normalised
## node dictionaries [method parse] returns - with every key outside [constant NODE_KEYS]
## dropped from each object. A non-object entry is left as it was.
##
## [b]This is the one an editor's "strip unknown keys" button should call, not
## [method strip_unknown].[/b] Round-tripping through [method parse]/[method stringify]
## repairs as it goes - a missing id is generated, a missing title becomes
## [constant DEFAULT_TITLE] - which is exactly right for a graph the editor is about to
## show, but wrong for a plain command list that never had an id or a position in the
## first place: stripping its comments should not also hand it four fields it never
## carried.
static func strip_unknown_raw(data: Array) -> Array:
	var out: Array = []
	for entry in data:
		if typeof(entry) == TYPE_DICTIONARY:
			out.append(_strip_dict_keys(entry, NODE_KEYS))
		else:
			out.append(entry)
	return out

static func _strip_dict_keys(source: Dictionary, known: PackedStringArray) -> Dictionary:
	var out := {}
	for key: Variant in source:
		if known.has(str(key)):
			out[key] = source[key]
	return out

## Problems with a graph that is already in memory - the checks from [method parse]
## that can be broken again by editing, minus the ones parsing repairs on the way in.
static func validate(nodes: Array[Dictionary]) -> Array[String]:
	var problems: Array[String] = []
	var ids := {}

	for node in nodes:
		var id: String = node["id"]
		if id == "":
			problems.append("A node has an empty id.")
		elif ids.has(id):
			problems.append("Duplicate id \"%s\"." % id)
		ids[id] = true

	for node in nodes:
		for i in (node["outputs"] as Array).size():
			var output: Dictionary = node["outputs"][i]
			if output["target"] != "" and not ids.has(output["target"]):
				problems.append("Node \"%s\": output %d targets missing node \"%s\"."
					% [node["id"], i, output["target"]])

	return problems
