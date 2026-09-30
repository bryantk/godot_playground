@tool
class_name PartySetup extends Resource

## What a new game's party is, as a resource you edit in the inspector: who is fighting,
## who is waiting in reserve, the gold, and what is in the bags. [member Party] reads
## [code]res://data/party.tres[/code] (see [constant Party.SETUP_PATH]) when the game
## starts and again on a new game, so changing the starting party is editing this file -
## no code. The Battle Data dock has a button that opens it.
##
## The members listed here are templates: the running party holds copies, so playing never
## changes the file, and a save only needs to remember each member's id.

## Who fights, in order. At most [constant Party.MAX_ACTIVE] of them take part in a battle
## (the first ones); any beyond that simply wait behind them.
@export var active: Array[PartyMember] = []

## Members in the roster who are not in the fighting line.
@export var reserve: Array[PartyMember] = []

@export var gold: int = 0

## Consumables in the bags: item id -> how many. Ids are [member Item.id]s (see the
## Items tab of the Battle Data dock).
@export var items: Dictionary[StringName, int] = {}

## Every piece of gear that exists in this game, so a saved game can turn an equipment id
## back into the real thing. Gear a listed member has equipped is found automatically and
## need not be repeated here; this is for gear that is only ever in the bags or a shop.
@export var equipment: Array[Equipment] = []

## Unequipped gear in the bags: equipment id -> how many.
@export var owned_equipment: Dictionary[StringName, int] = {}
