# Next session — where to pick up

Rewritten 2026-09-14 at the end of the stage C planning-and-build session. This is the
work queue; [open-questions.md](open-questions.md) is what is still undecided,
[solved-questions.md](solved-questions.md) is the decision record, and
[stage-c-plan.md](stage-c-plan.md) is the agreed plan this session is executing.

---

## Start here tomorrow

**Update 2026-09-20 — segment 5a (restart granularity) is built, tested and green.**
`EventCommand.doc_hash`, `EventRunner.to_save`/`to_save`-companion `restore`/`from_save`,
`EventScheduler.to_save`/`from_save`, and brain-suspend/motion-cancel ownership moved from
`GameEvent` into `EventRunner` itself (fixing the real gap the plan called out: a lease never
stopped whoever already had the actor, and only `GameEvent`'s own polling ever gave it back
before - `EventScheduler.reset_for_test()`/a restore now do too). `tests/event_save_test.gd`,
26 assertions, all eleven suites green (868 total).

**Not built: 5b (mid-command resume).** A `wait` captured 6 seconds into a 10-second count
restarts the full 10 on restore, not the remaining 4 - nothing calls a resumable executor's own
`capture()`/`restore()` yet (the interface exists, unused), and `GridMotion`/`FreeMotion`/`Actor`/
`ActorView` have no `to_save()`/`from_save()` at all. "Restart is always a legal downgrade"
(question 39) is exactly why 5a alone is still correct, just coarser than 5b will make it - start
here for that.

**Also not built: a call-frame stack captured mid-`call`.** `EventRunner.restore()` handles it
structurally (each frame carries its own `doc_path`/`page_index`, per the plan), but nothing
tests a runner captured while inside a nested `call` - worth a case before trusting it.

Segment 7 (routes) is still not started, and the previous note about it (below, 2026-09-19) is
now current: segment 5 no longer blocks it, but nothing has touched `events/event_route.gd`
either.

**Superseded 2026-09-19 note, kept for the record:** segment 7 has *not* been started. This section said so back on
2026-09-14, right after segment 6 landed, and nothing since has touched `events/event_route.gd`
(does not exist), `tests/event_route_test.gd` (does not exist), or rewired `RouteBrain` off its
own polled-command loop onto the runner. What *did* land in between (below) is GameEvent/editor
polish plus an out-of-band ramps/stairs/camera session — real work, just not segment 7, and not
previously written down here. Do not mistake the `route`/`routes/*.route.json` plumbing already
sitting in `EventDocument` (parsing and round-tripping a page's `route` field, segment 3's job)
for segment 7 itself — nothing compiles that data into a command stream or executes it yet.

~~**Segment 7 cannot start as planned yet, either.**~~ **No longer true as of 2026-09-20** -
segment 5a landed (above), so `EventRunner` does have `capture`/`restore`-shaped machinery
now (`to_save`/`restore`, not literally `capture`/`resumable` at the runner level - those stay
per-executor, 5b's job). Segment 7's own "interruption is the same mechanism as saving" can lean
on 5a's frame/cursor capture today; it just cannot lean on 5b's mid-command resume until that
exists too. The original point stands as a lesson, not a live blocker: this was worth deciding
explicitly before writing route code, and it was.

Segments 0–6 are built, tested and committed — segment 6 (`273066e`) added
`tests/event_scheduler_test.gd` (33 assertions at the time, 47 now — see below), on top of
segment 4 (`b244ac4`), the four motion-key defects (`e81e38b`) and questions 48–52's planning
session (`5d344ef`). Segment 5a joined them today (above). Eleven suites, all green.

**Decided 2026-09-20: segment 5 (save/restore) is next, and 5a is now done** - see
[stage-c-plan.md](stage-c-plan.md)'s own segment 5 section for the full shape. **5b
(mid-command resume) is where to pick up**, per the update at the top of this section.

### Playtesting the iso free demo found five more real gaps (2026-09-19/20)

Five commits after the last update (`891d743`), none of them adding to any of the ten headless
suites - each was verified with a one-off scratch probe (`tests/tmp_pass.gd`, restored after)
rather than a persisted assertion. **Worth backfilling into `tests/event_scheduler_test.gd`
before trusting this behaviour long-term**, especially the brain-suspend and route-cancel pair,
which nothing regresses on today but a headless run.

- **`21785bd`** — `action` and `jump` were both bound to Space; every press fired both. `action`
  moved to Enter.
- **`7deade7`** — new page field `lock_player` (siblings of `lock_facing`/`through`/
  `through_terrain` in storage, but scoped to one triggered run rather than the whole time the
  page is active): pushes `ModeStack.Mode.CUTSCENE` for the run's own duration. `halt_control`/
  `return_control` are the manual, unscoped equivalent. `graph_editor_panel.gd` gained a Trigger
  dropdown (`EventDocument.TRIGGERS`, the one place the seven strings are now spelled out) and a
  Lock player checkbox. Also added the iso free demo's two exercise NPCs: `Wanderer` (patrols,
  greets on `event_touch`) and `Spinner` (spins a full turn on `action`).
