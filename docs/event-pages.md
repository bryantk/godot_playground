# Event pages, routes, and the editor surfaces

Third document, alongside [architecture.md](architecture.md) (engine seams) and
[two-games.md](two-games.md) (two-game gap analysis). Written 2026-09-07.

This covers the event document format once an event has multiple pages, where autonomous
movement lives, how a page is chosen, and what has to exist in the Godot editor for routes
to be authored visually rather than typed.

It supersedes architecture.md §7.1 (document shape) and §7.6 (triggers).
[slime_a.event.json](events/slime_a.event.json) is the worked example; the other four files
in [docs/events/](events/) are single-page shorthand, still valid under §2.1.
[open-questions.md](open-questions.md) collects what is still undecided here and elsewhere;
[solved-questions.md](solved-questions.md) keeps the answers.

---

## 1. What changes

architecture.md treats an event as *one* graph with a trigger set on the node. Three
requirements change that:

1. An event has **pages** — each with its own logic, art and settings.
2. **Page selection is conditional**, evaluated last page to first; the first page whose
   conditions all pass is the active one.
3. **Movement patterns are data too**, edited with in-viewport tools rather than typed, and
   stored in the same JSON.

The consequences worth naming up front:

- **Trigger becomes a per-page setting**, not a node property. The whole point of pages is
  that a chest is untouchable on page 1, talks on page 2, and blocks the path on page 3 —
  those are different triggers.
- **Art becomes page-driven**, which is the first concrete reason `ActorView`
  (two-games.md §3.3) needs to exist independent of the space axis. Page switches
  re-apply art.
- **Autonomous movement is a page field, not a graph.** A patrol should not require opening
  a node graph, and it must be drawable in the viewport.
- **`graph_document.gd` stops being the whole document** and becomes the parser for one
  page's graph. A new layer owns the page wrapper.

---

## 2. Document format

```json
{
  "format": 1,
  "id": "slime_a",
  "pages": [
    {
      "conditions": [],
      "settings": { "trigger": "interact", "solid": true, "speed": 100 },
      "art":      { "view": "sprite", "sheet": "res://games/jrpg/art/slime.png", "directions": 4 },
      "route":    { "mode": "waypoints", "loop": "cycle", "waypoints": [] },
      "graph":    [ ]
    }
  ]
}
```

Every page key is optional and **absent means default, never inherited** (decided
2026-09-08, §6 Q4). A page with no `graph` is logic-free (art and a route only — a wandering
decoration); a page with no `route` stands still; a page with no `art` displays nothing.

The repetition that inheritance would have saved is an editor problem, not a format one: a
"duplicate page" button in the page bar (§4.1) fills the fields in. What that buys is that a
page is readable in isolation, diffs cleanly, and — matching the rule stated in
open-questions.md Cluster 4 — the in-memory page is always exactly the page in the file, with
no resolution pass between parse and `ActorView.apply_art`.

### 2.1 Backwards compatibility

`graph_document.parse` currently takes a top-level JSON *array* of nodes. Keep that working:
a top-level array is read as a single-page document with no conditions and default settings.
That matches the parser's existing "repair rather than reject" philosophy, keeps the four
examples in [docs/events/](events/) valid, and means a hand-typed one-page event never needs
the wrapper.

**Layering:** a new `EventDocument` owns the wrapper, page list, conditions, settings, art
and routes. It delegates each page's `graph` array to `graph_document` unchanged. The graph
editor keeps editing one graph at a time and gains a page selector; it never learns about
conditions.

### 2.2 Conditions

A page's `conditions` is an AND list — every entry must pass. Structured entries rather than
expression strings, because these are the things an editor needs to offer dropdowns for:

```json
"conditions": [
  {"flag": "stole_the_idol"},
  {"flag": "slime_a_dead", "is": false},
  {"var": "chapter", "op": ">=", "value": 2},
  {"self_flag": "talked"},
  {"item": "brass_key"},
  {"party_has": "melina"}
]
```

**Self flags** are the classic "talk once, then change permanently" mechanism without
polluting global flag space: per-event, per-map storage keyed `map_id:event_id:flag`, set by
a `set_self_flag` command. They belong in the save envelope (two-games.md §3.10) and are
easy to forget there.

