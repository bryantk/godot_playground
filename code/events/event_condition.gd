class_name EventCondition

## One condition representation, two authoring surfaces - question 16.
##
## An event page's [code]conditions[/code] is a structured list, because the page form
## offers dropdowns and because page selection has to know [i]which keys a condition
## mentions[/i] without evaluating it (see [method keys]). The [code]if[/code] command
## takes a typed expression, because it is written inline while building a graph and a
## form would be slower there. **Both become the tree below.** There is one evaluator,
## one predicate table, and one thing a validator has to understand.
##
## [b]Godot's [code]Expression[/code] cannot serve[/b], which is the reason this file has
## a hand-written parser in it. It executes a string and hands back a value - but not a
## tree, and the tree is the entire point: without it page selection cannot derive its
## subscription list, and an [code]if[/code] cannot be checked against the variable
## manifest at author time. A typo in a flag name would fail silently at run time, in the
## middle of a cutscene, which is the worst possible place to discover it.
##
## [b]The tree.[/b] Leaves test state; branches combine them.
##
## [codeblock]
## {"flag": "stole_the_idol"}                 a global flag
## {"flag": "slime_dead", "is": false}        ... negated
## {"var": "chapter", "op": ">=", "value": 2} a declared variable
## {"self_flag": "talked"}                    per-event, per-map
## {"item": "brass_key"}                      inventory
## {"party_has": "melina"}                    party roster
##
## {"all": [ ... ]}   every entry passes
## {"any": [ ... ]}   at least one passes
## {"not": { ... }}   the inverse
## [/codeblock]
##
## A page's flat [code]conditions[/code] array is sugar for [code]all[/code], which is
## what makes the common case - a short AND list - readable without nesting.

# -- The predicate table -------------------------------------------------------
#
# One table, so a predicate cannot exist on the page side and not in `if`. Adding one
# means an entry here, a branch in _test, and a token in the parser - and the validator,
# the key extractor and both authoring surfaces pick it up without being touched.

## Leaf kinds, mapped to the argument each carries.
const LEAVES := {
	"flag": "name",
	"self_flag": "name",
	"var": "name",
	"item": "name",
	"party_has": "name",
}

## Branch kinds, mapped to whether they take a list or a single child.
const BRANCHES := {"all": "list", "any": "list", "not": "one"}

## The comparisons [code]var[/code] accepts.
const OPERATORS: PackedStringArray = ["==", "!=", "<", "<=", ">", ">="]

## What a bare page [code]conditions[/code] array means.
const IMPLICIT_BRANCH := "all"


# -- Building ------------------------------------------------------------------

## A page's [code]conditions[/code] array as a tree.
##
## An empty list is [code]{}[/code] - the always-true condition, which is what page 1
## conventionally carries. One entry is that entry; several are an [code]all[/code].
static func from_list(entries: Variant) -> Dictionary:
	if typeof(entries) != TYPE_ARRAY:
		return entries if typeof(entries) == TYPE_DICTIONARY else {}

	var list: Array = entries
	if list.is_empty():
		return {}
	if list.size() == 1 and typeof(list[0]) == TYPE_DICTIONARY:
		return list[0]
	return {IMPLICIT_BRANCH: list.duplicate()}


## True for the always-passing condition - an empty tree.
static func is_always(tree: Dictionary) -> bool:
	return tree.is_empty()


# -- Evaluating ----------------------------------------------------------------

## Does [param tree] pass right now?
##
## [param ctx] carries what the leaves need beyond [code]GameState[/code]:
## [code]map[/code] and [code]event[/code] for self flags, and optional
## [code]has_item[/code] / [code]party_has[/code] [Callable]s for the two predicates whose
## systems do not exist yet.
##
## [b]An empty tree passes[/b], because that is page 1 with no conditions - the fallback
## that must always be reachable.
static func evaluate(tree: Variant, ctx: Dictionary = {}) -> bool:
	if typeof(tree) != TYPE_DICTIONARY:
		return false

	var node: Dictionary = tree
	if node.is_empty():
		return true

	if node.has("all"):
		for child in _children(node["all"]):
			if not evaluate(child, ctx):
				return false
		return true

	if node.has("any"):
		# An empty `any` is false: "at least one of nothing" is nothing. The asymmetry
		# with `all` is the standard one and is worth stating rather than discovering.
		for child in _children(node["any"]):
			if evaluate(child, ctx):
				return true
		return false

	if node.has("not"):
		return not evaluate(node["not"], ctx)

	return _test_leaf(node, ctx)


