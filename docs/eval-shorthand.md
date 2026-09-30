# The `@actor.` eval shorthand

A short way to ask questions about an actor inside an expression: where it is, how close it
is to something, and what its own flag says.

```
@guard.at(3, 0, 4)              is the guard standing on cell (3, 0, 4)?
@guard.near(3, 0, 4, 2)         is it within 2 cells of that cell?
@guard.near_event(@player, 2)   is it within 2 cells of the player?
@guard.flag("alerted")          has its own "alerted" flag been set?
@guard.flag("alerted", true)    set that flag            (debug terminal only)
```

The same spelling works everywhere an expression is accepted. The code lives in
`code/events/actor_queries.gd` (what each question means), `code/events/event_condition.gd`
(the parser and evaluator) and `code/world/debug/debug_menu.gd` (the terminal).

## Where you can use it

| Place | What it does with the result |
| --- | --- |
| A page's `conditions` (typed as an expression) | Decides whether the page is active. |
| The `if` command | Picks the `true` or `false` flow. |
| The `variable` command | Picks `true` or `false`, with `{v}` standing in for a variable. |
| The `eval_var` command | Stores the true/false result in a variable. |
| The debug terminal (debug menu, key `~`) | Prints the result. Also the only place a flag can be *written*. |

They all share one grammar, so a line that works in `if` works in the terminal and the other way round
(apart from the flag write, below).

## The four methods

### `@actor.at(x, y, z)` → true/false

True when the actor's cell is exactly `(x, y, z)`. The three numbers are whole cells, not
world units.

### `@actor.near(x, y, z, distance)` → true/false

True when the actor is within `distance` cells of the cell `(x, y, z)`.

Distance is **Manhattan**: `|dx| + |dy| + |dz|`, in cells. That matches how a grid actor
walks, so it reads the way you would count steps:

| Actor is at | `near(0,0,0, 1)` | `near(0,0,0, 2)` |
| --- | --- | --- |
| `(1, 0, 0)` | yes | yes |
| `(1, 0, 1)` (the diagonal) | **no** (2 away) | yes |
| `(2, 0, 0)` | no | yes |

`near(x, y, z, 0)` is the same question as `at(x, y, z)`.

### `@actor.near_event(@other, distance)` → true/false

Like `near`, but measured to another actor's current cell instead of a fixed one.
`@other` is written the same way as the first actor: `@player`, `@self`, `@npc_scout`.
The "event" in the name is historical - what it measures to is the other actor.

### `@actor.flag("name")` → true/false

Reads the actor's **own** flag called `name`. This is the per-event, per-map "self flag" -
the same storage as the `self.name` shorthand, `set_self_flag`, and the `self_flag`
page condition - looked up on the event that sits with that actor. An actor with no event
beside it has no flags, so it reads false.

`@actor.flag("name", true)` (or `false`) **writes** it. A write is refused outside the debug
terminal: in a condition a write would make "checking" change the world, so the parser
reports `"@guard.flag" with a value writes the flag, which a condition cannot do` and the
expression is treated as always-true (see [Errors](#errors)).

## Naming an actor

The part after `@` is resolved against the current map:

| Written | Means |
| --- | --- |
| `@self` | The actor this event belongs to. Not available in the terminal (nothing is "self" there). |
| `@player` | The player's actor. |
| `@guard`, `@npc_scout` | The actor whose id is `guard`, `npc_scout`. Ids are lower-case. |
| `@debug-3` | A hyphen is part of the name when a letter or digit follows it. |

An actor that is not on the map makes that one test read **false**, and a warning names
what it could not find, so a typo shows up in the output instead of silently never matching.

## Combining

The shorthand is an ordinary condition, so it combines with everything else in the grammar -
`and`, `or`, `not`, parentheses, flags, variables, `self.flag`, `has_item(...)`:

```
@player.near(12, 0, 5, 3) and not chapter >= 4
@self.near_event(@player, 1) and not @door.flag("locked")
```

A call is a complete test on its own and cannot be compared with `==` (so not
`@door.flag("locked") == false`); use `not` to negate it.

## In the debug terminal

The terminal evaluates GDScript expressions with `GameState` as their base, so the
shorthand is added by rewriting. Every `@name` becomes `actors["name"]` before the line is
run, and `actors` is handed to it as an input. You don't type that - you type the shorthand:

```
> @guard.at(3, 0, 4)
false
> @guard.flag("alerted", true)
true
> @guard.flag("alerted")
true
> @player.near_event(@guard, 4) and @guard.flag("alerted")
true
```

Because the terminal is GDScript underneath, use ordinary quoted strings (`"alerted"`, not
`&"alerted"`), and everything else on the terminal works alongside it: `flag("x")`,
`var_set("n", 3)`, Up/Down for history, Tab to complete.

## Things to know

**Conditions do not re-check when an actor moves.** A page picks its active page when
something it depends on changes, and the game tracks that through flags and variables. A
position emits nothing, so a *page* condition such as `@player.near(5,0,5,2)` is tested when the
page is chosen, not continuously. In an `if` command (evaluated when the graph reaches it)
it always reads the current position. To react to movement, test it from a graph - a looping
`if`, or an area trigger - rather than relying on a page condition.

**Flags are shared more widely than they look.** A self flag is stored under the map and
the *event's node name*. Placements here all call that node `GameEvent`, so two actors'
`flag("talked")` can be the same flag. Give each placement's event a distinct name if you
need them to be separate. (`self.talked` has always had this property.)

**The result is true/false.** `eval_var` therefore stores a boolean. It cannot store
a number such as "how far away is the player".

## Errors

Anything the parser cannot read makes the whole expression **always true** and reports the
problem (that is deliberate: an event that appears when it should not is easier to notice
than one that silently vanishes). The messages say what was wrong:

| You wrote | Reported |
| --- | --- |
| `@guard` | needs a method after it, as `@guard.near(...)` |
| `@guard.at(1, 2)` | `at` takes a cell: `at(x, y, z)` |
| `@guard.near(1, 2, 3)` | `near` takes a cell and a distance |
| `@guard.near_event(5, 2)` | `near_event` takes another actor and a distance |
| `@guard.flag(alerted)` | `flag` takes a quoted flag name |
| `@guard.flag("a", true)` in a condition | a condition cannot write a flag |
| `@guard.teleport(1)` | `@guard` has no method `teleport`; expected at, near, near_event or flag |

## How it is stored

Each call becomes one leaf of the condition tree, so structured conditions and the typed
form are the same thing:

```json
{"actor_at": "@guard", "cell": [3, 0, 4]}
{"actor_near": "@guard", "cell": [3, 0, 4], "distance": 2}
{"actor_near_event": "@guard", "event": "@player", "distance": 2}
{"actor_flag": "@guard", "name": "alerted"}
```

Any leaf can carry `"is": false` to negate it in place, as the other leaves can.
