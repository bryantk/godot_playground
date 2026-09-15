extends Node

## Headless assertions over [EventCondition] - the tree, the evaluator, the key
## extractor, the expression parser and the manifest check.
##
##     godot --headless --path . res://tests/event_condition_test.tscn
##
## The parser half is the reason this file is long. Godot's own [Expression] executes a
## string but returns no tree, and the tree is what page selection and author-time
## validation both need - so the parser here is hand-written and has to be held to the
## same standard as one.

const MAP := &"town_square"
const EVENT := &"greet_guard"

var _passed := 0
var _failed := 0


func _ready() -> void:
	print("")
	print("events -- conditions")
	print("")

	_test_shape()
	_test_evaluate()
	_test_compare()
	_test_keys()
	_test_parse_simple()
	_test_parse_precedence()
	_test_parse_predicates()
	_test_parse_errors()
	_test_equivalence()
	_test_validate()

	GameState.clear()
	print("")
	print("  %d passed, %d failed" % [_passed, _failed])
	print("")
	get_tree().quit(1 if _failed > 0 else 0)


# -- The tree ------------------------------------------------------------------

func _test_shape() -> void:
	_section("from_list -- a page's flat array is sugar for `all`")

	_ok(EventCondition.from_list([]).is_empty(), "no conditions is the empty tree")
	_ok(EventCondition.is_always(EventCondition.from_list([])),
		"  which is the always-passing one -- page 1's fallback")

	var one := EventCondition.from_list([{"flag": "a"}])
	_eq(one, {"flag": "a"}, "a single entry is that entry, unwrapped")

	var two := EventCondition.from_list([{"flag": "a"}, {"flag": "b"}])
	_ok(two.has("all"), "several entries become an `all`")
	_eq((two["all"] as Array).size(), 2, "  carrying both")


# -- Evaluation ----------------------------------------------------------------

func _test_evaluate() -> void:
	_section("evaluate -- flags, self flags and variables")

	GameState.clear()
	GameState.manifest = {&"chapter": {"type": TYPE_INT, "default": 0}}
	GameState.set_flag(&"stole_the_idol")
	GameState.var_set(&"chapter", 2)
	GameState.set_self_flag(MAP, EVENT, &"talked")

	var ctx := {"map": MAP, "event": EVENT}

	_ok(EventCondition.evaluate({}, ctx), "the empty tree passes")
	_ok(EventCondition.evaluate({"flag": "stole_the_idol"}, ctx), "a set flag passes")
	_ok(not EventCondition.evaluate({"flag": "never_set"}, ctx), "an unset flag does not")

	# `is: false` negates a leaf in place, which is what keeps a page's AND list flat.
	_ok(EventCondition.evaluate({"flag": "never_set", "is": false}, ctx),
		"is:false inverts a leaf without wrapping it in a not")
	_ok(not EventCondition.evaluate({"flag": "stole_the_idol", "is": false}, ctx),
		"  and the other way round")

	_ok(EventCondition.evaluate({"self_flag": "talked"}, ctx), "a self flag passes")
	_ok(not EventCondition.evaluate({"self_flag": "talked"}, {"map": MAP, "event": &"other"}),
		"  and is per-event: the same flag on another event is unset")

	_ok(EventCondition.evaluate({"var": "chapter", "op": ">=", "value": 2}, ctx),
		"a variable comparison passes")
	_ok(not EventCondition.evaluate({"var": "chapter", "op": ">", "value": 2}, ctx),
		"  strictly")

	_section("  branches")

	var both := {"all": [{"flag": "stole_the_idol"}, {"var": "chapter", "op": "==", "value": 2}]}
	_ok(EventCondition.evaluate(both, ctx), "an all with both passing")

	var half := {"all": [{"flag": "stole_the_idol"}, {"flag": "never_set"}]}
	_ok(not EventCondition.evaluate(half, ctx), "an all with one failing")
	_ok(EventCondition.evaluate({"any": [{"flag": "never_set"}, {"flag": "stole_the_idol"}]}, ctx),
		"an any needs only one")
	_ok(not EventCondition.evaluate({"any": []}, ctx),
		"an empty any is false -- at least one of nothing is nothing")
	_ok(EventCondition.evaluate({"all": []}, ctx), "  while an empty all is true")
	_ok(EventCondition.evaluate({"not": {"flag": "never_set"}}, ctx), "not inverts")

	_section("  item and party_has resolve through the context")

	# Neither system exists yet, so the leaf asks the context. Absent, it reads false and
	# warns - a page that silently never activates is the bug this project keeps calling
	# the hardest to attribute.
	var stocked := {
		"map": MAP, "event": EVENT,
		"has_item": func(name: String) -> bool: return name == "brass_key",
		"party_has": func(name: String) -> bool: return name == "melina",
	}
	_ok(EventCondition.evaluate({"item": "brass_key"}, stocked), "an item the provider has")
	_ok(not EventCondition.evaluate({"item": "sword"}, stocked), "  and one it does not")
	_ok(EventCondition.evaluate({"party_has": "melina"}, stocked), "a party member")

	_ok(not EventCondition.evaluate({"item": "brass_key"}, ctx),
		"with no provider at all it reads false")


