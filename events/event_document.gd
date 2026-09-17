class_name EventDocument

## The [code]{format, id, pages: []}[/code] wrapper around a page-aware event, and page
## selection - event-pages.md §2 and §2.3.
##
## [b]Layering.[/b] This file owns the wrapper, the page list and each page's
## [code]conditions[/code], [code]settings[/code] and [code]art[/code]. A page's
## [code]graph[/code] and [code]route[/code] are both delegated to
## [code]graph_document.gd[/code] unchanged - this file never reads a node of either.
## Conditions are evaluated through [EventCondition], never re-implemented here.
##
## [b]A route is a node array, the same shape a graph is.[/b] The graph editor's route
## view is the ordinary node editor pointed at [code]route[/code] instead of
## [code]graph[/code] - one editing surface and one schema for "a sequence of
## commands", rather than a second one for the [code]{mode, loop, waypoints}[/code]
## shape event-pages.md §3 describes but this codebase has not built a reader for yet.
##
## [b]Static and UI-free[/b], the same rule [code]graph_document.gd[/code] and
## [code]event_command.gd[/code] follow, so it is callable from an editor script and from
## a running game without either knowing about the other.
##
## [b]The parse contract: repair and report, never reject.[/b] A malformed page becomes a
## default one and is reported; a document with no pages gets one added. Matches
## [code]graph_document.parse[/code].
##
## [b]Absent means default, never inherited[/b] (question 17). A page missing a key gets
## that key's empty default, not a copy of the page before it.

const Doc := preload("res://addons/graph_editor/graph_document.gd")

const FORMAT := 1

## Document keys this file understands. See [method _extract_unknown] in
## [code]graph_document.gd[/code] - the same "keep what you don't recognise" rule applies
## at every level of this wrapper.
const DOCUMENT_KEYS: PackedStringArray = ["format", "id", "pages"]

## Page keys this file understands.
const PAGE_KEYS: PackedStringArray = ["conditions", "settings", "art", "route", "graph"]


# -- Defaults --------------------------------------------------------------------

## A page with no conditions, no settings, no art, no route and no graph - the empty
## default every field falls back to when a page omits it.
##
## [b]The two node arrays are typed[/b], matching what [method Doc.parse_nodes] hands
## back for a page that does have them. An untyped default is a trap for any reader
## that declares its own [code]Array[Dictionary][/code]: the bare-array document path
## in [method parse] replaces only [code]graph[/code], so an untyped [code]route[/code]
## would survive into every single-page document and fail that reader's assignment at
## run time.
static func default_page() -> Dictionary:
	var route: Array[Dictionary] = []
	var graph: Array[Dictionary] = []
	return {
		"conditions": [],
		"settings": {},
		"art": {},
		"route": route,
		"graph": graph,
		"_unknown": {},
	}

## A one-page document with nothing in it, for a file that fails to parse at all.
static func default_document() -> Dictionary:
	return {"format": FORMAT, "id": "", "pages": [default_page()], "_unknown": {}}


# -- Parsing -----------------------------------------------------------------------

