# Next session — where to pick up

Rewritten 2026-09-14 at the end of the stage C planning-and-build session. This is the
work queue; [open-questions.md](open-questions.md) is what is still undecided,
[solved-questions.md](solved-questions.md) is the decision record, and
[stage-c-plan.md](stage-c-plan.md) is the agreed plan this session is executing.

---

## Start here tomorrow

**Segment 4 of [stage-c-plan.md](stage-c-plan.md): the runner core.** Segments 0–3 are built,
tested and committed. Between segment 3 and segment 4, this session also did the editor/schema
work below (question 47), and a later session (2026-09-17) planned segment 4's shape in real
detail before writing it — questions 48–52 in `solved-questions.md`, superseding 12, plus 53
parked open. None of that later session's design changed any already-committed file except
`actors/motion/grid_motion.gd`; see below.

**The four motion-key defects are already fixed, uncommitted**
(`actors/motion/grid_motion.gd`, 2026-09-17) — done first since nothing else in segment 4 can
be tested without them: `step_keyed(dir) -> String` beside `step()`, backed by `_last_step_key`;
`move_to`'s empty-queue emit deferred past the point it returns its key; `jump` mints and
returns a `_fall_key`, resolved when the fall lands; `cancel()` now resolves `_step_key` and
`_fall_key` alongside `_route_key`. All eight existing suites still pass green with these in.
**Run them again before building on top, and commit them first** — they're a clean, isolated
diff and shouldn't get tangled into the runner's own commit.

### Editor and schema work — the `start` node (question 47, `docs/solved-questions.md`)

A graph's entry point used to be an unstated convention (whichever node came first in the
array). It is now an explicit per-page `start` command, one flow port, validated by
`EventCommand.validate_reachability(nodes)` — exactly one `start` expected, and every node
`start` cannot reach reported as an **orphaned chain** (a connected component of the unreached
set, not a flat count: a two-node dangling sequence is one chain).

- All five `docs/events/*.json` examples now open with a `start` node.
- `graph_editor_panel.gd`: an **Add Start** button, a **minimal page selector** (dropdown,
  condition summary, no reorder/add/duplicate/delete) so a page-wrapped document can be opened
  and switched between pages at all — before this the panel could only open a bare array and
  had no idea `EventDocument`/pages existed. Save writes back through `EventDocument` for a
  wrapped file, or bare `graph_document.stringify()` for one of the four plain-array examples —
  deliberately not unified, so opening and saving one of those four does not silently upgrade
  it to the wrapper shape.
- `event_editor_dock.gd` (the JSON text editor): **two toolbar rows** now (file ops, then
  buffer edits); **Validate** now handles a page-wrapped top-level object as well as a bare
  array, and both shapes get the dangling-target check (`graph_document.validate()`, which
  existed but was never actually called from this dock) and the new reachability check: two
  gaps closed at once. **Add** seeds a full node (id, title, one wired output) instead of a
  bare `{"command": "mov n 2"}` with neither. **Strip Unknown** was a real bug, not a request —
  it round-tripped the buffer through `parse()`/`stringify()`, which repairs as it goes (a
  missing id generated, a missing title defaulted), so "strip this comment" was quietly handing
  every plain command four fields it never had; `strip_unknown_raw()` on both
  `graph_document`/`EventDocument` now only removes keys, adding nothing.

Every message a reachability check produces quotes each node id individually (`"n2", "n3"`,
not a bare comma list) so `graph_editor_panel`'s click-to-jump still works on it — and the
`start` command's own name is deliberately left unquoted in the "N unreachable" message, or a
message beginning `unreachable from "start"` would always jump to the start node instead of
one of the actually-orphaned ones.

**Same-day follow-up:** an output's `type` (`"flow"`/`"bool"`/`"int"`/`"float"`/`"string"`)
merged into a `flow` name, replacing the separate per-node `flows` array entirely —
`{"flow": "next", "target": "n2"}` instead of a `flows` list plus `{"type": "flow", ...}`.
`graph_editor_panel.gd` now builds a node's ports from `EventCommand.flows_of(node)` rather
than from the file's own `outputs`, so the type dropdown and the `+ Output`/`-` buttons are
gone — a port is no longer something an author adds or removes, it follows from the command,
same as its arguments do (there is still no UI to choose a command at all). A `GraphNode`
also tints red (`self_modulate`) when `EventCommand.is_blocking(node)` is true. All five
example docs migrated; see question 47's follow-up note in `solved-questions.md`.