static func _children(value: Variant) -> Array:
	return value if typeof(value) == TYPE_ARRAY else []


## One leaf against the world. Unknown leaves are false - they were reported at parse and
## at validate, and failing closed here is safer than a page activating because nobody
## understood why it should not.
static func _test_leaf(node: Dictionary, ctx: Dictionary) -> bool:
	if node.has("flag"):
		return GameState.flag(StringName(node["flag"])) == _expected(node)

	if node.has("self_flag"):
		var map_id: StringName = ctx.get("map", &"")
		var event_id: StringName = ctx.get("event", &"")
		var held := GameState.self_flag(map_id, event_id, StringName(node["self_flag"]))
		return held == _expected(node)

	if node.has("var"):
		var current: Variant = GameState.var_get(StringName(node["var"]))
		return compare(current, str(node.get("op", "==")), node.get("value", 0))

	if node.has("item"):
		return _ask(ctx, "has_item", str(node["item"])) == _expected(node)

	if node.has("party_has"):
		return _ask(ctx, "party_has", str(node["party_has"])) == _expected(node)

	return false


## The [code]is[/code] field: a leaf may be negated in place rather than wrapped in a
## [code]not[/code], which keeps the flat page list flat.
static func _expected(node: Dictionary) -> bool:
	return bool(node.get("is", true))


## Asks [param ctx] for a predicate whose system does not exist yet.
##
## [b]Absent means false, and says so once.[/b] Inventory and the party roster are not
## built; a page testing one would otherwise silently never activate, which is the class
## of bug this project keeps calling the hardest to attribute - nothing failed, the chest
## simply never opened.
static func _ask(ctx: Dictionary, key: String, argument: String) -> bool:
	var provider: Variant = ctx.get(key)
	if provider is Callable and (provider as Callable).is_valid():
		return bool((provider as Callable).call(argument))

	push_warning("EventCondition: no '%s' provider in context, so '%s' reads false."
		% [key, argument])
	return false


## [param left] against [param right] under [param op]. Public because the runtime's
## [code]if[/code] and the page evaluator are the same comparison, and a second copy of
## this is a second set of edge cases.
static func compare(left: Variant, op: String, right: Variant) -> bool:
	match op:
		"==": return _loose_equal(left, right)
		"!=": return not _loose_equal(left, right)
		"<": return _as_number(left) < _as_number(right)
		"<=": return _as_number(left) <= _as_number(right)
		">": return _as_number(left) > _as_number(right)
		">=": return _as_number(left) >= _as_number(right)
	return false


## Equality across the types a variable may hold.
##
## [b]Numbers compare as numbers[/b] whatever they arrived as: JSON has one number type,
## so a variable declared [code]int[/code] and a literal [code]2[/code] parsed as a float
## must still be equal, or every comparison against a whole number is a coin toss.
static func _loose_equal(left: Variant, right: Variant) -> bool:
	var left_number := left is int or left is float
	var right_number := right is int or right is float
	if left_number and right_number:
		return is_equal_approx(_as_number(left), _as_number(right))
	if left is bool or right is bool:
		return bool(left) == bool(right)
	return str(left) == str(right)


static func _as_number(value: Variant) -> float:
	if value is bool:
		return 1.0 if value else 0.0
	if value is int or value is float:
		return float(value)
	if value is String and (value as String).is_valid_float():
		return float(value)
	return 0.0


# -- Keys ----------------------------------------------------------------------