## Reads [param text] into [code]{"format", "id", "pages", "problems", "_unknown"}[/code].
##
## A top-level JSON [i]array[/i] is read as a single default page whose [code]graph[/code]
## is that array - event-pages.md §2.1's backwards compatibility, which is what keeps a
## hand-typed one-page event from ever needing the wrapper.
static func parse(text: String) -> Dictionary:
	var problems: Array[String] = []

	var json := JSON.new()
	if json.parse(text) != OK:
		problems.append("Line %d: %s" % [json.get_error_line(), json.get_error_message()])
		var failed := default_document()
		failed["problems"] = problems
		return failed

	var data: Variant = json.data

	if typeof(data) == TYPE_ARRAY:
		var page := default_page()
		var sub := Doc.parse_nodes(data as Array)
		page["graph"] = sub["nodes"]
		problems.append_array(sub["problems"])
		return {"format": FORMAT, "id": "", "pages": [page], "problems": problems, "_unknown": {}}

	if typeof(data) != TYPE_DICTIONARY:
		problems.append("Top level must be an object or an array of nodes, found %s."
			% type_string(typeof(data)))
		var failed := default_document()
		failed["problems"] = problems
		return failed

	var source: Dictionary = data
	var format := int(source.get("format", FORMAT))
	var id := str(source.get("id", ""))

	var pages_raw: Variant = source.get("pages", [])
	if typeof(pages_raw) != TYPE_ARRAY:
		problems.append("\"pages\" must be an array, found %s - treated as empty."
			% type_string(typeof(pages_raw)))
		pages_raw = []

	var pages: Array[Dictionary] = []
	for i in (pages_raw as Array).size():
		pages.append(_read_page(pages_raw[i], i, problems))

	if pages.is_empty():
		problems.append("Document has no pages - added a default one.")
		pages.append(default_page())

	return {
		"format": format,
		"id": id,
		"pages": pages,
		"problems": problems,
		"_unknown": _extract_unknown(source, DOCUMENT_KEYS),
	}

static func _read_page(raw: Variant, index: int, problems: Array[String]) -> Dictionary:
	var where := "Page %d" % (index + 1)

	if typeof(raw) != TYPE_DICTIONARY:
		problems.append("%s must be an object, found %s - replaced with a default page."
			% [where, type_string(typeof(raw))])
		return default_page()

	var source: Dictionary = raw
	var page := default_page()

	page["conditions"] = _read_list(source.get("conditions", []), where, "conditions", problems)
	page["settings"] = _read_dict(source.get("settings", {}), where, "settings", problems)
	page["art"] = _read_dict(source.get("art", {}), where, "art", problems)
	page["route"] = _read_route(source.get("route", []), where, problems)
	page["graph"] = _read_nodes(source.get("graph", []), where, "graph", problems)

	page["_unknown"] = _extract_unknown(source, PAGE_KEYS)
	return page

## A page's [code]route[/code], in either shape it may legitimately hold.
##
## A node array is what the graph editor's route view reads and writes, and is read
## exactly like a [code]graph[/code]. A [Dictionary] is event-pages.md §3's
## [code]{mode, loop, waypoints}[/code] form, which nothing in this codebase has a
## reader for yet: it is carried through verbatim rather than reported or emptied, so a
## file authored against §3 - slime_a.event.json's three pages, today - keeps
## round-tripping byte for byte instead of losing its route to a shape change it was
## never rewritten for.
static func _read_route(raw: Variant, where: String, problems: Array[String]) -> Variant:
	if typeof(raw) == TYPE_DICTIONARY:
		return (raw as Dictionary).duplicate(true)
	return _read_nodes(raw, where, "route", problems)

## [param raw] as a typed node array, dropping anything in it that is not a node.
##
## Typed deliberately: [code]graph_document.gd[/code]'s helpers all declare
## [code]Array[Dictionary][/code] parameters, and GDScript refuses an untyped [Array]
## passed to one at run time - which a [method Dictionary.get] result generally is.
static func _as_nodes(raw: Variant) -> Array[Dictionary]:
	var nodes: Array[Dictionary] = []
	if typeof(raw) != TYPE_ARRAY:
		return nodes
	for entry in raw as Array:
		if entry is Dictionary:
			nodes.append(entry)
	return nodes

## A page's [code]route[/code] or [code]graph[/code] as a node array, read the same
## way [method Doc.parse_nodes] already reads a bare-array document.
static func _read_nodes(raw: Variant, where: String, field: String,
		problems: Array[String]) -> Array[Dictionary]:
	if typeof(raw) != TYPE_ARRAY:
		problems.append("%s: \"%s\" must be an array, found %s - treated as empty."
			% [where, field, type_string(typeof(raw))])
		raw = []

	var sub := Doc.parse_nodes(raw as Array)
	for message in sub["problems"]:
		problems.append("%s: %s" % [where, message])
	return sub["nodes"]