**Second same-day follow-up:** the Add Start button is gone. `graph_editor_panel._ensure_start_node()`
maintains "every graph with anything in it has exactly one start node" as an invariant instead
of a button — called after loading a page and after that page gains its first node, adding one
only when there is a real graph to belong to (an intentionally empty, route-only page stays
empty). The start node cannot be deleted or duplicated (`_on_delete_nodes_request`/
`_on_duplicate_nodes_request` both skip it), has no input slot (nothing may flow into where
execution begins), and is always green rather than blocking-red.

**What's left to build in segment 4**, now that the motion-key defects are done — see the
plan's Segment 4 section for the full detail on each:

- `events/event_context.gd` — identity (`map_id`/`event_id`, fixed for the runner's life,
  never reassigned by a `call` or a `change_map`) split from a live `MapContext` reference
  (rebound only on `change_map` completion, question 51); `resolve()` for `@`-refs;
  `condition_ctx()` feeding both `EventDocument.active_page()` and a running `if`/`eval` node
  from one function.
- `core/debug_flags.gd` (question 48) — `DebugFlags.is_fast_forward()`, held on backtick,
  read directly off `Input` rather than through `InputManager`'s owned-input stack, plus a
  `force_fast_forward` override for the test suite.
- `events/key_latch.gd` — one per runner, catches a key resolved synchronously inside
  `start()` (every headless test actor is viewless) without a mirror `EventBus` signal.
- `events/event_command_exec.gd` and `events/commands/*.gd` — the executor interface
  (`start()`, `tick(delta) -> Status`, `flow_port()`, `cancel()`, `resumable()`/`capture()`/
  `restore()`), with every blocking `RESUME_STATE` executor checking `DebugFlags` at the top
  of its own `tick()` per question 48.
- `events/event_runner.gd` — walks a page's graph node by node, owns a `KeyLatch`, and now
  also owns a **call stack** (question 49): `call` clones its target graph and pushes a
  `{nodes, cursor}` frame rather than spawning a second runner; `exit_call` (new registry
  entry, no args, no flow ports) pops the most-nested frame early.
- `core/event_scheduler.gd` — the fifth autoload; also, per question 51, the **owner of the
  exclusive runner's reference** once it acquires the slot, so a `GameEvent`'s map unloading
  can't destroy a runner still mid-chain across a `change_map`.
- A small registry revision to already-built `events/event_command.gd`: `change_map`'s
  `"flows"` becomes `["next"]` (was `[]`), and a new `exit_call` entry.

See the plan for the resumability rules — restart is always a legal downgrade, and a restart
command must finish inside the tick it starts or have no committed side effects before then.

**Run the full suite before starting**, including `event_document`, to confirm nothing
upstream drifted:

```bash
GODOT="/c/Users/kyle/Desktop/Godot_v4.7-stable_win64_console.exe"
for t in stage_a areas demo_scenes height event_command actor_naming event_condition event_document; do
  timeout 110 "$GODOT" --headless --path . res://tests/${t}_test.tscn
done
```

### Stage C segment 3 — `EventDocument`, pages, and the graph node fields (`c972090`)

Fixed the live data-loss bug: `graph_document.stringify`/`_read_node` used to carry only
`id`/`title`/`position`/`outputs`, and `graph_editor_panel._serialize()` dropped the rest
too, so opening any of the five `docs/events/` documents in the graph editor and saving
silently stripped every `command`, `args`, `blocking`, `key` and `flows` in the file.

- `graph_document.gd` now reads and writes all five node fields.
  `blocking`/`key`/`flows` are written **only when the node authored one** — a round trip
  never invents a `"blocking": false` nobody wrote — while `command`/`args` are always
  present, defaulting to `""`/`{}`. `parse()` is split so `parse_nodes(data: Array)` takes
  already-decoded JSON, which is what `event_document.gd` needs for a page's `graph`.
  `stringify()` is likewise split behind `to_data(nodes) -> Array`, so a page's graph
  embeds as data in the larger document instead of being stringified twice.