## Every [code]GameState[/code] key [param tree] reads, as a set of names.
##
## [b]This is why the page side is structured at all.[/b] `GameState` emits
## [signal GameState.changed] per key, and an event subscribes to exactly the keys its
## conditions mention - so nothing polls, nothing is wired by hand, and a condition
## cannot reference a key it forgot to listen for. Deriving this from a string would mean
## parsing it, which is the argument that made both surfaces share one tree.
##
## Self flags expand to the composite [code]map:event:flag[/code] key that
## [method GameState.set_self_flag] actually emits, when [param map_id] and
## [param event_id] are given - otherwise the bare name, which is enough for a validator
## but not for a subscription.
static func keys(tree: Variant, map_id: StringName = &"",
		event_id: StringName = &"") -> Array[StringName]:
	var found: Dictionary = {}
	_gather_keys(tree, map_id, event_id, found)

	var out: Array[StringName] = []
	for key: Variant in found:
		out.append(key)
	return out


static func _gather_keys(tree: Variant, map_id: StringName, event_id: StringName,
		into: Dictionary) -> void:
	if typeof(tree) != TYPE_DICTIONARY:
		return
	var node: Dictionary = tree

	for branch: Variant in BRANCHES:
		if not node.has(branch):
			continue
		if BRANCHES[branch] == "list":
			for child in _children(node[branch]):
				_gather_keys(child, map_id, event_id, into)
		else:
			_gather_keys(node[branch], map_id, event_id, into)
		return

	if node.has("flag"):
		into[StringName(node["flag"])] = true
	elif node.has("var"):
		into[StringName(node["var"])] = true
	elif node.has("self_flag"):
		var name := StringName(node["self_flag"])
		if map_id != &"" or event_id != &"":
			name = StringName(GameState.self_key(map_id, event_id, name))
		into[name] = true

	# item and party_has deliberately contribute nothing: neither system emits a change
	# signal yet, so a subscription naming one would never fire and would read as a
	# working subscription that simply never woke up.


# -- Validating ----------------------------------------------------------------

## Problems with [param tree], as messages.
##
## [param manifest] is [member GameState.manifest]. When it is empty every identifier is
## accepted - a project that has not declared its variables yet should not drown in
## warnings - but once it has entries, an identifier absent from it is an error. That is
## the check question 14 unlocked and question 16 bought: a graph testing
## [code]chpater[/code] is caught here rather than reading false forever at run time.
static func validate(tree: Variant, manifest: Dictionary = {}) -> Array[String]:
	var problems: Array[String] = []
	_validate_node(tree, manifest, "condition", problems)
	return problems


static func _validate_node(tree: Variant, manifest: Dictionary, where: String,
		problems: Array[String]) -> void:
	if typeof(tree) != TYPE_DICTIONARY:
		problems.append("%s must be an object, found %s."
			% [where, type_string(typeof(tree))])
		return

	var node: Dictionary = tree
	if node.is_empty():
		return

	for branch: Variant in BRANCHES:
		if not node.has(branch):
			continue
		if BRANCHES[branch] == "list":
			if typeof(node[branch]) != TYPE_ARRAY:
				problems.append("%s: \"%s\" must be a list, found %s."
					% [where, branch, type_string(typeof(node[branch]))])
				return
			var list: Array = node[branch]
			if list.is_empty():
				problems.append("%s: \"%s\" is empty%s." % [where, branch,
					", which is always false" if branch == "any" else ""])
			for i in list.size():
				_validate_node(list[i], manifest, "%s.%s[%d]" % [where, branch, i], problems)
		else:
			_validate_node(node[branch], manifest, "%s.not" % where, problems)
		return

	var kind := ""
	for leaf: Variant in LEAVES:
		if node.has(leaf):
			if kind != "":
				problems.append("%s tests both \"%s\" and \"%s\" - a leaf tests one thing."
					% [where, kind, leaf])
				return
			kind = leaf

	if kind == "":
		problems.append("%s has no test in it. Expected one of: %s."
			% [where, ", ".join(LEAVES.keys())])
		return

	if kind == "var":
		var op := str(node.get("op", "=="))
		if not OPERATORS.has(op):
			problems.append("%s: \"%s\" is not a comparison. Expected one of: %s."
				% [where, op, ", ".join(OPERATORS)])
		if not node.has("value"):
			problems.append("%s: \"var\" needs a \"value\" to compare against." % where)

	# Declared-name checks. Flags are not in the manifest - only variables are - so only
	# `var` is checked against it, and an unknown flag is not an error.
	if kind == "var" and not manifest.is_empty():
		var name := StringName(node["var"])
		if not manifest.has(name) and not manifest.has(String(name)):
			problems.append("%s: \"%s\" is not a declared variable.%s" % [where, name,
				_did_you_mean(String(name), manifest)])