static func _read_list(raw: Variant, where: String, field: String,
		problems: Array[String]) -> Array:
	if typeof(raw) != TYPE_ARRAY:
		problems.append("%s: \"%s\" must be an array, found %s - treated as empty."
			% [where, field, type_string(typeof(raw))])
		return []
	return (raw as Array).duplicate(true)

static func _read_dict(raw: Variant, where: String, field: String,
		problems: Array[String]) -> Dictionary:
	if typeof(raw) != TYPE_DICTIONARY:
		problems.append("%s: \"%s\" must be an object, found %s - treated as empty."
			% [where, field, type_string(typeof(raw))])
		return {}
	return (raw as Dictionary).duplicate(true)

## Every key in [param source] that is not in [param known] - see the identical helper in
## [code]graph_document.gd[/code], which this deliberately does not share a class with,
## the two files being independent readers of independent layers.
static func _extract_unknown(source: Dictionary, known: PackedStringArray) -> Dictionary:
	var extra := {}
	for key: Variant in source:
		if not known.has(str(key)):
			extra[key] = source[key]
	return extra

## The inverse of [method _extract_unknown] - see the identical private helper in
## [code]graph_document.gd[/code], duplicated rather than shared for the same reason
## [method _extract_unknown] is: independent readers of independent layers.
static func _strip_dict_keys(source: Dictionary, known: PackedStringArray) -> Dictionary:
	var out := {}
	for key: Variant in source:
		if known.has(str(key)):
			out[key] = source[key]
	return out


# -- Serialising ---------------------------------------------------------------

## The inverse of [method _read_route]: a §3 object back out exactly as it came in, a
## node array back out through [method Doc.to_data] like a graph.
static func _route_to_data(route: Variant) -> Variant:
	if typeof(route) == TYPE_DICTIONARY:
		return route
	return Doc.to_data(_as_nodes(route))

## [param doc] back to the on-disk wrapper form.
static func stringify(doc: Dictionary) -> String:
	var pages: Array = []
	for page in doc.get("pages", []) as Array:
		var page_dict: Dictionary = page
		var entry := {
			"conditions": page_dict.get("conditions", []),
			"settings": page_dict.get("settings", {}),
			"art": page_dict.get("art", {}),
			"route": _route_to_data(page_dict.get("route", [])),
			"graph": Doc.to_data(_as_nodes(page_dict.get("graph", []))),
		}
		for key: Variant in page_dict.get("_unknown", {}):
			entry[key] = page_dict["_unknown"][key]
		pages.append(entry)

	var out := {
		"format": doc.get("format", FORMAT),
		"id": doc.get("id", ""),
		"pages": pages,
	}
	for key: Variant in doc.get("_unknown", {}):
		out[key] = doc["_unknown"][key]

	# sort_keys off so the keys stay in the order written above.
	return JSON.stringify(out, "\t", false) + "\n"


# -- Page selection ------------------------------------------------------------

## The index of the active page in [param pages], evaluated last to first - the first
## page whose conditions all pass wins (event-pages.md §2.3). [param ctx] is passed
## straight through to [method EventCondition.evaluate].
##
## Returns [code]-1[/code] only if every page's conditions fail, which a page 1 with no
## conditions never does.
static func active_page(pages: Array, ctx: Dictionary = {}) -> int:
	for i in range(pages.size() - 1, -1, -1):
		var page: Dictionary = pages[i]
		var tree := EventCondition.from_list(page.get("conditions", []))
		if EventCondition.evaluate(tree, ctx):
			return i
	return -1

## Problems with [param pages] that only show up once they are all in view together -
## today, just the unreachable-page check §2.3 calls out: a page other than the first
## with an empty condition list makes every page before it dead code, since page
## selection never reaches them.
static func validate_pages(pages: Array) -> Array[String]:
	var problems: Array[String] = []
	for i in pages.size():
		var page: Dictionary = pages[i]
		var conditions: Array = page.get("conditions", [])
		if i > 0 and conditions.is_empty():
			problems.append(
				"Page %d has no conditions - page%s before it can never activate."
				% [i + 1, "s 1-%d are" % i if i > 1 else " 1 is"])
	return problems


