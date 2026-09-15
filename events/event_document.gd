class_name EventDocument

## The [code]{format, id, pages: []}[/code] wrapper around a page-aware event, and page
## selection - event-pages.md §2 and §2.3.
##
## [b]Layering.[/b] This file owns the wrapper, the page list and each page's
## [code]conditions[/code], [code]settings[/code], [code]art[/code] and [code]route[/code].
## A page's [code]graph[/code] is delegated to [code]graph_document.gd[/code] unchanged -
## this file never reads a node. Conditions are evaluated through [EventCondition], never
## re-implemented here.
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
static func default_page() -> Dictionary:
	return {
		"conditions": [],
		"settings": {},
		"art": {},
		"route": {},
		"graph": [],
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
	page["route"] = _read_dict(source.get("route", {}), where, "route", problems)

	var graph_raw: Variant = source.get("graph", [])
	if typeof(graph_raw) != TYPE_ARRAY:
		problems.append("%s: \"graph\" must be an array, found %s - treated as empty."
			% [where, type_string(typeof(graph_raw))])
		graph_raw = []

	var sub := Doc.parse_nodes(graph_raw as Array)
	page["graph"] = sub["nodes"]
	for message in sub["problems"]:
		problems.append("%s: %s" % [where, message])

	page["_unknown"] = _extract_unknown(source, PAGE_KEYS)
	return page

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


# -- Serialising ---------------------------------------------------------------

## [param doc] back to the on-disk wrapper form.
static func stringify(doc: Dictionary) -> String:
	var pages: Array = []
	for page in doc.get("pages", []) as Array:
		var page_dict: Dictionary = page
		var entry := {
			"conditions": page_dict.get("conditions", []),
			"settings": page_dict.get("settings", {}),
			"art": page_dict.get("art", {}),
			"route": page_dict.get("route", {}),
			"graph": Doc.to_data(page_dict.get("graph", [])),
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

		for message in Doc.unknown_report(page.get("graph", [])):
			lines.append("Page %d, %s" % [i + 1, message])

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
		page_dict["graph"] = Doc.strip_unknown(page_dict.get("graph", []))
		pages.append(page_dict)
	out["pages"] = pages

	return out