- **Unknown keys survive at every level, unconditionally** — not just `"//"`, any key
  none of these readers recognise, per decision 43 and this session's follow-up: they are
  kept rather than reported as problems, under a per-node/page/document `_unknown` map,
  and written back verbatim at the end of the entry. `graph_document.unknown_report()` /
  `strip_unknown()` and `EventDocument`'s equivalents back two new buttons on
  `event_editor_dock.gd` — **Unknown** lists what is riding along, **Strip Unknown**
  removes it — since nothing else in the editor surfaces this yet.
- `graph_editor_panel.gd` stashes everything it has no field for as `graph_extra` node
  meta at load, and `_serialize()` starts from that meta before overwriting the four
  fields the UI actually owns (id/title/position/outputs). Fixes the panel's half of the
  bug with no new UI — a node's command/args/etc. now survive a visual edit even though
  there is nothing to edit them with yet (that is event-pages.md §4.1, later).
- `events/event_document.gd` — the `{format, id, pages: []}` wrapper. A bare top-level
  array still reads as one default page (event-pages.md §2.1, backwards compatible).
  `active_page(pages, ctx)` picks last-to-first, first all-passing page wins (§2.3);
  `validate_pages()` is the "a later page has no conditions, so every page before it is
  dead code" check that falls out of the same rule.
- **The five `docs/events/*.json` examples are rewritten to the canonical output of
  `stringify()`** — tabs, a fixed key order, unknown keys (comments included) trailing —
  rather than their original hand layout. Byte-for-byte round trip means byte-for-byte
  against that canonical form now, which is the regression test for the bug above.
  **Side effect worth knowing**: Godot's `JSON` class has no integer type, so every
  number inside a raw passthrough dictionary (an `args`, `conditions`, `settings`, `art`
  or `route` value) now round-trips as a float — `"location": 2` became `"location": 2.0`.
  Cosmetic only (`EventCommand._coerce` accepts either), not attempted to fix: doing so
  generically would have erased the deliberate int/float distinction the docs already
  draw (`"location": 2` vs `"speed": 2.0`), which needs `EventCommand`'s per-argument
  types to fix properly rather than a blind "collapse whole floats" pass.
- 56 new assertions in `tests/event_document_test.gd`, all five suites before it still
  green.

---

## Run everything

```bash
GODOT="/c/Users/kyle/Desktop/Godot_v4.7-stable_win64_console.exe"
for t in stage_a areas demo_scenes height event_command actor_naming event_condition event_document; do
  timeout 110 "$GODOT" --headless --path . res://tests/${t}_test.tscn
done
```

