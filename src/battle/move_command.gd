class_name MoveCommand
extends Command
## 移动：沿寻路路径走到目标格，更新占位与朝向。
## 当前激活单位的移动按路径地形消耗扣减剩余移动力（策划 6.5 移动可拆两段），超耗拒绝；
## 非激活单位的脚本化移动（测试/事件）不校验不扣减，保持旧行为。

var path: Array[Vector2i] = []

func _init(p_actor: Unit = null, p_path: Array[Vector2i] = []) -> void:
	super(p_actor)
	path = p_path

func execute(battle: BattleManager) -> Array:
	if actor == null or path.is_empty():
		return []
	var from := actor.coords
	var dest: Vector2i = path.back()
	if not battle.grid.can_stop(dest, actor):
		push_error("MoveCommand: 目标格不可停留 %s" % dest)
		return []
	if battle.active_unit == actor and battle._activation_live:
		var cost := path_cost(battle.grid)
		if cost > battle.move_points_left:
			push_error("MoveCommand: 路径消耗 %d 超出剩余移动力 %d" % [cost, battle.move_points_left])
			return []
		battle.move_points_left -= cost
		battle.move_used = true
	battle.grid.move_unit(actor, dest)
	var last_step: Vector2i = dest - (path[path.size() - 2] if path.size() >= 2 else from)
	if last_step != Vector2i.ZERO:
		actor.facing = DamageCalculator.dominant_dir(last_step)
	return [{"type": "move", "unit": actor, "from": from, "path": path.duplicate()}]

## 路径地形消耗：逐格累加进入格消耗（path 不含起点，与 Grid.get_reachable / AStar 权重同口径）。
func path_cost(grid: Grid) -> int:
	var total := 0
	for c in path:
		var cell := grid.get_cell(c)
		if cell != null:
			total += grid.move_cost_of(cell, actor)
	return total