func _test_compare() -> void:
	_section("compare -- JSON has one number type, so 2 and 2.0 are equal")

	_ok(EventCondition.compare(2, "==", 2.0), "an int equals a float of the same value")
	_ok(EventCondition.compare(2.0, "==", 2), "  either way round")
	_ok(not EventCondition.compare(2, "==", 3), "and unequal ones do not")
	_ok(EventCondition.compare(1, "<", 2), "less than")
	_ok(EventCondition.compare(2, "<=", 2), "less than or equal")
	_ok(EventCondition.compare(3, ">", 2), "greater than")
	_ok(EventCondition.compare("melina", "==", "melina"), "strings compare as strings")
	_ok(EventCondition.compare(true, "==", true), "and bools as bools")
	_ok(not EventCondition.compare(1, "><", 2), "an unknown operator is false, not a crash")


# -- Keys ----------------------------------------------------------------------

func _test_keys() -> void:
	_section("keys -- the subscription list page selection needs")

	var tree := {"all": [
		{"flag": "stole_the_idol"},
		{"any": [{"var": "chapter", "op": ">=", "value": 2}, {"flag": "boss_dead"}]},
		{"not": {"flag": "cursed"}},
	]}

	var found := EventCondition.keys(tree)
	_eq(found.size(), 4, "every name in the tree, nested branches included")
	for name in ["stole_the_idol", "chapter", "boss_dead", "cursed"]:
		_ok(found.has(StringName(name)), "  %s" % name)

	_eq(EventCondition.keys({}).size(), 0, "the empty tree mentions nothing")

	_section("  self flags expand to the composite key GameState actually emits")

	# GameState.set_self_flag emits "map:event:flag", so a subscription to the bare name
	# would be a subscription that never fires -- and would look like it was working.
	var selfish := {"self_flag": "talked"}
	var composite := EventCondition.keys(selfish, MAP, EVENT)
	_eq(composite.size(), 1, "one key")
	_eq(composite[0], StringName(GameState.self_key(MAP, EVENT, &"talked")),
		"  and it is the composite GameState emits")

	var bare := EventCondition.keys(selfish)
	_eq(bare[0], &"talked", "without a map and event it stays bare, which suits a validator")

	# Neither system emits a change signal, so a subscription naming one would never wake.
	_eq(EventCondition.keys({"item": "brass_key"}).size(), 0,
		"item contributes no key, because nothing would ever emit it")


# -- Parsing -------------------------------------------------------------------

func _test_parse_simple() -> void:
	_section("parse_expression -- a bare name is a flag, a compared name is a variable")

	_eq(_tree("stole_the_idol"), {"flag": "stole_the_idol"}, "a bare name is a flag test")
	_eq(_tree("chapter >= 2"), {"var": "chapter", "op": ">=", "value": 2},
		"a compared name is a variable")
	_eq(_tree("chapter == 2"), {"var": "chapter", "op": "==", "value": 2}, "==")
	_eq(_tree("chapter != 2"), {"var": "chapter", "op": "!=", "value": 2}, "!=")
	_eq(_tree("gold < 100"), {"var": "gold", "op": "<", "value": 100}, "<")

	# The two-character operators have to be tokenised first, or ">=" reads as ">" plus a
	# stray "=" and the message blames the wrong character.
	_eq(_tree("hp <= 5"), {"var": "hp", "op": "<=", "value": 5}, "<= is one token, not two")

	_eq(_tree("name == \"melina\""), {"var": "name", "op": "==", "value": "melina"},
		"a quoted string is a value")
	_eq(_tree("name == 'melina'"), {"var": "name", "op": "==", "value": "melina"},
		"  single quotes too")
	_eq(_tree("ready == true"), {"var": "ready", "op": "==", "value": true}, "and true/false")
	_eq(_tree("depth > -3"), {"var": "depth", "op": ">", "value": -3}, "negative numbers")
	_eq(_tree("ratio < 1.5"), {"var": "ratio", "op": "<", "value": 1.5}, "and fractional ones")

	_eq(_tree("not cursed"), {"not": {"flag": "cursed"}}, "not negates")
	_eq(_tree("not not cursed"), {"not": {"not": {"flag": "cursed"}}}, "  and stacks")


