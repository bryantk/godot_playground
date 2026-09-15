extends Node

## Headless assertions over [EventDocument] and the node fields
## [code]graph_document.gd[/code] gained alongside it - command, args, blocking, key,
## flows, and unrecognised keys of every kind.
##
##     godot --headless --path . res://tests/event_document_test.tscn
##
## The regression test that matters most is [method _test_round_trip]: before this
## segment, opening any of the five documents in docs/events/ in the graph editor and
## saving silently stripped command/args/blocking/key/flows from every node.

const Doc := preload("res://addons/graph_editor/graph_document.gd")
const EXAMPLES := "res://docs/events/"

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("events -- EventDocument, pages and the graph node fields")
	print("")

	_test_node_fields()
	_test_unknown_keys()
	_test_bare_array_is_one_page()
	_test_page_repair()
	_test_active_page()
	_test_unreachable_warning()
	_test_round_trip()

	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- Node fields -----------------------------------------------------------------

func _test_node_fields() -> void:
	_section("graph_document -- command/args/blocking/key/flows survive a parse")

	var text := JSON.stringify([{
		"id": "n1", "title": "Line", "position": {"x": 10, "y": 20},
		"command": "say", "args": {"text": "hi"}, "blocking": false, "key": "cam",
		"flows": ["true", "false"],
		"outputs": [{"type": "flow", "target": ""}],
	}])

	var parsed := Doc.parse(text)
	_ok((parsed["problems"] as Array).is_empty(), "a well-formed node parses clean")

	var node: Dictionary = (parsed["nodes"] as Array)[0]
	_eq(node["command"], "say", "command carried through")
	_eq(node["args"], {"text": "hi"}, "args carried through")
	_eq(node["blocking"], false, "blocking carried through, false and all")
	_eq(node["key"], "cam", "key carried through")
	_eq(node["flows"], ["true", "false"], "flows carried through")

	_section("  absent stays absent -- no invented \"blocking\": false")

	var bare := Doc.parse(JSON.stringify([{
		"id": "n1", "outputs": [],
	}]))["nodes"][0] as Dictionary
	_ok(not bare.has("blocking"), "no blocking key when none was authored")
	_ok(not bare.has("key"), "no key when none was authored")
	_ok(not bare.has("flows"), "no flows when none was authored")
	_eq(bare["command"], "", "command defaults to empty, not missing")
	_eq(bare["args"], {}, "args defaults to empty, not missing")

	_section("  malformed values are reported and the node stays usable")

	var messy := Doc.parse(JSON.stringify([{
		"id": "n1", "outputs": [],
		"args": "not an object", "blocking": "yes", "key": 5, "flows": "nope",
	}]))
	_ok((messy["problems"] as Array).size() >= 4, "each malformed field is reported")
	var repaired: Dictionary = (messy["nodes"] as Array)[0]
	_eq(repaired["args"], {}, "a non-object args is dropped to empty")
	_ok(not repaired.has("blocking"), "a non-bool blocking is ignored, not coerced")
	_ok(not repaired.has("key"), "a non-string key is ignored")
	_ok(not repaired.has("flows"), "a non-array flows is ignored")


# -- Unknown keys ------------------------------------------------------------------

func _test_unknown_keys() -> void:
	_section("unknown keys -- kept verbatim, at node, page and document level")

	var text := JSON.stringify({
		"format": 1, "id": "e1", "extra_doc_field": "kept",
		"pages": [{
			"conditions": [], "//": "a page comment",
			"graph": [{
				"id": "n1", "//": "a node comment", "spare": 42,
				"command": "wait", "args": {"seconds": 1}, "outputs": [{"type": "flow", "target": ""}],
			}],
		}],
	})

	var doc := EventDocument.parse(text)
	_eq(doc["_unknown"], {"extra_doc_field": "kept"}, "a document-level key survives")

	var page: Dictionary = doc["pages"][0]
	_eq(page["_unknown"], {"//": "a page comment"}, "a page-level comment survives")

	var node: Dictionary = page["graph"][0]
	# JSON has one number type - 42 comes back as a float, same as everywhere else raw
	# JSON data passes through this reader untouched.
	_eq(node["_unknown"], {"//": "a node comment", "spare": 42.0},
		"a node keeps every key it doesn't recognise, not just \"//\"")

	var rewritten := EventDocument.stringify(doc)
	_ok(rewritten.contains("extra_doc_field"), "the document key is written back")
	_ok(rewritten.contains("a page comment"), "the page comment is written back")
	_ok(rewritten.contains("a node comment") and rewritten.contains("42"),
		"the node's unknown keys are both written back")

	_section("  the report and strip helpers a UI reaches for")

	var report := EventDocument.unknown_report(doc)
	_eq(report.size(), 4, "one message per unknown key, at every level")

	var stripped := EventDocument.strip_unknown(doc)
	_ok(EventDocument.unknown_report(stripped).is_empty(), "stripping clears every level")
	_eq(stripped["pages"][0]["graph"][0]["command"], "wait",
		"stripping touches nothing but the unknown keys")


# -- Backwards compatibility (event-pages.md §2.1) --------------------------------