**753 assertions, all green** as of the last commit (231+31+147+105+71+107+61, plus
demo_scenes' unnumbered checks). Godot is not on PATH; use the
`_console` build or a headless run prints nothing.

Three hazards worth re-reading before a long debugging session, all of which cost time
today:

- **A script that fails to parse hangs the run** rather than erroring — the scene loads
  with no script and nothing calls `quit()`. Wrap runs in `timeout` and grep the log head
  for `SCRIPT ERROR` before assuming the binary is slow.
- **A script error inside a test aborts that section silently.** The run still exits 0
  with assertions quietly missing. Watch the *count*, not just the exit code: striking the
  round dropped `stage_a` from 232 to 224 and nothing failed.
- **A new `class_name` is invisible until Godot re-imports.** A test referencing one that
  is not yet in the class cache hangs. Run `--headless --path . --import` after adding a
  global class.

---

## What was built today

### Stage C segment 0 — the round and the step pulse are struck (`60f040d`)

Removed from the design, not deferred (question 42). Speed classes and `credit` went with
them, so **`speed` now has exactly one meaning everywhere**: world units per second.

It cost nothing in code, which was the argument for doing it: `RULES["pulse"]`,
`RULES["round"]`, `suppresses_pulse()`, `rounds_active()` and
`GameProfile.Capability.STEP_PULSE` were all uncalled outside a test. `EventBus.actor_stepped`
and its three siblings survive unchanged — a step is still a published moment, it is just
no longer a clock. `InputIntent.lock_step` survives too, and stage C's exclusive slot will
be its only caller.

**The enum values are positional and a `.tres` stores raw ints**, so deleting `STEP_PULSE`
from the middle renumbered everything after it. Both profiles were regenerated through
`tools/make_profiles.tscn`; `core/game_profile.gd` now says so where the next person will
read it. **Re-run that tool after any change to the `Capability` enum.**

### Stage C segment 1 — `EventCommand` (`848cfe3`)

`events/event_command.gd`: 33 commands as one data table — argument names and types, flow
ports, blocking default, space, and which half of question 39's hybrid save each is in.
88 assertions.

`parse_route` returns `commands`, `problems` **and** `errors`. The third key is deliberate
duplication: `event_editor_dock.gd:557` reads `errors`/`error` and treats a
`problems`-only dictionary as a *clean* route, so emitting both lights the dock up
per-line without the dock being touched.

The five worked examples in `docs/events/` were updated for questions 40–42 and now parse
clean as part of the suite.

### Stage C segment 2 — `EventCondition` (`c4f7f79`)

`events/event_condition.gd`: the tree, the evaluator, the key extractor, a hand-written
tokeniser and recursive-descent parser, and the manifest check. 107 assertions.

The test that carries the decision is the **equivalence** one: a page's structured list
and a typed expression produce the same tree, evaluate the same, and subscribe to the
same keys. Two grammar rules to remember — **a bare name is a flag, a compared name is a
variable**, and `self.talked == false` is the negated leaf rather than a comparison.

`keys()` expands a self flag to the composite `map:event:flag` that
`GameState.set_self_flag` actually emits; `item` and `party_has` contribute no key,
because neither system emits a change signal and a subscription naming one would look like
it was working while never firing.

### Actor auto-naming (`722b4b3`, `00cf513`, `ff7a0f6`, `8419e6a`, and the stem default)

Not part of the plan — asked for during the session. `actors/actor_naming.gd`, 71
assertions.

- `assign()` / `assign_all()` give an actor an id and rename its placement node to match.
- Generated ids are **plain numbers** counting from 1, filling gaps.
- A first generated id renames the node to **`event__3`**; once an actor has an id, later
  renames keep whatever stem the node has, so a deliberate `Guard` stays `Guard__4`.
- An id of `player` (matched case-insensitively) names the node just `Player`.
- `Actor.actor_id` has a setter that renames the placement node **in the editor only** —
  `Actor` is now `@tool`, with `_ready` and `_exit_tree` returning early under
  `Engine.is_editor_hint()`.

**The editor-only guard is load-bearing.** All three demo scripts reach actors by node
path, so a rename at run time would break every `@onready` that names one. There is a test
asserting the hook does *not* fire at run time.

---

## Decisions taken today

Questions **39–45** are in [solved-questions.md](solved-questions.md) as cluster 10:
hybrid save granularity, `@` marking a resolvable term, the `face` split with
`turn_cw`/`turn_ccw`/`turn_180`, striking the round, `//` as comments, the seven triggers,
and routes being edited in a Routes panel plus a viewport gizmo.

**Question 46 is open and deferred:** what drives a monster now that the pulse is gone.
Stage C assumes routes tick on delta as background runners, because that is the only clock
left. That assumption is **one call site** — `EventScheduler.tick` — and
[open-questions.md](open-questions.md) says to check it is still one call site before
answering 46.

---

## Small things left open

- **The node stem for a hand-named node.** A first generated id discards whatever the node
  was called: a node deliberately named `Guard` with no id becomes `event__2`, not
  `Guard__2`. Nothing can tell a deliberate name from a prefab's default name, so this
  follows the literal rule. Give such an actor a word id if the name should survive.
- **Nothing calls `assign_all` yet.** The editor button is unbuilt — it belongs with the
  snap-to-cell shortcut on the wishlist in [open-questions.md](open-questions.md).
- **Two questions expected mid-build**, flagged in the plan: whether `ask` and `choice`
  are one command or two (architecture.md §7.3 says `choice`, the example says `ask`), and
  whether `follow` is a command or a route mode, since it appears in both lists.
- **`apply_art` does not match the `art` block** and will have to be reconciled in segment
  6 — `SpriteView2D.apply_art` reads `"frames"` and loads a `SpriteFrames`, but the example
  art block says `"sheet": "…png"`, and it early-returns for exactly the sheet-driven
  actor that block describes.

---

# The stage A and B notes below are kept as reference

Written 2026-09-08 and extended since. Still accurate about what stage A built and what
stage B owes; read the sections above first for where things actually stand.

## 1. The four questions — answered 2026-09-14

All four are decided and in [solved-questions.md](solved-questions.md). **Stage B is
unblocked.**

| # | Question | Answer |
| --- | --- | --- |
| 6 | Does turning in place open a round? | **No** — but it emits `EventBus.actor_turned` |
| 7 | Does bumping a wall open a round? | **No** — but it emits `EventBus.actor_blocked`, plus a "wait one step" input |
| 9 | Does scripted player movement pulse? | **No** — opt-in `pulse: true` per move command |
| 11 | Is monster AI authored as event graphs? | **Yes**, plus reusable named routes |

**The common thread in 6 and 7 is worth carrying into stage B:** *opening no round is not the
same as being silent.* `actor_turned` and `actor_blocked` are triggers — published always, so
they can be observed but nothing depends on them to drive anything.

**Revised the same day, and worth reading before touching any of this: the whole actor-event
set was redesigned around one rule.** *Every* actor event is now a trigger, not just 6 and
7's two. `actor_stepped` was gated by a per-actor `publishes_pulse` export and by
`ModeStack.suppresses_pulse()`; there was also a separate always-on `cell_entered` for
listeners that needed every actor's step regardless. Both are deleted. `EventBus` now
publishes **four** unconditional actor moments and their `player_*` shorthands:

| Signal | Fires when |
| --- | --- |
| `actor_stepped` / `player_stepped` | A step commits — body on the new cell, sprite not yet |
| `actor_settled` / `player_settled` | The sprite has caught up — the land-on-it moment |
| `actor_blocked` / `player_blocked` | A step was refused (7) |
| `actor_turned` / `player_turned` | Facing changed, with or without a step (6) |

**Built with the answers, and green** — 232 stage A assertions, up from 205
(`core/event_bus.gd`, `actors/actor.gd`, `actors/motion/grid_motion.gd`):

- `Actor.set_facing` publishes `actor_turned` for every facing change — a listener meaning
  "turned in place" checks the actor is not moving — and re-facing the way it already faces
  publishes nothing, or the signal would fire every frame a brain re-asserts its direction.
- The two `blocked.emit` sites in `GridMotion` now go through **`Actor.report_blocked`**, and
  `_settle()` now goes through the new **`Actor.report_settled`**, so terrain refusals,
  occupancy refusals and the settle moment each have one announcement point instead of one
  per call site that can drift.
- `actor_stepped` is unconditional: `publishes_pulse` and the `suppresses_pulse()` check
  inside `_commit_step` are both deleted, and so is `cell_entered` — `actor_stepped` now does
  its job. **What this means for question 9** (does scripted movement pulse — still no by
  default): the answer is unchanged, but the enforcement is no longer built. It moves to
  whatever consumes `actor_stepped` for AI purposes — `StepResponder`, below, must ask
  `ModeStack.suppresses_pulse()` itself before reacting, and a `pulse: true` command needs a
  way to tell it "react anyway" for that one step.
- **`EventBus` carries four `player_*` shorthands** — one the `actor_*` signal without the id,
  because most listeners only ever care about the player. Who the player is, is
  **`Actor.is_player()`**, one definition; `AreaComponent`'s PLAYER filter had a second copy
  of that test and now calls it. None of the four diverges from its `actor_*` counterpart any
  more — there is no gating left at this layer for `player_stepped` to disagree with.
- **One moment, one signal.** A `player_entered_cell` was written and deleted the same day: it
  fired with `player_stepped`, always, and differed only in dropping `from`. Want just the
  cell, take `(_from, to)` — Godot 4 will not connect a shorter callable, so the underscore is
  required, and it is still cheaper than a second name for one event. This is the rule the
  whole redesign applies at scale: a signal earns its place by covering a different *moment*,
  never a different payload subset or listener subset of an existing one.

**Still to build from these answers**, none of it stage A:

- The **"wait one step" input** that 7 promises — an `InputIntent` field and an action, on the
  stage B list below, not a stage C command.
- `StepResponder` must gate itself against `ModeStack` — see above. This did not exist as a
  requirement until the pulse gate moved out of `GridMotion`; it belongs to the
  `StepResponder` bullet below rather than being treated as already covered.
- `pulse: true` on move commands, and the responder-side hook it needs to reach — stage C,
  when `EventCommand` exists.
- **Shared routes** — stage C. `res://events/routes/<name>.route.json`, referenced as
  `{"use": "patrol_ns"}`. **Two route modes now, not one**: `steps` is a list of relative
  moves (`step_n`/`step_s`/`step_e`/`step_w`, plus `wait`/`face`) and is expected to be the
  common case, since a patrol is naturally authored that way and a `steps` route needs no
  anchor to be shared — reuse is free once the mode is relative. `waypoints` stays absolute
  cells for the gizmo-dragged case and is the one that needs the anchor trick: a shared
  `waypoints` template stores cells **relative to a spawn anchor**, not absolutely, or six
  guards using one template all patrol the same strip. event-pages.md §3 and §3.2 have the
  whole shape, including the three things the gizmo owes a shared `waypoints` route.

**Question 8 — the round watchdog — was cut on 2026-09-13.** Nothing force-closes a round;
the gate closes on its completion keys alone. Do not build one back in.

---

## 2. Stage B — game 1 vertical slice

In order, because each puts the one before it under load:

- [ ] **`StepResponder`** — per-actor `speed`/`credit`, driven by `EventBus.actor_stepped`.
      Resolution is **actor-at-a-time**: each responder drains its credit fully before the
      next acts, iterating `MapContext.actors()` for the stable order. **Must check
      `ModeStack.suppresses_pulse()` itself before reacting** — `actor_stepped` no longer
      gates that at the emitter (§1 above), so a responder that skips this check reacts to
      the player's cutscene steps exactly the bug question 9 was answered to prevent.
- [ ] **`RoundGate`** — opens on a committed step, joins over completion keys, closes when
      all resolve, holds `InputIntent.step` only, and runs only where
      `ModeStack.rounds_active()`. With question 8 cut there is no timeout underneath it, so
      **the join is the only thing that closes a round**: every command that can take the
      gate must resolve its key on every path out, including the ones that fail or get
      cancelled. That is the invariant to test hardest.
- [ ] **`push`** — the test case for transactional occupancy. Block chains, a block shoved
      into a monster, and a block pushed over a hole. `Occupancy.commit` already takes the
      multi-cell set; this is the caller it was built for.
- [ ] **Wire the "wait one step" input** — what question 7 promised in exchange for a wall
      bump not passing time. `InputIntent.wait` already exists and nothing produces it: it
      needs an action in `InputProfile` and a `GridMotion` path that opens a round and
      resolves its key without moving. Cheap, and it belongs **before** `RoundGate` is called
      done, because a round opened by a command that commits no step is the degenerate case
      the join has to survive.
- [ ] **Paint the JRPG map** — the `Pathing` layer exists, is wired to
      `MapContext.collision_node` and is empty, so that map is open ground and its walls are
      currently scenery. Painting it is a job for the tile editor; `1` in the demo shows the
      overlay. Until then `Passability` step 1 is exercised only by the headless tests.
- [ ] **Extend the headless harness** — drive "step north, step north, step east" through the
      round gate and assert exact final cells. A round is a discrete awaitable unit, which is
      what makes this cheap; `tests/stage_a_test.gd` has the `_step` / `_settled` helpers
      already.

---

## 3. Known gaps in what was built

Honest list of what stage A stubs or simplifies, so none of it is discovered instead of
decided:

- ~~**`Passability._terrain_allows` treats any occupied `GridMap` cell as impassable.**~~
  **Retired 2026-09-14** by separating the two questions rather than teaching one node to
  answer both. `collision_node` is the *wall* layer and occupied still means impassable
  there, which is correct; ground is `floor_node`, read by `Terrain`, where occupied means
  walkable. Neither has to guess which kind of layer it is looking at.
- **Physics is not consulted on a map with a `floor_node`.** `Passability` skips step 3
  there, because the floor slabs and the ramp and stair meshes are themselves colliders and
  a legitimate climb onto a ramp otherwise reads as walking into it. The cost is real: a
  pushable crate or a swinging door on a height map has to be an actor in `Occupancy`
  rather than a bare body.
- **A fall onto an occupied cell stops in the air above it.** The landing is refused by
  occupancy like any other step, the remaining depth is cleared, and the actor is left
  standing on nothing. Deliberate — the alternative is a pending fall nothing will ever pay
  out, which counts as busy and would hang a round forever. Visible and recoverable beats
  unclosable, but nothing re-triggers the fall when the blocker moves away.
- **Nothing falls except by stepping.** An actor spawned or teleported into mid-air stays
  there; gravity is a consequence of a step, not a background force. Fine today, worth
  knowing before an event drops someone down a shaft.
- **`ActorFactory` is written but never exercised.** Nothing constructs actors from a profile
  yet; the test builds them by hand. First real map will be its first caller.
- **`CameraRig.focus_of` is what a rig must follow, not `Actor.world_position`.** The body is
  authoritative and teleports a whole cell at grid commit, so a rig reading the body lurches
  once per step; `focus_of` adds the view's step offset so the camera tracks the sprite, which
  is what the eye tracks. Free motion leaves that offset at zero, so it is one expression for
  both. Both rigs use it. Anything that adds a third rig has to remember to.
- **`RoomCamera2D`'s deadzone was hiding that bug.** A 32×24 px deadzone against a 16 px cell
  absorbs a one-cell jump, so game 1 never showed it and the iso demo showed it immediately.
  Worth remembering when a demo "looks fine" — it may only mean the tolerance is wider than
  the defect.
- **Pixel alignment is a whole-system property, not a per-node one.** The camera, and every
  `SpriteView3D`, must round the same quantity through `Space.snap_to_basis` on the same
  basis-aligned grid, and only the rig may write a followed sprite's transform (see
  `SpriteView3D._set_offset`) so the sprite is never a tween step ahead of the camera. Four
  separate defects here each produced "the camera is jittery" and each needed a different
  fix; if a new view or rig appears, this is the invariant to hold. two-games.md §3.6 has
  the measurements.