- **`8c8eead`** — two bugs the NPCs above immediately exposed: `DebugPassabilityView` was gated
  on `default_motion == GRID`, so it never drew on a free-motion map at all - re-gated on
  `collision_node` being set instead. And `action`'s interact range used exact cell-arithmetic
  ("adjacent cell + facing it"), exact for a grid actor but a near-miss for a free one stopped a
  few pixels off - free players now get a world-distance check with no facing requirement.
- **`bf4dd0a`** — `EventScheduler.try_lease` only ever recorded who *may* drive an actor; it
  never stopped whoever already was, so a `RouteBrain`'s patrol kept walking through its own
  event's dialogue. New `Brain.suspend(on)` (segment 5's own planned shape - see below) fixes
  it; `GameEvent` suspends/resumes it around every triggered run. `DebugPassabilityView` also
  gained a third colour for `MapContext.registered_event_cells()`, since `Occupancy` never knew
  about a free-motion event's cell at all (the Spinner was invisible to it).
- **`e328f34`** — `Brain.suspend` alone left `GridMotion`'s already-issued `move_to` queue
  walking on its own via `_advance()`, so the Wanderer coasted two or three tiles past the cell
  it actually touched the player on before stopping. `motion().call_deferred(&"cancel")`
  alongside the suspend fixes it - deferred because `event_touch` reaches `GameEvent`
  synchronously from inside `GridMotion._commit_step` itself, and a reentrant `cancel()` there
  clobbered fields the still-running commit was about to set right back.

### GameEvent/editor follow-ups after segment 6, undocumented until now (2026-09-17/18)