func _test_parse_precedence() -> void:
	_section("  precedence -- and binds tighter than or")

	# The assertion that matters: `a or b and c` is a or (b and c), not (a or b) and c.
	# Getting this backwards produces conditions that are right most of the time, which
	# is the worst way to be wrong.
	var mixed := _tree("a or b and c")
	_ok(mixed.has("any"), "the top of `a or b and c` is the or")
	var branches: Array = mixed.get("any", [])
	_eq(branches.size(), 2, "  with two branches")
	_eq(branches[0], {"flag": "a"}, "  a on the left")
	_ok((branches[1] as Dictionary).has("all"), "  and the and on the right")

	var flipped := _tree("a and b or c")
	_ok(flipped.has("any"), "`a and b or c` is also an or at the top")
	_ok((flipped["any"][0] as Dictionary).has("all"), "  with the and on the LEFT this time")

	_eq(_tree("a and b and c"), {"all": [{"flag": "a"}, {"flag": "b"}, {"flag": "c"}]},
		"a chain of ands is one flat all, not a nest")
	_eq(_tree("a or b or c"), {"any": [{"flag": "a"}, {"flag": "b"}, {"flag": "c"}]},
		"and a chain of ors one flat any")

	_section("  parentheses override it")

	var forced := _tree("(a or b) and c")
	_ok(forced.has("all"), "(a or b) and c is an and at the top")
	_ok((forced["all"][0] as Dictionary).has("any"), "  with the or inside it")

	_eq(_tree("(((a)))"), {"flag": "a"}, "redundant parentheses collapse")
	_eq(_tree("not (a and b)"), {"not": {"all": [{"flag": "a"}, {"flag": "b"}]}},
		"not applies to a parenthesised group")

	# not binds tighter than and: `not a and b` is (not a) and b.
	var tight := _tree("not a and b")
	_ok(tight.has("all"), "`not a and b` is an and at the top")
	_eq((tight["all"] as Array)[0], {"not": {"flag": "a"}}, "  with not applying to a alone")


func _test_parse_predicates() -> void:
	_section("  self flags, calls and literals")

	_eq(_tree("self.talked"), {"self_flag": "talked"}, "self.talked is a self flag")
	_eq(_tree("not self.talked"), {"not": {"self_flag": "talked"}}, "  negatable")

	# A self flag holds a bool, so comparing it to false is a negation rather than a
	# comparison -- and comes out as the same leaf the page form writes.
	_eq(_tree("self.talked == false"), {"self_flag": "talked", "is": false},
		"self.talked == false is the negated leaf, not a comparison")
	_eq(_tree("self.talked == true"), {"self_flag": "talked", "is": true}, "  and == true is plain")

	_eq(_tree("has_item(\"brass_key\")"), {"item": "brass_key"}, "has_item builds an item leaf")
	_eq(_tree("party_has('melina')"), {"party_has": "melina"}, "party_has builds a party leaf")

	_ok(EventCondition.is_always(_tree("true")), "a bare `true` is the always-passing tree")
	_eq(_tree("false"), {"not": {}}, "and `false` is its inverse")

	_section("  mixed, the way an author would actually type one")

	_eq(_tree("chapter >= 2 and not slime_dead"),
		{"all": [{"var": "chapter", "op": ">=", "value": 2}, {"not": {"flag": "slime_dead"}}]},
		"chapter >= 2 and not slime_dead")


