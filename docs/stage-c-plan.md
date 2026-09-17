# Stage C — the event system, as planned

Agreed 2026-09-14. The build plan for the event authoring and execution system, alongside
[architecture.md](architecture.md) (engine seams), [two-games.md](two-games.md) (the two-game
gap analysis) and [event-pages.md](event-pages.md) (pages, routes, editor surfaces).

[next-session.md](next-session.md) is the work queue; [solved-questions.md](solved-questions.md)
is the decision record; [open-questions.md](open-questions.md) holds what is still undecided.

---

## Context

Stage A is built, tested and green, and every numbered design question is answered. What is
missing is the thing all of it was for: **an event can be authored as a JSON document and
executed at runtime.** Nothing executes one today. `events/commands/` is an empty, untracked
directory, no class named `EventCommand` exists, and the editor dock has been calling for one
by name since it was written — it reports "schema unchecked" and carries on.

This plan builds the **runtime spine**: strike the round, then the command registry,
conditions, the page-aware document, the runner, save/restore, the scheduler and routes.
Editor surfaces (a page bar, the Routes panel, viewport gizmos) come later, against a runtime
that already works and can be driven headlessly.

Two constraints shape everything below:

1. **Savable at almost any moment**, hybrid: movement, animation and `wait` resume exactly
   where they were; dialogue and frame-scale commands re-run from the top of their command.
   A GDScript coroutine suspended inside `await` cannot be serialised — its resumption point
   lives in the engine's function stack and nothing can enumerate or rebuild it. So this is
   not a preference for a state machine, it is a **structural requirement**: the runner
   sketched in [architecture.md](architecture.md) §7.4 ("a blocking command is awaited on its
   returned key") is unsaveable as written.
2. **The round and the step pulse are struck** — not deferred, removed.

---

## Decisions taken while planning, 2026-09-14

Recorded in [solved-questions.md](solved-questions.md) as questions 39–45.

| # | Decision |
| --- | --- |
| 39 | **Save granularity is hybrid.** Movement, animation and `wait` resume mid-command; dialogue and frame-scale commands restart from the top of their command. Battle saving is refused outright, not undefined. |
| 40 | **`@` marks a resolvable term.** `@player`, `@self`, `@npc_scout` are references resolved at runtime; a bare string is a literal string, never an actor id. |
| 41 | **`face` splits into `face_direction` and `face_to`.** Directions are `n`/`s`/`e`/`w` (+ diagonals in 8-dir), `random`, and the relative turns **`turn_cw` / `turn_ccw` / `turn_180`** — named by handedness, not degrees, because a `turn_cw` is 45° in game 2 and 90° in game 1 and a number would be wrong in one of them. |
| 42 | **The round and the step pulse are struck from the design.** Speed classes and `credit` go with them, so `speed` has exactly one meaning everywhere: world units per second. |
| 43 | **`//` keys are comments** — preserved verbatim through a parse/stringify round trip, ignored semantically. |
| 44 | **Seven triggers:** `player_touch`, `event_touch`, `action`, `auto` (exclusive or parallel), `on_load`, `leave_cell`, `on_flag`. |
| 45 | **Routes are edited in a Routes panel plus a viewport gizmo** — the panel lists every `res://events/routes/*.route.json` with its user count and edits the selected one; the gizmo drags whichever route the selected `GameEvent` uses. |

**Consequence of 40:** `"actor": "npc_scout"` in the example documents is wrong and becomes
`"@npc_scout"`. All five files in [docs/events/](events/) get updated, and a bare string in an
actor-typed arg is a validator error that suggests the `@` form.

**Consequence of 42:** the page/route `speed` values of `100` / `200` in the examples are not
a second unit system, they are simply wrong numbers, and become real speeds.

### One question left open

**46. What drives a monster, now that the pulse is gone?** Deferred 2026-09-14. The docs had
monsters acting on the player's step; with the pulse struck, nothing does. This plan does not
decide it. **Routes run as background runners on delta** because that is the only clock that
exists without a pulse, and it is what makes segment 7 testable — but the clock is one call
site (`EventScheduler.tick`), so a step-driven answer can replace it later without touching
route compilation, the runner or the save format.

---

## Decisions taken while planning segment 4 in detail, 2026-09-17

Recorded in [solved-questions.md](solved-questions.md) as questions 48–52, superseding 12.
None of segment 4's code exists yet — these are additions to the shape it will take, worked
out before writing it rather than discovered midway through.

| # | Decision |
| --- | --- |
| 48 | **A debug fast-forward flag**, held on backtick (`DebugFlags.is_fast_forward()`). Every blocking `RESUME_STATE` command collapses to its end state on its first tick when held; `GridMotion` and the dialogue window read the same flag themselves since they aren't `tick()`-shaped. |
| 49 | **`call` clones its target graph and runs it as a frame on the runner's own call stack** — not a shared reference, not a second runner. `EventContext` identity (`map_id`/`event_id`, so self flags) never changes across a `call`. New command `exit_call` pops the most-nested frame early. Supersedes 12's "own context with `parent_context`." |
| 50 | **Page `conditions` accepts the same string form `if` already has**, both compiling through `EventCondition.parse_expression` to the one tree. |
| 51 | **An exclusive runner can survive a `change_map` and keep running on the destination map.** `change_map` gains a `next` port (was terminal). The exclusive runner is owned by `EventScheduler` itself once it holds the slot, not by the `GameEvent`/`Actor` that spawned it, so a map unload can't destroy it. `EventContext` splits fixed identity from a live `MapContext` reference, rebound on arrival; actor refs re-resolve fresh by role. The arriving map's own `on_load`/background start-up is never gated on the traveling runner. |
| 52 | **A background route's pause/resume point is carried on the `Actor`** (`suspended_route: Dictionary`), not the runner or the scheduler — segment 5a's restart-vs-resume rule, applied to a route's own identity hash instead of a whole document's. |

**53 is open, not answered — parked in [open-questions.md](open-questions.md).** A raw
`Expression`-evaluated condition leaf and graph node (`eval`), for logic the structured tree
can't express. Leaning toward a read-only `State` facade bound into the expression rather than
the live `GameState` autoload, and an author-supplied `watch` list for the keys the tree side
gets for free — neither is decided.

---

## Segment 0 — strike the round

**Files:** two-games.md, solved-questions.md, architecture.md, `core/mode_stack.gd`,
`core/game_profile.gd`

Not deletion — surgery, because the round is load-bearing prose in three documents and four
already-answered questions lean on it.

- **two-games.md §3.1** — the round, the input gate, speed classes and `credit` are several
  pages of live design that would become a lie. Struck with a dated note saying what replaced
  it (nothing yet — question 46) rather than silently removed, matching how this project has
  handled every other correction on record.
- **solved-questions.md** — questions **6, 7, 9 and 10** are all "what opens and closes a
  round"; **8** cut the round watchdog. They keep their numbers and their reasoning and gain a
  superseded note. The record stays true rather than tidy.
- **`core/mode_stack.gd`** — delete the `"round"` and `"pulse"` keys from `RULES`, and
  `rounds_active()` / `suppresses_pulse()`. Both are **already called by nothing**, so this is
  dead code either way. `pauses_physics()` and `keeps_map` stay; `pauses_physics()` has real
  callers in both motion controllers.
- **`core/game_profile.gd`** — delete `Capability.STEP_PULSE`. Re-run `tools/make_profiles.tscn`
  afterwards, since the two profiles are generated.
- **Rename "ambient" to "background" throughout**, in docs and in code as it is written.
  architecture.md §7.5 introduced the word and question 25 leans on it ("in-flight ambient
  runners"). It names an event graph that runs while the player still has control, and
  "background" says that without having to be learned.
- **`core/input_intent.gd`** — `lock_step` **stays**. It was the round's hook and is wired to
  nothing, but an exclusive cutscene still has to stop the player walking off. Segment 6
  becomes its first and only caller, which is simpler than what it was designed for.

**Check:** the existing four suites stay green. That is the whole test — the code being removed
has no callers, and if that is wrong the suites say so immediately.

---

## Segment 1 — `EventCommand`, the registry

**Files:** `events/event_command.gd` (`class_name EventCommand`), `docs/events/*.json`,
`tests/event_command_test.gd`

The schema as data, one dictionary entry per command, exactly as architecture.md §7.2
specifies — so the dock's validate pass, the graph editor's inspector and the runtime read one
table, and adding a command is one entry plus one executor.

- `definitions() -> Dictionary` covering flow (`wait`, `goto`, `if`, `ask`, `label`, `end`,
  `call`, `wait_for`), actor (`move_to`, `move_by`, `step`, `face_direction`, `face_to`,
  `jump`, `follow`, `set_speed`, `teleport`, `wait_settle`), dialogue (`say`, `append_say`,
  `close_window`), state (`set_flag`, `set_var`, `add_var`, `set_self_flag`), map
  (`change_map`, `fade`, `shake`, `camera_to`, `camera_follow`), presentation (`play_anim`,
  `play_sound`, `play_music`, `set_visible`), plus `start_battle` and `re_validate`
  (question 23's escape hatch).
- Arg types `cell`, `dir`, `actor`, `float`, `int`, `bool`, `string`, `seconds`, `condition`,
  `?` marking optional. Cell and direction coercion reuses the shape of `RouteBrain._dir` —
  `Vector3i`, `Vector3` or a 3-element array.
- `parse_route(data) -> {"commands": [], "problems": [], "errors": []}`. **Both result keys
  deliberately:** the dock reads `errors`/`error` and would treat a `problems`-only dictionary
  as clean. Emitting both lights the dock up without touching it.
- Terse-form expansion (question 15): `"mov n 2"` → long form at parse, through an alias table.
  The dock seeds exactly that string.
- `validate_node(node) -> Array[String]`, every message quoting the node id — the graph editor
  finds a clickable node by scanning for the first quoted id.

**Test asserts:** every definition is well formed (flows non-empty, arg types known); terse
forms expand to the same structure as their long forms; all five example documents parse with
zero problems once updated; a bad arg type, an unknown command, a bare-string actor and a
`face_direction turn_left` each produce one specific problem at the right index.

---

## Segment 2 — conditions (question 16)

**Files:** `events/event_condition.gd`, `tests/event_condition_test.gd`

One representation, two authoring surfaces.

- Tree: leaves `{flag}`, `{var, op, value}`, `{self_flag}`, `{item}`, `{party_has}`; branches
  `{all: []}`, `{any: []}`, `{not: {}}`. A page's flat `conditions` array is sugar for `all`.
- `evaluate(tree, ctx) -> bool` against `GameState`.
- `keys(tree) -> Array[StringName]` — **the subscription list**, the whole reason the page side
  is structured. `core/game_state.gd` already documents this contract.
- `parse_expression(text) -> {"tree": {}, "problems": []}` — a real tokenizer and precedence
  parser (`and`/`or`/`not`, comparisons, parentheses) with byte offsets in problems. Godot's
  `Expression` cannot serve: it executes but returns no tree, and the tree is the point.
- `validate(tree, manifest)` — an identifier absent from `GameState.manifest` is an author-time
  error rather than a silent `false` at 2am.

**Test asserts:** the evaluator's truth table over flags, variables and self flags; `keys()`
returns exactly the referenced names and nothing more; ~20 expression strings parse to the
expected tree including precedence and parenthesisation; malformed expressions report a
position; a typo'd identifier is caught against a manifest.

---

## Segment 3 — `EventDocument`, pages, and the graph node fields

**Files:** `addons/graph_editor/graph_document.gd` (extended), `events/event_document.gd`,
`tests/event_document_test.gd`

**This segment fixes a live data-loss bug.** `graph_document.stringify` emits only
`id`/`title`/`position`/`outputs`, `_read_node` reads only those four, and
`graph_editor_panel._serialize()` drops the rest too. **Opening any example event in the graph
editor and saving strips every `command`, `args`, `blocking`, `key` and `flows` in the file.**
Nothing has noticed because nothing executes these documents yet.

- Extend `graph_document` to carry those five fields under its existing repair-and-report
  philosophy: an unknown command is reported, the node becomes a no-op, the graph still opens.
- Preserve unknown keys and `//` comments verbatim through a round trip (decision 43).
- `EventDocument` owns the wrapper `{format, id, pages: []}` with per-page `conditions`,
  `settings`, `art`, `route`, `graph`; a bare top-level array is one default page
  (event-pages.md §2.1). Absent means default, never inherited (question 17).
- `active_page(ctx) -> int` — last page to first, first all-passing page wins, with the
  "page 2 has no conditions, page 1 is unreachable" warning falling straight out.
- `goto`: the flow port is the only truth; `args.target` is a warning. `trigger: "touch"` in
  the examples normalises to `player_touch`.

**Test asserts:** byte-for-byte round trip of all five example documents — the regression test
for the data-loss bug; a bare array reads as one page; page priority picks the right page for a
set of flags; the unreachable-page warning fires; `//` keys survive; a malformed page is
repaired and reported rather than rejected.

**Pending small addition (question 50), not yet built:** `EventDocument`'s page-conditions
reader should accept a bare string alongside the structured array, routed through
`EventCondition.parse_expression` — the exact grammar `if` already has, just usable at the page
level too. **Parked, not built (question 53):** a raw `Expression`-evaluated `eval` leaf/node,
for logic outside that grammar entirely — see [open-questions.md](open-questions.md).

---

## Segment 4 — the runner core, and four motion-key defects

**Files:** `events/event_runner.gd`, `events/event_command_exec.gd`, `events/key_latch.gd`,
`events/event_context.gd`, `events/commands/*.gd`, `core/event_scheduler.gd`,
`actors/motion/*.gd`, `tests/event_runner_test.gd`

**Shape.** Runners are `RefCounted`, not `Node`s, and have no `_process`. `EventScheduler` owns
the one clock and calls `runner.tick(delta)` in a fixed, total order — exclusive first, then
background in start order. That buys determinism and a test that pumps
`EventScheduler.tick(1.0/60.0)` by hand and asserts exact state with no frame sampling. The
scheduler honours `ModeStack.pauses_physics()`, the same pause rule both motion controllers
already obey, so a MENU push freezes a cutscene and the step under it together.

**The executor interface** — `start()`, `tick(delta) -> Status`, `flow_port()`, `cancel()`, and
for the resumable ones `resumable()`, `capture()`, `restore(state)`. Two rules make it work:

- **Restart is always a legal downgrade.** The base `restore()` calls `start()`, so a command
  that stops being resumable in a later version simply ignores an old save's state. Shrinking
  the resumable set can never break a save.
- **A restart command must either complete within the tick it starts, or have no committed side
  effects until it completes.** `set_flag`, `goto`, `label` finish in their starting tick, so
  they can never be captured mid-flight. `say` and `ask` span many ticks but their only effect
  before completion is on screen — and on load the window does not exist, so re-running is the
  desired behaviour, not a compromise.

**Commands never `await` either.** One `KeyLatch` per runner connects `command_finished` and
`dialogue_finished` to a single handler and keeps a small ring of recently-resolved keys, so a
key that resolves *synchronously inside* `start()` — which is what a viewless actor does, and
every headless test actor is viewless — is already latched by the first `tick`. No mirror
signal is added to `EventBus`: the project's rule is one moment, one signal, and the consumer
decides what it means. The latch is the consumer deciding.

**`EventContext` (question 49, 51) is what a runner carries instead of reaching for globals
piecemeal.** `GameState` (flags, vars) needs no threading at all — it is a global autoload,
read directly by any executor or condition. What does need to travel is everything that
isn't global:

- **Identity** — `map_id`, `event_id`, fixed at the moment a runner first acquires the
  exclusive slot (or is created for a background/ambient trigger) and never reassigned after,
  including across a `call` (49) or a `change_map` (51, segment 6). Every `self_flag` read or
  written for the life of this runner resolves against this identity, not whatever document or
  map happens to be executing at the time.
- **A live reference** — the current `MapContext`, for `@`-resolution and cell lookups. Fixed
  for an ordinary runner; rebound exactly once, on `change_map` completion, for a runner that
  survives a map change (51).
- `resolve(ref: String) -> Actor` for `@player`/`@self`/`@npc_x`, and `condition_ctx() ->
  Dictionary` producing the exact `{map:, event:, has_item:, party_has:}` shape
  `EventCondition.evaluate`/`keys` already expect — one function feeding both a page's
  `active_page()` check and a running `if`/`eval` node, so the two can never disagree about
  what "self" means.

**`call` (question 49) runs inline: one runner, a call stack, not a second runner.** On a
`call` node, the runner loads the target `EventDocument`, resolves its `active_page(ctx)`
once, and takes a **deep copy** of that page's node array as a new `{nodes, cursor}` frame
pushed onto its own stack — the original parsed document is never aliased or mutated by
execution, so two actors calling into the same shared subroutine each get a private copy.
Reaching that frame's `end` pops back to the call site's own `next` port; the new command
**`exit_call`** (no args, no flow ports) pops the most-nested frame early from anywhere inside
it, and behaves like `end` when there is no frame to pop. `EventContext` is untouched by any of
this — self flags inside a called graph always belong to whoever originally triggered the
runner. A call-depth guard is a separate, smaller counter from the `goto`/node-budget one, so a
call cycle (A calls B calls A) is reported as that, not as a generic budget overrun.

**A debug fast-forward flag (question 48), read the same way `ModeStack.pauses_physics()` is —
by the consumer, not pushed at it.** `DebugFlags.is_fast_forward()`, held on backtick,
independent of `InputManager`'s owned-input stack since it has to keep working precisely when
nothing owns input (mid-cutscene, mid-dialogue). Every blocking `RESUME_STATE` executor
(`fade`, `shake`, `camera_to`, `camera_follow`, `play_anim`, `say`/`ask`/`close_window`, `wait`)
checks it at the top of `tick()` and collapses to its own end state on that tick if held —
a `fade` snaps to `to`, a `camera_to` snaps to its target cell, `play_anim` seeks to its last
frame where the visual can seek deterministically and otherwise just stops blocking. `wait`
has no end state to preserve, so it simply finishes. `GridMotion` and the dialogue window
aren't `tick()`-shaped, so they read the flag themselves — a route under fast-forward still
commits and settles every cell (occupancy, `actor_stepped`, every moment a monster would
otherwise see), just with zero tween time per cell, and the dialogue window reveals text
instantly and auto-advances anything that isn't a real choice.

**Four defects block the runner, and are already fixed** (`actors/motion/grid_motion.gd`,
uncommitted as of 2026-09-17 — done ahead of the rest of segment 4 since nothing else in this
segment can be tested without them). The invariant they violate is the one
two-games.md §3.1 stated when it cut the watchdog: *every command that can hold the gate must
resolve its completion key on every path out, including failure and cancellation.* With no
watchdog, a swallowed key is a permanently soft-locked game that still animates.

| | Defect | Fix |
| --- | --- | --- |
| a | `GridMotion.step()` returns `bool`; its `_step_key` is **unobtainable**, so a `step` cannot be joined — and routes compile to `step` | add `step_keyed(dir) -> String` beside it, backed by a `_last_step_key` that survives the synchronous settle a viewless actor takes |
| b | `GridMotion.move_to` on an empty queue **emits before returning the key**, so `await wait_for_command(key)` hangs forever | defer the emit; no in-tree caller observes the timing today |
| c | `GridMotion.jump` always returns `""`, including the real ladder-release fall | mint and return a `_fall_key`, emitted when the fall lands |
| d | **`cancel()` resolves `_route_key` but orphans `_step_key`** — a cutscene seizing an actor mid-step leaves a key outstanding forever | resolve it alongside the others |

(d) was found while planning and is the highest-value one: it is the defect the runner *and*
any future input gate both hit.

**Test asserts:** `greet_guard.event.json` runs to completion driving a headless actor and ends
one cell east of spawn; `say` nodes advance only when the test emits `dialogue_finished` with
their key; `if`/`goto`/`label`/`call` branch correctly; a `goto` cycle trips the node budget and
the message names the node; a non-blocking command's authored key is joined by a later
`wait_for`; and one row per defect. Plus the table-driven check that **every command in the
registry resolves its key on the success, blocked and cancelled paths**, so a new command
cannot be added without one.

---

## Segment 5 — save and restore

**Files:** `events/event_runner.gd`, `core/event_scheduler.gd`, `actors/motion/grid_motion.gd`,
`actors/motion/free_motion.gd`, `actors/actor.gd`, `actors/actor_view.gd`,
`actors/views/sprite_view_2d.gd`, `actors/brain/brain.gd`, `tests/event_save_test.gd`

Split in two, restart granularity first so the harness exists before the hard part.

**5a — restart granularity.** `to_save()`/`from_save()` on the runner and scheduler, leases, and
`Brain.suspend(on)` — a lease **must** stop the actor's brain or `PlayerBrain` steers the actor
a cutscene is walking, and there is no suspend seam today. A runner records which brains it
suspended so both `stop()` and a failed restore un-suspend them.

The envelope identifies a document by a **`doc_hash` over the normalised graph — commands, args
and wiring, never `title` or `position`**, which are explicitly editor bookkeeping. Hashing file
bytes would invalidate every save in the game the first time someone drags a node two pixels. A
hash mismatch **restarts the runner from its entry** rather than dropping it: re-running a
cutscene is recoverable, skipping one can leave a flag unset and a door shut forever.

**Consequence of question 49 (`call` clones and stacks):** a runner captured mid-`call` has to
serialise its **whole frame stack** — each frame's document reference, its cloned node array,
and its cursor — not just the top one. The clone means a restore cannot just reload the
document and replay from `start`; the cloned copy *is* what was running, and a hash mismatch on
any one frame restarts only that frame from its own entry, not the whole stack.

**Consequence of question 51 (an exclusive runner can outlive a map):** the save envelope for
such a runner records its **identity** (`map_id`/`event_id`, question 49/51's fixed fields), not
the live `MapContext` it happens to be pointed at — the live reference is never saved, since it
is always re-derived by loading whichever map the identity says is current and rebinding, the
same rebind a real `change_map` does at runtime.

**5b — mid-command resume.** `to_save()`/`from_save()` on both motion controllers, on `Actor`
and on `ActorView`, plus the restore ordering.

**Mid-step saving is cheaper than it sounds, because of an invariant that already holds.**
`_commit_step` snaps the body to the destination and commits occupancy *first* — "the body
snaps. It is authoritative from here on" — and only the sprite's offset catches up afterwards.
So a grid actor is **never logically between cells**: at capture `Actor.cell()` is a real cell
and occupancy already agrees. The snapshot needs only the visual remainder, the queue, the fall
counters and which keys were outstanding. On restore, occupancy is rebuilt from actor cells via
`Occupancy.place()` — never `commit_step()`, which would re-publish an `actor_stepped` for a
step that already happened.

Derived values are **recomputed, not stored**: `_step_back` and `_rest` are pure functions of
`(ctx, from, to)` through `Terrain.surface_offset`, and storing them would store world units
that break silently if a ramp is repainted or `cell_size` retuned. Per-frame fields
(`_step_intent`, `_run_scale`, `_intent`) are dropped — they are rewritten by `Brain` every
frame, and restoring `_step_intent` takes a phantom step. Keys are **re-minted**, because a key
names an in-flight await and nothing survives a load still awaiting the old one; `from_save`
returns the fresh keys for the caller to re-latch.

`FreeMotion` is the opposite case and needs a real world position — a free actor mid-jump is
genuinely mid-flight — so `Actor` stores **both** `cell` and `world` and prefers `world` for
free motion. One accepted cost, named rather than papered over: `AreaZone` membership lands one
physics frame late on restore, exactly as it does on spawn, because a collider added this frame
has not reached the physics server.

**Test asserts:** a run captured three nodes deep resumes at `n3`, not `n1`; changing a
command's args restarts at entry, changing only a node's `position` does not; a 4-cell `move_to`
captured mid-step restores to the same remainder and **travels exactly 4 cells in total** — the
assertion that catches a step replayed or dropped; after restore the actor's occupancy footprint
is exactly one cell; `wait 1.5` captured at 0.6 elapsed finishes 0.9 later; a capture mid-fall
lands the right depth with **one** `actor_falling`, not two; an animation captured at frame 2
restores there; `to_save()` during BATTLE returns `{}` and errors; and every failure mode —
document gone, actor missing, lease collision — leaves `ModeStack` at FIELD with no lease held
and no brain left suspended.

---

## Segment 6 — `EventScheduler` policy, `GameEvent`, and the seven triggers

**Files:** `core/event_scheduler.gd`, `events/game_event.gd`, `actors/actor_view.gd` and
`actors/views/*`, `actors/brain/player_brain.gd`, `tests/event_scheduler_test.gd`

- Scheduler policy per architecture.md §7.5: one exclusive slot, any number of background
  runners, actor leases so a patrol and a cutscene cannot fight over one guard, and background
  suspension while exclusive is held with a per-runner `keeps_running` opt-out for the
  waterfall case.
- **The exclusive slot's runner is owned by `EventScheduler` itself (question 51), not by
  whichever `GameEvent`/`Actor` spawned it.** The moment a runner acquires the slot, the
  scheduler takes and holds its own reference for as long as it holds the slot — a
  `GameEvent` is a child of the map scene it's placed on, so if it (or the `Actor`) stayed the
  thing keeping the `RefCounted` runner alive, the runner would be destroyed the instant its
  map unloads, whatever its graph still had left to do. Background/ambient runners keep the
  old, map-scoped ownership; this is exclusive-only.
- **`change_map` gets a `next` port** (`"flows": ["next"]`, a small revision to segment 1's
  already-built registry — was `[]`). Its executor stays busy across the actual map load and
  resolves onto `next` once the destination is ready, same as any other multi-tick blocking
  command. On completion it rebinds `EventContext`'s live `MapContext` reference (identity —
  `map_id`/`event_id` — is untouched, per question 51) and re-resolves every `@`-reference the
  rest of the chain needs fresh, by role, against the new map — `@player` looked up again
  rather than a stale node pointer carried over, which is correct whether the player's `Actor`
  turns out to persist across a load or gets respawned fresh each time (not yet decided; no
  map loader exists yet to decide it). Nothing on the new map waits for this runner to finish:
  `on_load`, `GameEvent` registration and background/ambient start-up proceed on their own
  schedule regardless.
- `GameEvent` per event-pages.md §4.3: owns the document path, evaluates pages, applies art on
  switch, registers cells with `MapContext.add_event_at` (which already exists).
- **The seven triggers (decision 44):** `player_touch` (player moves into the event's cell, or
  onto it when the event is through-passable), `event_touch` (the event moves into the player),
  `action` (interact button, facing it or standing on a through event), `auto` (exclusive or
  parallel), `on_load`, `leave_cell`, `on_flag`. `action` reuses the
  `events_at(player.cell() + player.facing())` lookup `MapContext` already supports; the two
  touch triggers hang off `actor_stepped`, which already fires unconditionally for every grid
  actor; `on_flag` falls out of the condition subscription page selection already needs.
- **`apply_art` has to be reconciled with the `art` block, which it does not match.**
  `ActorView.apply_art` is a virtual with **no caller anywhere**; `SpriteView2D.apply_art` reads
  `"frames"` and `load()`s it as `SpriteFrames`, but the example art block says
  `"sheet": "res://…/slime.png"` — a PNG, for the `SpriteSheet` path. Worse, it **early-returns
  when `_sprite == null`**, which is exactly the sheet-driven actor, so a sheet actor gets
  nothing. `SpriteView3D.apply_art` ignores `"directions"`. The vocabulary and the two
  implementations get made one thing here.
- **Input lock:** the exclusive slot pushes `ModeStack.Mode.CUTSCENE`, and `PlayerBrain._think`
  reads `ModeStack.is_field()` into `intent.lock_step(...)`. Two lines, and it makes segment 0's
  surviving `lock_step` hook finally do something.
- Page switches defer to graph completion, with `re_validate` as the authored escape hatch
  (question 23).

**Test asserts:** each of the seven triggers fires on its moment and not on the others; two
exclusive requests — the second queues or is refused by policy; a background runner suspends
while exclusive is held and resumes after, unless it opted out; a leased actor refuses a second
runner; a page switches on a flag change but **not** mid-graph until the graph completes, and
`re_validate` forces it; the input lock engages and releases; a sheet-backed actor's art
actually changes on a page switch.

---

## Segment 7 — routes compile to commands

**Files:** `events/event_route.gd`, `actors/brain/route_brain.gd`, `tests/event_route_test.gd`

A route must not be a second execution engine (event-pages.md §3.1) — it compiles to the same
command stream the runner already executes, and runs as a background runner.

- Modes `fixed`, `waypoints` (absolute cells), `steps` (relative tokens — the reusable one),
  `toward`/`away`, `random`; `loop` none/cycle/pingpong; `on_blocked` wait/skip/reverse/repath.
- **Interruption is the same mechanism as saving.** A cutscene taking a lease on a patrolling
  guard suspends its background runner; the route's position — waypoint index plus `pingpong`
  direction — is captured by the runner's ordinary `capture()`, and resumed when the lease is
  released. There is no separate "route bookmark": interruption and saving are one path, which
  is the thing to get right, because two-games.md §3.10 names route progress as one of the two
  things easiest to lose and latest to notice.
- **The resume point is carried on `Actor`, not the runner or the scheduler (question 52).**
  `Actor.suspended_route: Dictionary` is written from `capture()` at the moment a lease seizes
  it, alongside a hash of the route's own compiled command stream (segment 5a's `doc_hash`
  idea, at route granularity) — and the background runner is discarded. On release, a matching
  hash resumes verbatim via `restore()`; a mismatch (a different route assigned, or the route
  file changed while the lease was held) restarts from the route's own beginning instead, same
  "restart is always a legal downgrade" rule as 5a. Carried on the actor because it's what
  everything else, including the save envelope, already treats as authoritative — whatever
  later drives that actor, a fresh `RouteBrain` or a reload from disk, finds its resume point
  by reading the actor rather than needing a back-channel to whatever used to own the route.
- Shared routes at `res://events/routes/<name>.route.json`, referenced `{"use": "patrol_ns"}`,
  **resolved at parse** so the in-memory page never holds a `use` string. A missing target is a
  validator error — otherwise it reads in-game as a monster that simply stands still, the
  hardest class of bug to attribute because nothing failed.
- `RouteBrain` today understands four commands and polls `is_moving()` instead of joining keys.
  It gets rewired onto the compiled stream rather than kept as a parallel engine.

**Test asserts:** each mode compiles to the expected command sequence; `pingpong` reverses at
both ends; `on_blocked` policies behave against a wall; a `steps` route produces the same shape
from two different spawn cells; a shared route resolves and a missing one errors; **a patrol
interrupted at waypoint 3 heading backwards resumes at waypoint 3 heading backwards**, both
across a lease and across a save.

---

## File layout

```
res://events/
  event_command.gd  event_condition.gd  event_document.gd
  event_runner.gd   event_command_exec.gd  key_latch.gd  event_context.gd
  game_event.gd     event_route.gd
  commands/                         per-command executors
  routes/<name>.route.json          shared route templates
  <map_id>/<event_id>.event.json    real events, per-map folder (question 19)
core/event_scheduler.gd             autoload #5
docs/events/*.json                  documentation examples only
```

`EventScheduler` becomes the fifth autoload beside `InputManager`, `EventBus`, `GameState` and
`ModeStack`.

---

## Out of scope, deliberately

- **Editor surfaces** — the page bar, per-node command/args fields, the Routes panel and the
  viewport gizmos. Decided (45) but built later, against a working runtime.
- **A save file.** Hooks and a test harness only: the suite saves to a Dictionary, tears the
  world down and rebuilds. No `SaveGame` autoload, no `user://` file, no slots — that is stage
  E, and these hooks are what it will need.
- **Battle saving**, refused explicitly rather than left undefined.
- **What drives a monster** (question 46), deferred.

---

## Working order

One segment at a time: build, get its suite green, re-run every existing suite, commit, and
report. Eight commits, not one. Segments 1–3 are independent and could be reordered; 4 needs
1–3, 5 needs 4, 6 needs 5, 7 needs 6.

**Two questions expected mid-build:** whether `ask` and `choice` are one command or two
(architecture.md §7.3 says `choice`, the example says `ask`), and whether `follow` is a command
or a route mode, since it appears in both lists.

## Verification

```bash
GODOT="/c/Users/kyle/Desktop/Godot_v4.7-stable_win64_console.exe"
for t in stage_a areas demo_scenes height \
         event_command event_condition event_document \
         event_runner event_save event_scheduler event_route; do
  timeout 300 "$GODOT" --headless --path . res://tests/${t}_test.tscn
done
```

Godot is not on PATH; use the `_console` build or a headless run prints nothing. A script that
fails to parse **hangs** rather than erroring, so wrap runs in `timeout` and grep the log head
for `SCRIPT ERROR` before assuming the binary is slow.

The end-to-end check that says stage C works: a headless scene loads `slime_a.event.json`, page
conditions pick page 1, the route walks the slime, the player touches it, the graph runs, a flag
the graph sets switches the active page, **and a snapshot taken mid-route restores into a
running world that carries on from the same waypoint in the same direction.**