## The closest declared name, when there is an obvious one. A typo is the case this whole
## check exists for, so naming the intended variable is most of the value.
##
## [b]The threshold is 0.45 because of what a typo actually looks like.[/b] Godot compares
## bigrams, and a transposition - the commonest slip there is - scores about 0.5:
## "chpater" against "chapter" shares only ch, te and er of six pairs each. A threshold
## picked by eye at 0.6 rejects exactly the case the suggestion exists for. Unrelated
## names score near zero, so there is a lot of room below 0.45.
static func _did_you_mean(name: String, manifest: Dictionary) -> String:
	var best := ""
	var best_score := 0.0
	for key: Variant in manifest:
		var score := name.similarity(str(key))
		if score > best_score:
			best_score = score
			best = str(key)
	return " Did you mean \"%s\"?" % best if best_score >= 0.45 else ""


# -- Parsing an expression -----------------------------------------------------
#
# The grammar, loosest binding first:
#
#   expression := disjunction
#   disjunction:= conjunction ( "or" conjunction )*
#   conjunction:= negation ( "and" negation )*
#   negation   := "not" negation | primary
#   primary    := "(" expression ")" | comparison | predicate
#   comparison := operand ( "==" | "!=" | "<" | "<=" | ">" | ">=" ) operand
#   predicate  := identifier | "self" "." identifier | call
#   call       := identifier "(" string ")"
#   operand    := number | string | true | false | identifier
#
# Two conveniences worth naming, because they are where the two surfaces meet:
#
#   - A bare identifier is a FLAG test, and an identifier in a comparison is a VARIABLE.
#     That is exactly the distinction the structured form draws with {flag} and {var},
#     so the same sentence means the same thing typed either way.
#   - `self.talked` is a self flag. The dot is the only punctuation the grammar needs
#     beyond parentheses, and it reads the way the scope does.

## Function-call predicates, mapped to the leaf they build.
const CALLS := {"has_item": "item", "party_has": "party_has"}

## The word that opens a self flag, as in [code]self.talked[/code].
const SELF_SCOPE := "self"

const KEYWORDS: PackedStringArray = ["and", "or", "not", "true", "false"]


## Reads an expression string into the same tree the structured form produces.
##
## Returns [code]{"tree": Dictionary, "problems": Array[String]}[/code]. Problems carry a
## character offset in their text, so the dock can point at the place rather than at the
## line.
##
## An unparseable expression comes back as an empty tree, which reads as always-true.
## That is deliberate: a condition nobody could read should leave the page it guards
## reachable and loudly reported, not quietly unreachable. An event that vanishes is
## much harder to attribute than one that appears when it should not.
static func parse_expression(text: String) -> Dictionary:
	var problems: Array[String] = []
	var tokens := _tokenise(text, problems)
	if not problems.is_empty():
		return {"tree": {}, "problems": problems}

	var cursor := {"tokens": tokens, "at": 0}
	var tree := _parse_disjunction(cursor, problems)

	if problems.is_empty() and not _at_end(cursor):
		var token: Dictionary = tokens[cursor["at"]]
		problems.append("Unexpected \"%s\" at character %d." % [token["text"], token["at"]])

	if not problems.is_empty():
		return {"tree": {}, "problems": problems}
	return {"tree": tree, "problems": problems}


# -- Tokeniser -----------------------------------------------------------------

