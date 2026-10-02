# Making content: a game developer's guide

What the recent systems are and how to use them. Each section says *where it lives*, *what
you author*, and *how to try it*. Deeper notes are in the code comments and in
[eval-shorthand.md](eval-shorthand.md).

## Where things live

| You author | Where | Edited with |
| --- | --- | --- |
| Event graphs (what an actor or trigger does) | `data/events/<map_name>/<actor>.event.json` | **Graph** bottom panel |
| Shared patrol routes | `data/events/routes/<name>.route.json` | Graph panel |
| Heroes, enemies, troops, items, abilities, effects, equipment | `data/<kind>/*.tres` | **Battle Data** dock + inspector |
| The starting party | `data/party.tres` | Battle Data dock → *Party setup* |
| Enemy AI | an ordinary `.event.json` (anywhere), named by the enemy's `ai_path` | Graph panel |

A map's events live in a folder named for the map scene (`jrpg_demo.tscn` →
`data/events/jrpg_demo/`). An actor's event file is named after its placement: rename the node in
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
- **Self flags A-D**: `set_self_flag` has a **slot** dropdown (unset, A, B, C, D), and so does a
  `self_flag` row in the page form. A picked slot *is* the flag's name; (unset) uses the `name`
  field beside it. In a typed expression `self.A` is the same flag. A flag belongs to one
  placement (the placement's name, as its json is named).
- **Dropdown arguments**: arguments with a fixed set of values (the AI commands' `who`, `stat`,
  `op`, `rule`, `side`, `use_ability`'s ability, `if_status`'s effect, `follow_regroup`'s mode) are
  dropdowns in the node and are checked when a file is validated.
- **Position-aware pages**: a page condition using `@actor.at/near/near_event/flag` is re-checked
  whenever any actor settles on a cell, so a page can switch as the player walks up to it.
- **Conditions** (`if`, page conditions, `eval_var`) accept `@actor.at/near/near_event/flag` -
  see [eval-shorthand.md](eval-shorthand.md).

### The party caterpillar

The active party members who have a `follower_sheet` walk in a line behind the player,
automatically - there is nothing to author for them to follow. Followers pass the player and
each other but block (and are blocked by) other actors, hide during battle, and rebuild on
the new map. Name them in any command by position: `@follower_1`, `@follower_2`... (or by
member id, `@mage`).

| Command | Use |
| --- | --- |
| `follow_add` / `follow_remove` | `member: "mage"` to put a party member back in / take one out; or `actor: "@npc"` to make any actor trail the party. |
| `follow_show` | `visible` true/false, for everyone or one `actor`. |
| `follow_break` | Stop following (everyone, or one `actor`). They stay put, so ordinary `move_to`/`move_by`/`face_*` commands addressed to `@follower_1` etc. can walk them wherever the scene needs. |
| `follow_regroup` | `mode`: **line** (each walks to its place behind the player) or **player** (each walks onto the player's cell). They follow again afterwards; they stay on the player until it moves. `reached` when settled; wire `immediate` to not wait. |

A cutscene is usually: `follow_break` → move `@follower_1` / `@follower_2` → `follow_regroup`.

Give each member a `follower_sheet` (same layout as the player's art) in their resource.

---

## Battle content

Everything is a resource under `data/`. Open the **Battle Data** dock (left, bottom), pick a
tab, **New / Duplicate / Save / Delete**, and edit in the inspector. **Check data** lists
broken references (missing stats, empty troops, an AI file that isn't there, duplicate ids).

- **Ability** (`data/abilities`): what a combatant can do - kind (attack/skill/item/guard),
  target, `power`, element, MP cost, and `effects` to apply (with a chance). Power 0 = no
  damage, effects only. **Healing**: `heal_amount` + `heal_mag_scale` x the user's magic.
  **Dispel**: `dispel` removes the target's buffs, debuffs or both. `attack` and `guard`
  already exist and are shared.
- **Hero** (`data/heroes`) / **Enemy** (`data/enemies`): both are a `Combatant`: id, name,
  base stats, `abilities`. New heroes start with Attack + Guard, new enemies with Attack.
  - Heroes add equipment, `follower_sheet`, and **growth**: `level`/`xp`, `growth` (stat gain
    per level above 1, e.g. `{"atk": 2, "max_hp": 6}`) and a `learnset` (level → ability gained).
    Level and xp are saved; the rest follows from them.
  - Enemies add `gold_reward`, `xp_reward`, `drops` (items with a chance and count), `ai_path`.
- **Troop** (`data/troops`): groups of `{enemy, count}`. `start_battle` names a troop by id.
- **Status effect** (`data/effects`): per-stack `flat` and `percent` changes to
  `max_hp/max_mp/atk/def/mag/spd`; a duration in **rounds** (battle) or **steps** (field);
  optional `until_flag`; stacking = refresh / stack / ignore; `beneficial` (what a dispel
  targets) and `hp_per_round` (regeneration +, poison -). Apply from an ability, an item,
  or `Party` code; they expire and are saved. The battle scene lists what is on a battler.
- **Item** (`data/items`): name, price, and an `action` (an Ability: `power` = HP restored,
  plus `effects` and `dispel`), usable in battle and/or the field. Bag counts live in the
  party setup.
- **Equipment** (`data/equipment`): slot + a stat bonus.
- **Party setup** (`data/party.tres`): active members, reserve, gold, bag items, equipment
  catalogue, owned gear. Edited in the inspector; the game copies it on start and on a new game.

**After a win** the party gets the enemies' gold, their xp split between the survivors (with
level-ups and learned abilities in the log), and each defeated enemy's drops.

**Example data** ships under `data/`: heroes Hero, Mage, Cleric; enemies Slime, Awakened Slime,
Wolf, Bandit; troops `slime_pair`, `slime_awakened`, `wolf_pack`, `bandit_gang`; buffs/debuffs
(Haste, Rage, Regen, Sunder, Slow, Poison, Fortify); abilities (Heal, Cure, Haste, Rally, Sunder,
Poison Bite, Howl...); items (Potion, Antidote, Fortify Tonic). The Wolf and Bandit use the AI
graphs in `data/events/ai/` - open them in the Graph panel to see how they are built.
`tools/make_party_data.tscn` regenerates all of it.

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

**Test it**: in the Battle Data dock select an enemy and press **Test enemy AI** - it lists what
the graph would choose for five rounds, healthy and wounded, against your current party, without
fighting. **Check data** also flags AI graphs with broken nodes or a `use_ability` the enemy
doesn't have.

---

## Debug tools

Backtick (`` ` ``) opens the debug menu (debug builds).
- **Keys 1-7** toggle overlays: event, area, transfer marker, actor, passability, interact, **route** (draws each actor's stored `move_route` path).
- **Input replay**: *Record* → play → *Stop + save* (three rotating slots); *Replay 1/2/3* plays it back deterministically.
- **Terminal**: type a GDScript expression, run on `GameState` (`flag("door")`, `var_set("n", 3)`, `@guard.near(3,0,4,2)`). Up/Down = history, Tab = complete, Esc/backtick = leave the field.

## Running the tests

`godot --headless --path . res://tests/<name>.tscn` (see `tests/`). New this round:
`route_tracer_test`, `follower_chain_test`, `battle_effects_test` (effects, levels, rewards), `battle_ai_test`,
`battle_data_test`, `debug_terminal_test`. `tools/make_party_data.tscn` regenerates the demo party files.
