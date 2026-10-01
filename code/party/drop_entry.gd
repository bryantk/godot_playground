@tool
class_name DropEntry extends Resource

## One thing an [EnemyDef] may leave behind when it is defeated: an [Item], how many, and
## the chance it does ([BattleState.grant_rewards] rolls each once per defeated enemy).

@export var item: Item = null
@export var count: int = 1
@export_range(0.0, 1.0, 0.01) var chance: float = 1.0