- **`is_busy` and `is_travelling` are different questions.** `is_busy` means "still working
  through a command" — what a round joins on, and what stops a second step mid-step.
  `is_travelling` means "physically moving", which is what presentation wants. They only
  diverge for free motion, where steering with the stick moves the actor with no command in
  flight: `FreeMotion.is_busy()` is false the entire time it walks, so anything gated on it
  (a walk cycle, a footstep sound, a dust puff) silently never fires.
- **Demo spawns need clearance in every direction.** The JRPG player used to spawn one tile
  above the bottom wall, so pressing down did nothing and the demo read as broken rather than
  blocked; one of its NPCs was also spawned inside a wall tile, reserving a cell nothing could
  reach. Both fixed, and both are the kind of thing only walking the demo finds.
- **`ActorView` binds once.** `_ready` no longer re-runs `_after_bind` when the visual was
  already bound in code, because a subclass caches the visual's resting position there and a
  second capture folds in whatever correction had since been written — a drift that grows
  every frame once anything writes the transform per frame.
- **`InputManager`'s target stack is untested**, and nothing produces an `InputIntent` yet —
  there is no per-frame producer wiring `InputProfile` to a controller. Stage B needs one.
  `InputIntent.wait` is the field most obviously waiting on it: it is declared, documented,
  and set by nothing.