# -- Unknown keys ----------------------------------------------------------------

## Messages naming every unrecognised key still carried on [param doc] - document, page
## and node level alike - for an editor surface that wants to show what a round trip is
## silently keeping rather than dropping.
static func unknown_report(doc: Dictionary) -> Array[String]:
	var lines: Array[String] = []

	for key: Variant in doc.get("_unknown", {}):
		lines.append("Document: unknown key \"%s\"." % key)

	var pages: Array = doc.get("pages", [])
	for i in pages.size():
		var page: Dictionary = pages[i]
		for key: Variant in page.get("_unknown", {}):
			lines.append("Page %d: unknown key \"%s\"." % [i + 1, key])

		for message in Doc.unknown_report(_as_nodes(page.get("graph", []))):
			lines.append("Page %d, %s" % [i + 1, message])
		# A §3 object route has no nodes to report on - _as_nodes reads it as none.
		for message in Doc.unknown_report(_as_nodes(page.get("route", []))):
			lines.append("Page %d, route %s" % [i + 1, message])

	return lines

## [param doc] with every unrecognised key discarded, at every level. Leaves the input
## untouched.
static func strip_unknown(doc: Dictionary) -> Dictionary:
	var out: Dictionary = doc.duplicate(true)
	out["_unknown"] = {}

	var pages: Array = []
	for page in out.get("pages", []) as Array:
		var page_dict: Dictionary = page
		page_dict["_unknown"] = {}
		page_dict["graph"] = Doc.strip_unknown(_as_nodes(page_dict.get("graph", [])))
		# A §3 object route is left exactly as it is - there are no per-node unknown
		# keys in it to strip, and rewriting it as an empty array would be data loss.
		var route: Variant = page_dict.get("route", [])
		if typeof(route) != TYPE_DICTIONARY:
			page_dict["route"] = Doc.strip_unknown(_as_nodes(route))
		pages.append(page_dict)
	out["pages"] = pages

	return out

## [param data] - raw, freshly [method JSON.parse_string]'d data, not what [method parse]
## returns - with every key outside [constant DOCUMENT_KEYS], [constant PAGE_KEYS] or
## [code]graph_document[/code]'s [constant NODE_KEYS] dropped, at whichever levels
## [param data] actually has. Accepts either shape §2.1 allows: a bare array is handed
## straight to [method GraphDoc.strip_unknown_raw], a page-wrapped object is walked level
## by level. Anything else is returned untouched.
##
## The one an editor's "strip unknown keys" button should call - see the identical
## reasoning on [method GraphDoc.strip_unknown_raw]: going through [method parse] instead
## would repair every missing id, title, position and route/settings/art default into
## existence, which is right for a graph about to be shown but not for "just remove the
## comments".
static func strip_unknown_raw(data: Variant) -> Variant:
	if typeof(data) == TYPE_ARRAY:
		return Doc.strip_unknown_raw(data as Array)
	if typeof(data) != TYPE_DICTIONARY:
		return data

	var source: Dictionary = data
	var out := _strip_dict_keys(source, DOCUMENT_KEYS)

	var pages_raw: Variant = source.get("pages", [])
	if typeof(pages_raw) != TYPE_ARRAY:
		return out

	var pages: Array = []
	for page in pages_raw as Array:
		if typeof(page) != TYPE_DICTIONARY:
			pages.append(page)
			continue

		var stripped_page := _strip_dict_keys(page as Dictionary, PAGE_KEYS)
		var graph: Variant = (page as Dictionary).get("graph")
		if typeof(graph) == TYPE_ARRAY:
			stripped_page["graph"] = Doc.strip_unknown_raw(graph as Array)
		var route: Variant = (page as Dictionary).get("route")
		if typeof(route) == TYPE_ARRAY:
			stripped_page["route"] = Doc.strip_unknown_raw(route as Array)
		pages.append(stripped_page)
	out["pages"] = pages

	return out
