# Making content: a game developer's guide

What the recent systems are and how to use them. Each section says *where it lives*, *what
you author*, and *how to try it*. Deeper notes are in the code comments and in
[eval-shorthand.md](eval-shorthand.md).

## Where things live

| You author | Where | Edited with |
| --- | --- | --- |
| Event graphs (what an actor or trigger does) | `events/<map_name>/<actor>.event.json` | **Graph** bottom panel |
| Shared patrol routes | `events/routes/<name>.route.json` | Graph panel |
| Heroes, enemies, troops, items, abilities, effects, equipment | `data/<kind>/*.tres` | **Battle Data** dock + inspector |
| The starting party | `data/party.tres` | Battle Data dock → *Party setup* |
| Enemy AI | an ordinary `.event.json` (anywhere), named by the enemy's `ai_path` | Graph panel |

A map's events live in a folder named for the map scene (`jrpg_demo.tscn` →
`events/jrpg_demo/`). An actor's event file is named after its placement: rename the node in
the Scene dock and the file follows it (a duplicate gets its own copy). *Move Orphaned* is
gone; *Find Orphaned Events* in the actor menu archives unused files to `removed/`.

---

## Event graphs

Open the **Graph** panel, select an actor or event in the Scene dock, *Actor ▸ Load Actor
Event*. Commands are nodes; flows are the labelled ports on the right.

**Editor helpers**
- **Right-click a node**: Clone / Delete (the whole selection if it is part of one).
  Right-click empty canvas still opens the add-command picker.
- **Pick** button beside any cell argument: click it, then click the scene viewport (2D or
  3D) to fill the cell in. Esc cancels.
- **Route overlay**: select a placement and the viewport draws where its page's route (cyan)
  and graph (orange) would walk it. `?` marks a step that can't be known (towards/away the
  player), an X with ticks marks random/wander, a ring marks where a loop closes, dashes mark
  jumps and `move_route`. It follows the first wired branch only.
- **Page inspector** (right side): speed, animation speed, **Color** (tints the actor while
  the page is active), lock flags, conditions.

### Movement commands and their flows

`move_to`, `move_by`, `jump`, `move_route` share the same flows:

| Flow | Fires |
| --- | --- |
| `reached` | The move finished. |
| `blocked` | The target cell was inaccessible. **Wired**: the move counts as done and the graph goes on from here. **Unwired**: the event waits a frame and retries, so a looped patrol resumes the same loop once the player steps aside. |
| `immediate` | As the move starts; wire it and the graph doesn't wait. |
| `no_path_found` | `move_route` only - see below. |

`move_by` **cells** is either a literal delta (compass + distance in the node) or a token:
`forward`, `random`, `wander`, `towards_player`, `away_from_player`, optionally with a
distance (`wander:3`). The direction is decided **once** when the move starts, then walked
that many cells.

`move_route` finds a path with capped A* (`max_nodes`, default 2000), stores it on the actor
as JSON `move_to` steps (until the next `move_route`, and in saves), and walks it. Unreachable
or too far: `no_path_found` fires at once and the actor doesn't move. Grid actors only.

### Other commands added

- `shake` (`strength` px, `seconds`; `reached`/`immediate`) - camera shake.
- `set_color` (`actor`, `color`) - tint an actor; white restores it. `camera_move_by` takes
  the same `cells` tokens as `move_by`.
- **Conditions** (`if`, page conditions, `eval_var`) accept `@actor.at/near/near_event/flag` -
  see [eval-shorthand.md](eval-shorthand.md).

### The party caterpillar

The active party members who have a `follower_sheet` walk in a line behind the player,
automatically. Followers pass the player and each other but block (and are blocked by) other
actors, hide during battle, and rebuild on the new map.