func _test_bare_array_is_one_page() -> void:
	_section("a bare top-level array is one default page")

	var text := JSON.stringify([
		{"id": "n1", "command": "say", "args": {"text": "hi"},
			"outputs": [{"type": "flow", "target": ""}]},
	])

	var doc := EventDocument.parse(text)
	_eq(doc["format"], EventDocument.FORMAT, "format defaults in")
	_eq((doc["pages"] as Array).size(), 1, "exactly one page")

	var page: Dictionary = doc["pages"][0]
	_eq(page["conditions"], [], "no conditions -- the fallback page")
	_eq((page["graph"] as Array).size(), 1, "the array became that page's graph")
	_eq(page["graph"][0]["command"], "say", "  with its node read the ordinary way")


# -- Repair --------------------------------------------------------------------

func _test_page_repair() -> void:
	_section("a malformed page is repaired and reported, not rejected")

	var doc := EventDocument.parse(JSON.stringify({
		"pages": ["not an object", {"conditions": "not an array", "graph": "not an array"}],
	}))

	_eq((doc["pages"] as Array).size(), 2, "both entries still produced a page")
	_ok((doc["problems"] as Array).size() >= 3,
		"a problem for the non-object page, the bad conditions and the bad graph")
	_eq(doc["pages"][0], EventDocument.default_page(), "the non-object page became the default")
	_eq(doc["pages"][1]["conditions"], [], "bad conditions repaired to empty")
	_eq(doc["pages"][1]["graph"], [], "bad graph repaired to empty")

	var no_pages := EventDocument.parse(JSON.stringify({"format": 1}))
	_eq((no_pages["pages"] as Array).size(), 1, "a document with no pages gets a default one")
	_ok(not (no_pages["problems"] as Array).is_empty(), "  and says so")


# -- Page selection --------------------------------------------------------------

func _test_active_page() -> void:
	_section("active_page -- last to first, first all-passing page wins (§2.3)")

	GameState.clear()
	GameState.set_flag(&"stole_the_idol")
	var ctx := {"map": &"m", "event": &"e"}

	var pages: Array[Dictionary] = [
		_page([]),
		_page([{"flag": "stole_the_idol"}]),
		_page([{"self_flag": "defeated"}]),
	]

	_eq(EventDocument.active_page(pages, ctx), 1,
		"page 2 passes and page 3 does not, so page 2 wins over the fallback")

	GameState.set_self_flag(&"m", &"e", &"defeated")
	_eq(EventDocument.active_page(pages, ctx), 2, "once page 3 passes too, it wins -- checked first")

	GameState.clear()
	_eq(EventDocument.active_page(pages, ctx), 0, "with nothing set, only the fallback passes")

	_eq(EventDocument.active_page([], ctx), -1, "no pages at all is -1")
	_eq(EventDocument.active_page([_page([{"flag": "never"}])], ctx), -1,
		"and so is every page failing, with no fallback to catch it")

	GameState.clear()


func _test_unreachable_warning() -> void:
	_section("validate_pages -- a page with no conditions makes earlier pages dead code")

	var reachable := [_page([]), _page([{"flag": "a"}])]
	_ok(EventDocument.validate_pages(reachable).is_empty(),
		"page 1 is conventionally the only unconditional one -- no warning")

	var unreachable := [_page([]), _page([]), _page([{"flag": "a"}])]
	var problems := EventDocument.validate_pages(unreachable)
	_ok(problems.size() > 0, "page 2 has no conditions either, so page 1 is unreachable")
	_ok(problems[0].contains("Page 2"), "  and the message names the offending page")


# -- The round trip --------------------------------------------------------------

## The regression test for the data-loss bug this segment fixes: every example in
## docs/events/ parses and re-serialises to exactly the bytes on disk.
func _test_round_trip() -> void:
	_section("round trip -- the five worked examples, byte for byte")

	for name in ["cliff_jump", "greet_guard", "locked_door", "patrol_guard"]:
		var path := "%s%s.event.json" % [EXAMPLES, name]
		var text := FileAccess.get_file_as_string(path)
		var parsed := Doc.parse(text)
		_ok((parsed["problems"] as Array).is_empty(), "%s parses with no problems" % name)
		_eq(Doc.stringify(parsed["nodes"]), text, "%s round-trips byte for byte" % name)

	var path := "%sslime_a.event.json" % EXAMPLES
	var text := FileAccess.get_file_as_string(path)
	var doc := EventDocument.parse(text)
	_ok((doc["problems"] as Array).is_empty(), "slime_a parses with no problems")
	_eq((doc["pages"] as Array).size(), 3, "  its three pages")
	_eq(EventDocument.stringify(doc), text, "slime_a round-trips byte for byte")


# -- Helpers ---------------------------------------------------------------------

func _page(conditions: Array) -> Dictionary:
	var page := EventDocument.default_page()
	page["conditions"] = conditions
	return page

func _section(title: String) -> void:
	print("  %s" % title)

func _ok(condition: bool, what: String) -> void:
	print(("    ok    " if condition else "    FAIL  ") + what)
	if condition:
		_passed += 1
	else:
		_failed += 1

func _eq(got: Variant, want: Variant, what: String) -> void:
	var same: bool = got == want
	print(("    ok    " if same else "    FAIL  ") + what
		+ ("" if same else "  (got %s, want %s)" % [got, want]))
	if same:
		_passed += 1
	else:
		_failed += 1