- **`SpriteView2D` has a loose fallback** hunting for an `AnimatedSprite2D` child; it should
  take the visual explicitly once a real actor scene exists.
- **`move_to` is straight-line-then-stop**, and stops rather than repathing when blocked.
  `path: "astar"` is accepted in the schema and not implemented (architecture.md §12.5).

---

## 4. Loose ends outside the stages

- [ ] **`run/main_scene` points at `res://demos/demo_launcher.tscn`** — the development
      launcher. Should become game 1's main scene when one exists.
- [ ] **Vertical-face art at 14 texels per world unit**, not 16 — needed before wall art, not
      after (two-games.md §3.6).
- [ ] **Editor tooling wishlist** (open-questions.md Cluster 6, added 2026-09-14) — scaling
      area gizmos, a snap-to-cell shortcut on the root actor/event node, a static (non-
      animated) route preview that flags wall hits, and mid-step/mid-command save resume.
      None block a stage; noted so they aren't lost before the gizmo work starts.

---

## 5. After B

- **C** — `EventCommand` registry with capability tags, `EventRunner`, `EventScheduler`,
  `EventDocument`/`GameEvent`. Wants Cluster 4 (15, 16, 18, 19) settled first.
- **D** — game 2, in two passes (two-games.md §4.3). First `FreeMotion`, jumping and height
  against untextured boxes and a plain ortho camera, so a spine bug is diagnosable on its
  own; then the pixel rig, yaw stops and sprites, which is art pipeline rather than
  architecture.
- **E** — saves and the battle scene. The save envelope must carry self flags, monster
  `credit` and **route progress** (waypoint index plus pingpong direction).