**Two surfaces, one shape** (question 16, decided 2026-09-14). The `if` *command*
(architecture.md §7.2) still takes an expression string, because it is typed inline while
writing a graph and a form would be slower there — but **the string is parsed into exactly
the condition above**, not evaluated as a string. So there is one evaluator, one predicate
table (`flag`, `var`, `self_flag`, `item`, `party_has`, …), and one thing a validator has to
understand; the difference between a page and an `if` is the authoring surface, not the
format. Two things follow. The structured form carries `all` / `any` / `not` nesting so it
can hold anything a typed expression can — the flat AND list above is the *page* convention,
what the page form offers, not the limit of the representation. And a typed expression does
not survive a round trip: it normalises to the tree on read, the way §7.2's terse `mov n 2`
does. Godot's built-in `Expression` cannot be the evaluator, since it executes without
handing back a tree, so stage C owes a real parser.

### 2.3 Page selection

**Pages are checked from the last to the first. The first page whose conditions all pass
becomes active.** So a later page overrides an earlier one, and page 1 — conventionally with
no conditions — is the default that always passes.

```
page 3   flag: boss_dead          → checked first
page 2   flag: stole_the_idol     → checked second
page 1   (no conditions)          → the fallback
```

**A validator check falls straight out of this:** if any page other than the first has an
empty condition list, every page before it is unreachable. That is a common authoring
mistake and a cheap, specific warning to emit — "page 2 has no conditions; page 1 can never
activate".

**When are conditions re-evaluated?** The important question, and the one most likely to be
answered badly by default.

Polling every event every frame is wasteful with a few dozen events on a map. Recommend
**event-driven invalidation**: `GameState` emits `changed(key)`, and each event subscribes to
exactly the keys its conditions reference — a subscription list derivable automatically from
the condition entries, so nothing is wired by hand and nothing can be forgotten. Re-evaluate
only the events that reference a changed key, plus a full pass on map load and at round close
(two-games.md §3.1), since a round can change state.

**Page switching mid-execution** must be deferred. If a page's graph is running and a flag
change makes a different page active, swapping art and logic underneath the running graph is
a bug factory. Recommend: mark the event dirty and swap when the graph completes, or at the
next round close. See §6 Q2.

---

## 3. Routes

A route is the page's autonomous movement pattern — what the event does unprompted, as
distinct from the graph, which is what it does when triggered.

```json
"route": {
  "mode": "waypoints",
  "loop": "cycle",
  "on_blocked": "wait",
  "speed": 100,
  "waypoints": [
    {"cell": [6, 0, 4]},
    {"cell": [12, 0, 4], "face": [0, 0, 1], "wait": 2}
  ]
}
```

| Field | Values |
| --- | --- |
| `mode` | `fixed` (never moves), `waypoints`, `steps`, `toward` / `away` (an actor id, default player), `random` |
| `loop` | `none`, `cycle` (return to the first waypoint or the start of the step list), `pingpong` |
| `on_blocked` | `wait`, `skip` (drop that waypoint or step), `reverse`, `repath` (A\*, `waypoints` only) |
| `speed` | The speed class from two-games.md §3.1 — credit gained per pulse. `200` acts twice, `50` every other pulse. |
| `waypoints` | `waypoints` mode only. `cell` is required; `face` and `wait` (in steps or seconds by profile) are optional per point. |
| `steps` | `steps` mode only. A list of relative moves — see below. |

**Absolute cells for `waypoints`, relative for `steps` — two modes, not one field with two
notations.** The first draft of this document proposed one canonical stored shape (absolute)
with a relative-step notation accepted only as parser sugar. That was wrong for the case that
turned out to matter most: **`step_n`, `step_s`, `step_e`, `step_w` (open-questions 11's
route-reuse decision, 2026-09-14) are the single most common move command a route will ever
use**, because a patrolling guard is naturally authored as "two steps north, one east, wait,
two south" rather than as a list of world cells. Normalising that to absolute cells at parse
time would defeat the exact reuse it exists for — a route stored as absolute cells describes
one place, however it was typed.

So there are properly two modes, kept separate rather than merged:

- **`waypoints`** stays absolute cells, canonical, because it is what a gizmo drags in the
  viewport (§4.2) — dragging a handle onto a specific cell is inherently about *that* cell.
- **`steps`** is relative and stays relative — a list of single-cell moves, `wait`s and
  `face`s, using the same terse tokens as the graph's move commands (architecture.md §7.2's
  `mov n 2`-style sugar; a `steps` list is a sequence of those, one step per token):

  ```json
  "route": {
    "mode": "steps",
    "loop": "pingpong",
    "on_blocked": "wait",
    "speed": 100,
    "steps": ["n", "n", "e", {"wait": 2}, "s", "s", "w"]
  }
  ```

  A route in this mode never mentions a cell at all, which is what makes it **trivially
  reusable**: the same `steps` list, referenced by six guards in six different rooms
  (event-pages.md §3.2), patrols six different two-north-one-east-wait-two-south-west
  shapes, each relative to wherever that guard spawned. No anchor, no offset, no expansion
  step — the reuse §3.2 wanted from the anchor-relative `waypoints` scheme comes for free
  from choosing the relative mode, and `steps` should be the one a route library reaches for
  first. `waypoints`' anchor-relative sharing (§3.2) is the fallback for a patrol shape too
  organic to type as steps and worth dragging instead.

**`toward` / `away` / `random` modes are why the slime does not need a graph.** "Patrols
normally, chases you once you steal the idol" is two pages with two routes and no logic at
all. That is a large share of an RPG's monsters handled by data alone.

### 3.1 Routes compile to commands

A route must not be a second execution engine. Recommend it **compiles to the same command
stream `EventRunner` already executes** — a waypoint becomes `move_to`, a `wait` becomes
`wait`, `toward` becomes a `move_to` recomputed each pulse, and a `steps` entry compiles even
more directly than a waypoint does: `step_n` is already the `step` command (architecture.md
§7.3) by another name, so `steps` compiling to commands is closer to a direct read-through
than a translation.

Three things follow for free rather than needing design:

- Route steps are `blocking`, so they join the round and hold the input gate exactly like a
  graph's `move_to` (two-games.md §3.1). No separate gate integration.
- `on_blocked` maps onto the `blocked` signal `MotionController` already emits.
- A complex patrol that outgrows the route form can be rewritten as a graph with `goto`
  (as [patrol_guard.event.json](events/patrol_guard.event.json) does today) with no change
  in behaviour, because both end up as the same commands.

### 3.2 Shared routes

Decided 2026-09-14 alongside open-questions 11: **a route can live in a library and be used
by many monsters**, rather than being copied into each one's page. Six guards patrolling the
same shape is the ordinary case, and six copies is six places to edit when the shape changes.

A route lives at `res://events/routes/<name>.route.json` — one file per route, so it diffs
cleanly and the editor can list what exists — and a page references it by name:

```json
"route": {"use": "patrol_ns", "speed": 50}
```

`mode`, `loop`, `on_blocked` and `speed` may be overridden at the reference site. `waypoints`
and `steps` may not be partially overridden: a page either uses the template's list or
authors its own inline, because a half-overridden move list has no readable meaning.

**`steps` is the mode a shared patrol should be written in, and it needs no anchor at all.**
§3 settled this the same day as this section: a `steps` route is a list of relative moves —
`step_n`, `step_s`, `step_e`, `step_w`, `wait`, `face` — and never mentions a cell, so it is
reusable by construction. Six guards referencing one `steps` template each patrol their own
two-north-one-east shape relative to wherever they spawned, with no expansion pass and
nothing to resolve at parse beyond the ordinary `use` lookup. This is expected to be **most**
shared routes, because a patrol is naturally authored this way in the first place — reuse
falls out of picking the right mode, not out of machinery built to enable it.

**`waypoints` can still be shared, and that case does need an anchor, because absolute cells
are the one thing `steps` cannot express** — an organic path too irregular to type as steps,
worth dragging in the gizmo instead. A shared `waypoints` template stores offsets from the
instance's spawn cell, expanded at parse against that cell into the absolute form §3 expects
everywhere else. Treat this as the fallback: reach for `steps` first, and reach for a shared
`waypoints` template only when the shape genuinely has to be drawn.