static func _tokenise(text: String, problems: Array[String]) -> Array:
	var tokens: Array = []
	var i := 0

	while i < text.length():
		var c := text[i]

		if c == " " or c == "\t" or c == "\n" or c == "\r":
			i += 1
			continue

		# Two-character operators first, or ">=" tokenises as ">" and a stray "=".
		if i + 1 < text.length() and OPERATORS.has(text.substr(i, 2)):
			tokens.append({"kind": "op", "text": text.substr(i, 2), "at": i})
			i += 2
			continue

		if c == "<" or c == ">":
			tokens.append({"kind": "op", "text": c, "at": i})
			i += 1
			continue

		if c == "=":
			problems.append("Single \"=\" at character %d is an assignment, not a test - use \"==\"." % i)
			return tokens

		if c == "(" or c == ")" or c == ".":
			tokens.append({"kind": c, "text": c, "at": i})
			i += 1
			continue

		if c == "\"" or c == "'":
			var close := text.find(c, i + 1)
			if close < 0:
				problems.append("Unclosed string starting at character %d." % i)
				return tokens
			tokens.append({"kind": "string", "text": text.substr(i + 1, close - i - 1), "at": i})
			i = close + 1
			continue

		if c.is_valid_int() or (c == "-" and i + 1 < text.length() and text[i + 1].is_valid_int()):
			var start := i
			i += 1
			while i < text.length() and (text[i].is_valid_int() or text[i] == "."):
				i += 1
			tokens.append({"kind": "number", "text": text.substr(start, i - start), "at": start})
			continue

		if _is_name_start(c):
			var start := i
			while i < text.length() and _is_name_body(text[i]):
				i += 1
			var word := text.substr(start, i - start)
			var kind := "keyword" if KEYWORDS.has(word.to_lower()) else "name"
			tokens.append({"kind": kind, "text": word, "at": start})
			continue

		problems.append("Unexpected character \"%s\" at character %d." % [c, i])
		return tokens

	return tokens


static func _is_name_start(c: String) -> bool:
	return c == "_" or (c.to_lower() != c.to_upper())


static func _is_name_body(c: String) -> bool:
	return _is_name_start(c) or c.is_valid_int()


# -- Recursive descent ---------------------------------------------------------

static func _at_end(cursor: Dictionary) -> bool:
	return cursor["at"] >= (cursor["tokens"] as Array).size()


static func _peek(cursor: Dictionary) -> Dictionary:
	return {} if _at_end(cursor) else cursor["tokens"][cursor["at"]]


static func _take(cursor: Dictionary) -> Dictionary:
	var token := _peek(cursor)
	cursor["at"] = int(cursor["at"]) + 1
	return token


static func _is_word(token: Dictionary, word: String) -> bool:
	return token.get("kind", "") == "keyword" and str(token.get("text", "")).to_lower() == word


static func _parse_disjunction(cursor: Dictionary, problems: Array[String]) -> Dictionary:
	var left := _parse_conjunction(cursor, problems)
	if not _is_word(_peek(cursor), "or"):
		return left

	var branches: Array = [left]
	while _is_word(_peek(cursor), "or"):
		_take(cursor)
		branches.append(_parse_conjunction(cursor, problems))
	return {"any": branches}


static func _parse_conjunction(cursor: Dictionary, problems: Array[String]) -> Dictionary:
	var left := _parse_negation(cursor, problems)
	if not _is_word(_peek(cursor), "and"):
		return left

	var branches: Array = [left]
	while _is_word(_peek(cursor), "and"):
		_take(cursor)
		branches.append(_parse_negation(cursor, problems))
	return {"all": branches}


static func _parse_negation(cursor: Dictionary, problems: Array[String]) -> Dictionary:
	if _is_word(_peek(cursor), "not"):
		_take(cursor)
		return {"not": _parse_negation(cursor, problems)}
	return _parse_primary(cursor, problems)