Seven commits between `ccac832` (this file's last update) and the ramps/stairs session below,
none of them segment 7 and none of them written down here at the time:

- **`4acc8c3`/`947c7b6` — three new page fields: `lock_facing`, `through`, `through_terrain`.**
  Siblings of `art`/`conditions`/`settings`, applied to `GameEvent`'s own actor whenever the
  active page (re)activates. `lock_facing` gates at the source, `Actor.set_facing` itself, so it
  holds regardless of who is asking. `through` pushes into `Occupancy.set_phasing` directly
  (`Actor._claim_spawn_cell` only reads `through_actors` once, at spawn, so a page switch has to
  reach the table pathing actually consults) and changes the `action` trigger's proximity rule
  from "adjacent and facing" to "on the same cell" for a through event. `947c7b6` regenerated
  every `docs/events/*.json` example plus the two real `events/` documents through the actual
  parse/stringify pipeline so the three fields are explicit rather than only implied by absence,
  and added Lock facing/Through/Through terrain checkboxes to `graph_editor_panel.gd`'s page
  inspector.
- **`83e10b7`/`d699119` — `GameEvent` remembers and restores facing across an interaction, and
  faces the interactor by default.** Captures the event's actor's facing right before a trigger
  starts a runner and restores it after, unless a movement/facing executor actually touched that
  same actor while it ran (`EventContext.mark_actor_touched`/`self_actor_touched`, armed *before*
  `run_exclusive`/`run_background` since a synchronous graph can finish inside that call).
  `_face_interactor()` then turns the actor toward the player by default on
  `action`/`player_touch`/`event_touch` — the half of `lock_facing`'s own doc comment ("will NOT
  look at the event/player... when true", implying the false case does look) that had never
  actually been built. Also fixed a test-isolation bug: `event_scheduler_test.gd` never freed a
  test's built world, so an earlier test's `GameEvent` stayed connected to the global `EventBus`
  indefinitely and could race a later test for the exclusive slot.
- **`7b6b5af`/`03ac513` — editor tooling: `Actor` no longer owns an event path, `GameEvent`
  alone does; an "Open Event Graph" button on both inspectors.** `Actor.event_path` is gone
  entirely — it duplicated `GameEvent.document_path` and was a leftover from before `GameEvent`
  existed. Selecting an `Actor` or `GameEvent` now shows a button in its own inspector
  (`actor_event_inspector.gd`, new) that opens or creates its event file in the graph editor's
  bottom panel directly, rather than needing that dock already open with the node re-selected
  there. This is editor-surface work stage-c-plan.md marked "out of scope, deliberately... built
  later, against a working runtime" — it got built anyway, ahead of segment 7, because it made
  the GameEvent work above easier to iterate on by hand.

### An out-of-band session on multi-tile ramps, stairs and the camera

Not segment 7 — a detour into `core/terrain.gd`, `tools/make_height_items.gd` and
`actors/motion/grid_motion.gd` to fix `apply_art`-adjacent height/visual issues found
while playing the demos. Landed together in one commit rather than folded into segment 7.

- **Multi-tile ramp/stairs runs.** `Terrain.ramp_run`/`surface_offset` generalise
  `RAMP_RISE` to any run length via a `<kind>_<length>_<index>` item-name suffix
  (`ramp_3_2` is the middle third of a three-tile ramp); `tools/make_height_items.gd`
  builds those variants for `RUN_LENGTHS := [2, 3]` alongside the plain one-tile items.
- **Real collision instead of a placeholder slab.** Every ramp/stairs item's shape is now
  an exact trimesh built off its own mesh (`mesh.create_trimesh_shape()`), not a fixed
  half-height box — needed so a stairs tread's blocky risers have real geometry to
  raycast against (below).
- **`GridMotion._ground_clearance()`** raycasts the real ground mesh under the sprite
  every frame of a step that touches a ramp/stairs cell, correcting the straight-line
  tween between the two idealised surface heights — a smooth ramp agrees with that line
  everywhere, a stairs mesh's risers do not. `Terrain.stance_offset` also nudges a
  settled actor's footing into the slope rather than balancing at the idealised centre.
- **Camera height easing (`OrthoPixelRig._track`)**: the rig now chases an eased
  `_camera_target` on Y only, X/Z stay pixel-pinned to `focus_of` unsmoothed (the
  `demo_scenes_test.gd` invariant depends on that). This exists because the clearance
  raycast above can legitimately move by a visible amount between two adjacent frames,
  and the camera needs to absorb that rather than whip-pan with it.
- **Fixed the actual jitter bug**: `_ground_clearance`'s own raycast passed
  `ctx.cell_size.y * 2.0` as its search radius while the comment beside it says "one cell
  of headroom either way" — the code was searching twice as far as intended. That let the
  ray occasionally punch past the real stairs tread and hit whatever solid geometry sat
  farther above or below (a ceiling, the floor of the level above), and since the hit
  flickered between the real tread and that farther surface as the horizontal position
  moved frame to frame, the sprite visibly jittered climbing stairs — smooth ramps never
  showed it because the ray always found the (single, flat) ramp surface immediately.
  Fixed by passing `ctx.cell_size.y` unmultiplied. All ten suites still green after the
  fix (147 assertions in `height_test.gd`).
- New `core/debug_passability_view.gd` + `core/occupancy.blocking_cells()` +
  `debug_flags.show_debug_view()`/`debug_view_toggled`: an in-game overlay for every
  blocked cell, toggled by the same key `is_fast_forward` already reserves the opposite
  sense of.

### Same detour, continued (2026-09-19): slope speed, and both HUD pieces made global

Also not segment 7. Two independent changes, two commits.

- **`GridMotion` climbs ramps/stairs slower and descends them faster than flat ground**
  (`slope_up_speed_scale`/`slope_down_speed_scale`, plus `slope_camera_align_scale` sharpening
  the climb the more it lines up with the camera's own depth axis). Reads the true surface
  height through `Terrain.surface_offset`, not the cell, so each half-cell of a ramp climb is
  caught on its own. `MotionController.max_depth_boost` became a constant
  (`MAX_DEPTH_BOOST`) in the same commit — nothing had ever varied it per actor.
  `height_test.gd` gained 3 assertions (150 total) checking both halves of the ramp climb and
  the stairs descent against a flat baseline.
- **`DebugPassabilityView` and `MainUI` moved from per-scene children to global autoload
  singletons** (`GameUI`, `DebugPassabilityView` in `project.godot`), so both exist before any
  demo scene loads and survive switching between them instead of every demo carrying its own
  copy. `MapContext` gained group membership (`&"map_context"`, `_enter_tree`/`_exit_tree`) so
  the debug overlay can find whichever map is currently loaded without a `NodePath` into it — no
  valid grid map means it skips drawing rather than freeing itself, since a global can't
  `queue_free` over a demo scene it doesn't like. `GameUI` is a `CanvasLayer` so it draws above
  whatever map is current regardless of tree order, and hides `MainUI` while no map is loaded
  (the demo launcher). Verified against `demo_scenes_test.gd`, which runs all three demos plus
  the launcher back to back in one process — exactly the case that needed the singletons to
  follow the map across scene changes.

**Current suite totals, all green** (re-run 2026-09-19):
231 (stage_a) + 31 (areas) + 150 (height) + 112 (event_command) + 71 (actor_naming) +
107 (event_condition) + 73 (event_document) + 20 (event_runner) + 47 (event_scheduler) = **842**,
plus `demo_scenes_test.gd`'s unnumbered checks. Segments 5 and 7 still have no suite of their own
(`event_save_test.gd`/`event_route_test.gd` don't exist).

**Updated 2026-09-20**: `event_save_test.gd` now exists (26 assertions, segment 5a - see the
top of this file) - **868** total across eleven suites. `event_route_test.gd` (segment 7) still
doesn't.

### What segment 6 actually built

`EventScheduler` gained actor leases (`try_lease`/`release_lease` — a patrol and a cutscene
cannot both drive one guard), `EventRunner.keeps_running` as the waterfall opt-out from
"background suspends while exclusive is held", and a test-only `reset_for_test()`.

`events/game_event.gd` is new: owns a document, evaluates the active page via
`EventDocument.active_page`, applies its art through `ActorView.apply_art`, registers its cell
with `MapContext`, and starts a runner through `EventScheduler` when one of the seven triggers
fires — `player_touch`/`event_touch`/`leave_cell` off `actor_stepped`, `action` off a new
`EventBus.player_interacted` (`Brain` now actually reads `InputIntent.interact`, which nothing
consumed before this), `on_load`/`auto` at `_ready()`, `on_flag` off `GameState.changed`. A page
switch defers to graph completion (question 23); `re_validate` is **not** wired to force one
early yet — still segment 4's generic no-op fallback.

**Fixed the `apply_art` defect the plan named**, and it was worse than described: both
`SpriteView2D` and `SpriteView3D` only ever looked for an `AnimatedSprite2D`/`3D` and did
nothing for a `SpriteSheet`/`SpriteSheet3D` visual — which is **every actor prefab this project
ships**, so `apply_art` was a complete no-op in both demos before this. Both now read
`"sheet"` (a texture path) for the sheet-driven visual alongside the existing `"frames"` (a
`SpriteFrames` path); 2D also reads `"directions"`/`"idle"`, silently ignored before.

`PlayerBrain` now calls `intent.lock_step(not ModeStack.is_field())` — segment 0's `lock_step`
hook finally has a caller.

**Wired into both demo scenes, confirmed by hand**: an NPC with no brain (`Npc_17_9` in
`jrpg_demo`, `Event__1` in `isoish_grid_demo`) gets a `GameEvent` with an action-triggered
`face_to`/`say` graph and reconciled sheet art, at `res://events/<map_id>/<event_id>.event.json`
— the real-event layout the plan calls for, distinct from `docs/events/`, which stays
documentation-only.

**Left for later, unchanged from segment 4**: `follow`, `close_window`, `fade`, `shake`,
`camera_to`, `camera_follow`, `play_anim`, `play_sound`, `play_music`, `start_battle` still have
no executor; `change_map` is still a named placeholder with no real map loader behind it.

### What segment 4 actually built, and what it deliberately left unbuilt

`events/event_context.gd`, `events/key_latch.gd`, `events/event_command_exec.gd` (the executor
interface), `events/commands/*.gd`, `events/event_runner.gd`, `core/event_scheduler.gd` (the
fifth autoload — clock only, no leases/triggers yet) and `core/debug_flags.gd` (question 48),
plus a small registry revision to `events/event_command.gd`: `change_map`'s `flows` is now
`["next"]` and a new `exit_call` entry exists (question 49/51).

**`EventRunner` is iterative, not recursive** — a trampoline loop (`_drive`), because the first
draft called `_enter_node`/`_advance`/`_pop_frame` back and forth and a goto cycle ran the node
budget a thousand real GDScript call frames deep before it ever tripped, throwing engine-level
"Stack underflow" errors. Worth remembering for anything that walks a graph: bound the *call
stack depth*, not just the iteration count, or the guard you wrote is not the thing that stops
it.

**A `call` frame popping must resume the caller's own `call` node, not just vanish** — the
first draft of `exit_call`/`end` popped a frame and left the frame beneath sitting on its
unresolved `call` node, which the trampoline re-entered and pushed right back: an infinite loop
disguised as a cycle. `_pop_frame()` now always cascades into `_advance_cursor` on whatever is
exposed beneath, which is what actually resumes the caller at `call`'s own `next`.

**A fifth motion-key defect, found while wiring `move_by` into an executor:**
`GridMotion.move_to`'s non-empty-queue path read `_route_key` *after* calling `_advance()`,
which can itself walk the whole queue to completion synchronously for a viewless actor and
clear that same field as part of emitting it — so the method returned `""` for a route that
had, in fact, already resolved a real key. Same family as the four fixed before segment 4
started; fixed the same way (read into a local before the call that might race it).

**Left unbuilt, deliberately, with no executor and a fallback to report-and-carry-on:**
`follow`, `close_window`, `fade`, `shake`, `camera_to`, `camera_follow`, `play_anim`,
`play_sound`, `play_music`, `start_battle` — each needs a subsystem that doesn't exist yet
(a background/lease system, a force-close hook, a camera rig hookup for events, an animation
hookup, an audio subsystem, a battle scene). None of the five worked examples' *tested* paths
need them; `cliff_jump.event.json` uses `camera_to`/`camera_follow` and is not exercised
end-to-end by the current suite because of it — worth building a real executor for those two
before that example is anyone's regression test.

**`change_map`'s executor is a named placeholder, not the real thing.** It warns once and
resolves immediately; the actual map load, and the `EventContext` rebind that goes with it
(question 51), need a map loader that doesn't exist yet. The registry shape (`"next"` port) is
already right for whenever that lands.

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

Segment 4 is now built exactly along those lines — see "What segment 4 actually built" above
for the shape it ended up taking and where it deliberately stopped. The resumability rules
(restart is always a legal downgrade; a restart command must finish inside the tick it starts
or have no committed side effects before then) are designed for but not yet exercised —
segment 5 is what will actually call `capture()`/`restore()` on anything.

**Run the full suite before starting segment 7**, to confirm nothing upstream drifted:

```bash
GODOT="/c/Users/kyle/Desktop/Godot_v4.7-stable_win64_console.exe"
for t in stage_a areas demo_scenes height event_command actor_naming event_condition event_document event_runner event_scheduler; do
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
for t in stage_a areas demo_scenes height event_command actor_naming event_condition event_document event_runner event_scheduler event_save; do
  timeout 110 "$GODOT" --headless --path . res://tests/${t}_test.tscn
done
```

**868 assertions, all green** as of 2026-09-20 (231+31+150+112+71+107+73+20+47+26, plus
demo_scenes' unnumbered checks — `event_save_test.gd` (26) is segment 5a, new today; see
"Update 2026-09-20" at the top of this file). Godot is not on PATH; use the
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

- **Ladder mount/dismount need their own hooks**, not just the geometry in
  `Terrain.resolve_step`/`_from_ladder`. Four moments: mount climbing (from the ground,
  pressing into the wall), mount descending (from the ledge above, pressing away from
  it — the branch discussed below), dismount at the top, dismount at the bottom. Kyle
  wants to lock an actor's facing toward the ladder on mount, but as a per-actor choice
  rather than baked into `Terrain` — a monster might want different behavior than the
  player — so this needs to be a hook (signal, or a virtual on `Brain`/`Actor`) something
  can opt into, not a rule enforced at the resolver.
- **Mounting a ladder going down lands diagonally and should not.** In
  `Terrain.resolve_step`, the "down onto the top rung" branch —
  `if has_ladder(ctx, below) and ladder_facing(ctx, below) == -dir: return _step_to(below, 0, true)`
  — moves the actor from `from` straight to `below` (`ahead - UP`), which is forward
  *and* down in the same step: a diagonal move, the one shape `resolve_step`'s own doc
  comment says this project's step rules cannot express. Kyle wants mounting from above
  to land on the cell *above* the ladder's own occupied cell first (i.e. `ahead`, at the
  unchanged Y — the ledge cell right at the top rung, between two pathable tiles) and
  have the *next* step be the one that actually descends onto the ladder. Needs a real
  test case once built: a ladder cell sandwiched between two otherwise-pathable tiles
  (approached and mounted from both the ledge above and the ground below), which nothing
  in `height_test.gd` currently covers.
- **Grid movement assumes every actor is one cell.** `Actor._claim_spawn_cell` and
  `GridMotion` place/move a mover through a single origin cell (`Occupancy.place`/`move`),
  unlike `GridObstacle`, which already computes a multi-cell footprint from its collision
  shapes for static props (`core/grid_obstacle.gd:_footprint_cells`). Nothing today lets an
  actor (a large monster, a multi-tile boss) claim more than its origin cell — occupancy,
  `Passability.can_enter`, and step commit would all need to reason about a footprint of
  cells, not one, before an actor bigger than 1x1 can exist. Worth doing before any boss or
  oversized NPC is authored.
- **The node stem for a hand-named node.** A first generated id discards whatever the node
  was called: a node deliberately named `Guard` with no id becomes `event__2`, not
  `Guard__2`. Nothing can tell a deliberate name from a prefab's default name, so this
  follows the literal rule. Give such an actor a word id if the name should survive.
- **Nothing calls `assign_all` yet.** The editor button is unbuilt — it belongs with the
  snap-to-cell shortcut on the wishlist in [open-questions.md](open-questions.md).
- **Two questions expected mid-build**, flagged in the plan: whether `ask` and `choice`
  are one command or two (architecture.md §7.3 says `choice`, the example says `ask`), and
  whether `follow` is a command or a route mode, since it appears in both lists.
- ~~**`apply_art` does not match the `art` block** and will have to be reconciled in segment
  6~~ **Fixed in segment 6** (`273066e`) — see "What segment 6 actually built" above. Both
  `SpriteView2D`/`SpriteView3D.apply_art` now read `"sheet"` for the sheet-driven visual, which
  is every actor prefab this project ships.

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