**`fixed`, `toward`, `away` and `random` have no waypoints or steps at all**, so sharing them
is a bare named reference with nothing to resolve — and those modes carry a large share of an
RPG's monsters on their own, before either move-list mode is even in play.

**A reference resolves at parse.** The in-memory page holds a fully expanded route, never a
`use` string, which is the same rule §2.1 and question 17 apply everywhere else: accept
shorthand at the boundary, normalise immediately, keep one shape in memory. That is also why
this is not the page inheritance question 17 rejected — that was implicit and positional;
this is explicit, named and gone by the time anything reads it.

**What the editor owes a shared route** (§4.2 gizmos), none of it optional past the second
user:

- **A user count, shown before editing.** Dragging one guard's handle moves all six, and the
  author must know that before the drag, not after.
- **"Make local copy".** The way the seventh guard stops being the sixth.
- **A validator error for a missing `use` target**, at import. A typo'd route name would
  otherwise read in-game as a monster that simply stands still — the hardest class of bug to
  attribute, because nothing failed.

---

## 4. Editor surfaces

Three now, with clear division:

| Surface | Edits | Exists? |
| --- | --- | --- |
| `graph_editor` | one page's `graph` | yes — needs a page selector |
| `event_editor` dock | the whole JSON as text, plus validate | yes — needs page-aware validation |
| **route gizmos** | a page's `route`, in the 2D/3D viewport | **new** |

### 4.1 Graph editor additions

A page bar (tabs or a dropdown) listing pages with a one-line condition summary, plus add,
duplicate, delete and **reorder**. Reordering must be prominent, because order *is* priority
(§2.3) — a reorder silently changes which page wins.

### 4.2 Route gizmos — the new work

Requirements: draw the path in the viewport, drag waypoints, click to append, delete, snap to
cells on grid maps, and preview.

The Godot-specific shape of this, since it is the least familiar part:

- **2D:** `EditorPlugin._forward_canvas_gui_input` for clicks and drags, and
  `_forward_canvas_draw_over_viewport` to draw the path, numbered handles and direction
  arrows.
- **3D:** `EditorNode3DGizmoPlugin` with real handles (`_get_handle_value`,
  `_set_handle`, `_commit_handle`), which gives snapping and the standard drag feel for free.
- **Both spaces again.** One route model, two gizmo implementations, converting through
  `Space` — the same pattern as `SpaceAdapter` and `ActorView`. The route data itself never
  knows which space it is drawn in, since waypoints are `Vector3i` cells.
- **Preview:** a viewport button that walks a ghost sprite along the route at the configured
  speed. Cheap to build once routes compile to commands (§3.1) and worth far more than it
  costs — a patrol that looks right in a still image can still be wrong.
- **A shared `steps` route has nothing to drag.** It is a token list, edited as text or a
  small step-by-step list widget, not a viewport gizmo — the gizmo in this section is for
  `waypoints` only. A `steps` route still wants a **preview**, walking the ghost from each
  using actor's own spawn cell, since that is the only way to see the shape it produces.
- **A shared `waypoints` route is drawn around the instance, edited in the template** (§3.2).
  Handles sit at spawn-anchor plus offset for the actor being looked at, so the gizmo still
  looks absolute; the drag writes the offset back to the `.route.json`, which moves every
  other user. Hence the user count and "make local copy" that §3.2 asks for — they belong on
  this surface, next to the handles, not in a separate inspector.

**The real friction: undo, and where the data lives during editing.** Godot's
`EditorUndoRedoManager` operates on object properties, but the source of truth here is an
external JSON file. Fighting that is the main implementation risk in this document.

Recommended approach — mirror what `event_editor_dock.gd` already does deliberately: the file
stays the source of truth, the gizmo edits an in-memory `EventDocument` with an explicit
dirty flag and Save/Reload, and undo within an editing session is a small internal stack of
route snapshots rather than editor-integrated undo. Routes are small, snapshots are cheap,
and the dock's existing convention means the editor already behaves this way — one model of
"when does my change hit disk", not two. The cost is that `Ctrl+Z` does not cross between
gizmo edits and ordinary scene edits. See §6 Q3.