| Command | Use |
| --- | --- |
| `follow_add` / `follow_remove` | `member: "mage"` to put a party member back in / take one out; or `actor: "@npc"` to make any actor trail the party. |
| `follow_show` | `visible` true/false, for everyone or one `actor`. |
| `follow_group` | Walk everyone to their place behind the player. `reached` when settled; wire `immediate` to not wait. |

Give each member a `follower_sheet` (same layout as the player's art) in their resource.

---

## Battle content

Everything is a resource under `data/`. Open the **Battle Data** dock (left, bottom), pick a
tab, **New / Duplicate / Save / Delete**, and edit in the inspector. **Check data** lists
broken references (missing stats, empty troops, an AI file that isn't there, duplicate ids).

- **Ability** (`data/abilities`): what a combatant can do - kind (attack/skill/item/guard),
  target, `power`, element, MP cost, and `effects` to apply (with a chance). Power 0 = no
  damage, effects only. `attack` and `guard` already exist and are shared.
- **Hero** (`data/heroes`) / **Enemy** (`data/enemies`): both are a `Combatant`: id, name,
  base stats, `abilities`. New heroes start with Attack + Guard, new enemies with Attack.
  Heroes add equipment, `follower_sheet`; enemies add `gold_reward` and `ai_path`.
- **Troop** (`data/troops`): groups of `{enemy, count}`. `start_battle` names a troop by id.
- **Status effect** (`data/effects`): per-stack `flat` and `percent` changes to
  `max_hp/max_mp/atk/def/mag/spd`; a duration in **rounds** (battle) or **steps** (field);
  optional `until_flag`; stacking = refresh / stack / ignore. Apply from an ability, an item,
  or `Party` code; they expire and are saved.
- **Item** (`data/items`): name, price, and an `action` (an Ability: `power` = HP restored,
  plus effects), usable in battle and/or the field. Bag counts live in the party setup.
- **Equipment** (`data/equipment`): slot + a stat bonus.
- **Party setup** (`data/party.tres`): active members, reserve, gold, bag items, equipment
  catalogue, owned gear. Edited in the inspector; the game copies it on start and on a new game.

### Enemy AI

Build a graph in the Graph panel whose page 1 uses the **battle** commands, save it, and put
its path in the enemy's `ai_path`. It runs at the start of the enemy's turn; the first
`use_ability` reached is the turn. No AI (or nothing reached) = a random ability.

| Command | Does |
| --- | --- |
| `if_round` | `op`/`value`, or `every` N rounds. |
| `if_stat` | `who` self/target, `stat` hp/mp/atk/…, `op`, `value`, `percent`. |
| `if_status` | Does self/target have a status effect? |
| `if_count` | How many allies/enemies are standing. |
| `if_random` | True `chance` percent of the time. |
| `choose_target` | `rule`: first, random, self, lowest_hp, most_hp, lowest_hp_percent, highest_atk/def/mag/spd, lowest_spd/def; `side` enemies/allies. |
| `use_ability` | Use `ability` (by id) on the chosen target; ends the decision. |

Example: *if hp under 30% → `use_ability heal` on self; else `choose_target lowest_hp` → `use_ability attack`.*

---

## Debug tools

Backtick (`` ` ``) opens the debug menu (debug builds).
- **Keys 1-7** toggle overlays: event, area, transfer marker, actor, passability, interact, **route** (draws each actor's stored `move_route` path).
- **Input replay**: *Record* → play → *Stop + save* (three rotating slots); *Replay 1/2/3* plays it back deterministically.
- **Terminal**: type a GDScript expression, run on `GameState` (`flag("door")`, `var_set("n", 3)`, `@guard.near(3,0,4,2)`). Up/Down = history, Tab = complete, Esc/backtick = leave the field.

## Running the tests

`godot --headless --path . res://tests/<name>.tscn` (see `tests/`). New this round:
`route_tracer_test`, `follower_chain_test`, `battle_effects_test`, `battle_ai_test`,
`battle_data_test`, `debug_terminal_test`. `tools/make_party_data.tscn` regenerates the demo party files.