func _test_parse_errors() -> void:
	_section("  errors carry a position, so the dock can point at it")

	_ok(_problems("chapter >= ").size() > 0, "a comparison with nothing after it")
	_ok(_problems("(a and b").size() > 0, "an unclosed parenthesis")
	_ok(_problems("a and").size() > 0, "a dangling and")
	_ok(_problems("\"unclosed").size() > 0, "an unclosed string")
	_ok(_problems("a $ b").size() > 0, "a character that means nothing")
	_ok(_problems("self").size() > 0, "self with no flag after it")
	_ok(_problems("has_item(brass_key)").size() > 0, "a call argument that is not quoted")
	_ok(_problems("has_item").size() > 0, "a call with no argument at all")
	_ok(_problems("a b").size() > 0, "two conditions with no operator between them")
	_ok(_problems("chapter >= chpater").size() > 0,
		"comparing against a name, which would let a typo look like a comparison")

	# `=` is the mistake every author makes once, and the message should say so rather
	# than reporting an unexpected character.
	var assignment := _problems("chapter = 2")
	_ok(assignment.size() > 0, "a single = is reported")
	_ok(assignment.size() > 0 and assignment[0].contains("=="),
		"  and the message names the fix")

	var positioned := _problems("a and $")
	_ok(positioned.size() > 0 and positioned[0].contains("character"),
		"a problem names the character position")

	# A condition nobody could read leaves its page reachable and says so loudly. An
	# event that silently vanishes is far harder to attribute than one that appears.
	_ok(EventCondition.is_always(_tree("(a and b")),
		"an unparseable expression is the always-true tree, not a silently false one")


func _test_equivalence() -> void:
	_section("one representation -- the two surfaces agree (question 16)")

	GameState.clear()
	GameState.manifest = {&"chapter": {"type": TYPE_INT, "default": 0}}
	GameState.set_flag(&"stole_the_idol")
	GameState.var_set(&"chapter", 3)
	var ctx := {"map": MAP, "event": EVENT}

	# The claim the decision rests on: a page's structured list and a typed expression
	# are the SAME tree, so they cannot drift into meaning different things.
	var structured := EventCondition.from_list([
		{"flag": "stole_the_idol"},
		{"var": "chapter", "op": ">=", "value": 2},
	])
	var typed := _tree("stole_the_idol and chapter >= 2")

	_eq(typed, structured, "the page form and the typed form are the same tree")
	_eq(EventCondition.evaluate(typed, ctx), EventCondition.evaluate(structured, ctx),
		"  so they evaluate the same")
	_eq(EventCondition.keys(typed), EventCondition.keys(structured),
		"  and subscribe to the same keys")


# -- Validation ----------------------------------------------------------------

func _test_validate() -> void:
	_section("validate -- caught at author time, not at 2am")

	var manifest := {&"chapter": {"type": TYPE_INT, "default": 0}}

	_ok(EventCondition.validate({"var": "chapter", "op": ">=", "value": 2}, manifest).is_empty(),
		"a declared variable is clean")

	# The check question 14 unlocked and question 16 bought.
	var typo := EventCondition.validate({"var": "chpater", "op": ">=", "value": 2}, manifest)
	_ok(typo.size() > 0, "an undeclared variable is an error")
	_ok(typo.size() > 0 and typo[0].contains("chapter"),
		"  and the message suggests the one that was meant")

	_ok(EventCondition.validate({"var": "chapter", "op": "=>", "value": 2}, manifest).size() > 0,
		"a bad operator is reported")
	_ok(EventCondition.validate({"var": "chapter", "op": ">="}, manifest).size() > 0,
		"a comparison with no value is reported")
	_ok(EventCondition.validate({"flag": "anything"}, manifest).is_empty(),
		"flags are not in the manifest, so any flag name is fine")

	_ok(EventCondition.validate({"nonsense": 1}, manifest).size() > 0,
		"a leaf with no known test is reported")
	_ok(EventCondition.validate({"flag": "a", "var": "chapter"}, manifest).size() > 0,
		"a leaf testing two things at once is reported")
	_ok(EventCondition.validate({"any": []}, manifest).size() > 0,
		"an empty any is reported -- it can never pass")
	_ok(EventCondition.validate({"all": [{"var": "chpater", "op": "==", "value": 1}]},
		manifest).size() > 0, "and problems are found inside branches")

	_ok(EventCondition.validate({"var": "anything", "op": "==", "value": 1}, {}).is_empty(),
		"an empty manifest accepts every name, so an early project is not drowned")


# -- Helpers -------------------------------------------------------------------

func _tree(text: String) -> Dictionary:
	return EventCondition.parse_expression(text)["tree"]


func _problems(text: String) -> Array:
	return EventCondition.parse_expression(text)["problems"]


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