### 4.3 Where the event lives in a scene

An event needs a scene presence to be positioned and drawn. Proposal:

```
GameEvent (Node)          ← owns the document path, page evaluation, active page
├─ Actor (Node)           ← identity, id, cell; optional
├─ ActorView              ← art, re-applied on page switch
└─ MotionController       ← route and graph commands both drive this
```

`GameEvent` replaces `EventSource` from architecture.md §7.6, absorbing its trigger,
condition and filter fields into page settings — but **not** `fire_on`, which is removed
rather than moved: every trigger fires at step commit, and the land-on-it case is a
`wait_settle` command at the top of the page's own graph (architecture.md §5). An event with no `Actor` is a bodiless region
trigger; one with an `Actor` is an NPC, monster, chest or door — the same node either way,
which keeps the "what is at this cell?" lookup uniform.

---

## 5. Ripples into the other documents

- **architecture.md §7.1** — document shape superseded by §2 here. `graph_document` keeps
  its node format; the wrapper is new and additive.
- **architecture.md §7.6** — `EventSource` becomes `GameEvent`; `trigger`, `condition` and
  `once` move into page `settings`, and `pulse_filter` likewise. `fire_on` is deleted.
- **two-games.md §3.3** — `ActorView` gains `apply_art(art: Dictionary)`, called on page
  activation.
- **two-games.md §3.7** — capability tags now apply to route fields too: `mode: "toward"`
  needs `grid_motion` or a pathfinder; `speed` classes need the step pulse.
- **two-games.md §3.10** — self flags join the save envelope, and so does **route
  progress**: the current waypoint index and the `pingpong` direction. Active page is
  derivable from conditions, so it need not be saved. Self flags and route progress are the
  two easiest things in this document to omit and only notice much later.

---

## 6. Open questions

**All seven are answered.** Kept here with their decisions rather than deleted, since each
one names the §2–§4 text it governs.

1. ~~Structured conditions vs expression strings?~~ ✅ **Both surfaces, one representation**
   (2026-09-14). Pages keep structured entries, `if` keeps its string, and the string is
   parsed into the same structured condition — one evaluator, one predicate table, and `if`
   gets the same static validation against the manifest that pages do. The cost is a real
   parser in stage C, since `Expression` returns no tree. §2.2; solved-questions cluster 4,
   question 16.
2. ~~Mid-execution page switch?~~ ✅ **Defer to graph completion** (2026-09-14), with an
   explicit **re-validate** command a graph can hit to force page selection to run at a beat
   the author chooses. Prevents "the chest changed art halfway through its own cutscene"
   without making a long ambient graph blind to a flag it just set. §2.3; solved-questions
   cluster 7, question 23.
3. ~~Gizmo undo?~~ ✅ **The snapshot stack, for now** (2026-09-14), keeping one model of when
   a change hits disk rather than two. Accepted cost: `Ctrl+Z` does not cross between gizmo
   and ordinary scene edits. Timebox it. §4.2; solved-questions cluster 6, question 22.
4. ~~Do pages inherit?~~ — **decided 2026-09-08: no.** Pages are fully explicit; absent
   means default. The repetition goes to a "duplicate page" editor button instead. §2.
5. ~~Route `wait` units — steps or seconds?~~ ✅ **Seconds**, in both games (2026-09-14), and
   not the unit-tagged compromise: a tag would add a per-field discriminator to serve one
   game only. `wait` is a plain number of seconds and the parser branches on nothing. "Wait
   one step", if ever wanted, is its own command. solved-questions cluster 4, question 18.
6. ~~One document per event, or a map-level bundle?~~ ✅ **Per-event files, in a per-map
   folder** (2026-09-14). Each event diffs, moves and renames cleanly; the folder — not a
   bundle — is what answers "dozens of tiny files", and it is exactly what the dock globs to
   open a map's worth at once. solved-questions cluster 4, question 19.
7. ~~Can a graph change its own page?~~ ✅ **No** (2026-09-14). There is no `set_page`
   command; page selection stays driven purely by §2.3's conditions, checked rather than
   assigned. A graph that wants a different page active sets the flag or variable the target
   page's conditions test. solved-questions cluster 3, question 13.