static func _parse_primary(cursor: Dictionary, problems: Array[String]) -> Dictionary:
	if _at_end(cursor):
		problems.append("Expression ends early - something was expected here.")
		return {}

	var token := _peek(cursor)

	if token["kind"] == "(":
		_take(cursor)
		var inner := _parse_disjunction(cursor, problems)
		if _peek(cursor).get("kind", "") != ")":
			problems.append("Unclosed \"(\" opened at character %d." % token["at"])
			return {}
		_take(cursor)
		return inner

	# self.talked
	if token["kind"] == "name" and str(token["text"]).to_lower() == SELF_SCOPE:
		_take(cursor)
		if _peek(cursor).get("kind", "") != ".":
			problems.append("\"self\" at character %d needs a flag after it, as self.talked."
				% token["at"])
			return {}
		_take(cursor)
		var flag := _peek(cursor)
		if flag.get("kind", "") != "name":
			problems.append("Expected a self flag name after \"self.\" at character %d."
				% token["at"])
			return {}
		_take(cursor)
		return _maybe_compare({"self_flag": flag["text"]}, "self_flag", cursor, problems)

	# has_item("brass_key")
	if token["kind"] == "name" and CALLS.has(str(token["text"]).to_lower()):
		return _parse_call(cursor, problems)

	if token["kind"] == "keyword" and str(token["text"]).to_lower() in ["true", "false"]:
		# A bare literal is legal and occasionally useful while editing - `true` is an
		# always-passing condition written out loud.
		_take(cursor)
		return {} if str(token["text"]).to_lower() == "true" else {"not": {}}

	if token["kind"] == "name":
		_take(cursor)
		return _maybe_compare({"flag": token["text"]}, "flag", cursor, problems)

	problems.append("Expected a condition at character %d, found \"%s\"."
		% [token["at"], token["text"]])
	return {}


## A name is a flag on its own and a variable in a comparison, so the decision cannot be
## made until the token after it has been seen. This is that lookahead.
static func _maybe_compare(leaf: Dictionary, kind: String, cursor: Dictionary,
		problems: Array[String]) -> Dictionary:
	var next := _peek(cursor)
	if next.get("kind", "") != "op":
		return leaf

	var op := str(_take(cursor)["text"])
	var value: Variant = _parse_operand(cursor, problems)

	if kind == "self_flag":
		# `self.talked == false` is a negated self flag rather than a comparison, since a
		# self flag holds nothing but a bool.
		if op == "==" or op == "!=":
			var wanted := bool(value) if op == "==" else not bool(value)
			return {"self_flag": leaf["self_flag"], "is": wanted}
		problems.append("A self flag holds true or false, so \"%s\" cannot be compared with \"%s\"."
			% [leaf["self_flag"], op])
		return leaf

	# A name being compared is a variable, not a flag - which is the one place the two
	# authoring surfaces have to agree on what a bare word meant.
	return {"var": leaf["flag"], "op": op, "value": value}


static func _parse_operand(cursor: Dictionary, problems: Array[String]) -> Variant:
	if _at_end(cursor):
		problems.append("Expression ends after a comparison - nothing to compare against.")
		return 0

	var token := _take(cursor)
	match token["kind"]:
		"number":
			var text := str(token["text"])
			return int(text) if not text.contains(".") else float(text)
		"string":
			return token["text"]
		"keyword":
			var word := str(token["text"]).to_lower()
			if word == "true" or word == "false":
				return word == "true"
		"name":
			# Comparing a variable against another name is not supported: nothing in the
			# format wants it, and accepting it would make `chapter >= chpater` legal.
			problems.append("\"%s\" at character %d is a name, not a value. Compare against a number, a string, or true/false."
				% [token["text"], token["at"]])
			return 0

	problems.append("Expected a value at character %d, found \"%s\"."
		% [token["at"], token["text"]])
	return 0


static func _parse_call(cursor: Dictionary, problems: Array[String]) -> Dictionary:
	var token := _take(cursor)
	var leaf := str(CALLS[str(token["text"]).to_lower()])

	if _peek(cursor).get("kind", "") != "(":
		problems.append("\"%s\" at character %d needs an argument, as %s(\"name\")."
			% [token["text"], token["at"], token["text"]])
		return {}
	_take(cursor)

	var argument := _peek(cursor)
	if argument.get("kind", "") != "string":
		problems.append("\"%s\" at character %d takes a quoted name."
			% [token["text"], token["at"]])
		return {}
	_take(cursor)

	if _peek(cursor).get("kind", "") != ")":
		problems.append("Unclosed \"(\" in \"%s\" at character %d." % [token["text"], token["at"]])
		return {}
	_take(cursor)

	return {leaf: argument["text"]}
